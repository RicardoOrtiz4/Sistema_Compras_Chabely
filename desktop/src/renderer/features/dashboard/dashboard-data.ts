export type DashboardCounts = {
  intakeReview: number;
  sourcing: number;
  sourcingReadyToSend: number;
  pendingDireccion: number;
  pendingEta: number;
  contabilidad: number;
  hasRemoteCounters: boolean;
};

export type PurchaseOrderSummary = {
  id: string;
  requesterName: string;
  areaName: string;
  status: string;
  supplier: string;
  urgency: string;
  updatedAt: number;
};

export const emptyCounts: DashboardCounts = {
  intakeReview: 0,
  sourcing: 0,
  sourcingReadyToSend: 0,
  pendingDireccion: 0,
  pendingEta: 0,
  contabilidad: 0,
  hasRemoteCounters: false,
};

export function mapDashboardCounts(value: unknown): DashboardCounts {
  if (!value || typeof value !== "object") {
    return emptyCounts;
  }

  const data = value as Record<string, unknown>;
  if ("status" in data || "sourcing" in data) {
    const status = asMap(data.status);
    const sourcing = asMap(data.sourcing);

    return {
      intakeReview: asInt(status.intakeReview),
      sourcing: asInt(status.sourcing),
      sourcingReadyToSend: asInt(sourcing.readyToSend),
      pendingDireccion: asInt(status.approvalQueue),
      pendingEta: asInt(status.paymentDone),
      contabilidad: asInt(status.contabilidad),
      hasRemoteCounters: Object.keys(status).length > 0 || Object.keys(sourcing).length > 0,
    };
  }

  const counts = { ...emptyCounts };
  for (const orderValue of Object.values(data)) {
    if (!orderValue || typeof orderValue !== "object") continue;
    const order = orderValue as Record<string, unknown>;
    switch (asString(order.status)) {
      case "intakeReview":
        counts.intakeReview += 1;
        break;
      case "sourcing":
        counts.sourcing += 1;
        break;
      case "readyForApproval":
        counts.sourcingReadyToSend += 1;
        break;
      case "approvalQueue":
        counts.pendingDireccion += 1;
        break;
      case "paymentDone":
        counts.pendingEta += 1;
        break;
      case "contabilidad":
        counts.contabilidad += 1;
        break;
      default:
        break;
    }
  }

  return counts;
}

export function mapOrdersList(value: unknown): PurchaseOrderSummary[] {
  if (!value || typeof value !== "object") {
    return [];
  }

  const orders: PurchaseOrderSummary[] = [];

  for (const [id, orderValue] of Object.entries(value as Record<string, unknown>)) {
    if (!orderValue || typeof orderValue !== "object") continue;
    const order = orderValue as Record<string, unknown>;
    orders.push({
      id,
      requesterName: asString(order.requesterName),
      areaName: asString(order.areaName),
      status: asString(order.status),
      supplier: asString(order.supplier),
      urgency: asString(order.urgency) || "normal",
      updatedAt: asInt(order.updatedAt),
    });
  }

  return orders.sort((a, b) => b.updatedAt - a.updatedAt).slice(0, 8);
}

function asMap(value: unknown) {
  return value && typeof value === "object" ? (value as Record<string, unknown>) : {};
}

function asInt(value: unknown) {
  if (typeof value === "number") return Math.trunc(value);
  if (typeof value === "string") return Number.parseInt(value.trim(), 10) || 0;
  return 0;
}

function asString(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}
