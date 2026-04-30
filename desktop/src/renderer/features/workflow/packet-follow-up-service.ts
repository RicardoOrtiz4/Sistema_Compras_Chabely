import { get, push, ref, serverTimestamp, update } from "firebase/database";
import { database } from "@/lib/firebase/client";
import type { PacketBundleRecord } from "@/features/purchase-packets/packet-data";
import type { PurchaseOrderItem, PurchaseOrderRecord } from "@/features/orders/orders-data";
import { sanitizeForFirebase } from "@/lib/firebase/sanitize";
import type { AppUser } from "@/store/session-store";

type TimingUpdate = {
  statusDurations: Record<string, number>;
  statusEnteredAt: number;
};

function actorRoleLabel(actor: AppUser) {
  return actor.areaDisplay.trim() || actor.role.trim() || actor.id;
}

function statusTimingUpdate(order: PurchaseOrderRecord): TimingUpdate {
  const now = Date.now();
  const enteredAt = order.statusEnteredAt ?? order.updatedAt ?? order.createdAt ?? now;
  const elapsed = Math.max(now - enteredAt, 0);
  const nextDurations = { ...order.statusDurations };
  nextDurations[order.status] = (nextDurations[order.status] ?? 0) + elapsed;

  return {
    statusDurations: nextDurations,
    statusEnteredAt: now,
  };
}

async function appendEvent(
  orderId: string,
  input: {
    fromStatus?: string;
    toStatus?: string | null;
    byUserId: string;
    byRole: string;
    type: string;
    comment?: string;
    itemsSnapshot?: PurchaseOrderItem[];
  },
) {
  const payload: Record<string, unknown> = {
    fromStatus: input.fromStatus ?? null,
    toStatus: input.toStatus ?? null,
    byUserId: input.byUserId,
    byRole: input.byRole,
    timestamp: serverTimestamp(),
    type: input.type,
  };

  const trimmedComment = input.comment?.trim();
  if (trimmedComment) {
    payload.comment = trimmedComment;
  }

  if (input.itemsSnapshot) {
    payload.itemsSnapshot = sanitizeForFirebase(input.itemsSnapshot);
  }

  await push(ref(database, `purchaseOrders/${orderId}/events`), payload);
}

function dedupeLinks(...groups: string[][]) {
  return [...new Set(groups.flatMap((group) => group.map((item) => item.trim()).filter(Boolean)))];
}

function withUpdatedItems(
  order: PurchaseOrderRecord,
  itemLines: Set<number>,
  mutate: (item: PurchaseOrderItem) => PurchaseOrderItem,
) {
  let changedCount = 0;
  const items = order.items.map((item) => {
    if (!itemLines.has(item.line)) {
      return item;
    }
    const nextItem = mutate(item);
    if (nextItem !== item) {
      changedCount += 1;
    }
    return nextItem;
  });

  return { items, changedCount };
}

async function syncLinkedPacketStatuses(orderIds: Iterable<string>) {
  const orderIdSet = new Set([...orderIds].filter(Boolean));
  if (!orderIdSet.size) return;

  const [packetItemsSnapshot, packetsSnapshot, ordersSnapshot] = await Promise.all([
    get(ref(database, "packet_items")),
    get(ref(database, "packets")),
    get(ref(database, "purchaseOrders")),
  ]);

  const packetItemsNode = (packetItemsSnapshot.val() ?? {}) as Record<
    string,
    Record<string, Record<string, unknown>>
  >;
  const packetsNode = (packetsSnapshot.val() ?? {}) as Record<string, Record<string, unknown>>;
  const ordersNode = (ordersSnapshot.val() ?? {}) as Record<string, Record<string, unknown>>;

  const candidatePacketIds = new Set<string>();
  for (const [packetId, items] of Object.entries(packetItemsNode)) {
    for (const item of Object.values(items ?? {})) {
      const packetOrderId = typeof item.orderId === "string" ? item.orderId.trim() : "";
      if (orderIdSet.has(packetOrderId)) {
        candidatePacketIds.add(packetId);
      }
    }
  }

  for (const packetId of candidatePacketIds) {
    const packet = packetsNode[packetId];
    if (!packet) continue;

    const packetItems = Object.values(packetItemsNode[packetId] ?? {});
    if (!packetItems.length) continue;

    const isComplete = packetItems.every((packetItem) => {
      if (packetItem.closedAsUnpurchasable === true) return true;
      const orderId = typeof packetItem.orderId === "string" ? packetItem.orderId.trim() : "";
      const lineNumber =
        typeof packetItem.lineNumber === "number"
          ? packetItem.lineNumber
          : Number(packetItem.lineNumber ?? packetItem.itemId?.toString().replace("line_", ""));

      const order = ordersNode[orderId];
      const rawItems = Array.isArray(order?.items)
        ? order.items
        : order?.items && typeof order.items === "object"
          ? Object.values(order.items as Record<string, unknown>)
          : [];
      const matchingItem = rawItems.find((raw) => {
        if (!raw || typeof raw !== "object") return false;
        const data = raw as Record<string, unknown>;
        return Number(data.line ?? 0) === lineNumber;
      });
      if (!matchingItem || typeof matchingItem !== "object") return false;
      const data = matchingItem as Record<string, unknown>;
      return Boolean(data.arrivedAt) || Boolean(data.notPurchasedAt);
    });

    if (isComplete && packet.status !== "completed") {
      await update(ref(database, `packets/${packetId}`), {
        status: "completed",
        updatedAt: serverTimestamp(),
      });
    }
  }
}

export async function registerEtaForOrderItems(
  order: PurchaseOrderRecord,
  itemLines: Set<number>,
  etaDate: Date,
  actor: AppUser,
) {
  if (!itemLines.size) {
    throw new Error("Selecciona al menos un item para registrar ETA.");
  }

  const etaTimestamp = new Date(
    etaDate.getFullYear(),
    etaDate.getMonth(),
    etaDate.getDate(),
  ).getTime();

  const { items, changedCount } = withUpdatedItems(order, itemLines, (item) => {
    if (!item.requiresFulfillment) return item;
    return { ...item, deliveryEtaDate: etaTimestamp };
  });

  if (!changedCount) {
    throw new Error("No hubo items válidos para registrar ETA.");
  }

  await update(ref(database, `purchaseOrders/${order.id}`), {
    items,
    etaDate: etaTimestamp,
    updatedAt: serverTimestamp(),
  });

  await appendEvent(order.id, {
    fromStatus: order.status,
    toStatus: order.status,
    byUserId: actor.id,
    byRole: actorRoleLabel(actor),
    type: "items_eta",
    comment: `${changedCount} item(s) con fecha estimada registrada.`,
    itemsSnapshot: sanitizeForFirebase(items),
  });
}

export async function sendOrderItemsToFacturas(
  order: PurchaseOrderRecord,
  itemLines: Set<number>,
  actor: AppUser,
) {
  if (!itemLines.size) {
    throw new Error("Selecciona al menos un item para enviar a facturas.");
  }

  const sentAt = Date.now();
  const { items, changedCount } = withUpdatedItems(order, itemLines, (item) => {
    if (!item.requiresFulfillment || !item.deliveryEtaDate) return item;
    return { ...item, sentToContabilidadAt: sentAt };
  });

  if (!changedCount) {
    throw new Error("No hubo items válidos para enviar a facturas y evidencias.");
  }

  const timingUpdate = statusTimingUpdate(order);
  await update(ref(database, `purchaseOrders/${order.id}`), {
    status: "contabilidad",
    items,
    updatedAt: serverTimestamp(),
    ...timingUpdate,
  });

  await appendEvent(order.id, {
    fromStatus: order.status,
    toStatus: "contabilidad",
    byUserId: actor.id,
    byRole: actorRoleLabel(actor),
    type: "items_to_facturas",
    comment: `${changedCount} item(s) enviados a facturas y evidencias.`,
    itemsSnapshot: sanitizeForFirebase(items),
  });
}

export async function attachAccountingEvidenceToOrder(
  order: PurchaseOrderRecord,
  input: {
    facturaUrls: string[];
    paymentReceiptUrls: string[];
    internalOrdersByLine: Record<number, string>;
    actor: AppUser;
  },
) {
  const facturas = input.facturaUrls.map((item) => item.trim()).filter(Boolean);
  const receipts = input.paymentReceiptUrls.map((item) => item.trim()).filter(Boolean);

  if (!facturas.length || !receipts.length) {
    throw new Error("Agrega al menos un link de factura y un link de recibo de pago.");
  }

  const items = order.items.map((item) => {
    const internalOrder = input.internalOrdersByLine[item.line]?.trim();
    return internalOrder ? { ...item, internalOrder } : item;
  });

  const mergedFacturas = dedupeLinks(order.facturaPdfUrls, facturas);
  const mergedReceipts = dedupeLinks(order.paymentReceiptUrls, receipts);
  await update(ref(database, `purchaseOrders/${order.id}`), {
    items: sanitizeForFirebase(items),
    facturaPdfUrls: mergedFacturas,
    facturaPdfUrl: mergedFacturas[0] ?? null,
    paymentReceiptUrls: mergedReceipts,
    facturaUploadedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await appendEvent(order.id, {
    fromStatus: order.status,
    toStatus: order.status,
    byUserId: input.actor.id,
    byRole: actorRoleLabel(input.actor),
    type: "accounting_evidence",
    comment: `${facturas.length} link(s) de factura y ${receipts.length} link(s) de recibo agregados.`,
  });
}

export async function registerArrivalForOrderItems(
  order: PurchaseOrderRecord,
  itemLines: Set<number>,
  actor: AppUser,
) {
  if (!itemLines.size) {
    throw new Error("Selecciona al menos un item para registrar llegada.");
  }

  const arrivedAt = Date.now();
  const normalizedName = actor.name.trim() || actor.id;
  const normalizedArea = actor.areaDisplay.trim();

  const { items, changedCount } = withUpdatedItems(order, itemLines, (item) => {
    if (!item.deliveryEtaDate || item.isArrivalRegistered || item.isNotPurchased) return item;
    return {
      ...item,
      arrivedAt,
      arrivedByName: normalizedName,
      arrivedByArea: normalizedArea || undefined,
      isArrivalRegistered: true,
      isResolved: true,
    };
  });

  if (!changedCount) {
    throw new Error("No hubo items válidos para registrar como llegados.");
  }

  const allResolved = items.every((item) => item.isResolved || item.arrivedAt || item.notPurchasedAt);
  const nextStatus = allResolved ? "eta" : order.status;
  const payload: Record<string, unknown> = {
    items,
    materialArrivedAt: serverTimestamp(),
    materialArrivedName: normalizedName,
    materialArrivedArea: normalizedArea || null,
    updatedAt: serverTimestamp(),
  };

  if (allResolved) {
    payload.status = nextStatus;
    payload.completedAt = serverTimestamp();
    if (order.status !== nextStatus) {
      Object.assign(payload, statusTimingUpdate(order));
    }
  }

  await update(ref(database, `purchaseOrders/${order.id}`), payload);

  await appendEvent(order.id, {
    fromStatus: order.status,
    toStatus: order.status === nextStatus ? order.status : nextStatus,
    byUserId: actor.id,
    byRole: actorRoleLabel(actor),
    type: "items_arrived",
    comment: allResolved
      ? `${changedCount} item(s) marcados como llegados. La orden quedó lista para confirmación de recibido.`
      : `${changedCount} item(s) marcados como llegados por Compras.`,
    itemsSnapshot: sanitizeForFirebase(items),
  });

  await syncLinkedPacketStatuses([order.id]);
}

export async function confirmRequesterReceived(order: PurchaseOrderRecord, actor: AppUser) {
  if (order.status !== "eta") {
    throw new Error("La orden aún no está lista para confirmar recibido.");
  }
  if (order.requesterReceivedAt) {
    return;
  }

  const normalizedName = actor.name.trim() || actor.id;
  const normalizedArea = actor.areaDisplay.trim();
  await update(ref(database, `purchaseOrders/${order.id}`), {
    requesterReceivedAt: serverTimestamp(),
    requesterReceivedName: normalizedName,
    requesterReceivedArea: normalizedArea || null,
    requesterReceiptAutoConfirmed: null,
    completedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await appendEvent(order.id, {
    fromStatus: order.status,
    toStatus: null,
    byUserId: actor.id,
    byRole: actorRoleLabel(actor),
    type: "received",
    comment: "Orden confirmada como recibida por el solicitante.",
  });
}

export function packetItemLineSet(
  bundle: PacketBundleRecord,
  orderId: string,
  predicate?: (itemRef: PacketBundleRecord["packet"]["itemRefs"][number]) => boolean,
) {
  const lines = new Set<number>();
  for (const itemRef of bundle.packet.itemRefs) {
    if (itemRef.orderId !== orderId) continue;
    if (predicate && !predicate(itemRef)) continue;
    lines.add(itemRef.lineNumber);
  }
  return lines;
}
