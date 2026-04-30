import { useEffect, useMemo, useState } from "react";
import { FileText, Search } from "lucide-react";
import { Link } from "react-router-dom";
import { hasComprasAccess, hasDireccionApprovalAccess } from "@/lib/access-control";
import { useRtdbValue } from "@/lib/firebase/hooks";
import {
  countFulfillmentItems,
  hasAllItemsArrived,
  isRequesterReceiptConfirmed,
  mapOrders,
  requesterReceiptStatusLabel,
  type PurchaseOrderRecord,
} from "@/features/orders/orders-data";
import { getOrderStatusLabel } from "@/features/orders/order-status";
import { type PacketBundleRecord, usePacketWorkflowData } from "@/features/purchase-packets/packet-data";
import {
  attachAccountingEvidenceToOrder,
  registerArrivalForOrderItems,
  registerEtaForOrderItems,
  sendOrderItemsToFacturas,
} from "@/features/workflow/packet-follow-up-service";
import { StatusBadge } from "@/shared/ui/status-badge";
import { useSessionStore } from "@/store/session-store";
import { Snackbar } from "@/shared/ui/snackbar";

type FollowUpTab = "eta" | "facturas";
type UrgencyFilter = "all" | "normal" | "urgente";

function formatDateTime(value?: number) {
  if (!value) return "Sin fecha";
  return new Intl.DateTimeFormat("es-MX", { dateStyle: "short", timeStyle: "short" }).format(
    new Date(value),
  );
}

function formatDateInput(value?: number) {
  if (!value) return "";
  const date = new Date(value);
  const year = date.getFullYear();
  const month = `${date.getMonth() + 1}`.padStart(2, "0");
  const day = `${date.getDate()}`.padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function splitLinks(value: string) {
  return value
    .split(/\r?\n/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function getExecutionReadyBundles(bundles: PacketBundleRecord[]) {
  return bundles.filter(
    (bundle) => bundle.packet.status === "execution_ready" || bundle.packet.status === "completed",
  );
}

function buildPacketOrders(bundle: PacketBundleRecord, ordersById: Record<string, PurchaseOrderRecord>) {
  const ids = [...new Set(bundle.packet.itemRefs.map((item) => item.orderId).filter(Boolean))];
  return ids
    .map((id) => ordersById[id])
    .filter((order): order is PurchaseOrderRecord => Boolean(order))
    .sort((left, right) => left.id.localeCompare(right.id, "es"));
}

function buildEtaWorkItems(bundle: PacketBundleRecord, ordersById: Record<string, PurchaseOrderRecord>) {
  return bundle.packet.itemRefs
    .map((itemRef) => {
      const order = ordersById[itemRef.orderId];
      const orderItem = order?.items.find((item) => item.line === itemRef.lineNumber);
      if (!order || !orderItem || !orderItem.requiresFulfillment) return null;
      if (orderItem.deliveryEtaDate && orderItem.sentToContabilidadAt) return null;
      return { itemRef, order, orderItem };
    })
    .filter((item): item is NonNullable<typeof item> => Boolean(item));
}

function buildFacturasWorkItems(bundle: PacketBundleRecord, ordersById: Record<string, PurchaseOrderRecord>) {
  return bundle.packet.itemRefs
    .map((itemRef) => {
      const order = ordersById[itemRef.orderId];
      const orderItem = order?.items.find((item) => item.line === itemRef.lineNumber);
      if (!order || !orderItem || itemRef.closedAsUnpurchasable) return null;
      if (!orderItem.sentToContabilidadAt || orderItem.isResolved) return null;
      return { itemRef, order, orderItem };
    })
    .filter((item): item is NonNullable<typeof item> => Boolean(item));
}

function matchesSearch(order: PurchaseOrderRecord, search: string) {
  if (!search.trim()) return true;
  const normalized = search.trim().toLowerCase();
  return [
    order.id,
    order.requesterName,
    order.areaName,
    ...order.items.map((item) => item.description),
    ...order.items.map((item) => item.partNumber ?? ""),
    ...order.items.map((item) => item.supplier ?? ""),
  ]
    .join(" ")
    .toLowerCase()
    .includes(normalized);
}

function matchesUrgency(order: PurchaseOrderRecord, urgency: UrgencyFilter) {
  return urgency === "all" ? true : order.urgency === urgency;
}

function summarizePacketStage(
  bundle: PacketBundleRecord,
  ordersById: Record<string, PurchaseOrderRecord>,
  tab: FollowUpTab,
) {
  if (tab === "eta") {
    const workItems = buildEtaWorkItems(bundle, ordersById);
    const pendingEta = workItems.filter((item) => !item.orderItem.deliveryEtaDate).length;
    const readyForFacturas = workItems.filter(
      (item) => item.orderItem.deliveryEtaDate && !item.orderItem.sentToContabilidadAt,
    ).length;
    return `Sin ETA: ${pendingEta} | Listos para facturas: ${readyForFacturas}`;
  }

  const workItems = buildFacturasWorkItems(bundle, ordersById);
  const orders = buildPacketOrders(bundle, ordersById);
  const facturaLinkCount = orders.reduce((sum, order) => sum + order.facturaPdfUrls.length, 0);
  const paymentReceiptLinkCount = orders.reduce(
    (sum, order) => sum + order.paymentReceiptUrls.length,
    0,
  );
  return `Pendientes por llegada: ${workItems.length} | Facturas: ${facturaLinkCount} | Recibos: ${paymentReceiptLinkCount}`;
}

export function PacketFollowUpPage() {
  const profile = useSessionStore((state) => state.profile);
  const ordersState = useRtdbValue("purchaseOrders", mapOrders, Boolean(profile));
  const packetState = usePacketWorkflowData(Boolean(profile), ordersState.data ?? []);
  const canViewModule = hasComprasAccess(profile) || hasDireccionApprovalAccess(profile);
  const canOperate = hasComprasAccess(profile);

  const [tab, setTab] = useState<FollowUpTab>("eta");
  const [urgencyFilter, setUrgencyFilter] = useState<UrgencyFilter>("all");
  const [search, setSearch] = useState("");
  const [actionMessage, setActionMessage] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  const orders = ordersState.data ?? [];
  const bundles = getExecutionReadyBundles(packetState.data.packets);
  const ordersById = useMemo(
    () => Object.fromEntries(orders.map((order) => [order.id, order])),
    [orders],
  );

  const stageCards = useMemo(() => {
    const candidates =
      tab === "eta"
        ? bundles.filter((bundle) => buildEtaWorkItems(bundle, ordersById).length > 0)
        : bundles.filter((bundle) => buildFacturasWorkItems(bundle, ordersById).length > 0);

    return candidates.filter((bundle) => {
      const relatedOrders = buildPacketOrders(bundle, ordersById);
      return relatedOrders.some(
        (order) => matchesUrgency(order, urgencyFilter) && matchesSearch(order, search),
      );
    });
  }, [bundles, ordersById, search, tab, urgencyFilter]);

  const waitingOrders = useMemo(
    () =>
      orders.filter((order) => {
        const stageMatch =
          tab === "eta"
            ? order.items.some(
                (item) => item.requiresFulfillment && item.deliveryEtaDate && !item.sentToContabilidadAt,
              )
            : order.items.some((item) => item.sentToContabilidadAt && !item.isResolved);
        return stageMatch && matchesUrgency(order, urgencyFilter) && matchesSearch(order, search);
      }),
    [orders, search, tab, urgencyFilter],
  );

  useEffect(() => {
    if (!actionError) return;
    const timer = window.setTimeout(() => setActionError(null), 3600);
    return () => window.clearTimeout(timer);
  }, [actionError]);

  useEffect(() => {
    if (!actionMessage) return;
    const timer = window.setTimeout(() => setActionMessage(null), 3600);
    return () => window.clearTimeout(timer);
  }, [actionMessage]);

  if (!canViewModule) {
    return (
      <div className="rounded-[18px] border border-slate-200 bg-white px-5 py-4 text-sm text-slate-600">
        No tienes permisos para ver esta pantalla.
      </div>
    );
  }

  return (
    <div className="space-y-5 pb-4">
      <section className="rounded-[20px] border border-slate-200 bg-white px-5 py-5">
        <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
          <div>
            <p className="text-[20px] font-semibold text-slate-900">
              {tab === "eta" ? "Agregar fecha estimada" : "Facturas y evidencias"}
            </p>
            <p className="mt-1 text-sm text-slate-600">
              {tab === "eta"
                ? "Registra ETA y envia items a facturas una vez aprobados los paquetes."
                : "Guarda evidencias contables y registra la llegada del material."}
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            <StatusBadge label={`${bundles.length} paquete(s)`} tone="info" />
            <StatusBadge label={`${waitingOrders.length} orden(es) activas`} tone="warning" />
          </div>
        </div>

        <div className="mt-5 flex flex-wrap gap-3">
          <button
            type="button"
            onClick={() => setTab("eta")}
            className={[
              "rounded-full border px-5 py-2 text-sm font-medium transition",
              tab === "eta"
                ? "border-slate-900 bg-slate-900 text-white"
                : "border-slate-400 bg-white text-slate-700",
            ].join(" ")}
          >
            ETA y envio a facturas
          </button>
          <button
            type="button"
            onClick={() => setTab("facturas")}
            className={[
              "rounded-full border px-5 py-2 text-sm font-medium transition",
              tab === "facturas"
                ? "border-slate-900 bg-slate-900 text-white"
                : "border-slate-400 bg-white text-slate-700",
            ].join(" ")}
          >
            Facturas, recibos y llegada
          </button>
        </div>

        <div className="mt-5 inline-flex overflow-hidden rounded-full border border-slate-500 bg-white">
          {[
            { key: "all", label: "Todas" },
            { key: "normal", label: "Normal" },
            { key: "urgente", label: "Urgente" },
          ].map((option) => {
            const active = urgencyFilter === option.key;
            return (
              <button
                key={option.key}
                type="button"
                onClick={() => setUrgencyFilter(option.key as UrgencyFilter)}
                className={[
                  "px-5 py-2 text-sm font-medium transition",
                  active ? "bg-slate-900 text-white" : "bg-white text-slate-700 hover:bg-slate-50",
                ].join(" ")}
              >
                {option.label}
              </button>
            );
          })}
        </div>

        <label className="relative mt-5 block">
          <Search
            size={16}
            className="pointer-events-none absolute left-0 top-1/2 -translate-y-1/2 text-slate-500"
          />
          <input
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Buscar por folio, solicitante, area o articulo"
            className="w-full border-0 border-b border-slate-500 bg-transparent py-2 pl-6 text-[15px] text-slate-900 outline-none"
          />
        </label>
      </section>

      <section className="grid gap-5 2xl:grid-cols-[1.2fr_0.8fr]">
        <article className="space-y-4">
          {ordersState.isLoading || packetState.isLoading ? (
            <div className="rounded-[18px] border border-slate-200 bg-white px-5 py-6 text-sm text-slate-500">
              Cargando seguimiento...
            </div>
          ) : ordersState.error || packetState.error ? (
            <div className="rounded-[18px] border border-red-200 bg-red-50 px-5 py-6 text-sm text-red-700">
              No se pudo leer el modulo: {ordersState.error ?? packetState.error}
            </div>
          ) : !stageCards.length ? (
            <div className="rounded-[18px] border border-slate-200 bg-white px-5 py-6 text-sm text-slate-500">
              No hay paquetes pendientes en esta etapa.
            </div>
          ) : (
            <>
              <div className="rounded-[20px] border border-slate-200 bg-white px-5 py-4">
                <p className="text-[18px] font-semibold text-slate-900">
                  {tab === "eta" ? "Paquetes pendientes por ETA" : "Paquetes pendientes por llegada"}
                </p>
              </div>
              {stageCards.map((bundle) =>
                tab === "eta" ? (
                  <EtaPacketCard
                    key={`${tab}-${bundle.packet.id}`}
                    bundle={bundle}
                    ordersById={ordersById}
                    canOperate={canOperate}
                    actor={profile}
                    onActionMessage={(value) => {
                      setActionError(null);
                      setActionMessage(value);
                    }}
                    onActionError={(value) => {
                      setActionMessage(null);
                      setActionError(value);
                    }}
                  />
                ) : (
                  <FacturasPacketCard
                    key={`${tab}-${bundle.packet.id}`}
                    bundle={bundle}
                    ordersById={ordersById}
                    canOperate={canOperate}
                    actor={profile}
                    onActionMessage={(value) => {
                      setActionError(null);
                      setActionMessage(value);
                    }}
                    onActionError={(value) => {
                      setActionMessage(null);
                      setActionError(value);
                    }}
                  />
                ),
              )}
            </>
          )}
        </article>

        <aside className="rounded-[20px] border border-slate-200 bg-white px-5 py-5">
          <p className="text-[18px] font-semibold text-slate-900">Ordenes en espera</p>
          <p className="mt-1 text-sm text-slate-600">
            {tab === "eta"
              ? "Ordenes listas para pasar a facturas y evidencias."
              : "Ordenes pendientes por llegada o confirmacion final."}
          </p>

          <div className="mt-5 space-y-4">
            {waitingOrders.length ? (
              waitingOrders.map((order) => (
                <div
                  key={order.id}
                  className="rounded-[18px] border border-slate-200 bg-slate-50 px-4 py-4"
                >
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <p className="text-sm font-semibold text-slate-900">{order.id}</p>
                      <p className="mt-1 text-xs text-slate-500">
                        {order.requesterName} | {order.areaName}
                      </p>
                    </div>
                    <StatusBadge label={getOrderStatusLabel(order.status)} tone="info" />
                  </div>
                  <p className="mt-3 text-sm text-slate-600">
                    {tab === "eta"
                      ? `${order.items.filter((item) => item.requiresFulfillment && item.deliveryEtaDate && !item.sentToContabilidadAt).length} item(s) con ETA listos para enviar.`
                      : `${order.items.filter((item) => item.sentToContabilidadAt && !item.isResolved).length} item(s) pendientes por llegada.`}
                  </p>
                  <p className="mt-2 text-xs text-slate-500">
                    Estado de cierre: {requesterReceiptStatusLabel(order)}
                  </p>
                  <div className="mt-3">
                    <Link
                      to={`/orders/history/${order.id}/print`}
                      className="inline-flex items-center rounded-2xl border border-slate-700 bg-white px-3 py-2 text-sm font-medium text-slate-800"
                    >
                      <FileText size={15} className="mr-2" />
                      Ver PDF
                    </Link>
                  </div>
                </div>
              ))
            ) : (
              <p className="text-sm text-slate-500">No hay ordenes esperando en esta etapa.</p>
            )}
          </div>
        </aside>
      </section>
      <Snackbar message={actionError} tone="error" />
      <Snackbar message={actionMessage} tone="success" />
    </div>
  );
}

function EtaPacketCard({
  bundle,
  ordersById,
  canOperate,
  actor,
  onActionMessage,
  onActionError,
}: {
  bundle: PacketBundleRecord;
  ordersById: Record<string, PurchaseOrderRecord>;
  canOperate: boolean;
  actor: ReturnType<typeof useSessionStore.getState>["profile"];
  onActionMessage: (value: string) => void;
  onActionError: (value: string) => void;
}) {
  const workItems = buildEtaWorkItems(bundle, ordersById);
  const [selectedItemIds, setSelectedItemIds] = useState<string[]>(workItems.map((item) => item.itemRef.id));
  const [etaDate, setEtaDate] = useState(formatDateInput(Date.now() + 86400000));
  const [busyAction, setBusyAction] = useState<"eta" | "facturas" | null>(null);
  const pendingEtaItems = workItems.filter((item) => !item.orderItem.deliveryEtaDate);
  const readyForFacturasItems = workItems.filter(
    (item) => item.orderItem.deliveryEtaDate && !item.orderItem.sentToContabilidadAt,
  );
  const orders = buildPacketOrders(bundle, ordersById);

  async function handleRegisterEta() {
    if (!actor) return;
    const selected = pendingEtaItems.filter((item) => selectedItemIds.includes(item.itemRef.id));
    if (!selected.length) return onActionError("Selecciona al menos un item sin ETA.");
    if (!etaDate) return onActionError("Selecciona una fecha de ETA.");
    setBusyAction("eta");
    try {
      const grouped = new Map<string, Set<number>>();
      for (const item of selected) {
        if (!grouped.has(item.order.id)) grouped.set(item.order.id, new Set<number>());
        grouped.get(item.order.id)?.add(item.orderItem.line);
      }
      for (const [orderId, lines] of grouped.entries()) {
        const order = ordersById[orderId];
        if (order) await registerEtaForOrderItems(order, lines, new Date(etaDate), actor);
      }
      onActionMessage("ETA registrada para los items seleccionados.");
    } catch (error) {
      onActionError(error instanceof Error ? error.message : "No se pudo registrar ETA.");
    } finally {
      setBusyAction(null);
    }
  }

  async function handleSendToFacturas() {
    if (!actor) return;
    const selected = readyForFacturasItems.filter((item) => selectedItemIds.includes(item.itemRef.id));
    if (!selected.length) return onActionError("Selecciona al menos un item listo para facturas.");
    setBusyAction("facturas");
    try {
      const grouped = new Map<string, Set<number>>();
      for (const item of selected) {
        if (!grouped.has(item.order.id)) grouped.set(item.order.id, new Set<number>());
        grouped.get(item.order.id)?.add(item.orderItem.line);
      }
      for (const [orderId, lines] of grouped.entries()) {
        const order = ordersById[orderId];
        if (order) await sendOrderItemsToFacturas(order, lines, actor);
      }
      onActionMessage("Items enviados a facturas y evidencias.");
    } catch (error) {
      onActionError(error instanceof Error ? error.message : "No se pudieron enviar los items.");
    } finally {
      setBusyAction(null);
    }
  }

  return (
    <article className="rounded-[20px] border border-slate-200 bg-white px-5 py-5">
      <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">
            Seguimiento ETA
          </p>
          <h4 className="mt-1 text-xl font-semibold text-slate-900">
            {(bundle.packet.folio ?? bundle.packet.id).trim()} | {bundle.packet.supplierName}
          </h4>
          <p className="mt-1 text-sm text-slate-500">
            {orders.map((order) => order.id).join(", ") || "Sin ordenes ligadas"}
          </p>
          <p className="mt-2 text-sm text-slate-700">{summarizePacketStage(bundle, ordersById, "eta")}</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <StatusBadge label={`Sin ETA: ${pendingEtaItems.length}`} tone="warning" />
          <StatusBadge label={`Listos a facturas: ${readyForFacturasItems.length}`} tone="info" />
          <Link
            to={`/purchase-packets/${bundle.packet.id}/pdf`}
            className="inline-flex items-center rounded-2xl border border-slate-300 bg-white px-3 py-2 text-sm font-medium text-slate-700"
          >
            <FileText size={15} className="mr-2" />
            Ver PDF
          </Link>
        </div>
      </div>

      <div className="mt-5 space-y-3">
        {workItems.map(({ itemRef, order, orderItem }) => {
          const checked = selectedItemIds.includes(itemRef.id);
          return (
            <label
              key={itemRef.id}
              className="flex items-start gap-3 rounded-[18px] border border-slate-200 bg-slate-50 px-4 py-3"
            >
              <input
                type="checkbox"
                checked={checked}
                onChange={(event) =>
                  setSelectedItemIds((current) =>
                    event.target.checked
                      ? [...current, itemRef.id]
                      : current.filter((value) => value !== itemRef.id),
                  )
                }
                disabled={!canOperate}
                className="mt-1"
              />
              <div className="flex-1">
                <div className="flex flex-wrap items-center gap-2">
                  <p className="text-sm font-semibold text-slate-900">
                    {order.id} | L{orderItem.line} | {orderItem.description}
                  </p>
                  <StatusBadge
                    label={orderItem.deliveryEtaDate ? "ETA lista" : "Sin ETA"}
                    tone={orderItem.deliveryEtaDate ? "success" : "warning"}
                  />
                  {orderItem.sentToContabilidadAt ? (
                    <StatusBadge label="Enviado a facturas" tone="info" />
                  ) : null}
                </div>
                <p className="mt-1 text-xs text-slate-500">
                  {orderItem.quantity} {orderItem.unit} | Proveedor:{" "}
                  {orderItem.supplier || bundle.packet.supplierName}
                </p>
                <p className="mt-1 text-xs text-slate-500">
                  ETA: {formatDateTime(orderItem.deliveryEtaDate)} | Facturas:{" "}
                  {formatDateTime(orderItem.sentToContabilidadAt)}
                </p>
              </div>
            </label>
          );
        })}
      </div>

      <div className="mt-5 grid gap-3 lg:grid-cols-[220px_auto] 2xl:grid-cols-[220px_auto_auto]">
        <input
          type="date"
          value={etaDate}
          onChange={(event) => setEtaDate(event.target.value)}
          disabled={!canOperate || busyAction !== null}
          className="rounded-[18px] border border-slate-300 bg-white px-4 py-3 text-sm text-slate-900 outline-none"
        />
        <button
          type="button"
          onClick={() => void handleRegisterEta()}
          disabled={!canOperate || busyAction !== null || pendingEtaItems.length === 0}
          className="rounded-2xl border border-slate-900 bg-slate-900 px-4 py-2.5 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
        >
          {busyAction === "eta" ? "Guardando ETA..." : "Registrar ETA"}
        </button>
        <button
          type="button"
          onClick={() => void handleSendToFacturas()}
          disabled={!canOperate || busyAction !== null || readyForFacturasItems.length === 0}
          className="rounded-2xl border border-slate-700 bg-white px-4 py-2.5 text-sm font-medium text-slate-800 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {busyAction === "facturas" ? "Enviando..." : "Enviar a facturas y evidencias"}
        </button>
      </div>
    </article>
  );
}

function FacturasPacketCard({
  bundle,
  ordersById,
  canOperate,
  actor,
  onActionMessage,
  onActionError,
}: {
  bundle: PacketBundleRecord;
  ordersById: Record<string, PurchaseOrderRecord>;
  canOperate: boolean;
  actor: ReturnType<typeof useSessionStore.getState>["profile"];
  onActionMessage: (value: string) => void;
  onActionError: (value: string) => void;
}) {
  const workItems = buildFacturasWorkItems(bundle, ordersById);
  const orders = buildPacketOrders(bundle, ordersById);
  const [selectedArrivalIds, setSelectedArrivalIds] = useState<string[]>(workItems.map((item) => item.itemRef.id));
  const [facturaLinks, setFacturaLinks] = useState("");
  const [receiptLinks, setReceiptLinks] = useState("");
  const [busyAction, setBusyAction] = useState<"links" | "arrival" | null>(null);
  const [internalOrdersByLine, setInternalOrdersByLine] = useState<Record<string, string>>(
    Object.fromEntries(
      workItems.map((item) => [
        `${item.order.id}:${item.orderItem.line}`,
        item.orderItem.internalOrder ?? "",
      ]),
    ),
  );

  const hasEvidence = orders.every(
    (order) => order.facturaPdfUrls.length > 0 && order.paymentReceiptUrls.length > 0,
  );

  async function handleSaveLinks() {
    if (!actor) return;
    const facturas = splitLinks(facturaLinks);
    const receipts = splitLinks(receiptLinks);
    if (!facturas.length || !receipts.length) {
      return onActionError("Agrega al menos un link de factura y uno de recibo.");
    }
    setBusyAction("links");
    try {
      for (const order of orders) {
        const internalOrders = Object.fromEntries(
          workItems
            .filter((item) => item.order.id === order.id)
            .map((item) => [
              item.orderItem.line,
              internalOrdersByLine[`${item.order.id}:${item.orderItem.line}`] ?? "",
            ]),
        );
        await attachAccountingEvidenceToOrder(order, {
          facturaUrls: facturas,
          paymentReceiptUrls: receipts,
          internalOrdersByLine: internalOrders,
          actor,
        });
      }
      setFacturaLinks("");
      setReceiptLinks("");
      onActionMessage("Links de facturas y recibos guardados.");
    } catch (error) {
      onActionError(error instanceof Error ? error.message : "No se pudieron guardar los links.");
    } finally {
      setBusyAction(null);
    }
  }

  async function handleRegisterArrival() {
    if (!actor) return;
    const selected = workItems.filter((item) => selectedArrivalIds.includes(item.itemRef.id));
    if (!selected.length) {
      return onActionError("Selecciona al menos un item para registrar llegada.");
    }
    setBusyAction("arrival");
    try {
      const grouped = new Map<string, Set<number>>();
      for (const item of selected) {
        if (!grouped.has(item.order.id)) grouped.set(item.order.id, new Set<number>());
        grouped.get(item.order.id)?.add(item.orderItem.line);
      }
      for (const [orderId, lines] of grouped.entries()) {
        const order = ordersById[orderId];
        if (order) await registerArrivalForOrderItems(order, lines, actor);
      }
      onActionMessage(
        "Llegada registrada. Si la orden ya quedo completa, el solicitante podra confirmar de recibido.",
      );
    } catch (error) {
      onActionError(error instanceof Error ? error.message : "No se pudo registrar la llegada.");
    } finally {
      setBusyAction(null);
    }
  }

  return (
    <article className="rounded-[20px] border border-slate-200 bg-white px-5 py-5">
      <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">
            Facturas y llegada
          </p>
          <h4 className="mt-1 text-xl font-semibold text-slate-900">
            {(bundle.packet.folio ?? bundle.packet.id).trim()} | {bundle.packet.supplierName}
          </h4>
          <p className="mt-1 text-sm text-slate-500">
            {orders.map((order) => order.id).join(", ") || "Sin ordenes ligadas"}
          </p>
          <p className="mt-2 text-sm text-slate-700">
            {summarizePacketStage(bundle, ordersById, "facturas")}
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <StatusBadge label={`Pendientes: ${workItems.length}`} tone="warning" />
          <StatusBadge label={hasEvidence ? "Con links" : "Sin links"} tone={hasEvidence ? "success" : "info"} />
          <Link
            to={`/purchase-packets/${bundle.packet.id}/pdf`}
            className="inline-flex items-center rounded-2xl border border-slate-300 bg-white px-3 py-2 text-sm font-medium text-slate-700"
          >
            <FileText size={15} className="mr-2" />
            Ver PDF
          </Link>
        </div>
      </div>

      <div className="mt-5 space-y-3">
        {workItems.map(({ itemRef, order, orderItem }) => {
          const key = `${order.id}:${orderItem.line}`;
          const checked = selectedArrivalIds.includes(itemRef.id);
          return (
            <div
              key={itemRef.id}
              className="rounded-[18px] border border-slate-200 bg-slate-50 px-4 py-3"
            >
              <label className="flex items-start gap-3">
                <input
                  type="checkbox"
                  checked={checked}
                  onChange={(event) =>
                    setSelectedArrivalIds((current) =>
                      event.target.checked
                        ? [...current, itemRef.id]
                        : current.filter((value) => value !== itemRef.id),
                    )
                  }
                  disabled={!canOperate}
                  className="mt-1"
                />
                <div className="flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <p className="text-sm font-semibold text-slate-900">
                      {order.id} | L{orderItem.line} | {orderItem.description}
                    </p>
                    <StatusBadge
                      label={orderItem.arrivedAt ? "Llegado" : "Pendiente"}
                      tone={orderItem.arrivedAt ? "success" : "warning"}
                    />
                  </div>
                  <p className="mt-1 text-xs text-slate-500">
                    ETA: {formatDateTime(orderItem.deliveryEtaDate)} | Enviado a facturas:{" "}
                    {formatDateTime(orderItem.sentToContabilidadAt)}
                  </p>
                </div>
              </label>
              <div className="mt-3">
                <label className="block text-xs font-medium uppercase tracking-[0.18em] text-slate-500">
                  OC interna
                </label>
                <input
                  value={internalOrdersByLine[key] ?? ""}
                  onChange={(event) =>
                    setInternalOrdersByLine((current) => ({
                      ...current,
                      [key]: event.target.value,
                    }))
                  }
                  disabled={!canOperate || busyAction !== null}
                  className="mt-2 w-full rounded-[18px] border border-slate-300 bg-white px-4 py-3 text-sm text-slate-900 outline-none"
                />
              </div>
            </div>
          );
        })}
      </div>

      <div className="mt-5 grid gap-4 2xl:grid-cols-2">
        <label className="block">
          <span className="mb-2 block text-sm font-medium text-slate-700">Links de factura</span>
          <textarea
            value={facturaLinks}
            onChange={(event) => setFacturaLinks(event.target.value)}
            disabled={!canOperate || busyAction !== null}
            rows={4}
            placeholder="Un link por linea"
            className="w-full resize-none rounded-[18px] border border-slate-300 bg-white px-4 py-3 text-sm text-slate-900 outline-none"
          />
        </label>
        <label className="block">
          <span className="mb-2 block text-sm font-medium text-slate-700">
            Links de recibo de pago
          </span>
          <textarea
            value={receiptLinks}
            onChange={(event) => setReceiptLinks(event.target.value)}
            disabled={!canOperate || busyAction !== null}
            rows={4}
            placeholder="Un link por linea"
            className="w-full resize-none rounded-[18px] border border-slate-300 bg-white px-4 py-3 text-sm text-slate-900 outline-none"
          />
        </label>
      </div>

      {orders.some((order) => order.facturaPdfUrls.length || order.paymentReceiptUrls.length) ? (
        <div className="mt-5 grid gap-3 md:grid-cols-2">
          {orders.map((order) => (
            <div key={order.id} className="rounded-[18px] bg-slate-100 px-4 py-4 text-sm text-slate-600">
              <p className="font-semibold text-slate-900">{order.id}</p>
              <p className="mt-2">Facturas: {order.facturaPdfUrls.length}</p>
              <p>Recibos: {order.paymentReceiptUrls.length}</p>
              <p className="mt-2 text-xs text-slate-500">
                Cierre:{" "}
                {isRequesterReceiptConfirmed(order)
                  ? "Solicitante confirmo"
                  : hasAllItemsArrived(order)
                    ? "Esperando confirmacion"
                    : "En proceso"}{" "}
                | Entregables: {countFulfillmentItems(order)}
              </p>
            </div>
          ))}
        </div>
      ) : null}

      <div className="mt-5 flex flex-col gap-3 sm:flex-row sm:flex-wrap">
        <button
          type="button"
          onClick={() => void handleSaveLinks()}
          disabled={!canOperate || busyAction !== null}
          className="rounded-2xl border border-slate-700 bg-white px-4 py-2.5 text-sm font-medium text-slate-800 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {busyAction === "links" ? "Guardando links..." : "Guardar links"}
        </button>
        <button
          type="button"
          onClick={() => void handleRegisterArrival()}
          disabled={!canOperate || busyAction !== null || !hasEvidence}
          className="rounded-2xl border border-slate-900 bg-slate-900 px-4 py-2.5 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
        >
          {busyAction === "arrival" ? "Registrando..." : "Registrar llegada"}
        </button>
      </div>
    </article>
  );
}
