import { get, push, ref, runTransaction, set, update } from "firebase/database";
import { database } from "@/lib/firebase/client";
import type {
  PacketBundleRecord,
  PacketDecisionAction,
  PacketItemRefRecord,
  PurchasePacketStatus,
  RequestOrderItemRecord,
  RequestOrderRecord,
} from "@/features/purchase-packets/packet-data";
import type { PurchaseOrderItem, PurchaseOrderRecord } from "@/features/orders/orders-data";
import type { AppUser } from "@/store/session-store";

function asString(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function asNumber(value: unknown) {
  if (typeof value === "number") return value;
  if (typeof value === "string") {
    const parsed = Number(value.trim());
    return Number.isFinite(parsed) ? parsed : undefined;
  }
  return undefined;
}

function buildPacketItemRefId(orderId: string, itemId: string) {
  return `${orderId}::${itemId}`;
}

function buildOperationId() {
  return `op_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
}

function packetPrefixFromEmail(email?: string) {
  return email?.toLowerCase().includes("acerpro") ? "ACE" : "CHA";
}

function mapLegacyOrder(rawOrder: PurchaseOrderRecord): RequestOrderRecord {
  return {
    id: rawOrder.id,
    requesterId: rawOrder.requesterId,
    requesterName: rawOrder.requesterName,
    areaId: rawOrder.areaId,
    areaName: rawOrder.areaName,
    urgency: rawOrder.urgency,
    status: "ready_for_approval",
    createdAt: rawOrder.createdAt,
    updatedAt: rawOrder.updatedAt,
    source: "legacy",
    items: rawOrder.items.map((item) => ({
      id: `line_${item.line}`,
      lineNumber: item.line,
      partNumber: item.partNumber,
      description: item.description,
      quantity: item.quantity,
      unit: item.unit,
      supplierName: item.supplier,
      estimatedAmount: item.budget,
      customer: item.customer,
      isClosed: false,
    })),
  };
}

async function fetchNewOrderById(orderId: string): Promise<RequestOrderRecord | null> {
  const orderSnapshot = await get(ref(database, `orders/${orderId}`));
  if (!orderSnapshot.exists() || typeof orderSnapshot.val() !== "object") {
    return null;
  }

  const orderData = orderSnapshot.val() as Record<string, unknown>;
  const itemSnapshot = await get(ref(database, `order_items/${orderId}`));
  const itemsNode =
    itemSnapshot.exists() && typeof itemSnapshot.val() === "object"
      ? (itemSnapshot.val() as Record<string, Record<string, unknown>>)
      : {};

  const items = Object.entries(itemsNode).map(([itemId, raw]) => ({
    id: asString(raw.itemId) || itemId,
    lineNumber: (asNumber(raw.lineNumber) ?? asNumber(raw.line) ?? 0) as number,
    partNumber: asString(raw.partNumber),
    description: asString(raw.description),
    quantity: asNumber(raw.quantity) ?? 0,
    unit: asString(raw.unit),
    supplierName: asString(raw.supplierName) || asString(raw.supplier) || undefined,
    estimatedAmount: asNumber(raw.estimatedAmount) ?? asNumber(raw.budget),
    customer: asString(raw.customer) || undefined,
    isClosed: raw.isClosed === true,
  }));

  return {
    id: orderId,
    requesterId: asString(orderData.requesterId),
    requesterName: asString(orderData.requesterName),
    areaId: asString(orderData.areaId),
    areaName: asString(orderData.areaName),
    urgency: asString(orderData.urgency) || "normal",
    status: (asString(orderData.status) || "draft") as RequestOrderRecord["status"],
    items,
    createdAt: asNumber(orderData.createdAt),
    updatedAt: asNumber(orderData.updatedAt),
    source: "new",
  };
}

async function ensureNewOrderMirror(order: RequestOrderRecord) {
  const orderRef = ref(database, `orders/${order.id}`);
  const snapshot = await get(orderRef);
  if (!snapshot.exists()) {
    await set(orderRef, {
      requesterId: order.requesterId,
      requesterName: order.requesterName,
      areaId: order.areaId,
      areaName: order.areaName,
      urgency: order.urgency,
      status: order.status,
      createdAt: order.createdAt ?? Date.now(),
      updatedAt: order.updatedAt ?? Date.now(),
      projection: {},
      source: order.source,
    });
  }

  for (const item of order.items) {
    await set(ref(database, `order_items/${order.id}/${item.id}`), {
      itemId: item.id,
      lineNumber: item.lineNumber,
      partNumber: item.partNumber,
      description: item.description,
      quantity: item.quantity,
      unit: item.unit,
      supplierName: item.supplierName ?? null,
      estimatedAmount: item.estimatedAmount ?? null,
      customer: item.customer ?? null,
      isClosed: item.isClosed,
    });
  }
}

async function updateNewOrderMirrorStatus(
  orderIds: Iterable<string>,
  status: RequestOrderRecord["status"],
) {
  const now = Date.now();

  for (const orderId of new Set(orderIds)) {
    const orderRef = ref(database, `orders/${orderId}`);
    const snapshot = await get(orderRef);
    if (!snapshot.exists() || typeof snapshot.val() !== "object") {
      continue;
    }

    await update(orderRef, {
      status,
      updatedAt: now,
    });
  }
}

async function collectPacketAssignmentsByItemRefId() {
  const snapshot = await get(ref(database, "packet_items"));
  if (!snapshot.exists() || typeof snapshot.val() !== "object") {
    return new Map<string, string[]>();
  }

  const packetItemsNode = snapshot.val() as Record<string, Record<string, Record<string, unknown>>>;
  const assignments = new Map<string, string[]>();

  for (const [packetId, packetItems] of Object.entries(packetItemsNode)) {
    if (!packetItems || typeof packetItems !== "object") continue;

    for (const [itemRefId, rawItem] of Object.entries(packetItems)) {
      if (!rawItem || typeof rawItem !== "object") continue;
      const data = rawItem as Record<string, unknown>;
      const effectiveItemRefId =
        asString(data.itemRefId) || itemRefId;

      if (!effectiveItemRefId) continue;

      const current = assignments.get(effectiveItemRefId) ?? [];
      current.push(packetId);
      assignments.set(effectiveItemRefId, current);
    }
  }

  return assignments;
}

async function fetchReadyOrderById(
  orderId: string,
  legacyOrdersById: Record<string, PurchaseOrderRecord>,
): Promise<RequestOrderRecord> {
  const newOrder = await fetchNewOrderById(orderId);
  if (newOrder) {
    return newOrder;
  }

  const legacy = legacyOrdersById[orderId];
  if (!legacy) {
    throw new Error(`No existe la orden ${orderId}.`);
  }

  return mapLegacyOrder(legacy);
}

async function reserveNextGeneralQuoteFolio(actor: AppUser) {
  const counterRef = ref(database, "counters/folios/generalQuoteNext");
  const result = await runTransaction(counterRef, (current) => {
    const value = typeof current === "number" ? current : Number(current ?? 0) || 0;
    return value + 1;
  });

  const nextValue =
    typeof result.snapshot.val() === "number"
      ? result.snapshot.val()
      : Number(result.snapshot.val() ?? 0) || 0;

  if (!result.committed || nextValue <= 0) {
    throw new Error("No se pudo reservar el folio de cotizacion general.");
  }

  return `${packetPrefixFromEmail(actor.email)}-PP-${String(nextValue).padStart(6, "0")}`;
}

async function updateLegacyOrdersStatus(
  orderIds: Iterable<string>,
  status: string,
  actor: AppUser,
  eventType: "advance" | "return",
  comment?: string,
) {
  for (const orderId of new Set(orderIds)) {
    const orderRef = ref(database, `purchaseOrders/${orderId}`);
    const snapshot = await get(orderRef);
    if (!snapshot.exists() || typeof snapshot.val() !== "object") continue;
    const order = snapshot.val() as Record<string, unknown>;
    const durations = { ...(typeof order.statusDurations === "object" && order.statusDurations ? (order.statusDurations as Record<string, number>) : {}) };
    const currentStatus = asString(order.status);
    const enteredAt =
      asNumber(order.statusEnteredAt) ?? asNumber(order.updatedAt) ?? asNumber(order.createdAt) ?? Date.now();
    durations[currentStatus] = (durations[currentStatus] ?? 0) + Math.max(Date.now() - enteredAt, 0);

    await update(orderRef, {
      status,
      updatedAt: Date.now(),
      statusEnteredAt: Date.now(),
      statusDurations: durations,
    });

    await push(ref(database, `purchaseOrders/${orderId}/events`), {
      fromStatus: currentStatus || null,
      toStatus: status,
      byUserId: actor.id,
      byRole: actor.areaDisplay || actor.role,
      timestamp: Date.now(),
      type: eventType,
      comment: comment?.trim() || null,
    });
  }
}

function buildDecisionPayload(
  actor: AppUser,
  packetId: string,
  action: PacketDecisionAction,
  reason?: string,
  affectedItemRefIds: string[] = [],
) {
  return {
    packetId,
    action,
    actorId: actor.id,
    actorName: actor.name,
    actorArea: actor.areaDisplay,
    timestamp: Date.now(),
    reason: reason?.trim() || null,
    affectedItemRefIds,
  };
}

function statusTimingUpdate(order: PurchaseOrderRecord) {
  const enteredAt = order.statusEnteredAt ?? order.updatedAt ?? order.createdAt ?? Date.now();
  const durations = { ...order.statusDurations };
  durations[order.status] = (durations[order.status] ?? 0) + Math.max(Date.now() - enteredAt, 0);
  return {
    statusDurations: durations,
    statusEnteredAt: Date.now(),
  };
}

function resolveLegacyOrderNextState(items: PurchaseOrderItem[], fallbackStatus: string) {
  if (!items.length) return fallbackStatus;
  const allResolved = items.every((item) => item.isResolved);
  return allResolved ? "eta" : fallbackStatus;
}

export async function createPacketFromReadyOrders(input: {
  actor: AppUser;
  supplierName: string;
  totalAmount: number;
  evidenceUrls: string[];
  itemRefIds: string[];
  legacyOrdersById: Record<string, PurchaseOrderRecord>;
}) {
  const supplierName = input.supplierName.trim();
  if (!supplierName) {
    throw new Error("Proveedor requerido.");
  }
  if (!input.itemRefIds.length) {
    throw new Error("Selecciona al menos un item.");
  }

  const packetAssignmentsByItemRefId = await collectPacketAssignmentsByItemRefId();
  const hydratedRefs: PacketItemRefRecord[] = [];
  const affectedOrders = new Map<string, RequestOrderRecord>();

  for (const refId of [...new Set(input.itemRefIds)]) {
    const separator = refId.indexOf("::");
    if (separator <= 0 || separator >= refId.length - 2) {
      throw new Error(`Referencia invalida ${refId}.`);
    }

    const orderId = refId.slice(0, separator);
    const itemId = refId.slice(separator + 2);
    const order =
      affectedOrders.get(orderId) ??
      (await fetchReadyOrderById(orderId, input.legacyOrdersById));
    affectedOrders.set(orderId, order);

    if (order.status !== "ready_for_approval") {
      throw new Error(`La orden ${orderId} no esta lista para agrupacion.`);
    }

    const item = order.items.find((candidate) => candidate.id === itemId);
    if (!item) {
      throw new Error(`No existe el item ${itemId} en la orden ${orderId}.`);
    }
    if (item.isClosed) {
      throw new Error(`El item ${itemId} de la orden ${orderId} ya esta cerrado.`);
    }

    const packetAssignments = packetAssignmentsByItemRefId.get(refId) ?? [];
    if (packetAssignments.length > 0) {
      throw new Error(
        `El item ${itemId} de la orden ${orderId} ya pertenece a otro paquete.`,
      );
    }

    hydratedRefs.push({
      id: buildPacketItemRefId(orderId, item.id),
      orderId,
      itemId: item.id,
      lineNumber: item.lineNumber,
      description: item.description,
      quantity: item.quantity,
      unit: item.unit,
      amount: item.estimatedAmount,
      closedAsUnpurchasable: false,
    });
  }

  for (const order of affectedOrders.values()) {
    await ensureNewOrderMirror(order);
  }

  const packetRef = push(ref(database, "packets"));
  const packetId = packetRef.key ?? buildOperationId();
  const now = Date.now();
  const packetPayload = {
    supplierName,
    status: "draft" as PurchasePacketStatus,
    version: 1,
    totalAmount: input.totalAmount,
    evidenceUrls: input.evidenceUrls.map((url) => url.trim()).filter(Boolean),
    createdAt: now,
    updatedAt: now,
    createdBy: input.actor.id,
  };

  await set(packetRef, packetPayload);
  for (const itemRef of hydratedRefs) {
    await set(ref(database, `packet_items/${packetId}/${itemRef.id}`), {
      itemRefId: itemRef.id,
      orderId: itemRef.orderId,
      itemId: itemRef.itemId,
      lineNumber: itemRef.lineNumber,
      description: itemRef.description,
      quantity: itemRef.quantity,
      unit: itemRef.unit,
      amount: itemRef.amount ?? null,
      closedAsUnpurchasable: false,
    });
  }

  return packetId;
}

export async function createAndSubmitPacketFromReadyOrders(input: {
  actor: AppUser;
  supplierName: string;
  totalAmount: number;
  evidenceUrls: string[];
  itemRefIds: string[];
  legacyOrdersById: Record<string, PurchaseOrderRecord>;
}) {
  const packetId = await createPacketFromReadyOrders(input);
  const folio = await reserveNextGeneralQuoteFolio(input.actor);
  const now = Date.now();

  await update(ref(database, `packets/${packetId}`), {
    status: "approval_queue",
    version: 2,
    updatedAt: now,
    submittedAt: now,
    submittedBy: input.actor.id,
    folio,
  });

  const affectedOrderIds = input.itemRefIds
    .map((itemRefId) => itemRefId.split("::")[0]?.trim())
    .filter(Boolean) as string[];

  await updateLegacyOrdersStatus(affectedOrderIds, "approvalQueue", input.actor, "advance");
  await updateNewOrderMirrorStatus(affectedOrderIds, "approval_queue");

  return { packetId, folio };
}

export async function submitPacketForExecutiveApproval(bundle: PacketBundleRecord, actor: AppUser) {
  if (bundle.packet.status === "approval_queue") {
    throw new Error("El paquete ya fue enviado a aprobacion ejecutiva.");
  }

  const folio = bundle.packet.folio?.trim() || (await reserveNextGeneralQuoteFolio(actor));
  await update(ref(database, `packets/${bundle.packet.id}`), {
    status: "approval_queue",
    version: bundle.packet.version + 1,
    updatedAt: Date.now(),
    submittedAt: Date.now(),
    submittedBy: actor.id,
    folio,
  });

  await updateLegacyOrdersStatus(
    bundle.packet.itemRefs.map((item) => item.orderId),
    "approvalQueue",
    actor,
    "advance",
  );
  await updateNewOrderMirrorStatus(
    bundle.packet.itemRefs.map((item) => item.orderId),
    "approval_queue",
  );
}

export async function approvePacket(bundle: PacketBundleRecord, actor: AppUser) {
  if (bundle.packet.status !== "approval_queue") {
    throw new Error("Solo se pueden aprobar paquetes en aprobacion ejecutiva.");
  }

  await update(ref(database, `packets/${bundle.packet.id}`), {
    status: "execution_ready",
    version: bundle.packet.version + 1,
    updatedAt: Date.now(),
  });
  const decisionId = push(ref(database, `packet_decisions/${bundle.packet.id}`)).key ?? buildOperationId();
  await set(
    ref(database, `packet_decisions/${bundle.packet.id}/${decisionId}`),
    buildDecisionPayload(actor, bundle.packet.id, "approve"),
  );

  await updateLegacyOrdersStatus(
    bundle.packet.itemRefs.map((item) => item.orderId),
    "paymentDone",
    actor,
    "advance",
    "Todos los paquetes del proveedor fueron aprobados por Direccion General.",
  );
  await updateNewOrderMirrorStatus(
    bundle.packet.itemRefs.map((item) => item.orderId),
    "execution_ready",
  );
}

export async function returnPacketForRework(
  bundle: PacketBundleRecord,
  actor: AppUser,
  reason: string,
) {
  if (bundle.packet.status !== "approval_queue") {
    throw new Error("Solo se pueden regresar paquetes en aprobacion ejecutiva.");
  }

  const trimmedReason = reason.trim();
  if (!trimmedReason) {
    throw new Error("Motivo requerido para regresar el paquete.");
  }

  await update(ref(database, `packets/${bundle.packet.id}`), {
    status: "draft",
    version: bundle.packet.version + 1,
    updatedAt: Date.now(),
  });
  const decisionId = push(ref(database, `packet_decisions/${bundle.packet.id}`)).key ?? buildOperationId();
  await set(
    ref(database, `packet_decisions/${bundle.packet.id}/${decisionId}`),
    buildDecisionPayload(actor, bundle.packet.id, "return_for_rework", trimmedReason),
  );

  await updateLegacyOrdersStatus(
    bundle.packet.itemRefs.map((item) => item.orderId),
    "sourcing",
    actor,
    "return",
    trimmedReason,
  );
  await updateNewOrderMirrorStatus(
    bundle.packet.itemRefs.map((item) => item.orderId),
    "sourcing",
  );
}

export async function closePacketItemsAsUnpurchasable(
  bundle: PacketBundleRecord,
  actor: AppUser,
  itemRefIds: string[],
  reason: string,
  legacyOrdersById: Record<string, PurchaseOrderRecord>,
) {
  if (bundle.packet.status !== "approval_queue") {
    throw new Error("Solo se pueden cerrar items en paquetes en aprobacion ejecutiva.");
  }

  const trimmedReason = reason.trim();
  if (!trimmedReason) {
    throw new Error("Motivo requerido para cierre sin compra.");
  }

  const targetIds = [...new Set(itemRefIds.map((item) => item.trim()).filter(Boolean))];
  if (!targetIds.length) {
    throw new Error("Selecciona al menos un item para cerrar.");
  }

  const packetItemMap = new Map(bundle.packet.itemRefs.map((item) => [item.id, item]));
  for (const itemRefId of targetIds) {
    if (!packetItemMap.has(itemRefId)) {
      throw new Error(`El paquete no contiene la referencia ${itemRefId}.`);
    }
    await update(ref(database, `packet_items/${bundle.packet.id}/${itemRefId}`), {
      closedAsUnpurchasable: true,
    });
  }

  const decisionId =
    push(ref(database, `packet_decisions/${bundle.packet.id}`)).key ?? buildOperationId();
  await set(
    ref(database, `packet_decisions/${bundle.packet.id}/${decisionId}`),
    buildDecisionPayload(actor, bundle.packet.id, "close_unpurchasable", trimmedReason, targetIds),
  );

  const selectedByOrderId = new Map<string, Set<number>>();
  for (const itemRefId of targetIds) {
    const itemRef = packetItemMap.get(itemRefId);
    if (!itemRef) continue;
    if (!selectedByOrderId.has(itemRef.orderId)) {
      selectedByOrderId.set(itemRef.orderId, new Set<number>());
    }
    selectedByOrderId.get(itemRef.orderId)?.add(itemRef.lineNumber);
  }

  const normalizedName = actor.name.trim() || actor.id;
  const normalizedArea = actor.areaDisplay.trim();
  const markedAt = Date.now();

  for (const [orderId, lines] of selectedByOrderId.entries()) {
    const order = legacyOrdersById[orderId];
    if (!order) continue;

    const nextItems = order.items.map((item) => {
      if (!lines.has(item.line) || item.isNotPurchased) {
        return item;
      }
      return {
        ...item,
        notPurchasedAt: markedAt,
        notPurchasedByName: normalizedName,
        notPurchasedByArea: normalizedArea || undefined,
        notPurchasedReason: trimmedReason,
        isNotPurchased: true,
        requiresFulfillment: false,
        isResolved: true,
      };
    });

    const nextStatus = resolveLegacyOrderNextState(nextItems, order.status);
    const payload: Record<string, unknown> = {
      items: nextItems,
      updatedAt: Date.now(),
    };

    if (nextStatus !== order.status) {
      payload.status = nextStatus;
      payload.completedAt = Date.now();
      Object.assign(payload, statusTimingUpdate(order));
    }

    await update(ref(database, `purchaseOrders/${orderId}`), payload);
    await push(ref(database, `purchaseOrders/${orderId}/events`), {
      fromStatus: order.status,
      toStatus: nextStatus,
      byUserId: actor.id,
      byRole: actor.areaDisplay || actor.role,
      timestamp: Date.now(),
      type: "close_unpurchasable",
      comment: `${lines.size} item(s) cerrados sin compra. ${trimmedReason}`,
      itemsSnapshot: nextItems,
    });
  }

  const packetItemsSnapshot = await get(ref(database, `packet_items/${bundle.packet.id}`));
  const packetItemsNode =
    packetItemsSnapshot.exists() && typeof packetItemsSnapshot.val() === "object"
      ? (packetItemsSnapshot.val() as Record<string, Record<string, unknown>>)
      : {};
  const allClosed = Object.values(packetItemsNode).every(
    (item) => item.closedAsUnpurchasable === true,
  );

  await update(ref(database, `packets/${bundle.packet.id}`), {
    status: allClosed ? "completed" : bundle.packet.status,
    version: bundle.packet.version + 1,
    updatedAt: Date.now(),
  });
}
