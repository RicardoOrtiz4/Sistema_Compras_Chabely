import { ChevronDown, ChevronUp, FileText, Link2, Plus, Send } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { hasComprasAccess } from "@/lib/access-control";
import { mapOrders } from "@/features/orders/orders-data";
import {
  type PacketBundleRecord,
  type RequestOrderRecord,
  usePacketWorkflowData,
} from "@/features/purchase-packets/packet-data";
import { createAndSubmitPacketFromReadyOrders } from "@/features/purchase-packets/purchase-packets-service";
import { savePacketPreviewDraft } from "@/features/purchase-packets/packet-pdf-preview-state";
import { useRtdbValue } from "@/lib/firebase/hooks";
import { useSessionStore } from "@/store/session-store";
import { Snackbar } from "@/shared/ui/snackbar";
import { StatusBadge } from "@/shared/ui/status-badge";

type PendingDashboardItem = {
  refId: string;
  orderId: string;
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

  if (!items.length) return null;

  return {
    supplier,
    orderIds: [...new Set(items.map((item) => item.orderId))],
    items,
    totalAmount: items.reduce((sum, item) => sum + item.amount, 0),
  };
}

function urgencyTone(urgency: string) {
  return urgency === "urgente" ? "danger" : "info";
}

function openUrl(url: string) {
  window.open(url, "_blank", "noopener,noreferrer");
}

export function ComprasDashboardPage() {
  const navigate = useNavigate();
  const profile = useSessionStore((state) => state.profile);
  const canOperate = hasComprasAccess(profile);
  const legacyOrdersState = useRtdbValue("purchaseOrders", mapOrders, canOperate);
  const packetState = usePacketWorkflowData(canOperate, legacyOrdersState.data ?? []);

  const [selectedSupplier, setSelectedSupplier] = useState<string | null>(null);
  const [quoteUrlInput, setQuoteUrlInput] = useState("");
  const [quoteUrls, setQuoteUrls] = useState<string[]>([]);
  const [expandedOrderIds, setExpandedOrderIds] = useState<string[]>([]);
  const [isSending, setIsSending] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [actionMessage, setActionMessage] = useState<string | null>(null);

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
    const nextSupplier =
      selectedSupplier && suppliers.includes(selectedSupplier) ? selectedSupplier : suppliers[0] ?? null;
    if (nextSupplier !== selectedSupplier) {
      setSelectedSupplier(nextSupplier);
      setQuoteUrls([]);
      setExpandedOrderIds([]);
    }
  }, [selectedSupplier, suppliers]);

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

  const selectedBatch = useMemo(
    () => (selectedSupplier ? buildSupplierBatch(selectedSupplier, pendingOrders) : null),
    [pendingOrders, selectedSupplier],
  );

  if (!canOperate) {
    return (
      <div className="rounded-[18px] border border-slate-200 bg-white px-5 py-4 text-sm text-slate-600">
        No tienes permisos para ver esta pantalla.
      </div>
    );
  }

  function toggleOrderExpanded(orderId: string) {
    setExpandedOrderIds((current) =>
      current.includes(orderId) ? current.filter((value) => value !== orderId) : [...current, orderId],
    );
  }

  function addQuoteUrl() {
    const normalized = quoteUrlInput.trim();
    if (!normalized) return;
    setQuoteUrls((current) => (current.includes(normalized) ? current : [...current, normalized]));
    setQuoteUrlInput("");
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

  async function handleSendBatch() {
    if (!profile || !selectedBatch) return;
    if (!quoteUrls.length) {
      setActionError("Agrega al menos un link de cotizacion.");
      return;
    }

    const confirmed = window.confirm(
      `Se enviara el paquete del proveedor ${selectedBatch.supplier} a Direccion General.`,
    );
    if (!confirmed) return;

    setActionError(null);
    setActionMessage(null);
    setIsSending(true);
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
      setIsSending(false);
    }
  }

  return (
    <div className="space-y-5 pb-4">
      {packetState.isLoading || legacyOrdersState.isLoading ? (
        <div className="rounded-[18px] border border-slate-200 bg-white px-5 py-6 text-sm text-slate-500">
          Cargando dashboard...
        </div>
      ) : packetState.error || legacyOrdersState.error ? (
        <div className="rounded-[18px] border border-red-200 bg-red-50 px-5 py-6 text-sm text-red-700">
          No se pudo cargar el modulo: {packetState.error ?? legacyOrdersState.error}
        </div>
      ) : !pendingOrders.length ? (
        <div className="rounded-[18px] border border-slate-200 bg-white px-5 py-6 text-sm text-slate-500">
          No hay items pendientes por agrupar en Dashboard.
        </div>
      ) : (
        <>
          <section className="rounded-[22px] border border-slate-200 bg-white px-5 py-5">
            <p className="text-[20px] font-semibold text-slate-900">Agrupar por proveedor</p>
            <p className="mt-1 text-sm text-slate-600">
              Selecciona un proveedor detectado en los items pendientes y envia su cotizacion a Direccion General.
            </p>

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
                                {orderItems.length} item(s) con este proveedor
                              </p>
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
                                {expanded ? <ChevronUp size={15} className="mr-2" /> : <ChevronDown size={15} className="mr-2" />}
                                {expanded ? "Ocultar items" : "Ver items"}
                              </button>
                            </div>
                          </div>

                          {expanded ? (
                            <div className="mt-4 space-y-2">
                              {orderItems.map((item) => (
                                <div
                                  key={item.refId}
                                  className="flex items-start justify-between gap-3 rounded-[16px] border border-slate-200 bg-white px-4 py-3"
                                >
                                  <div>
                                    <p className="text-sm font-medium text-slate-900">Item {item.lineNumber}</p>
                                    <p className="mt-1 text-sm text-slate-700">
                                      {item.description} | {item.quantity} {item.unit}
                                    </p>
                                  </div>
                                  <p className="text-sm text-slate-700">
                                    ${item.amount.toLocaleString("es-MX")}
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

                <div className="mt-5 flex flex-wrap gap-3">
                  <button
                    type="button"
                    onClick={addQuoteUrl}
                    className="inline-flex items-center rounded-2xl border border-slate-700 bg-white px-4 py-2 text-sm font-medium text-slate-800"
                  >
                    <Plus size={15} className="mr-2" />
                    Agregar link de cotizacion
                  </button>
                  <button
                    type="button"
                    onClick={openSelectedBatchPdf}
                    className="inline-flex items-center rounded-2xl border border-slate-700 bg-slate-100 px-4 py-2 text-sm font-medium text-slate-800"
                  >
                    <FileText size={15} className="mr-2" />
                    Ver PDF de paquete por proveedor
                  </button>
                </div>

                <div className="mt-4">
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

                  <div className="mt-3">
                    {!quoteUrls.length ? (
                      <p className="text-sm text-slate-500">Aun no hay links de cotizacion agregados.</p>
                    ) : (
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
                    )}
                  </div>
                </div>

                <div className="mt-5 flex justify-end">
                  <button
                    type="button"
                    onClick={handleSendBatch}
                    disabled={isSending}
                    className="inline-flex items-center rounded-2xl border border-slate-900 bg-slate-900 px-4 py-2.5 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
                  >
                    <Send size={15} className="mr-2" />
                    {isSending ? "Enviando..." : "Enviar a Direccion General"}
                  </button>
                </div>
              </>
            ) : null}
          </section>

          <section className="rounded-[22px] border border-slate-200 bg-white px-5 py-5">
            <p className="text-[20px] font-semibold text-slate-900">Ordenes en espera</p>
            <p className="mt-1 text-sm text-slate-600">
              Las ordenes permanecen aqui hasta que todos sus items se hayan mandado a Direccion General.
            </p>

            <div className="mt-5 divide-y divide-slate-200">
              {pendingOrders.map((order) => (
                <div
                  key={order.orderId}
                  className="flex flex-col gap-3 py-4 lg:flex-row lg:items-center lg:justify-between"
                >
                  <div>
                    <p className="text-sm font-semibold text-slate-900">{order.orderId}</p>
                    <p className="mt-1 text-xs text-slate-500">
                      {order.pendingItems.length} item(s) pendientes | {order.sentItemsCount > 0 ? "Espera" : "Pendiente"}
                    </p>
                  </div>
                  <Link
                    to={`/orders/history/${order.orderId}/print`}
                    className="inline-flex items-center rounded-2xl border border-slate-700 bg-white px-3 py-2 text-sm font-medium text-slate-800"
                  >
                    <FileText size={15} className="mr-2" />
                    Ver PDF
                  </Link>
                </div>
              ))}
            </div>
          </section>
        </>
      )}

      <Snackbar message={actionError} tone="error" />
      <Snackbar message={actionMessage} tone="success" />
    </div>
  );
}
