import type { PurchaseOrderEvent, PurchaseOrderRecord } from "@/features/orders/orders-data";

export type MonitoringRow = {
  order: PurchaseOrderRecord;
  status: string;
  elapsedMs: number;
  actor: string;
  enteredAt?: number;
  isCurrent: boolean;
};

const monitoredStatuses = [
  "draft",
  "intakeReview",
  "sourcing",
  "readyForApproval",
  "approvalQueue",
  "paymentDone",
  "contabilidad",
  "orderPlaced",
  "eta",
] as const;

export function isMonitorableOrder(order: PurchaseOrderRecord) {
  const isRejectedDraft = order.status === "draft" && (Boolean(order.lastReturnReason?.trim()) || order.returnCount > 0);
  const isConfirmedRejected = isRejectedDraft && Boolean(order.rejectionAcknowledgedAt);
  const isFinished = order.status === "eta";
  return (!order.isDraft || isRejectedDraft) && !isFinished && !isConfirmedRejected;
}

export function currentStatusElapsed(order: PurchaseOrderRecord, now = Date.now()) {
  const since = order.statusEnteredAt ?? order.updatedAt ?? order.createdAt;
  if (!since) return 0;
  return Math.max(now - since, 0);
}

export function accumulatedStatusElapsed(order: PurchaseOrderRecord, status: string, now = Date.now()) {
  let total = order.statusDurations[status] ?? 0;
  if (order.status === status) {
    total += currentStatusElapsed(order, now);
  }
  return total;
}

export function latestEventForStatus(events: PurchaseOrderEvent[], status: string) {
  let selected: PurchaseOrderEvent | null = null;
  for (const event of events) {
    if (event.toStatus !== status) continue;
    if (!selected || (event.timestamp ?? 0) >= (selected.timestamp ?? 0)) {
      selected = event;
    }
  }
  return selected;
}

export function buildMonitoringRows(
  order: PurchaseOrderRecord,
  actorNamesById: Record<string, string>,
  now = Date.now(),
) {
  const rows: MonitoringRow[] = [];

  for (const status of monitoredStatuses) {
    const isCurrent = order.status === status;
    const elapsedMs = accumulatedStatusElapsed(order, status, now);
    const event = latestEventForStatus(order.events, status) ?? undefined;
    const enteredAt = isCurrent
      ? order.statusEnteredAt ?? event?.timestamp ?? order.updatedAt ?? order.createdAt
      : event?.timestamp ?? (status === "draft" ? order.createdAt : undefined);
    const shouldInclude = isCurrent || elapsedMs > 0 || Boolean(event) || (status === "draft" && Boolean(order.createdAt));
    if (!shouldInclude) continue;

    rows.push({
      order,
      status,
      elapsedMs,
      actor: actorForStatus(order, status, event, actorNamesById),
      enteredAt,
      isCurrent,
    });
  }

  return rows.length
    ? rows
    : [
        {
          order,
          status: order.status,
          elapsedMs: currentStatusElapsed(order, now),
          actor: actorForStatus(order, order.status, undefined, actorNamesById),
          enteredAt: order.statusEnteredAt ?? order.updatedAt ?? order.createdAt,
          isCurrent: true,
        },
      ];
}

export function formatMonitoringDuration(ms: number) {
  if (ms <= 0) return "0 s";
  const totalSeconds = Math.floor(ms / 1000);
  const days = Math.floor(totalSeconds / 86400);
  const hours = Math.floor((totalSeconds % 86400) / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  if (days > 0) return `${days} d ${hours} h ${minutes} min ${seconds} s`;
  if (hours > 0) return `${Math.floor(totalSeconds / 3600)} h ${minutes} min ${seconds} s`;
  if (minutes > 0) return `${minutes} min ${seconds} s`;
  return `${seconds} s`;
}

export function requesterReceiptStatusLabel(order: PurchaseOrderRecord) {
  if (order.requesterReceivedAt) {
    return order.requesterReceiptAutoConfirmed ? "Confirmada automatica" : "Confirmada";
  }
  if (order.materialArrivedAt) {
    return "Pendiente de confirmacion";
  }
  return order.status === "eta" ? "Finalizada" : "En proceso";
}

function describeActor(name?: string, area?: string) {
  const trimmedName = name?.trim() ?? "";
  const trimmedArea = area?.trim() ?? "";
  if (!trimmedName && !trimmedArea) return "";
  if (!trimmedName) return trimmedArea;
  if (!trimmedArea) return trimmedName;
  return `${trimmedName} (${trimmedArea})`;
}

function eventActorLabel(event: PurchaseOrderEvent | undefined, actorNamesById: Record<string, string>) {
  if (!event) return "";
  const byUserId = event.byUserId.trim();
  const resolvedName = byUserId ? actorNamesById[byUserId]?.trim() || byUserId : "Sistema";
  const role = event.byRole.trim();
  return role ? `${resolvedName} (${role})` : resolvedName;
}

function actorForStatus(
  order: PurchaseOrderRecord,
  status: string,
  event: PurchaseOrderEvent | undefined,
  actorNamesById: Record<string, string>,
) {
  const eventLabel = eventActorLabel(event, actorNamesById);
  if (eventLabel) return eventLabel;

  switch (status) {
    case "draft":
    case "intakeReview":
      return describeActor(order.requesterName, order.areaName) || order.requesterName || "Solicitante";
    case "sourcing":
    case "readyForApproval":
      return describeActor(order.processByName, order.processByArea) || "Operacion";
    case "approvalQueue":
    case "paymentDone":
      return describeActor(order.authorizedByName, order.authorizedByArea) || "Validacion";
    case "contabilidad":
    case "orderPlaced":
      return describeActor(order.contabilidadName, order.contabilidadArea) || "Cierre documental";
    case "eta":
      return (
        describeActor(order.requesterReceivedName, order.requesterReceivedArea) ||
        describeActor(order.materialArrivedName, order.materialArrivedArea) ||
        describeActor(order.contabilidadName, order.contabilidadArea) ||
        "Sistema"
      );
    default:
      return "Sistema";
  }
}
