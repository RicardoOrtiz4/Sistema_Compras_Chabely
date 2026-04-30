import { push, ref, serverTimestamp, update } from "firebase/database";
import { database } from "@/lib/firebase/client";
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
    toStatus?: string;
    byUserId: string;
    byRole: string;
    type: string;
    comment?: string;
    itemsSnapshot?: PurchaseOrderRecord["items"];
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

export async function authorizeOrderToCompras(order: PurchaseOrderRecord, actor: AppUser) {
  const normalizedName = actor.name.trim() || actor.id;
  const normalizedArea = actor.areaDisplay.trim();
  const timingUpdate = statusTimingUpdate(order);

  await update(ref(database, `purchaseOrders/${order.id}`), {
    status: "sourcing",
    authorizedByName: normalizedName,
    authorizedByArea: normalizedArea || null,
    authorizedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...timingUpdate,
  });

  await appendEvent(order.id, {
    fromStatus: order.status,
    toStatus: "sourcing",
    byUserId: actor.id,
    byRole: actorRoleLabel(actor),
    type: "advance",
    itemsSnapshot: sanitizeForFirebase(order.items),
  });
}

export async function returnOrderToRequester(
  order: PurchaseOrderRecord,
  actor: AppUser,
  comment: string,
) {
  const trimmedComment = comment.trim();
  const timingUpdate = statusTimingUpdate(order);
  const enteredAt = order.statusEnteredAt ?? order.updatedAt ?? order.createdAt ?? Date.now();
  const reviewDuration = Math.max(Date.now() - enteredAt, 0);

  await update(ref(database, `purchaseOrders/${order.id}`), {
    status: "draft",
    isDraft: true,
    lastReturnReason: trimmedComment || null,
    lastReturnFromStatus: order.status,
    rejectionAcknowledgedAt: null,
    lastReviewDurationMs: reviewDuration,
    returnCount: (order.returnCount ?? 0) + 1,
    pdfUrl: null,
    authorizedByName: null,
    authorizedByArea: null,
    authorizedAt: null,
    processByName: null,
    processByArea: null,
    processAt: null,
    updatedAt: serverTimestamp(),
    ...timingUpdate,
  });

  await appendEvent(order.id, {
    fromStatus: order.status,
    toStatus: "draft",
    byUserId: actor.id,
    byRole: actorRoleLabel(actor),
    type: "return",
    comment: trimmedComment,
    itemsSnapshot: sanitizeForFirebase(order.items),
  });
}

function buildSupplierBudgets(items: PurchaseOrderItem[]) {
  const budgets: Record<string, number> = {};
  for (const item of items) {
    const supplier = item.supplier?.trim() ?? "";
    const budget = item.budget;
    if (!supplier || budget === undefined || budget <= 0) continue;
    budgets[supplier] = (budgets[supplier] ?? 0) + budget;
  }
  return budgets;
}

function resolveSingleSupplier(items: PurchaseOrderItem[]) {
  const suppliers = [...new Set(items.map((item) => item.supplier?.trim() ?? "").filter(Boolean))];
  return suppliers.length === 1 ? suppliers[0] : null;
}

function resolveSingleInternalOrder(items: PurchaseOrderItem[]) {
  const internalOrders = [
    ...new Set(items.map((item) => item.internalOrder?.trim() ?? "").filter(Boolean)),
  ];
  return internalOrders.length === 1 ? internalOrders[0] : null;
}

function sumItemBudgets(items: PurchaseOrderItem[]) {
  return items.reduce((sum, item) => sum + (item.budget ?? 0), 0);
}

export function hasComprasAssignment(item: PurchaseOrderItem) {
  const supplier = item.supplier?.trim() ?? "";
  return supplier.length > 0 && item.budget !== undefined && item.budget > 0;
}

export function isComprasDraftComplete(items: PurchaseOrderItem[]) {
  return items.length > 0 && items.every(hasComprasAssignment);
}

export async function processOrderToDashboard(
  order: PurchaseOrderRecord,
  actor: AppUser,
  items: PurchaseOrderItem[],
) {
  const normalizedName = actor.name.trim() || actor.id;
  const normalizedArea = actor.areaDisplay.trim();
  const timingUpdate = statusTimingUpdate(order);
  const totalBudget = sumItemBudgets(items);
  const supplierBudgets = buildSupplierBudgets(items);
  const primarySupplier = resolveSingleSupplier(items);
  const primaryInternalOrder = resolveSingleInternalOrder(items);

  await update(ref(database, `purchaseOrders/${order.id}`), {
    status: "readyForApproval",
    items: sanitizeForFirebase(items),
    supplier: primarySupplier,
    internalOrder: primaryInternalOrder,
    budget: totalBudget,
    supplierBudgets,
    processByName: normalizedName,
    processByArea: normalizedArea || null,
    processAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...timingUpdate,
  });

  await appendEvent(order.id, {
    fromStatus: order.status,
    toStatus: "readyForApproval",
    byUserId: actor.id,
    byRole: actorRoleLabel(actor),
    type: "advance",
    comment: "Datos de Compras completados y enviados al dashboard.",
    itemsSnapshot: sanitizeForFirebase(items),
  });
}
