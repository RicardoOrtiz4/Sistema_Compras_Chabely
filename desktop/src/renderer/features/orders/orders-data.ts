export type OrderUrgency = "normal" | "urgente";

export type PurchaseOrderItem = {
  line: number;
  pieces: number;
  partNumber: string;
  description: string;
  quantity: number;
  unit: string;
  customer?: string;
  supplier?: string;
  budget?: number;
  internalOrder?: string;
  estimatedDate?: number;
  deliveryEtaDate?: number;
  sentToContabilidadAt?: number;
  reviewFlagged: boolean;
  reviewComment?: string;
  receivedQuantity?: number;
  receivedComment?: string;
  arrivedAt?: number;
  arrivedByName?: string;
  arrivedByArea?: string;
  notPurchasedAt?: number;
  notPurchasedByName?: string;
  notPurchasedByArea?: string;
  notPurchasedReason?: string;
  isArrivalRegistered: boolean;
  isNotPurchased: boolean;
  requiresFulfillment: boolean;
  isResolved: boolean;
};

export type PurchaseOrderEvent = {
  id: string;
  fromStatus?: string;
  toStatus?: string;
  byUserId: string;
  byRole: string;
  timestamp?: number;
  type?: string;
  comment?: string;
  itemsSnapshot?: PurchaseOrderItem[];
};

export type PurchaseOrderRecord = {
  id: string;
  companyId?: string;
  requesterId: string;
  requesterName: string;
  areaId: string;
  areaName: string;
  urgency: OrderUrgency;
  status: string;
  items: PurchaseOrderItem[];
  clientNote?: string;
  urgentJustification?: string;
  supplier?: string;
  internalOrder?: string;
  budget?: number;
  supplierBudgets?: Record<string, number>;
  pdfUrl?: string;
  authorizedByName?: string;
  authorizedByArea?: string;
  authorizedAt?: number;
  lastReturnReason?: string;
  lastReturnFromStatus?: string;
  rejectionAcknowledgedAt?: number;
  lastReviewDurationMs?: number;
  processByName?: string;
  processByArea?: string;
  processAt?: number;
  contabilidadName?: string;
  contabilidadArea?: string;
  facturaPdfUrl?: string;
  facturaPdfUrls: string[];
  paymentReceiptUrls: string[];
  facturaUploadedAt?: number;
  completedAt?: number;
  etaDate?: number;
  materialArrivedAt?: number;
  materialArrivedName?: string;
  materialArrivedArea?: string;
  requesterReceivedAt?: number;
  requesterReceivedName?: string;
  requesterReceivedArea?: string;
  requesterReceiptAutoConfirmed?: boolean;
  returnCount: number;
  isDraft: boolean;
  createdAt?: number;
  updatedAt?: number;
  requestedDeliveryDate?: number;
  statusEnteredAt?: number;
  statusDurations: Record<string, number>;
  events: PurchaseOrderEvent[];
};

export function mapOrders(value: unknown): PurchaseOrderRecord[] {
  if (!value || typeof value !== "object") {
    return [];
  }

  const orders: PurchaseOrderRecord[] = [];

  for (const [id, rawOrder] of Object.entries(value as Record<string, unknown>)) {
    if (!rawOrder || typeof rawOrder !== "object") continue;
    const data = rawOrder as Record<string, unknown>;
    orders.push({
      id,
      companyId: asOptionalString(data.companyId),
      requesterId: asString(data.requesterId),
      requesterName: asString(data.requesterName),
      areaId: asString(data.areaId),
      areaName: asString(data.areaName),
      urgency: asString(data.urgency) === "urgente" ? "urgente" : "normal",
      status: asString(data.status),
      items: mapOrderItems(data.items),
      clientNote: asOptionalString(data.clientNote),
      urgentJustification: asOptionalString(data.urgentJustification),
      supplier: asOptionalString(data.supplier),
      internalOrder: asOptionalString(data.internalOrder),
      budget: asNumber(data.budget),
      supplierBudgets: mapSupplierBudgets(data.supplierBudgets),
      pdfUrl: asOptionalString(data.pdfUrl),
      authorizedByName: asOptionalString(data.authorizedByName),
      authorizedByArea: asOptionalString(data.authorizedByArea),
      authorizedAt: asNumber(data.authorizedAt),
      lastReturnReason: asOptionalString(data.lastReturnReason),
      lastReturnFromStatus: asOptionalString(data.lastReturnFromStatus),
      rejectionAcknowledgedAt: asNumber(data.rejectionAcknowledgedAt),
      lastReviewDurationMs: asNumber(data.lastReviewDurationMs),
      processByName: asOptionalString(data.processByName),
      processByArea: asOptionalString(data.processByArea),
      processAt: asNumber(data.processAt),
      contabilidadName: asOptionalString(data.contabilidadName),
      contabilidadArea: asOptionalString(data.contabilidadArea),
      facturaPdfUrl: asOptionalString(data.facturaPdfUrl),
      facturaPdfUrls: asStringList(data.facturaPdfUrls),
      paymentReceiptUrls: asStringList(data.paymentReceiptUrls),
      facturaUploadedAt: asNumber(data.facturaUploadedAt),
      completedAt: asNumber(data.completedAt),
      etaDate: asNumber(data.etaDate),
      materialArrivedAt: asNumber(data.materialArrivedAt),
      materialArrivedName: asOptionalString(data.materialArrivedName),
      materialArrivedArea: asOptionalString(data.materialArrivedArea),
      requesterReceivedAt: asNumber(data.requesterReceivedAt),
      requesterReceivedName: asOptionalString(data.requesterReceivedName),
      requesterReceivedArea: asOptionalString(data.requesterReceivedArea),
      requesterReceiptAutoConfirmed: asBoolean(data.requesterReceiptAutoConfirmed),
      returnCount: asNumber(data.returnCount) ?? 0,
      isDraft: asBoolean(data.isDraft),
      createdAt: asNumber(data.createdAt),
      updatedAt: asNumber(data.updatedAt),
      requestedDeliveryDate: asNumber(data.requestedDeliveryDate),
      statusEnteredAt: asNumber(data.statusEnteredAt),
      statusDurations: mapStatusDurations(data.statusDurations),
      events: mapOrderEvents(data.events),
    });
  }

  return orders.sort((a, b) => (b.updatedAt ?? 0) - (a.updatedAt ?? 0));
}

function mapOrderItems(value: unknown): PurchaseOrderItem[] {
  const rawItems =
    Array.isArray(value)
      ? value
      : value && typeof value === "object"
        ? Object.values(value as Record<string, unknown>)
        : [];

  return rawItems
    .filter((item) => item && typeof item === "object")
    .map((item) => {
      const data = item as Record<string, unknown>;
      return {
        line: asNumber(data.line) ?? 0,
        pieces: asNumber(data.pieces) ?? asNumber(data.quantity) ?? 0,
        partNumber: asString(data.partNumber),
        description: asString(data.description),
        quantity: asNumber(data.quantity) ?? 0,
        unit: asString(data.unit),
        customer: asOptionalString(data.customer),
        supplier: asOptionalString(data.supplier),
        budget: asNumber(data.budget),
        internalOrder: asOptionalString(data.internalOrder),
        estimatedDate: asNumber(data.estimatedDate),
        deliveryEtaDate: asNumber(data.deliveryEtaDate),
        sentToContabilidadAt: asNumber(data.sentToContabilidadAt),
        reviewFlagged: asBoolean(data.reviewFlagged),
        reviewComment: asOptionalString(data.reviewComment),
        receivedQuantity: asNumber(data.receivedQuantity),
        receivedComment: asOptionalString(data.receivedComment),
        arrivedAt: asNumber(data.arrivedAt),
        arrivedByName: asOptionalString(data.arrivedByName),
        arrivedByArea: asOptionalString(data.arrivedByArea),
        notPurchasedAt: asNumber(data.notPurchasedAt),
        notPurchasedByName: asOptionalString(data.notPurchasedByName),
        notPurchasedByArea: asOptionalString(data.notPurchasedByArea),
        notPurchasedReason: asOptionalString(data.notPurchasedReason),
        isArrivalRegistered: asNumber(data.arrivedAt) !== undefined,
        isNotPurchased: asNumber(data.notPurchasedAt) !== undefined,
        requiresFulfillment: asNumber(data.notPurchasedAt) === undefined,
        isResolved:
          asNumber(data.notPurchasedAt) !== undefined || asNumber(data.arrivedAt) !== undefined,
      };
    });
}

function mapOrderEvents(value: unknown): PurchaseOrderEvent[] {
  if (!value || typeof value !== "object") {
    return [];
  }

  const events: PurchaseOrderEvent[] = [];
  for (const [id, rawEvent] of Object.entries(value as Record<string, unknown>)) {
    if (!rawEvent || typeof rawEvent !== "object") continue;
    const data = rawEvent as Record<string, unknown>;
    events.push({
      id,
      fromStatus: asOptionalString(data.fromStatus),
      toStatus: asOptionalString(data.toStatus),
      byUserId: asString(data.byUserId),
      byRole: asString(data.byRole),
      timestamp: asNumber(data.timestamp) ?? undefined,
      type: asOptionalString(data.type),
      comment: asOptionalString(data.comment),
      itemsSnapshot: mapOrderItems(data.itemsSnapshot),
    });
  }

  return events.sort((a, b) => (a.timestamp ?? 0) - (b.timestamp ?? 0));
}

function mapStatusDurations(value: unknown) {
  if (!value || typeof value !== "object") {
    return {};
  }

  const durations: Record<string, number> = {};
  for (const [key, raw] of Object.entries(value as Record<string, unknown>)) {
    const parsed = asNumber(raw);
    if (parsed !== undefined) {
      durations[key] = parsed;
    }
  }
  return durations;
}

function mapSupplierBudgets(value: unknown) {
  if (!value || typeof value !== "object") {
    return undefined;
  }

  const budgets: Record<string, number> = {};
  for (const [key, raw] of Object.entries(value as Record<string, unknown>)) {
    const parsed = asNumber(raw);
    if (parsed !== undefined && key.trim()) {
      budgets[key.trim()] = parsed;
    }
  }

  return Object.keys(budgets).length ? budgets : undefined;
}

function asString(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function asOptionalString(value: unknown) {
  const next = asString(value);
  return next || undefined;
}

function asNumber(value: unknown) {
  if (typeof value === "number") return Math.trunc(value);
  if (typeof value === "string") {
    const parsed = Number.parseInt(value.trim(), 10);
    return Number.isNaN(parsed) ? undefined : parsed;
  }
  return undefined;
}

function asBoolean(value: unknown) {
  if (typeof value === "boolean") return value;
  if (typeof value === "string") {
    return value.trim().toLowerCase() === "true";
  }
  return false;
}

function asStringList(value: unknown) {
  if (Array.isArray(value)) {
    return value.map(asString).filter(Boolean);
  }
  if (value && typeof value === "object") {
    return Object.values(value as Record<string, unknown>).map(asString).filter(Boolean);
  }
  const next = asString(value);
  return next ? [next] : [];
}

export function countFulfillmentItems(order: PurchaseOrderRecord) {
  return order.items.filter((item) => item.requiresFulfillment).length;
}

export function countResolvedItems(order: PurchaseOrderRecord) {
  return order.items.filter((item) => item.isResolved).length;
}

export function hasAllItemsArrived(order: PurchaseOrderRecord) {
  const trackedItems = order.items.filter((item) => item.requiresFulfillment);
  if (!trackedItems.length) return false;
  return trackedItems.every((item) => item.isArrivalRegistered);
}

export function requiresRequesterReceiptConfirmation(order: PurchaseOrderRecord) {
  return countFulfillmentItems(order) > 0;
}

export function isRequesterReceiptConfirmed(order: PurchaseOrderRecord) {
  return Boolean(order.requesterReceivedAt);
}

export function isArrivalPendingConfirmation(order: PurchaseOrderRecord) {
  return hasAllItemsArrived(order) && !isRequesterReceiptConfirmed(order);
}

export function requesterReceiptStatusLabel(order: PurchaseOrderRecord) {
  const hasNotPurchasedItems = order.items.some((item) => item.isNotPurchased);
  const fulfillmentCount = countFulfillmentItems(order);

  if (fulfillmentCount === 0 && hasNotPurchasedItems) {
    return "Cerrada sin compra";
  }

  if (order.requesterReceiptAutoConfirmed) {
    return hasNotPurchasedItems
      ? "Cerrada parcial sin confirmacion"
      : "Llegado pero no confirmado";
  }

  if (isRequesterReceiptConfirmed(order)) {
    return hasNotPurchasedItems
      ? "Recibida parcial por solicitante"
      : "Recibida por solicitante";
  }

  if (isArrivalPendingConfirmation(order)) {
    return hasNotPurchasedItems
      ? "Llegada parcial pendiente de confirmacion"
      : "Llegado pendiente de confirmacion";
  }

  return order.status || "Sin estado";
}
