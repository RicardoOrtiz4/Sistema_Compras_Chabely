import { useEffect, useMemo, useState } from "react";
import { onValue, ref } from "firebase/database";
import { database } from "@/lib/firebase/client";
import type { PurchaseOrderItem, PurchaseOrderRecord } from "@/features/orders/orders-data";

export type RequestOrderStatus =
  | "draft"
  | "intake_review"
  | "sourcing"
  | "ready_for_approval"
  | "approval_queue"
  | "execution_ready"
  | "documents_check"
  | "completed";

export type PurchasePacketStatus =
  | "draft"
  | "approval_queue"
  | "execution_ready"
  | "completed";

export type PacketDecisionAction = "approve" | "return_for_rework" | "close_unpurchasable";

export type RequestOrderItemRecord = {
  id: string;
  lineNumber: number;
  partNumber: string;
  description: string;
  quantity: number;
  unit: string;
  supplierName?: string;
  estimatedAmount?: number;
  customer?: string;
  isClosed: boolean;
};

export type RequestOrderRecord = {
  id: string;
  requesterId: string;
  requesterName: string;
  areaId: string;
  areaName: string;
  urgency: string;
  status: RequestOrderStatus;
  items: RequestOrderItemRecord[];
  createdAt?: number;
  updatedAt?: number;
  source: "new" | "legacy";
};

export type PacketItemRefRecord = {
  id: string;
  orderId: string;
  itemId: string;
  lineNumber: number;
  description: string;
  quantity: number;
  unit: string;
  amount?: number;
  closedAsUnpurchasable: boolean;
};

export type PurchasePacketRecord = {
  id: string;
  supplierName: string;
  status: PurchasePacketStatus;
  version: number;
  totalAmount: number;
  evidenceUrls: string[];
  itemRefs: PacketItemRefRecord[];
  createdAt?: number;
  updatedAt?: number;
  createdBy?: string;
  submittedAt?: number;
  submittedBy?: string;
  folio?: string;
};

export type PacketDecisionRecord = {
  id: string;
  packetId: string;
  action: PacketDecisionAction;
  actorId: string;
  actorName: string;
  actorArea: string;
  timestamp: number;
  reason?: string;
  affectedItemRefIds: string[];
};

export type PacketBundleRecord = {
  packet: PurchasePacketRecord;
  decisions: PacketDecisionRecord[];
};

type PacketWorkflowState = {
  readyOrders: RequestOrderRecord[];
  packets: PacketBundleRecord[];
  legacyOrders: PurchaseOrderRecord[];
};

function asObjectMap(value: unknown) {
  if (!value || typeof value !== "object") {
    return {} as Record<string, Record<string, unknown>>;
  }

  const result: Record<string, Record<string, unknown>> = {};
  for (const [key, raw] of Object.entries(value as Record<string, unknown>)) {
    if (raw && typeof raw === "object") {
      result[key] = raw as Record<string, unknown>;
    }
  }
  return result;
}

function asString(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function asOptionalString(value: unknown) {
  const next = asString(value);
  return next || undefined;
}

function asNumber(value: unknown) {
  if (typeof value === "number") return value;
  if (typeof value === "string") {
    const parsed = Number(value.trim());
    return Number.isFinite(parsed) ? parsed : undefined;
  }
  return undefined;
}

function asBoolean(value: unknown) {
  if (typeof value === "boolean") return value;
  if (typeof value === "string") return value.trim().toLowerCase() === "true";
  return false;
}

function parseStringList(value: unknown) {
  if (Array.isArray(value)) {
    return value.map(asString).filter(Boolean);
  }
  if (value && typeof value === "object") {
    return Object.values(value as Record<string, unknown>).map(asString).filter(Boolean);
  }
  const next = asString(value);
  return next ? [next] : [];
}

function inferLineNumber(rawItemId?: string) {
  const value = rawItemId?.trim() ?? "";
  if (value.startsWith("line_")) {
    return Number.parseInt(value.slice(5), 10) || 0;
  }
  return Number.parseInt(value, 10) || 0;
}

function normalizeRequestOrderStatus(raw?: string): RequestOrderStatus {
  switch ((raw ?? "").trim().toLowerCase()) {
    case "intake_review":
      return "intake_review";
    case "sourcing":
      return "sourcing";
    case "ready_for_approval":
      return "ready_for_approval";
    case "approval_queue":
      return "approval_queue";
    case "execution_ready":
      return "execution_ready";
    case "documents_check":
      return "documents_check";
    case "completed":
      return "completed";
    default:
      return "draft";
  }
}

function normalizePacketStatus(raw?: string): PurchasePacketStatus {
  switch ((raw ?? "").trim().toLowerCase()) {
    case "approval_queue":
      return "approval_queue";
    case "execution_ready":
      return "execution_ready";
    case "completed":
      return "completed";
    default:
      return "draft";
  }
}

function normalizeDecisionAction(raw?: string): PacketDecisionAction {
  switch ((raw ?? "").trim().toLowerCase()) {
    case "approve":
      return "approve";
    case "close_unpurchasable":
      return "close_unpurchasable";
    default:
      return "return_for_rework";
  }
}

function mapRequestOrderItems(value: unknown): RequestOrderItemRecord[] {
  const rawItems =
    value && typeof value === "object"
      ? Object.entries(value as Record<string, unknown>)
      : [];

  return rawItems
    .filter(([, raw]) => raw && typeof raw === "object")
    .map(([itemId, raw]) => {
      const data = raw as Record<string, unknown>;
      return {
        id: asString(data.itemId) || itemId,
        lineNumber: (asNumber(data.lineNumber) ?? asNumber(data.line) ?? 0) as number,
        partNumber: asString(data.partNumber),
        description: asString(data.description),
        quantity: asNumber(data.quantity) ?? 0,
        unit: asString(data.unit),
        supplierName: asOptionalString(data.supplierName) ?? asOptionalString(data.supplier),
        estimatedAmount: asNumber(data.estimatedAmount) ?? asNumber(data.budget),
        customer: asOptionalString(data.customer),
        isClosed: asBoolean(data.isClosed),
      };
    });
}

function legacyStatusToNew(raw: string): RequestOrderStatus {
  switch (raw) {
    case "intakeReview":
      return "intake_review";
    case "sourcing":
      return "sourcing";
    case "readyForApproval":
      return "ready_for_approval";
    case "approvalQueue":
      return "approval_queue";
    case "paymentDone":
    case "orderPlaced":
      return "execution_ready";
    case "contabilidad":
      return "documents_check";
    case "eta":
      return "completed";
    default:
      return "draft";
  }
}

function mapLegacyOrderItems(items: PurchaseOrderItem[]): RequestOrderItemRecord[] {
  return items.map((item) => ({
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
  }));
}

function buildAssignedPacketItemRefSet(
  rawPackets: Record<string, Record<string, unknown>>,
  rawPacketItems: Record<string, Record<string, unknown>>,
) {
  const assigned = new Set<string>();

  for (const [packetId, packet] of Object.entries(rawPackets)) {
    const status = normalizePacketStatus(asString(packet.status));
    if (status === "completed") continue;

    const packetItems = rawPacketItems[packetId] ?? {};
    for (const [itemRefId, rawItem] of Object.entries(packetItems)) {
      if (!rawItem || typeof rawItem !== "object") continue;
      const data = rawItem as Record<string, unknown>;
      if (asBoolean(data.closedAsUnpurchasable)) continue;

      const effectiveItemRefId = asString(data.itemRefId) || itemRefId;
      if (effectiveItemRefId) {
        assigned.add(effectiveItemRefId);
      }
    }
  }

  return assigned;
}

function buildReadyOrders(
  rawOrders: Record<string, Record<string, unknown>>,
  rawOrderItems: Record<string, Record<string, unknown>>,
  legacyOrders: PurchaseOrderRecord[],
  rawPackets: Record<string, Record<string, unknown>>,
  rawPacketItems: Record<string, Record<string, unknown>>,
) {
  const merged = new Map<string, RequestOrderRecord>();
  const assignedPacketItemRefIds = buildAssignedPacketItemRefSet(rawPackets, rawPacketItems);

  for (const legacy of legacyOrders) {
    const status = legacyStatusToNew(legacy.status);
    if (status !== "ready_for_approval") continue;
    const items = mapLegacyOrderItems(legacy.items).filter(
      (item) => !assignedPacketItemRefIds.has(`${legacy.id}::${item.id}`),
    );
    if (!items.length) continue;

    merged.set(legacy.id, {
      id: legacy.id,
      requesterId: legacy.requesterId,
      requesterName: legacy.requesterName,
      areaId: legacy.areaId,
      areaName: legacy.areaName,
      urgency: legacy.urgency,
      status,
      items,
      createdAt: legacy.createdAt,
      updatedAt: legacy.updatedAt,
      source: "legacy",
    });
  }

  for (const [orderId, data] of Object.entries(rawOrders)) {
    const status = normalizeRequestOrderStatus(asString(data.status));
    if (status !== "ready_for_approval") continue;
    const itemMap = rawOrderItems[orderId] ?? (data.items as Record<string, unknown> | undefined);
    const items = mapRequestOrderItems(itemMap).filter(
      (item) => !assignedPacketItemRefIds.has(`${orderId}::${item.id}`),
    );
    if (!items.length) continue;

    merged.set(orderId, {
      id: orderId,
      requesterId: asString(data.requesterId),
      requesterName: asString(data.requesterName),
      areaId: asString(data.areaId),
      areaName: asString(data.areaName),
      urgency: asString(data.urgency) || "normal",
      status,
      items,
      createdAt: asNumber(data.createdAt),
      updatedAt: asNumber(data.updatedAt),
      source: "new",
    });
  }

  return [...merged.values()].sort((left, right) => (right.updatedAt ?? 0) - (left.updatedAt ?? 0));
}

function mapPacketItemRefs(value: unknown): PacketItemRefRecord[] {
  const rawItems =
    value && typeof value === "object"
      ? Object.entries(value as Record<string, unknown>)
      : [];

  return rawItems
    .filter(([, raw]) => raw && typeof raw === "object")
    .map(([id, raw]) => {
      const data = raw as Record<string, unknown>;
      const itemId = asString(data.itemId);
      return {
        id: asString(data.itemRefId) || id,
        orderId: asString(data.orderId),
        itemId,
        lineNumber: (asNumber(data.lineNumber) ?? inferLineNumber(itemId)) as number,
        description: asString(data.description),
        quantity: asNumber(data.quantity) ?? 0,
        unit: asString(data.unit),
        amount: asNumber(data.amount),
        closedAsUnpurchasable: asBoolean(data.closedAsUnpurchasable),
      };
    })
    .sort((left, right) => left.id.localeCompare(right.id, "es"));
}

function buildPackets(
  rawPackets: Record<string, Record<string, unknown>>,
  rawPacketItems: Record<string, Record<string, unknown>>,
  rawDecisions: Record<string, Record<string, unknown>>,
) {
  const bundles: PacketBundleRecord[] = [];

  for (const [packetId, data] of Object.entries(rawPackets)) {
    const decisionsNode = rawDecisions[packetId] ?? {};
    const decisions = Object.entries(decisionsNode)
      .filter(([, raw]) => raw && typeof raw === "object")
      .map(([decisionId, raw]) => {
        const decision = raw as Record<string, unknown>;
        return {
          id: decisionId,
          packetId: asString(decision.packetId) || packetId,
          action: normalizeDecisionAction(asString(decision.action)),
          actorId: asString(decision.actorId),
          actorName: asString(decision.actorName),
          actorArea: asString(decision.actorArea),
          timestamp: (asNumber(decision.timestamp) ?? Date.now()) as number,
          reason: asOptionalString(decision.reason),
          affectedItemRefIds: parseStringList(decision.affectedItemRefIds),
        };
      })
      .sort((left, right) => right.timestamp - left.timestamp);

    bundles.push({
      packet: {
        id: packetId,
        supplierName: asString(data.supplierName),
        status: normalizePacketStatus(asString(data.status)),
        version: (asNumber(data.version) ?? 0) as number,
        totalAmount: asNumber(data.totalAmount) ?? 0,
        evidenceUrls: parseStringList(data.evidenceUrls),
        itemRefs: mapPacketItemRefs(rawPacketItems[packetId]),
        createdAt: asNumber(data.createdAt),
        updatedAt: asNumber(data.updatedAt),
        createdBy: asOptionalString(data.createdBy),
        submittedAt: asNumber(data.submittedAt),
        submittedBy: asOptionalString(data.submittedBy),
        folio: asOptionalString(data.folio),
      },
      decisions,
    });
  }

  return bundles.sort(
    (left, right) => (right.packet.updatedAt ?? 0) - (left.packet.updatedAt ?? 0),
  );
}

export function usePacketWorkflowData(enabled: boolean, legacyOrders: PurchaseOrderRecord[]) {
  const [ordersNode, setOrdersNode] = useState<Record<string, Record<string, unknown>>>({});
  const [orderItemsNode, setOrderItemsNode] = useState<Record<string, Record<string, unknown>>>({});
  const [packetsNode, setPacketsNode] = useState<Record<string, Record<string, unknown>>>({});
  const [packetItemsNode, setPacketItemsNode] = useState<Record<string, Record<string, unknown>>>({});
  const [packetDecisionsNode, setPacketDecisionsNode] = useState<Record<string, Record<string, unknown>>>({});
  const [isLoading, setIsLoading] = useState(enabled);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!enabled) {
      setOrdersNode({});
      setOrderItemsNode({});
      setPacketsNode({});
      setPacketItemsNode({});
      setPacketDecisionsNode({});
      setIsLoading(false);
      setError(null);
      return;
    }

    setIsLoading(true);
    setError(null);
    let pending = 5;
    const markLoaded = () => {
      pending -= 1;
      if (pending <= 0) {
        setIsLoading(false);
      }
    };

    const subscriptions = [
      onValue(
        ref(database, "orders"),
        (snapshot) => {
          setOrdersNode(asObjectMap(snapshot.val()));
          markLoaded();
        },
        (nextError) => {
          setError(nextError.message);
          setIsLoading(false);
        },
      ),
      onValue(
        ref(database, "order_items"),
        (snapshot) => {
          setOrderItemsNode(asObjectMap(snapshot.val()));
          markLoaded();
        },
        (nextError) => {
          setError(nextError.message);
          setIsLoading(false);
        },
      ),
      onValue(
        ref(database, "packets"),
        (snapshot) => {
          setPacketsNode(asObjectMap(snapshot.val()));
          markLoaded();
        },
        (nextError) => {
          setError(nextError.message);
          setIsLoading(false);
        },
      ),
      onValue(
        ref(database, "packet_items"),
        (snapshot) => {
          setPacketItemsNode(asObjectMap(snapshot.val()));
          markLoaded();
        },
        (nextError) => {
          setError(nextError.message);
          setIsLoading(false);
        },
      ),
      onValue(
        ref(database, "packet_decisions"),
        (snapshot) => {
          setPacketDecisionsNode(asObjectMap(snapshot.val()));
          markLoaded();
        },
        (nextError) => {
          setError(nextError.message);
          setIsLoading(false);
        },
      ),
    ];

    return () => {
      for (const unsubscribe of subscriptions) {
        unsubscribe();
      }
    };
  }, [enabled]);

  const data = useMemo<PacketWorkflowState>(
    () => ({
      readyOrders: buildReadyOrders(
        ordersNode,
        orderItemsNode,
        legacyOrders,
        packetsNode,
        packetItemsNode,
      ),
      packets: buildPackets(packetsNode, packetItemsNode, packetDecisionsNode),
      legacyOrders,
    }),
    [legacyOrders, orderItemsNode, ordersNode, packetDecisionsNode, packetItemsNode, packetsNode],
  );

  return { data, isLoading, error };
}
