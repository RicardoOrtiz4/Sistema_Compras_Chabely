import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';

type OrderPayload = {
  requesterId: string;
  requesterName: string;
  areaId: string;
  areaName: string;
  urgency: string;
  clientNote?: string | null;
  items: admin.firestore.DocumentData[];
};

type AllowedTransitions = Record<string, string[]>;

type RoleTransitions = Record<string, string[]>;

admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();

const allowedTransitions: AllowedTransitions = {
  draft: ['pendingCompras'],
  pendingCompras: ['authorizedGerencia'],
  authorizedGerencia: ['paymentDone'],
  paymentDone: ['orderPlaced'],
  orderPlaced: ['eta'],
};

const roleTransitions: RoleTransitions = {
  administrador: ['pendingCompras', 'authorizedGerencia', 'paymentDone', 'orderPlaced', 'eta'],
  compras: ['authorizedGerencia'],
  gerencia: ['paymentDone'],
  contabilidad: ['orderPlaced', 'eta'],
};

const REGION = 'us-central1';

export const assignFolioAndCreateOrder = functions
  .region(REGION)
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Debes iniciar sesi�n.');
    }

    const orderData = data.order as OrderPayload | undefined;
    if (!orderData || !Array.isArray(orderData.items) || orderData.items.length == 0) {
      throw new functions.https.HttpsError('invalid-argument', 'Faltan items.');
    }

    const draftId = data.draftId as string | undefined;
    const uid = context.auth.uid;
    const role = (context.auth.token.role as string | undefined) ?? 'usuario';

    const counterRef = db.collection('counters').doc('folios');
    const ordersRef = db.collection('purchaseOrders');

    const result = await db.runTransaction(async (transaction) => {
      const counterSnap = await transaction.get(counterRef);
      const current = (counterSnap.data()?.purchaseOrderNext as number | undefined) ?? 1;
      const nextValue = current + 1;
      transaction.set(counterRef, { purchaseOrderNext: nextValue }, { merge: true });

      const folio = current.toString().padStart(6, '0');
      const orderRef = draftId ? ordersRef.doc(draftId) : ordersRef.doc();
      const now = admin.firestore.FieldValue.serverTimestamp();

      const orderRecord = {
        ...orderData,
        folio,
        status: 'pendingCompras',
        isDraft: false,
        lastReturnReason: admin.firestore.FieldValue.delete(),
        updatedAt: now,
        createdAt: createdAtValue,
        visibility: {
          contabilidad: false,
        },
      };

      transaction.set(orderRef, orderRecord, { merge: true });

      const eventRef = orderRef.collection('events').doc();
      transaction.set(eventRef, {
        fromStatus: 'draft',
        toStatus: 'pendingCompras',
        byUserId: uid,
        byRole: role,
        timestamp: now,
        type: 'advance',
      });

      return { orderId: orderRef.id, folio };
    });

    await notifyRole('compras', {
      title: 'Nueva requisici�n',
      body: `Folio ${result.folio} lista para revisar`,
    },
    { orderId: result.orderId });

    return result;
  });

export const transitionStatus = functions
  .region(REGION)
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Debes iniciar sesi�n.');
    }

    const orderId = data.orderId as string | undefined;
    const targetStatus = data.targetStatus as string | undefined;
    if (!orderId || !targetStatus) {
      throw new functions.https.HttpsError('invalid-argument', 'Datos incompletos.');
    }

    const role = (context.auth.token.role as string | undefined) ?? 'usuario';
    const allowed = roleTransitions[role] ?? [];
    if (!allowed.includes(targetStatus) && role != 'administrador') {
      throw new functions.https.HttpsError('permission-denied', 'Rol sin permisos.');
    }

    const orderRef = db.collection('purchaseOrders').doc(orderId);

    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(orderRef);
      if (!snapshot.exists) {
        throw new functions.https.HttpsError('not-found', 'Orden no encontrada.');
      }
      const currentStatus = snapshot.data()?.status as string;
      const validTargets = allowedTransitions[currentStatus] ?? [];
      if (!validTargets.includes(targetStatus)) {
        throw new functions.https.HttpsError('failed-precondition', 'Transici�n inv�lida.');
      }

      const now = admin.firestore.FieldValue.serverTimestamp();
      transaction.update(orderRef, {
        status: targetStatus,
        updatedAt: now,
      });
      const eventRef = orderRef.collection('events').doc();
      transaction.set(eventRef, {
        fromStatus: currentStatus,
        toStatus: targetStatus,
        byUserId: context.auth?.uid,
        byRole: role,
        timestamp: now,
        type: 'advance',
      });
    });
  });

export const returnToUser = functions
  .region(REGION)
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Debes iniciar sesi�n.');
    }

    const orderId = data.orderId as string | undefined;
    const comment = (data.comment as string | undefined)?.trim();
    if (!orderId || !comment) {
      throw new functions.https.HttpsError('invalid-argument', 'Se requiere comentario.');
    }

    const orderRef = db.collection('purchaseOrders').doc(orderId);

    const requesterId = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(orderRef);
      if (!snapshot.exists) {
        throw new functions.https.HttpsError('not-found', 'Orden no encontrada.');
      }

      transaction.update(orderRef, {
        status: 'draft',
        isDraft: true,
        lastReturnReason: comment,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      const eventRef = orderRef.collection('events').doc();
      transaction.set(eventRef, {
        fromStatus: snapshot.data()?.status,
        toStatus: 'draft',
        byUserId: context.auth?.uid,
        byRole: (context.auth?.token.role as string | undefined) ?? 'usuario',
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        type: 'return',
        comment,
      });

      return snapshot.data()?.requesterId as string;
    });

    await notifyUser(requesterId, {
      title: 'Orden requiere ajustes',
      body: comment,
    },
    { orderId });
  });

async function notifyRole(role: string, notification: { title: string; body: string }, data?: Record<string, string>) {
  const query = await db
    .collection('users')
    .where('role', '==', role)
    .where('isActive', '==', true)
    .get();
  const tokens = query.docs
    .map((doc) => doc.data().fcmTokens as string[] | undefined)
    .flat()
    .filter((token): token is string => Boolean(token));

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
  const doc = await db.collection('users').doc(uid).get();
  if (!doc.exists) {
    return;
  }
  const tokens = (doc.data()?.fcmTokens as string[] | undefined) ?? [];
  if (tokens.length === 0) return;

  await messaging.sendEachForMulticast({
    tokens,
    notification,
    data,
  });
}

// TODO: generatePdfOnFinalState trigger based on status once plantilla est� lista.
