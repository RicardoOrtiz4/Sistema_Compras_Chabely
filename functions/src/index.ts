import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';

type OrderPayload = {
  requesterId: string;
  requesterName: string;
  areaId: string;
  areaName: string;
  urgency: string;
  clientNote?: string | null;
  items: Record<string, unknown>[];
};

type CreateUserPayload = {
  name: string;
  email: string;
  password: string;
  role: string;
  areaId: string;
};

type UserContext = {
  uid: string;
  role: string;
  areaId: string;
  areaName: string;
  name: string;
  email: string;
};

type AllowedTransitions = Record<string, string[]>;

type AreaTransitions = Record<string, string[]>;

admin.initializeApp();
const db = admin.database();
const messaging = admin.messaging();

const allowedTransitions: AllowedTransitions = {
  draft: ['pendingCompras'],
  pendingCompras: ['authorizedGerencia'],
  authorizedGerencia: ['paymentDone'],
  paymentDone: ['orderPlaced'],
  orderPlaced: ['eta'],
};

const AREA_COMPRAS = 'Compras';
const AREA_GERENCIA = 'Gerencia';
const AREA_CONTABILIDAD = 'Contabilidad';
const AREA_SOFTWARE = 'Software';

const areaTransitions: AreaTransitions = {
  [AREA_COMPRAS]: ['authorizedGerencia'],
  [AREA_GERENCIA]: ['paymentDone'],
  [AREA_CONTABILIDAD]: ['orderPlaced', 'eta'],
};

const allowedRoles = new Set(['usuario', 'administrador']);
const defaultAreas: Record<string, { name: string }> = {
  [AREA_COMPRAS]: { name: AREA_COMPRAS },
  [AREA_GERENCIA]: { name: AREA_GERENCIA },
  [AREA_CONTABILIDAD]: { name: AREA_CONTABILIDAD },
  [AREA_SOFTWARE]: { name: AREA_SOFTWARE },
};

const REGION = 'us-central1';
const PURCHASE_ORDER_FOLIO_COUNTER = 'counters/folios/purchaseOrderNext';
const PURCHASE_ORDER_COUNTERS_ROOT = 'purchaseOrderCounters';
const LEGACY_COMPANY_KEYS = ['chabely', 'acerpro'];
const TRACKED_ORDER_STATUSES = new Set([
  'pendingCompras',
  'cotizaciones',
  'authorizedGerencia',
  'paymentDone',
  'contabilidad',
]);

type PurchaseOrderCounterSummary = {
  status: string;
  requesterId: string;
  rejected: boolean;
  readyToSend: boolean;
};

export const createUserProfile = functions
  .region(REGION)
  .auth.user()
  .onCreate(async (user) => {
    const userRef = db.ref(`users/${user.uid}`);
    const snapshot = await userRef.get();
    if (snapshot.exists()) return;

    const emailPrefix = user.email?.split('@')[0];
    await userRef.set({
      name: user.displayName ?? emailPrefix ?? 'Usuario',
      email: user.email ?? '',
      role: 'usuario',
      areaId: 'por-definir',
      isActive: true,
      createdAt: admin.database.ServerValue.TIMESTAMP,
      updatedAt: admin.database.ServerValue.TIMESTAMP,
    });
  });

export const assignFolioAndCreateOrder = functions
  .region(REGION)
  .https.onCall(async (data, context) => {
    let stage = 'start';
    try {
      stage = 'auth';
      if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Debes iniciar sesion.');
      }

      stage = 'resolveUser';
      const actor = await resolveUserContext(context);

      stage = 'validateOrder';
      const orderData = data.order as OrderPayload | undefined;
      if (!orderData || !Array.isArray(orderData.items) || orderData.items.length == 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Faltan items.');
      }

      stage = 'buildOrder';
      const draftId = data.draftId as string | undefined;
      const uid = actor.uid;
      const requesterName = actor.name || orderData.requesterName;
      const areaId = actor.areaId || orderData.areaId;
      const areaName = actor.areaName || orderData.areaName || areaId;
      if (!areaId) {
        throw new functions.https.HttpsError('failed-precondition', 'Area requerida.');
      }

      stage = 'folio';
      const folio = await reserveNextFolio();

      stage = 'orderId';
      const orderId = folio;

      stage = 'writeOrder';
      const now = admin.database.ServerValue.TIMESTAMP;
      const orderRecord = {
        requesterId: orderData.requesterId,
        requesterName,
        areaId,
        areaName,
        urgency: orderData.urgency,
        clientNote: orderData.clientNote ?? null,
        items: orderData.items,
        status: 'pendingCompras',
        isDraft: false,
        lastReturnReason: null,
        updatedAt: now,
        createdAt: now,
        visibility: {
          contabilidad: false,
        },
      };

      const orderRef = db.ref(`purchaseOrders/${orderId}`);
      if (draftId && draftId !== orderId) {
        await db.ref().update({
          [`purchaseOrders/${orderId}`]: orderRecord,
          [`purchaseOrders/${draftId}`]: null,
        });
      } else {
        await orderRef.update(orderRecord);
      }

      stage = 'writeEvent';
      const eventRef = orderRef.child('events').push();
      await eventRef.set({
        fromStatus: 'draft',
        toStatus: 'pendingCompras',
        byUserId: uid,
        byRole: areaName || areaId || actor.role,
        timestamp: now,
        type: 'advance',
        itemsSnapshot: orderData.items,
      });

      const result = { orderId };

      try {
        stage = 'notifyArea';
        await notifyArea(
          AREA_COMPRAS,
          {
            title: 'Nueva requisicion',
            body: `Folio ${orderId} lista para revisar`,
          },
          { orderId: result.orderId }
        );
      } catch (error) {
        functions.logger.warn('notifyArea failed', {
          orderId: result.orderId,
          error: formatError(error),
        });
      }

      return result;
    } catch (error) {
      functions.logger.error('assignFolioAndCreateOrder failed', {
        uid: context.auth?.uid ?? null,
        stage,
        error: formatError(error),
        data: summarizeOrderRequest(data),
      });
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }
      throw new functions.https.HttpsError(
        'internal',
        `No se pudo crear la orden (${stage}): ${formatErrorMessage(error)}`,
        { stage }
      );
    }
  });

export const reservePurchaseOrderFolio = functions
  .region(REGION)
  .https.onCall(async (_data, context) => {
    try {
      if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Debes iniciar sesion.');
      }
      const folio = await peekNextFolio();
      return { folio };
    } catch (error) {
      functions.logger.error('reservePurchaseOrderFolio failed', {
        uid: context.auth?.uid ?? null,
        error: formatError(error),
      });
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }
      throw new functions.https.HttpsError(
        'internal',
        `No se pudo reservar el folio: ${formatErrorMessage(error)}`
      );
    }
  });

export const transitionStatus = functions
  .region(REGION)
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Debes iniciar sesiÃ³n.');
    }

    const orderId = data.orderId as string | undefined;
    const targetStatus = data.targetStatus as string | undefined;
    if (!orderId || !targetStatus) {
      throw new functions.https.HttpsError('invalid-argument', 'Datos incompletos.');
    }

    const actor = await resolveUserContext(context);
    const allowed = areaTransitions[actor.areaId] ?? [];
    if (!isAdminRole(actor.role) && !allowed.includes(targetStatus)) {
      throw new functions.https.HttpsError('permission-denied', 'Area sin permisos.');
    }

    const orderRef = db.ref(`purchaseOrders/${orderId}`);
    const snapshot = await orderRef.get();
    if (!snapshot.exists()) {
      throw new functions.https.HttpsError('not-found', 'Orden no encontrada.');
    }

    const currentStatus = (snapshot.val() as { status?: string } | null)?.status;
    const validTargets = allowedTransitions[currentStatus ?? ''] ?? [];
    if (!validTargets.includes(targetStatus)) {
      throw new functions.https.HttpsError('failed-precondition', 'TransiciÃ³n invÃ¡lida.');
    }

    const now = admin.database.ServerValue.TIMESTAMP;
    await orderRef.update({
      status: targetStatus,
      updatedAt: now,
    });
    const eventRef = orderRef.child('events').push();
    await eventRef.set({
      fromStatus: currentStatus ?? '',
      toStatus: targetStatus,
      byUserId: context.auth?.uid ?? '',
      byRole: actor.areaName || actor.areaId || actor.role,
      timestamp: now,
      type: 'advance',
    });
  });

export const returnToUser = functions
  .region(REGION)
  .https.onCall(async (data, context) => {
    let stage = 'start';
    try {
      stage = "auth";
      if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Debes iniciar sesi?n.');
      }

      stage = "validate";
      const orderId = data.orderId as string | undefined;
      const comment = (data.comment as string | undefined)?.trim();
      if (!orderId || !comment) {
        throw new functions.https.HttpsError('invalid-argument', 'Se requiere comentario.');
      }

      stage = "resolveUser";
      const actor = await resolveUserContext(context);

      stage = "fetchOrder";
      const orderRef = db.ref(`purchaseOrders/${orderId}`);
      const snapshot = await orderRef.get();
      if (!snapshot.exists()) {
        throw new functions.https.HttpsError('not-found', 'Orden no encontrada.');
      }

      const orderData = snapshot.val() as {
        requesterId?: string;
        status?: string;
        items?: unknown;
      } | null;
      const requesterId = orderData?.requesterId ?? '';
      if (!requesterId) {
        throw new functions.https.HttpsError('failed-precondition', 'No se encontr? solicitante.');
      }

      stage = "updateOrder";
      const now = admin.database.ServerValue.TIMESTAMP;
      await orderRef.update({
        status: 'draft',
        isDraft: true,
        lastReturnReason: comment,
        updatedAt: now,
      });

      stage = "writeEvent";
      const eventRef = orderRef.child("events").push();
      await eventRef.set({
        fromStatus: orderData?.status ?? '',
        toStatus: 'draft',
        byUserId: context.auth?.uid ?? '',
        byRole: actor.areaName || actor.areaId || actor.role,
        timestamp: now,
        type: 'return',
        comment,
        itemsSnapshot: orderData?.items ?? null,
      });

      stage = "notifyUser";
      try {
        await notifyUser(
          requesterId,
          {
            title: 'Orden requiere ajustes',
            body: comment,
          },
          { orderId }
        );
      } catch (error) {
        functions.logger.warn('notifyUser failed', {
          orderId,
          requesterId,
          error: formatError(error),
        });
      }
    } catch (error) {
      functions.logger.error('returnToUser failed', {
        uid: context.auth?.uid ?? null,
        stage,
        error: formatError(error),
      });
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }
      throw new functions.https.HttpsError(
        'internal',
        `No se pudo devolver la orden (${stage}): ${formatErrorMessage(error)}`
      );
    }
  });

export const syncPurchaseOrderCounters = functions
  .region(REGION)
  .database.ref('/purchaseOrders/{orderId}')
  .onWrite(async (change) => {
    const before = summarizePurchaseOrderForCounters(change.before.val());
    const after = summarizePurchaseOrderForCounters(change.after.val());
    const tasks: Promise<unknown>[] = [];

    if (before.status !== after.status) {
      if (before.status) {
        tasks.push(applyCounterDelta(statusCounterPath(before.status), -1));
      }
      if (after.status) {
        tasks.push(applyCounterDelta(statusCounterPath(after.status), 1));
      }
    }

    if (before.readyToSend !== after.readyToSend) {
      if (before.readyToSend) {
        tasks.push(applyCounterDelta(cotizacionesReadyCounterPath(), -1));
      }
      if (after.readyToSend) {
        tasks.push(applyCounterDelta(cotizacionesReadyCounterPath(), 1));
      }
    }

    const rejectedChanged =
      before.rejected !== after.rejected || before.requesterId !== after.requesterId;
    if (rejectedChanged) {
      if (before.rejected && before.requesterId) {
        tasks.push(applyCounterDelta(rejectedCounterPath(before.requesterId), -1));
      }
      if (after.rejected && after.requesterId) {
        tasks.push(applyCounterDelta(rejectedCounterPath(after.requesterId), 1));
      }
    }

    if (tasks.length == 0) {
      return null;
    }

    await Promise.all(tasks);
    return null;
  });

export const notifyRequesterWhenMaterialArrives = functions
  .region(REGION)
  .database.ref('/purchaseOrders/{orderId}')
  .onWrite(async (change, context) => {
    if (!change.after.exists()) {
      return null;
    }

    const before = (change.before.exists() ? change.before.val() : null) as {
      materialArrivedAt?: unknown;
      requesterReceivedAt?: unknown;
    } | null;
    const after = change.after.val() as {
      status?: unknown;
      requesterId?: unknown;
      materialArrivedAt?: unknown;
      requesterReceivedAt?: unknown;
    } | null;

    const afterStatus = typeof after?.status == 'string' ? after.status : '';
    const requesterId =
      typeof after?.requesterId == 'string' ? after.requesterId.trim() : '';
    const beforeMaterialArrived = before?.materialArrivedAt != null;
    const afterMaterialArrived = after?.materialArrivedAt != null;
    const alreadyReceived = after?.requesterReceivedAt != null;

    if (afterStatus != 'eta') {
      return null;
    }
    if (!afterMaterialArrived || beforeMaterialArrived) {
      return null;
    }
    if (!requesterId || alreadyReceived) {
      return null;
    }

    try {
      await notifyUser(
        requesterId,
        {
          title: 'Tu material ya llego',
          body: `La orden ${context.params.orderId} ya fue reportada como recibida. Revisa el detalle y confirma cuando te entreguen el material.`,
        },
        notificationData({
          orderId: String(context.params.orderId ?? ''),
          route: `/orders/${String(context.params.orderId ?? '')}`,
          type: 'material_arrived',
        })
      );
    } catch (error) {
      functions.logger.warn('notifyRequesterWhenMaterialArrives failed', {
        orderId: context.params.orderId ?? null,
        requesterId,
        error: formatError(error),
      });
    }

    return null;
  });

export const notifyStakeholdersOnOrderStatusChange = functions
  .region(REGION)
  .database.ref('/purchaseOrders/{orderId}')
  .onWrite(async (change, context) => {
    if (!change.after.exists()) {
      return null;
    }

    const before = (change.before.exists() ? change.before.val() : null) as {
      status?: unknown;
    } | null;
    const after = change.after.val() as {
      status?: unknown;
      requesterId?: unknown;
      etaDate?: unknown;
    } | null;

    const beforeStatus = typeof before?.status == 'string' ? before.status : '';
    const afterStatus = typeof after?.status == 'string' ? after.status : '';
    if (!afterStatus || beforeStatus == afterStatus) {
      return null;
    }

    const orderId = String(context.params.orderId ?? '').trim();
    const requesterId =
      typeof after?.requesterId == 'string' ? after.requesterId.trim() : '';
    const etaLabel = formatShortDate(after?.etaDate);

    try {
      switch (afterStatus) {
        case 'pendingCompras':
          if (!change.before.exists()) {
            return null;
          }
          await notifyArea(
            AREA_COMPRAS,
            {
              title: 'Orden pendiente en Compras',
              body: `Folio ${orderId} requiere revision nuevamente.`,
            },
            notificationData({
              orderId,
              route: '/orders/pending',
              type: 'order_pending_compras',
            })
          );
          return null;
        case 'paymentDone':
          await notifyArea(
            AREA_COMPRAS,
            {
              title: 'Orden pendiente de ETA',
              body: `Folio ${orderId} requiere registrar fecha estimada de entrega.`,
            },
            notificationData({
              orderId,
              route: '/orders/eta',
              type: 'order_pending_eta',
            })
          );
          return null;
        case 'contabilidad':
          await notifyArea(
            AREA_CONTABILIDAD,
            {
              title: 'Orden pendiente en Contabilidad',
              body: `Folio ${orderId} requiere registrar factura y cierre.`,
            },
            notificationData({
              orderId,
              route: '/orders/contabilidad',
              type: 'order_pending_accounting',
            })
          );
          if (requesterId) {
            await notifyUser(
              requesterId,
              {
                title: 'Tu orden sigue avanzando',
                body: etaLabel
                  ? `La orden ${orderId} ya entro a Contabilidad. Fecha estimada de entrega: ${etaLabel}.`
                  : `La orden ${orderId} ya entro a Contabilidad.`,
              },
              notificationData({
                orderId,
                route: `/orders/${orderId}`,
                type: 'order_in_accounting',
              })
            );
          }
          return null;
        default:
          return null;
      }
    } catch (error) {
      functions.logger.warn('notifyStakeholdersOnOrderStatusChange failed', {
        orderId: context.params.orderId ?? null,
        beforeStatus,
        afterStatus,
        error: formatError(error),
      });
      return null;
    }
  });

export const notifyStakeholdersOnQuoteStatusChange = functions
  .region(REGION)
  .database.ref('/supplierQuotes/{quoteId}')
  .onWrite(async (change, context) => {
    if (!change.after.exists()) {
      return null;
    }

    const before = (change.before.exists() ? change.before.val() : null) as {
      status?: unknown;
    } | null;
    const after = change.after.val() as {
      status?: unknown;
      supplier?: unknown;
      orderIds?: unknown;
      items?: unknown;
    } | null;

    const beforeStatus = typeof before?.status == 'string' ? before.status : '';
    const afterStatus = typeof after?.status == 'string' ? after.status : '';
    if (!afterStatus || beforeStatus == afterStatus) {
      return null;
    }

    const quoteId = String(context.params.quoteId ?? '').trim();
    const supplier = typeof after?.supplier == 'string' ? after.supplier.trim() : '';
    const supplierLabel = supplier || `Compra ${quoteId}`;
    const orderId = firstOrderIdFromQuote(after);

    try {
      switch (afterStatus) {
        case 'pendingDireccion':
          await notifyArea(
            AREA_GERENCIA,
            {
              title: 'Compra pendiente de autorizacion',
              body: `${supplierLabel} requiere revision en Direccion General.`,
            },
            notificationData({
              quoteId,
              orderId,
              route: quoteId
                  ? `/orders/direccion/cotizacion/${quoteId}`
                  : '/orders/direccion/dashboard',
              type: 'quote_pending_direccion',
            })
          );
          return null;
        case 'rejected':
          await notifyArea(
            AREA_COMPRAS,
            {
              title: 'Compra rechazada por Direccion General',
              body: `${supplierLabel} requiere ajustes para continuar.`,
            },
            notificationData({
              quoteId,
              orderId,
              route: '/orders/cotizaciones/dashboard',
              type: 'quote_rejected',
            })
          );
          return null;
        default:
          return null;
      }
    } catch (error) {
      functions.logger.warn('notifyStakeholdersOnQuoteStatusChange failed', {
        quoteId: context.params.quoteId ?? null,
        beforeStatus,
        afterStatus,
        error: formatError(error),
      });
      return null;
    }
  });

export const rebuildPurchaseOrderCounters = functions
  .region(REGION)
  .https.onCall(async (_data, context) => {
    await ensureAdmin(context);

    const snapshot = await db.ref('purchaseOrders').get();
    const raw = snapshot.exists() ? snapshot.val() : null;
    const counters = buildPurchaseOrderCounters(raw);

    await db.ref(PURCHASE_ORDER_COUNTERS_ROOT).set(counters);

    return {
      rebuilt: true,
      totalOrders: countPurchaseOrders(raw),
    };
  });

export const createUserWithRole = functions
  .region(REGION)
  .https.onCall(async (data, context) => {
    await ensureAdmin(context);

    const payload = (data ?? {}) as Partial<CreateUserPayload>;
    const name = asTrimmedString(payload.name);
    const email = asTrimmedString(payload.email);
    const password = typeof payload.password == 'string' ? payload.password : '';
    const areaId = asTrimmedString(payload.areaId);
    const rawRole = asTrimmedString(payload.role);
    const normalizedRole = rawRole.length > 0 ? normalizeRole(rawRole) : 'usuario';
    const role = normalizedRole == 'admin' ? 'administrador' : normalizedRole;
    const effectiveAreaId = role == 'administrador' ? AREA_SOFTWARE : areaId;

    if (!email) {
      throw new functions.https.HttpsError('invalid-argument', 'Correo requerido.');
    }
    if (!name) {
      throw new functions.https.HttpsError('invalid-argument', 'Nombre requerido.');
    }
    if (password.length < 6) {
      throw new functions.https.HttpsError('invalid-argument', 'Contrasena invalida.');
    }
    if (!effectiveAreaId) {
      throw new functions.https.HttpsError('invalid-argument', 'Area requerida.');
    }
    if (!allowedRoles.has(role)) {
      throw new functions.https.HttpsError('invalid-argument', 'Rol invalido.');
    }

    const areaName = await resolveAreaName(effectiveAreaId);
    const displayName = name || email.split('@')[0] || 'Usuario';
    await ensureUniqueUser(email, displayName);
    let createdUid: string | null = null;
    try {
      const userRecord = await admin.auth().createUser({
        email,
        password,
        displayName,
      });
      createdUid = userRecord.uid;
      await admin.auth().setCustomUserClaims(createdUid, { role });

      const now = admin.database.ServerValue.TIMESTAMP;
      await db.ref(`users/${createdUid}`).set({
        name: displayName,
        email,
        nameLower: displayName.toLowerCase(),
        emailLower: email.toLowerCase(),
        role,
        areaId: effectiveAreaId,
        areaName,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      });

      return { uid: createdUid };
    } catch (error) {
      if (isAuthEmailExists(error)) {
        throw new functions.https.HttpsError('already-exists', 'El correo ya existe.');
      }
      if (createdUid) {
        await admin.auth().deleteUser(createdUid).catch(() => null);
        await db.ref(`users/${createdUid}`).remove().catch(() => null);
      }
      throw new functions.https.HttpsError('internal', `No se pudo crear el usuario: ${String(error)}`);
    }
  });

export const seedAreas = functions
  .region(REGION)
  .https.onCall(async (_data, context) => {
    await ensureAdmin(context);
    return upsertDefaultAreas();
  });

export const deleteUserByUid = functions
  .region(REGION)
  .https.onCall(async (data, context) => {
    await ensureAdmin(context);

    const payload = (data ?? {}) as { uid?: unknown };
    const uid = asTrimmedString(payload.uid);
    if (!uid) {
      throw new functions.https.HttpsError('invalid-argument', 'UID requerido.');
    }
    if (uid == context.auth?.uid) {
      throw new functions.https.HttpsError('failed-precondition', 'No puedes eliminar tu propio usuario.');
    }

    try {
      await admin.auth().deleteUser(uid);
    } catch (error) {
      if (!isAuthUserNotFound(error)) {
        throw new functions.https.HttpsError('internal', `No se pudo eliminar en Auth: ${String(error)}`);
      }
    }

    await db.ref(`users/${uid}`).remove();
  });

async function notifyArea(areaId: string, notification: { title: string; body: string }, data?: Record<string, string>) {
  const snapshot = await db.ref('users').orderByChild('areaId').equalTo(areaId).get();
  if (!snapshot.exists()) return;

  const tokens: string[] = [];
  snapshot.forEach((child) => {
    const value = child.val() as { isActive?: boolean; fcmTokens?: unknown } | null;
    if (value?.isActive !== true) return;
    tokens.push(...extractTokens(value?.fcmTokens));
  });

  if (tokens.length === 0) return;

  await messaging.sendEachForMulticast({
    tokens,
    notification: {
      title: notification.title,
      body: notification.body,
    },
    data,
  });
}

async function notifyUser(uid: string, notification: { title: string; body: string }, data?: Record<string, string>) {
  const snapshot = await db.ref(`users/${uid}`).get();
  if (!snapshot.exists()) {
    return;
  }
  const value = snapshot.val() as { fcmTokens?: unknown } | null;
  const tokens = extractTokens(value?.fcmTokens);
  if (tokens.length === 0) return;

  await messaging.sendEachForMulticast({
    tokens,
    notification,
    data,
  });
}

function notificationData(
  values: Record<string, string | null | undefined>
): Record<string, string> | undefined {
  const entries = Object.entries(values).filter(
    (entry): entry is [string, string] => Boolean(entry[1] && entry[1].trim().length > 0)
  );
  if (entries.length === 0) {
    return undefined;
  }
  return Object.fromEntries(entries);
}

function formatShortDate(value: unknown): string {
  const date = asDate(value);
  if (!date) return '';
  const day = date.getDate().toString().padStart(2, '0');
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  const year = date.getFullYear().toString();
  return `${day}/${month}/${year}`;
}

function asDate(value: unknown): Date | null {
  if (typeof value == 'number' && Number.isFinite(value)) {
    return new Date(value);
  }
  if (typeof value == 'string') {
    const parsed = Date.parse(value);
    if (!Number.isNaN(parsed)) {
      return new Date(parsed);
    }
  }
  return null;
}

function firstOrderIdFromQuote(value: { orderIds?: unknown; items?: unknown } | null | undefined): string {
  for (const orderId of extractStringArray(value?.orderIds)) {
    if (orderId.trim().length > 0) {
      return orderId.trim();
    }
  }

  const rawItems = value?.items;
  if (Array.isArray(rawItems)) {
    for (const item of rawItems) {
      if (item && typeof item == 'object' && typeof (item as { orderId?: unknown }).orderId == 'string') {
        const orderId = (item as { orderId: string }).orderId.trim();
        if (orderId) return orderId;
      }
    }
  } else if (rawItems && typeof rawItems == 'object') {
    for (const item of Object.values(rawItems)) {
      if (item && typeof item == 'object' && typeof (item as { orderId?: unknown }).orderId == 'string') {
        const orderId = (item as { orderId: string }).orderId.trim();
        if (orderId) return orderId;
      }
    }
  }

  return '';
}

function extractStringArray(value: unknown): string[] {
  if (Array.isArray(value)) {
    return value
      .map((entry) => (typeof entry == 'string' ? entry.trim() : ''))
      .filter((entry) => entry.length > 0);
  }
  return [];
}

async function upsertDefaultAreas(): Promise<{ created: boolean; added: number }> {
  const areasRef = db.ref('areas');
  const snapshot = await areasRef.get();
  if (!snapshot.exists()) {
    await areasRef.set(defaultAreas);
    return { created: true, added: Object.keys(defaultAreas).length };
  }

  const raw = snapshot.val();
  if (!raw || typeof raw !== 'object') {
    await areasRef.set(defaultAreas);
    return { created: true, added: Object.keys(defaultAreas).length };
  }

  const existing = raw as Record<string, unknown>;
  const updates: Record<string, { name: string }> = {};
  for (const [id, value] of Object.entries(defaultAreas)) {
    if (!Object.prototype.hasOwnProperty.call(existing, id)) {
      updates[id] = value;
    }
  }

  const added = Object.keys(updates).length;
  if (added > 0) {
    await areasRef.update(updates);
  }
  return { created: false, added };
}

async function resolveAreaName(areaId: string): Promise<string> {
  const snapshot = await db.ref(`areas/${areaId}`).get();
  if (!snapshot.exists()) {
    throw new functions.https.HttpsError('invalid-argument', 'Area invalida.');
  }
  const value = snapshot.val() as { name?: unknown } | string | null;
  if (typeof value == 'string' && value.trim().length > 0) {
    return value.trim();
  }
  if (value && typeof value == 'object' && typeof value.name == 'string' && value.name.trim().length > 0) {
    return value.name.trim();
  }
  return areaId;
}

async function resolveUserContext(context: functions.https.CallableContext): Promise<UserContext> {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Debes iniciar sesion.');
  }

  const uid = context.auth.uid;
  let role = normalizeRole(context.auth.token.role as string | undefined);
  let areaId = '';
  let areaName = '';
  let name = '';
  let email = '';

  const snapshot = await db.ref(`users/${uid}`).get();
  if (snapshot.exists()) {
    const value = snapshot.val() as {
      role?: unknown;
      areaId?: unknown;
      areaName?: unknown;
      name?: unknown;
      email?: unknown;
    } | null;
    if (value && typeof value === 'object') {
      if (typeof value.role == 'string') {
        role = normalizeRole(value.role);
      }
      if (typeof value.areaId == 'string') {
        areaId = value.areaId;
      }
      if (typeof value.areaName == 'string') {
        areaName = value.areaName;
      }
      if (typeof value.name == 'string') {
        name = value.name;
      }
      if (typeof value.email == 'string') {
        email = value.email;
      }
    }
  }

  if (!areaName && areaId) {
    areaName = areaId;
  }

  return {
    uid,
    role,
    areaId,
    areaName,
    name,
    email,
  };
}

async function ensureUniqueUser(email: string, name: string): Promise<void> {
  try {
    await admin.auth().getUserByEmail(email);
    throw new functions.https.HttpsError('already-exists', 'El correo ya existe.');
  } catch (error) {
    if (!isAuthUserNotFound(error)) {
      throw new functions.https.HttpsError('internal', `No se pudo validar el correo: ${String(error)}`);
    }
  }

  const snapshot = await db.ref('users').get();
  if (!snapshot.exists()) return;
  const raw = snapshot.val();
  if (!raw || typeof raw !== 'object') return;

  const emailLower = email.toLowerCase();
  const nameLower = name.toLowerCase();
  const records = Object.values(raw as Record<string, Record<string, unknown>>);
  for (const record of records) {
    const recordEmail = typeof record.emailLower == 'string' && record.emailLower.length > 0
      ? record.emailLower
      : typeof record.email == 'string'
        ? record.email.toLowerCase()
        : '';
    if (recordEmail && recordEmail == emailLower) {
      throw new functions.https.HttpsError('already-exists', 'El correo ya existe.');
    }
    const recordName = typeof record.nameLower == 'string' && record.nameLower.length > 0
      ? record.nameLower
      : typeof record.name == 'string'
        ? record.name.toLowerCase()
        : '';
    if (recordName && recordName == nameLower) {
      throw new functions.https.HttpsError('already-exists', 'El nombre ya existe.');
    }
  }
}

async function ensureAdmin(context: functions.https.CallableContext): Promise<void> {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Debes iniciar sesion.');
  }

  let role = normalizeRole(context.auth.token.role as string | undefined);
  if (!isAdminRole(role)) {
    const snapshot = await db.ref(`users/${context.auth.uid}/role`).get();
    if (snapshot.exists()) {
      role = normalizeRole(snapshot.val() as string | undefined);
    }
  }

  if (!isAdminRole(role)) {
    throw new functions.https.HttpsError('permission-denied', 'Rol sin permisos.');
  }
}

function asTrimmedString(value: unknown): string {
  return typeof value == 'string' ? value.trim() : '';
}

function summarizePurchaseOrderForCounters(value: unknown): PurchaseOrderCounterSummary {
  if (!value || typeof value !== 'object') {
    return emptyPurchaseOrderCounterSummary();
  }

  const record = value as Record<string, unknown>;
  const status = normalizeTrackedStatus(record.status);
  const requesterId = asTrimmedString(record.requesterId);

  return {
    status,
    requesterId,
    rejected: isRejectedPurchaseOrder(record),
    readyToSend: isPurchaseOrderReadyToSend(record),
  };
}

function emptyPurchaseOrderCounterSummary(): PurchaseOrderCounterSummary {
  return {
    status: '',
    requesterId: '',
    rejected: false,
    readyToSend: false,
  };
}

function normalizeTrackedStatus(value: unknown): string {
  const status = asTrimmedString(value);
  return TRACKED_ORDER_STATUSES.has(status) ? status : '';
}

function isRejectedPurchaseOrder(order: Record<string, unknown>): boolean {
  const status = asTrimmedString(order.status);
  const reason = asTrimmedString(order.lastReturnReason);
  return status == 'draft' && reason.length > 0;
}

function isPurchaseOrderReadyToSend(order: Record<string, unknown>): boolean {
  if (asTrimmedString(order.status) != 'cotizaciones') {
    return false;
  }
  if (!hasQuoteLinks(order)) {
    return false;
  }

  const items = extractPurchaseOrderItems(order.items);
  if (items.length == 0) {
    return false;
  }

  return items.every((item) => item.supplier.length > 0 && item.budget > 0);
}

function hasQuoteLinks(order: Record<string, unknown>): boolean {
  const links = order.cotizacionLinks;
  if (Array.isArray(links)) {
    return links.some((entry) => {
      if (!entry || typeof entry !== 'object') return false;
      return asTrimmedString((entry as Record<string, unknown>).url).length > 0;
    });
  }

  if (links && typeof links === 'object') {
    return Object.values(links as Record<string, unknown>).some((entry) => {
      if (!entry || typeof entry !== 'object') return false;
      return asTrimmedString((entry as Record<string, unknown>).url).length > 0;
    });
  }

  const urls = extractStringList(order.cotizacionPdfUrls);
  if (urls.some((url) => url.length > 0)) {
    return true;
  }

  return asTrimmedString(order.cotizacionPdfUrl).length > 0;
}

function extractPurchaseOrderItems(value: unknown): Array<{ supplier: string; budget: number }> {
  if (Array.isArray(value)) {
    const items: Array<{ supplier: string; budget: number }> = [];
    for (const entry of value) {
      const item = summarizePurchaseOrderItem(entry);
      if (item) {
        items.push(item);
      }
    }
    return items;
  }

  if (value && typeof value === 'object') {
    const items: Array<{ supplier: string; budget: number }> = [];
    for (const entry of Object.values(value as Record<string, unknown>)) {
      const item = summarizePurchaseOrderItem(entry);
      if (item) {
        items.push(item);
      }
    }
    return items;
  }

  return [];
}

function summarizePurchaseOrderItem(value: unknown): { supplier: string; budget: number } | null {
  if (!value || typeof value !== 'object') {
    return null;
  }

  const record = value as Record<string, unknown>;
  return {
    supplier: asTrimmedString(record.supplier),
    budget: parseNumericValue(record.budget),
  };
}

function extractStringList(value: unknown): string[] {
  if (Array.isArray(value)) {
    return value.map(asTrimmedString).filter((entry) => entry.length > 0);
  }

  if (value && typeof value === 'object') {
    return Object.values(value as Record<string, unknown>)
      .map(asTrimmedString)
      .filter((entry) => entry.length > 0);
  }

  return [];
}

function parseNumericValue(value: unknown): number {
  if (typeof value == 'number') {
    return Number.isFinite(value) ? value : 0;
  }
  if (typeof value == 'string') {
    const parsed = Number(value.trim());
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function buildPurchaseOrderCounters(value: unknown): Record<string, unknown> {
  const status = Object.fromEntries(
    Array.from(TRACKED_ORDER_STATUSES).map((entry) => [entry, 0])
  ) as Record<string, number>;
  const rejectedByUser: Record<string, number> = {};
  let readyToSend = 0;

  if (value && typeof value === 'object') {
    for (const rawOrder of Object.values(value as Record<string, unknown>)) {
      const summary = summarizePurchaseOrderForCounters(rawOrder);
      if (summary.status) {
        status[summary.status] = (status[summary.status] ?? 0) + 1;
      }
      if (summary.readyToSend) {
        readyToSend += 1;
      }
      if (summary.rejected && summary.requesterId) {
        rejectedByUser[summary.requesterId] =
          (rejectedByUser[summary.requesterId] ?? 0) + 1;
      }
    }
  }

  return {
    status,
    cotizaciones: {
      readyToSend,
    },
    rejectedByUser,
  };
}

function countPurchaseOrders(value: unknown): number {
  if (!value || typeof value !== 'object') {
    return 0;
  }
  return Object.keys(value as Record<string, unknown>).length;
}

function statusCounterPath(status: string): string {
  return `${PURCHASE_ORDER_COUNTERS_ROOT}/status/${status}`;
}

function cotizacionesReadyCounterPath(): string {
  return `${PURCHASE_ORDER_COUNTERS_ROOT}/cotizaciones/readyToSend`;
}

function rejectedCounterPath(uid: string): string {
  return `${PURCHASE_ORDER_COUNTERS_ROOT}/rejectedByUser/${uid}`;
}

async function applyCounterDelta(path: string, delta: number): Promise<void> {
  if (delta == 0) return;

  await db.ref(path).transaction((current) => {
    const next = parseCounterValue(current) + delta;
    return next > 0 ? next : 0;
  });
}

function isAuthUserNotFound(error: unknown): boolean {
  return (
    typeof error == 'object' &&
    error != null &&
    'code' in error &&
    (error as { code?: string }).code == 'auth/user-not-found'
  );
}

function isAuthEmailExists(error: unknown): boolean {
  return (
    typeof error == 'object' &&
    error != null &&
    'code' in error &&
    (error as { code?: string }).code == 'auth/email-already-exists'
  );
}


function extractTokens(value: unknown): string[] {
  if (!value) return [];
  if (Array.isArray(value)) {
    return value.map((token) => token.toString()).filter(Boolean);
  }
  if (typeof value === 'object') {
    const entries = Object.entries(value as Record<string, unknown>);
    return entries
      .map(([key, raw]) => {
        if (typeof raw === 'string' && raw.length > 0) {
          return raw;
        }
        if (raw === true) {
          return key;
        }
        return null;
      })
      .filter((token): token is string => Boolean(token));
  }
  return [];
}

function normalizeRole(role?: string): string {
  return (role ?? 'usuario').toLowerCase().trim();
}

function isAdminRole(role: string): boolean {
  const normalized = normalizeRole(role);
  return normalized == 'administrador' || normalized == 'admin';
}


function summarizeOrderRequest(data: unknown): Record<string, unknown> {
  if (!data || typeof data !== 'object') {
    return { type: typeof data };
  }
  const payload = data as { draftId?: unknown; order?: OrderPayload };
  const order = payload.order;
  return {
    draftId: typeof payload.draftId === 'string' ? payload.draftId : null,
    requesterId: order?.requesterId ?? null,
    urgency: order?.urgency ?? null,
    itemCount: Array.isArray(order?.items) ? order?.items.length : 0,
  };
}

function formatError(error: unknown): Record<string, unknown> {
  if (error instanceof functions.https.HttpsError) {
    return { code: error.code, message: error.message, details: error.details };
  }
  if (error && typeof error === 'object') {
    return {
      name: 'name' in error ? String((error as { name?: unknown }).name) : 'Error',
      message: 'message' in error ? String((error as { message?: unknown }).message) : String(error),
      stack: 'stack' in error ? String((error as { stack?: unknown }).stack) : null,
    };
  }
  return { message: String(error) };
}

function formatErrorMessage(error: unknown): string {
  if (error instanceof functions.https.HttpsError) {
    return error.message;
  }
  if (error && typeof error === 'object' && 'message' in error) {
    return String((error as { message?: unknown }).message);
  }
  return String(error);
}

async function reserveNextFolio(): Promise<string> {
  const counterRef = db.ref(PURCHASE_ORDER_FOLIO_COUNTER);
  const currentSnapshot = await counterRef.get();
  const currentValue = parseCounterValue(currentSnapshot.val());
  const legacySeed = currentValue > 0 ? 0 : await resolveLegacyCounterMax();
  const counterResult = await counterRef.transaction((current) => {
    const base = parseCounterValue(current);
    const effective = base > 0 ? base : legacySeed;
    return effective + 1;
  });
  if (!counterResult.committed) {
    throw new functions.https.HttpsError('aborted', 'No se pudo reservar el folio.');
  }
  const nextValue = counterResult.snapshot.val();
  const current = parseCounterValue(nextValue);
  if (current <= 0) {
    throw new functions.https.HttpsError('internal', 'Folio invalido.');
  }
  return current.toString().padStart(6, '0');
}

async function peekNextFolio(): Promise<string> {
  const snapshot = await db.ref(PURCHASE_ORDER_FOLIO_COUNTER).get();
  const currentValue = parseCounterValue(snapshot.val());
  const effective = currentValue > 0 ? currentValue : await resolveLegacyCounterMax();
  return (effective + 1).toString().padStart(6, '0');
}

function parseCounterValue(raw: unknown): number {
  if (typeof raw === 'number') {
    return Number.isFinite(raw) ? Math.trunc(raw) : 0;
  }
  if (typeof raw === 'string') {
    const parsed = Number.parseInt(raw, 10);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

async function resolveLegacyCounterMax(): Promise<number> {
  const values = await Promise.all(
    LEGACY_COMPANY_KEYS.map(async (company) => {
      const snapshot = await db.ref(`counters/folios/${company}/purchaseOrderNext`).get();
      return parseCounterValue(snapshot.val());
    })
  );
  return values.reduce((max, value) => (value > max ? value : max), 0);
}

// TODO: generatePdfOnFinalState trigger based on status once plantilla estÃ© lista.

