import { useEffect, useMemo, useState } from "react";
import { ChevronDown, ChevronUp, FileText, Link2, Plus, Send } from "lucide-react";
import { Link, useNavigate } from "react-router-dom";
import { hasComprasAccess, hasDireccionApprovalAccess } from "@/lib/access-control";
import { mapOrders } from "@/features/orders/orders-data";
import {
  type PacketBundleRecord,
  type RequestOrderItemRecord,
  type RequestOrderRecord,
  usePacketWorkflowData,
} from "@/features/purchase-packets/packet-data";
import {
  approvePacket,
  closePacketItemsAsUnpurchasable,
  createAndSubmitPacketFromReadyOrders,
  returnPacketForRework,
} from "@/features/purchase-packets/purchase-packets-service";
import { useRtdbValue } from "@/lib/firebase/hooks";
import { useSessionStore } from "@/store/session-store";
import { StatusBadge } from "@/shared/ui/status-badge";
import { savePacketPreviewDraft } from "@/features/purchase-packets/packet-pdf-preview-state";

type PendingDashboardItem = {
  refId: string;
  orderId: string;
  orderLabel: string;
  requesterName: string;
  areaName: string;
  urgency: string;
  lineNumber: number;
  description: string;
  quantity: number;
  unit: string;
  supplierName: string;
  amount: number;
};

type PendingDashboardOrder = {
  orderId: string;
  requesterName: string;
  areaName: string;
  urgency: string;
  pendingItems: PendingDashboardItem[];
  sentItemsCount: number;
};

type SupplierBatch = {
  supplier: string;
  orderIds: string[];
  items: PendingDashboardItem[];
  totalAmount: number;
};

function formatDateTime(value?: number) {
  if (!value) return "Sin fecha";
  return new Intl.DateTimeFormat("es-MX", { dateStyle: "short", timeStyle: "short" }).format(
    new Date(value),
  );
}

function packetTone(status: string) {
  switch (status) {
    case "approval_queue":
      return "warning" as const;
    case "execution_ready":
      return "success" as const;
    case "completed":
      return "neutral" as const;
    default:
      return "info" as const;
  }
}

function formatPacketStatus(status: string) {
  switch (status) {
    case "draft":
      return "Borrador";
    case "approval_queue":
      return "Direccion General";
    case "execution_ready":
      return "Aprobado";
    case "completed":
      return "Completado";
    default:
      return status || "Sin estado";
  }
}

function buildPendingOrders(
  readyOrders: RequestOrderRecord[],
  packets: PacketBundleRecord[],
): PendingDashboardOrder[] {
  const sentCounts = new Map<string, number>();

  for (const bundle of packets) {
    if (bundle.packet.status === "completed") continue;
    for (const item of bundle.packet.itemRefs) {
      if (item.closedAsUnpurchasable) continue;
      sentCounts.set(item.orderId, (sentCounts.get(item.orderId) ?? 0) + 1);
    }
  }

  return readyOrders
    .map((order) => {
      const pendingItems = order.items
        .filter((item) => !item.isClosed)
        .map((item) => ({
          refId: `${order.id}::${item.id}`,
          orderId: order.id,
          orderLabel: order.id,
          requesterName: order.requesterName,
          areaName: order.areaName,
          urgency: order.urgency,
          lineNumber: item.lineNumber,
          description: item.description,
          quantity: item.quantity,
          unit: item.unit,
          supplierName: item.supplierName?.trim() ?? "",
          amount: item.estimatedAmount ?? 0,
        }))
        .filter((item) => item.supplierName);

      return {
        orderId: order.id,
        requesterName: order.requesterName,
        areaName: order.areaName,
        urgency: order.urgency,
        pendingItems,
        sentItemsCount: sentCounts.get(order.id) ?? 0,
      };
    })
    .filter((order) => order.pendingItems.length > 0)
    .sort((left, right) => left.orderId.localeCompare(right.orderId, "es"));
}

function buildSupplierBatch(
  supplier: string,
  pendingOrders: PendingDashboardOrder[],
): SupplierBatch | null {
  const items = pendingOrders
    .flatMap((order) => order.pendingItems)
    .filter((item) => item.supplierName === supplier);

  if (!items.length) {
    return null;
  }

  return {
    supplier,
    orderIds: [...new Set(items.map((item) => item.orderId))],
    items,
    totalAmount: items.reduce((sum, item) => sum + item.amount, 0),
  };
}

function openUrl(url: string) {
  window.open(url, "_blank", "noopener,noreferrer");
}

export function PurchasePacketsPage() {
  const navigate = useNavigate();
  const profile = useSessionStore((state) => state.profile);
  const legacyOrdersState = useRtdbValue("purchaseOrders", mapOrders, Boolean(profile));
  const packetState = usePacketWorkflowData(Boolean(profile), legacyOrdersState.data ?? []);

  const canUseModule = hasComprasAccess(profile) || hasDireccionApprovalAccess(profile);
  const canSendToDireccion = hasComprasAccess(profile);
  const canApprove = hasDireccionApprovalAccess(profile);

  const [selectedSupplier, setSelectedSupplier] = useState<string | null>(null);
  const [quoteUrlInput, setQuoteUrlInput] = useState("");
  const [quoteUrls, setQuoteUrls] = useState<string[]>([]);
  const [expandedOrderIds, setExpandedOrderIds] = useState<string[]>([]);
  const [workingPacketId, setWorkingPacketId] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [actionMessage, setActionMessage] = useState<string | null>(null);
  const [returnReasonByPacketId, setReturnReasonByPacketId] = useState<Record<string, string>>({});
  const [closeReasonByPacketId, setCloseReasonByPacketId] = useState<Record<string, string>>({});
  const [closeSelectionByPacketId, setCloseSelectionByPacketId] = useState<Record<string, string[]>>(
    {},
  );

  const legacyOrdersById = useMemo(
    () => Object.fromEntries((legacyOrdersState.data ?? []).map((order) => [order.id, order])),
    [legacyOrdersState.data],
  );

  const pendingOrders = useMemo(
    () => buildPendingOrders(packetState.data.readyOrders, packetState.data.packets),
    [packetState.data.packets, packetState.data.readyOrders],
  );

  const suppliers = useMemo(
    () =>
      [...new Set(pendingOrders.flatMap((order) => order.pendingItems.map((item) => item.supplierName)))]
        .filter(Boolean)
        .sort((left, right) => left.localeCompare(right, "es")),
    [pendingOrders],
  );

  useEffect(() => {
    const nextSupplier = selectedSupplier && suppliers.includes(selectedSupplier) ? selectedSupplier : suppliers[0] ?? null;
    if (nextSupplier !== selectedSupplier) {
      setSelectedSupplier(nextSupplier);
      setQuoteUrls([]);
      setExpandedOrderIds([]);
    }
  }, [selectedSupplier, suppliers]);

  const selectedBatch = useMemo(
    () => (selectedSupplier ? buildSupplierBatch(selectedSupplier, pendingOrders) : null),
    [pendingOrders, selectedSupplier],
  );

  const approvalPackets = useMemo(
    () =>
      packetState.data.packets.filter(
        (bundle) => bundle.packet.status === "approval_queue" || bundle.packet.status === "draft",
      ),
    [packetState.data.packets],
  );

  const executionReadyPackets = useMemo(
    () => packetState.data.packets.filter((bundle) => bundle.packet.status === "execution_ready"),
    [packetState.data.packets],
  );

  if (!canUseModule) {
    return (
      <div className="rounded-[18px] border border-slate-200 bg-white px-5 py-4 text-sm text-slate-600">
        No tienes permisos para ver esta pantalla.
      </div>
    );
  }

  function toggleOrderExpanded(orderId: string) {
    setExpandedOrderIds((current) =>
      current.includes(orderId)
        ? current.filter((value) => value !== orderId)
        : [...current, orderId],
    );
  }

  function addQuoteUrl() {
    const normalized = quoteUrlInput.trim();
    if (!normalized) return;
    setQuoteUrls((current) => (current.includes(normalized) ? current : [...current, normalized]));
    setQuoteUrlInput("");
  }

  async function handleSendBatch() {
    if (!profile || !selectedBatch) return;
    setActionError(null);
    setActionMessage(null);
    setWorkingPacketId("new");
    try {
      const result = await createAndSubmitPacketFromReadyOrders({
        actor: profile,
        supplierName: selectedBatch.supplier,
        totalAmount: selectedBatch.totalAmount,
        evidenceUrls: quoteUrls,
        itemRefIds: selectedBatch.items.map((item) => item.refId),
        legacyOrdersById,
      });
      setQuoteUrls([]);
      setExpandedOrderIds([]);
      setActionMessage(
        `Paquete enviado a Direccion General.${result.folio ? ` Folio ${result.folio}.` : ""}`,
      );
    } catch (error) {
      setActionError(
        error instanceof Error ? error.message : "No se pudo enviar el paquete a Direccion General.",
      );
    } finally {
      setWorkingPacketId(null);
    }
  }

  function openSelectedBatchPdf() {
    if (!selectedBatch) return;
    savePacketPreviewDraft({
      supplier: selectedBatch.supplier,
      orderIds: selectedBatch.orderIds,
      items: selectedBatch.items.map((item) => ({
        orderId: item.orderId,
        lineNumber: item.lineNumber,
        description: item.description,
        quantity: item.quantity,
        unit: item.unit,
        amount: item.amount,
      })),
      totalAmount: selectedBatch.totalAmount,
      evidenceUrls: quoteUrls,
      issuedAt: Date.now(),
    });
    void navigate("/purchase-packets/preview");
  }

  async function handleApprovePacket(bundle: PacketBundleRecord) {
    if (!profile) return;
    setActionError(null);
    setActionMessage(null);
    setWorkingPacketId(bundle.packet.id);
    try {
      await approvePacket(bundle, profile);
      setActionMessage("Paquete aprobado por Direccion General.");
    } catch (error) {
      setActionError(error instanceof Error ? error.message : "No se pudo aprobar el paquete.");
    } finally {
      setWorkingPacketId(null);
    }
  }

  async function handleReturnPacket(bundle: PacketBundleRecord) {
    if (!profile) return;
    const reason = (returnReasonByPacketId[bundle.packet.id] ?? "").trim();
    if (!reason) {
      setActionError("Ingresa un motivo antes de regresar el paquete.");
      return;
    }

    setActionError(null);
    setActionMessage(null);
    setWorkingPacketId(bundle.packet.id);
    try {
      await returnPacketForRework(bundle, profile, reason);
      setReturnReasonByPacketId((current) => ({ ...current, [bundle.packet.id]: "" }));
      setActionMessage("Paquete regresado a Compras.");
    } catch (error) {
      setActionError(error instanceof Error ? error.message : "No se pudo regresar el paquete.");
    } finally {
      setWorkingPacketId(null);
    }
  }

  async function handleCloseItems(bundle: PacketBundleRecord) {
    if (!profile) return;
    const selectedItemIds = closeSelectionByPacketId[bundle.packet.id] ?? [];
    const reason = (closeReasonByPacketId[bundle.packet.id] ?? "").trim();

    if (!selectedItemIds.length) {
      setActionError("Selecciona al menos un item antes de cerrarlo sin compra.");
      return;
    }
    if (!reason) {
      setActionError("Ingresa un motivo antes de cerrar items sin compra.");
      return;
    }

    setActionError(null);
    setActionMessage(null);
    setWorkingPacketId(bundle.packet.id);
    try {
      await closePacketItemsAsUnpurchasable(
        bundle,
        profile,
        selectedItemIds,
        reason,
        legacyOrdersById,
      );
      setCloseReasonByPacketId((current) => ({ ...current, [bundle.packet.id]: "" }));
      setCloseSelectionByPacketId((current) => ({ ...current, [bundle.packet.id]: [] }));
      setActionMessage("Items marcados como no comprables.");
    } catch (error) {
      setActionError(error instanceof Error ? error.message : "No se pudieron cerrar los items.");
    } finally {
      setWorkingPacketId(null);
    }
  }

  return (
    <div className="space-y-6 pb-4">
      <section className="rounded-[22px] border border-slate-200 bg-white px-5 py-5">
        <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
          <div>
            <p className="text-[20px] font-semibold text-slate-900">Compras / Dashboard</p>
            <p className="mt-1 text-sm text-slate-600">
              Agrupa items por proveedor, agrega cotizaciones y manda el paquete a Direccion General.
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <StatusBadge label={`${pendingOrders.length} orden(es) en espera`} tone="info" />
            <StatusBadge label={`${approvalPackets.length} paquete(s) por revisar`} tone="warning" />
            <StatusBadge label={`${executionReadyPackets.length} paquete(s) aprobados`} tone="success" />
            <Link
              to="/purchase-packets/history"
              className="inline-flex items-center rounded-2xl border border-slate-300 bg-white px-3 py-2 text-sm font-medium text-slate-700"
            >
              Historial de PDFs
            </Link>
          </div>
        </div>

        {actionError ? (
          <div className="mt-5 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
            {actionError}
          </div>
        ) : null}
        {actionMessage ? (
          <div className="mt-5 rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-700">
            {actionMessage}
          </div>
        ) : null}
      </section>

      <section className="grid gap-5 xl:grid-cols-[1.1fr_0.9fr]">
        <article className="rounded-[22px] border border-slate-200 bg-white px-5 py-5">
          <p className="text-[20px] font-semibold text-slate-900">Agrupar por proveedor</p>
          <p className="mt-1 text-sm text-slate-600">
            Selecciona un proveedor detectado en los items pendientes y prepara el paquete a enviar.
          </p>

          {packetState.isLoading || legacyOrdersState.isLoading ? (
            <div className="mt-5 text-sm text-slate-500">Cargando ordenes para dashboard...</div>
          ) : packetState.error || legacyOrdersState.error ? (
            <div className="mt-5 text-sm text-red-700">
              No se pudo cargar el modulo: {packetState.error ?? legacyOrdersState.error}
            </div>
          ) : !suppliers.length ? (
            <div className="mt-5 rounded-[18px] bg-slate-100 px-4 py-4 text-sm text-slate-600">
              No hay items pendientes por agrupar en este momento.
            </div>
          ) : (
            <>
              <label className="mt-5 block">
                <span className="mb-2 block text-sm font-medium text-slate-700">Proveedor</span>
                <select
                  value={selectedSupplier ?? ""}
                  onChange={(event) => {
                    setSelectedSupplier(event.target.value || null);
                    setQuoteUrls([]);
                    setExpandedOrderIds([]);
                  }}
                  className="w-full rounded-[18px] border border-slate-300 bg-white px-4 py-3 text-[15px] text-slate-900 outline-none"
                >
                  {suppliers.map((supplier) => (
                    <option key={supplier} value={supplier}>
                      {supplier}
                    </option>
                  ))}
                </select>
              </label>

              {selectedBatch ? (
                <>
                  <div className="mt-5 grid gap-3 md:grid-cols-3">
                    <InfoBox label="Ordenes involucradas" value={`${selectedBatch.orderIds.length}`} />
                    <InfoBox label="Items del proveedor" value={`${selectedBatch.items.length}`} />
                    <InfoBox
                      label="Monto detectado"
                      value={`$${selectedBatch.totalAmount.toLocaleString("es-MX")}`}
                    />
                  </div>

                  <div className="mt-5">
                    <p className="text-sm font-medium text-slate-700">Ordenes involucradas</p>
                    <div className="mt-3 space-y-3">
                      {selectedBatch.orderIds.map((orderId) => {
                        const order = pendingOrders.find((candidate) => candidate.orderId === orderId);
                        const orderItems = selectedBatch.items.filter((item) => item.orderId === orderId);
                        const expanded = expandedOrderIds.includes(orderId);
                        if (!order) return null;

                        return (
                          <div
                            key={orderId}
                            className="rounded-[18px] border border-slate-200 bg-slate-50 px-4 py-4"
                          >
                            <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
                              <div>
                                <p className="text-sm font-semibold text-slate-900">{orderId}</p>
                                <p className="mt-1 text-xs text-slate-500">
                                  {order.requesterName} · {order.areaName}
                                </p>
                                <div className="mt-2 flex flex-wrap gap-2">
                                  <StatusBadge
                                    label={order.urgency === "urgente" ? "Urgente" : "Normal"}
                                    tone={order.urgency === "urgente" ? "danger" : "neutral"}
                                  />
                                  <StatusBadge
                                    label={`${orderItems.length} item(s) con este proveedor`}
                                    tone="info"
                                  />
                                </div>
                              </div>

                              <div className="flex flex-wrap gap-2">
                                <Link
                                  to={`/orders/history/${orderId}/print`}
                                  className="inline-flex items-center rounded-2xl border border-slate-700 bg-white px-3 py-2 text-sm font-medium text-slate-800"
                                >
                                  <FileText size={15} className="mr-2" />
                                  Ver PDF
                                </Link>
                                <button
                                  type="button"
                                  onClick={() => toggleOrderExpanded(orderId)}
                                  className="inline-flex items-center rounded-2xl border border-slate-300 bg-white px-3 py-2 text-sm font-medium text-slate-700"
                                >
                                  {expanded ? (
                                    <ChevronUp size={15} className="mr-2" />
                                  ) : (
                                    <ChevronDown size={15} className="mr-2" />
                                  )}
                                  {expanded ? "Ocultar items" : "Ver items"}
                                </button>
                              </div>
                            </div>

                            {expanded ? (
                              <div className="mt-4 space-y-2">
                                {orderItems.map((item) => (
                                  <div
                                    key={item.refId}
                                    className="rounded-[16px] border border-slate-200 bg-white px-4 py-3"
                                  >
                                    <p className="text-sm font-medium text-slate-900">
                                      Item {item.lineNumber} · {item.description}
                                    </p>
                                    <p className="mt-1 text-xs text-slate-500">
                                      {item.quantity} {item.unit} · ${item.amount.toLocaleString("es-MX")}
                                    </p>
                                  </div>
                                ))}
                              </div>
                            ) : null}
                          </div>
                        );
                      })}
                    </div>
                  </div>
                </>
              ) : null}
            </>
          )}
        </article>

        <article className="rounded-[22px] border border-slate-200 bg-white px-5 py-5">
          <p className="text-[20px] font-semibold text-slate-900">Cotizacion y envio</p>
          <p className="mt-1 text-sm text-slate-600">
            Agrega links del proveedor y manda el paquete directo a Direccion General.
          </p>

          {selectedBatch ? (
            <div className="mt-5 space-y-4">
              <div className="rounded-[18px] bg-slate-100 px-4 py-4 text-sm text-slate-700">
                <p className="font-medium text-slate-900">{selectedBatch.supplier}</p>
                <p className="mt-1">{selectedBatch.items.length} item(s) listos para enviarse.</p>
              </div>

              <label className="block">
                <span className="mb-2 block text-sm font-medium text-slate-700">
                  Agregar link de cotizacion
                </span>
                <div className="flex gap-2">
                  <input
                    value={quoteUrlInput}
                    onChange={(event) => setQuoteUrlInput(event.target.value)}
                    placeholder="https://drive.google.com/..."
                    className="flex-1 border-0 border-b border-slate-500 bg-transparent px-0 py-2 text-[15px] text-slate-900 outline-none"
                  />
                  <button
                    type="button"
                    onClick={addQuoteUrl}
                    className="inline-flex items-center rounded-2xl border border-slate-700 bg-white px-4 py-2 text-sm font-medium text-slate-800"
                  >
                    <Plus size={15} className="mr-2" />
                    Agregar
                  </button>
                </div>
              </label>

              {quoteUrls.length ? (
                <div className="space-y-2">
                  {quoteUrls.map((url) => (
                    <div
                      key={url}
                      className="flex items-center justify-between gap-3 rounded-[16px] border border-slate-200 bg-slate-50 px-4 py-3 text-sm"
                    >
                      <button
                        type="button"
                        onClick={() => openUrl(url)}
                        className="inline-flex min-w-0 items-center text-left text-blue-700 underline"
                      >
                        <Link2 size={14} className="mr-2 shrink-0" />
                        <span className="truncate">{url}</span>
                      </button>
                      <button
                        type="button"
                        onClick={() => setQuoteUrls((current) => current.filter((value) => value !== url))}
                        className="rounded-2xl border border-slate-300 bg-white px-3 py-1 text-xs font-medium text-slate-700"
                      >
                        Quitar
                      </button>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="text-sm text-slate-500">Aun no hay links de cotizacion agregados.</p>
              )}

              <div className="flex flex-wrap gap-3">
                <button
                  type="button"
                  onClick={openSelectedBatchPdf}
                  className="inline-flex items-center rounded-2xl border border-slate-700 bg-white px-4 py-2.5 text-sm font-medium text-slate-800"
                >
                  <FileText size={15} className="mr-2" />
                  Ver PDF de paquete por proveedor
                </button>
                <button
                  type="button"
                  onClick={handleSendBatch}
                  disabled={!canSendToDireccion || workingPacketId === "new"}
                  className="inline-flex items-center rounded-2xl border border-slate-900 bg-slate-900 px-4 py-2.5 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
                >
                  <Send size={15} className="mr-2" />
                  {workingPacketId === "new" ? "Enviando..." : "Enviar a Direccion General"}
                </button>
              </div>
            </div>
          ) : (
            <div className="mt-5 rounded-[18px] bg-slate-100 px-4 py-4 text-sm text-slate-600">
              Selecciona un proveedor para preparar su paquete.
            </div>
          )}
        </article>
      </section>

      <section className="rounded-[22px] border border-slate-200 bg-white px-5 py-5">
        <p className="text-[20px] font-semibold text-slate-900">Ordenes en espera</p>
        <p className="mt-1 text-sm text-slate-600">
          Las ordenes permanecen aqui hasta que todos sus items se hayan mandado a Direccion General.
        </p>

        {pendingOrders.length ? (
          <div className="mt-5 divide-y divide-slate-200">
            {pendingOrders.map((order) => (
              <div key={order.orderId} className="flex flex-col gap-3 py-4 lg:flex-row lg:items-center lg:justify-between">
                <div>
                  <p className="text-sm font-semibold text-slate-900">{order.orderId}</p>
                  <p className="mt-1 text-xs text-slate-500">
                    {order.requesterName} · {order.areaName}
                  </p>
                </div>
                <div className="flex flex-wrap items-center gap-3">
                  <span className="text-sm text-slate-600">
                    {order.pendingItems.length} item(s) pendientes · {order.sentItemsCount > 0 ? "Espera" : "Pendiente"}
                  </span>
                  <Link
                    to={`/orders/history/${order.orderId}/print`}
                    className="inline-flex items-center rounded-2xl border border-slate-700 bg-white px-3 py-2 text-sm font-medium text-slate-800"
                  >
                    <FileText size={15} className="mr-2" />
                    Ver PDF
                  </Link>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="mt-5 text-sm text-slate-500">
            No hay ordenes esperando agrupacion.
          </div>
        )}
      </section>

      <section className="grid gap-5 xl:grid-cols-[1.1fr_0.9fr]">
        <article className="rounded-[22px] border border-slate-200 bg-white px-5 py-5">
          <p className="text-[20px] font-semibold text-slate-900">Direccion General</p>
          <p className="mt-1 text-sm text-slate-600">
            Revisa los paquetes enviados por proveedor y decide si avanzan o regresan a Compras.
          </p>

          {!approvalPackets.length ? (
            <div className="mt-5 rounded-[18px] bg-slate-100 px-4 py-4 text-sm text-slate-600">
              No hay paquetes pendientes de revision ejecutiva.
            </div>
          ) : (
            <div className="mt-5 space-y-4">
              {approvalPackets.map((bundle) => (
                <ExecutivePacketCard
                  key={bundle.packet.id}
                  bundle={bundle}
                  canApprove={canApprove}
                  isBusy={workingPacketId === bundle.packet.id}
                  returnReason={returnReasonByPacketId[bundle.packet.id] ?? ""}
                  closeReason={closeReasonByPacketId[bundle.packet.id] ?? ""}
                  selectedCloseItemIds={closeSelectionByPacketId[bundle.packet.id] ?? []}
                  onChangeReturnReason={(value) =>
                    setReturnReasonByPacketId((current) => ({ ...current, [bundle.packet.id]: value }))
                  }
                  onChangeCloseReason={(value) =>
                    setCloseReasonByPacketId((current) => ({ ...current, [bundle.packet.id]: value }))
                  }
                  onToggleCloseItem={(itemRefId, selected) =>
                    setCloseSelectionByPacketId((current) => {
                      const next = new Set(current[bundle.packet.id] ?? []);
                      if (selected) next.add(itemRefId);
                      else next.delete(itemRefId);
                      return { ...current, [bundle.packet.id]: [...next] };
                    })
                  }
                  onApprove={() => void handleApprovePacket(bundle)}
                  onReturn={() => void handleReturnPacket(bundle)}
                  onCloseItems={() => void handleCloseItems(bundle)}
                />
              ))}
            </div>
          )}
        </article>

        <article className="rounded-[22px] border border-slate-200 bg-white px-5 py-5">
          <p className="text-[20px] font-semibold text-slate-900">Paquetes aprobados</p>
          <p className="mt-1 text-sm text-slate-600">
            Referencia rapida de paquetes ya aprobados y listos para seguimiento.
          </p>

          {!executionReadyPackets.length ? (
            <div className="mt-5 rounded-[18px] bg-slate-100 px-4 py-4 text-sm text-slate-600">
              No hay paquetes aprobados por mostrar.
            </div>
          ) : (
            <div className="mt-5 space-y-3">
              {executionReadyPackets.map((bundle) => (
                <div
                  key={bundle.packet.id}
                  className="rounded-[18px] border border-slate-200 bg-slate-50 px-4 py-4"
                >
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <p className="text-sm font-semibold text-slate-900">
                        {(bundle.packet.folio ?? bundle.packet.id).trim()} · {bundle.packet.supplierName}
                      </p>
                      <p className="mt-1 text-xs text-slate-500">
                        {bundle.packet.itemRefs.length} item(s) · $
                        {bundle.packet.totalAmount.toLocaleString("es-MX")}
                      </p>
                    </div>
                    <StatusBadge
                      label={formatPacketStatus(bundle.packet.status)}
                      tone={packetTone(bundle.packet.status)}
                    />
                  </div>
                  <div className="mt-3">
                    <Link
                      to={`/purchase-packets/${bundle.packet.id}/pdf`}
                      className="inline-flex items-center rounded-2xl border border-slate-700 bg-white px-3 py-2 text-sm font-medium text-slate-800"
                    >
                      <FileText size={15} className="mr-2" />
                      Ver PDF de paquete
                    </Link>
                  </div>
                </div>
              ))}
            </div>
          )}
        </article>
      </section>
    </div>
  );
}

function ExecutivePacketCard({
  bundle,
  canApprove,
  isBusy,
  returnReason,
  closeReason,
  selectedCloseItemIds,
  onChangeReturnReason,
  onChangeCloseReason,
  onToggleCloseItem,
  onApprove,
  onReturn,
  onCloseItems,
}: {
  bundle: PacketBundleRecord;
  canApprove: boolean;
  isBusy: boolean;
  returnReason: string;
  closeReason: string;
  selectedCloseItemIds: string[];
  onChangeReturnReason: (value: string) => void;
  onChangeCloseReason: (value: string) => void;
  onToggleCloseItem: (itemRefId: string, selected: boolean) => void;
  onApprove: () => void;
  onReturn: () => void;
  onCloseItems: () => void;
}) {
  return (
    <article className="rounded-[20px] border border-slate-200 bg-slate-50 px-4 py-4">
      <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
        <div>
          <p className="text-sm font-semibold text-slate-900">
            {(bundle.packet.folio ?? bundle.packet.id).trim()} · {bundle.packet.supplierName}
          </p>
          <p className="mt-1 text-xs text-slate-500">
            {bundle.packet.itemRefs.length} item(s) · $
            {bundle.packet.totalAmount.toLocaleString("es-MX")}
          </p>
          <p className="mt-1 text-xs text-slate-500">
            Enviado: {formatDateTime(bundle.packet.submittedAt)}
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <StatusBadge label={formatPacketStatus(bundle.packet.status)} tone={packetTone(bundle.packet.status)} />
          <StatusBadge label={`v${bundle.packet.version}`} tone="neutral" />
        </div>
      </div>

      <div className="mt-3">
        <Link
          to={`/purchase-packets/${bundle.packet.id}/pdf`}
          className="inline-flex items-center rounded-2xl border border-slate-700 bg-white px-3 py-2 text-sm font-medium text-slate-800"
        >
          <FileText size={15} className="mr-2" />
          Ver PDF de paquete
        </Link>
      </div>

      {bundle.packet.evidenceUrls.length ? (
        <div className="mt-4 rounded-[16px] border border-slate-200 bg-white px-4 py-3">
          <p className="text-sm font-medium text-slate-800">Links de cotizacion</p>
          <div className="mt-2 space-y-2">
            {bundle.packet.evidenceUrls.map((url) => (
              <button
                key={url}
                type="button"
                onClick={() => openUrl(url)}
                className="block text-left text-sm text-blue-700 underline"
              >
                {url}
              </button>
            ))}
          </div>
        </div>
      ) : null}

      <div className="mt-4 space-y-2">
        {bundle.packet.itemRefs.map((item) => (
          <label
            key={item.id}
            className="flex gap-3 rounded-[16px] border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700"
          >
            <input
              type="checkbox"
              checked={selectedCloseItemIds.includes(item.id)}
              disabled={!canApprove || item.closedAsUnpurchasable || isBusy}
              onChange={(event) => onToggleCloseItem(item.id, event.target.checked)}
              className="mt-1"
            />
            <span className="flex-1">
              {item.orderId} · Item {item.lineNumber} · {item.description} · $
              {item.amount?.toLocaleString("es-MX") ?? "0"}
              {item.closedAsUnpurchasable ? " · Cerrado sin compra" : ""}
            </span>
          </label>
        ))}
      </div>

      {canApprove && bundle.packet.status === "approval_queue" ? (
        <div className="mt-4 space-y-3">
          <div className="flex flex-col gap-3 lg:flex-row">
            <input
              value={returnReason}
              onChange={(event) => onChangeReturnReason(event.target.value)}
              placeholder="Motivo para regresar a Compras"
              className="flex-1 border-0 border-b border-slate-500 bg-transparent px-0 py-2 text-[15px] text-slate-900 outline-none"
            />
            <button
              type="button"
              onClick={onReturn}
              disabled={isBusy}
              className="rounded-2xl border border-red-700 bg-red-700 px-4 py-2.5 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
            >
              {isBusy ? "Procesando..." : "Regresar a Compras"}
            </button>
          </div>

          <div className="flex flex-col gap-3 lg:flex-row">
            <input
              value={closeReason}
              onChange={(event) => onChangeCloseReason(event.target.value)}
              placeholder="Motivo para cerrar sin compra"
              className="flex-1 border-0 border-b border-slate-500 bg-transparent px-0 py-2 text-[15px] text-slate-900 outline-none"
            />
            <button
              type="button"
              onClick={onCloseItems}
              disabled={isBusy}
              className="rounded-2xl border border-slate-700 bg-white px-4 py-2.5 text-sm font-medium text-slate-800 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {isBusy ? "Procesando..." : "Cerrar no comprables"}
            </button>
          </div>

          <button
            type="button"
            onClick={onApprove}
            disabled={isBusy}
            className="rounded-2xl border border-slate-900 bg-slate-900 px-4 py-2.5 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
          >
            {isBusy ? "Aprobando..." : "Aprobar paquete"}
          </button>
        </div>
      ) : null}
    </article>
  );
}

function InfoBox({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-[18px] bg-slate-100 px-4 py-4">
      <p className="text-xs font-medium uppercase tracking-[0.16em] text-slate-500">{label}</p>
      <p className="mt-2 text-sm font-medium text-slate-900">{value}</p>
    </div>
  );
}
