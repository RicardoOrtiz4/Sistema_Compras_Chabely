import { useEffect, useMemo, useState } from "react";
import { ArrowLeft } from "lucide-react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { hasComprasAccess } from "@/lib/access-control";
import { useRtdbValue } from "@/lib/firebase/hooks";
import { mapOrders, type PurchaseOrderItem } from "@/features/orders/orders-data";
import {
  hasComprasAssignment,
  isComprasDraftComplete,
} from "@/features/workflow/authorize-orders-service";
import {
  readComprasPendingDraft,
  saveComprasPendingDraft,
} from "@/features/workflow/compras-pending-state";
import { useSessionStore } from "@/store/session-store";
import { StatusBadge } from "@/shared/ui/status-badge";

function uniqueSupplierOptions(orders: ReturnType<typeof mapOrders>) {
  return [
    ...new Set(
      orders.flatMap((order) => order.items.map((item) => item.supplier?.trim() ?? "").filter(Boolean)),
    ),
  ].sort((left, right) => left.localeCompare(right, "es"));
}

export function ComprasPendingDataPage() {
  const params = useParams();
  const orderId = params.orderId ?? "";
  const navigate = useNavigate();
  const profile = useSessionStore((state) => state.profile);
  const canOperate = hasComprasAccess(profile);
  const ordersState = useRtdbValue("purchaseOrders", mapOrders, canOperate && Boolean(orderId));
  const order = (ordersState.data ?? []).find((item) => item.id === orderId && item.status === "sourcing");
  const supplierOptions = useMemo(() => uniqueSupplierOptions(ordersState.data ?? []), [ordersState.data]);

  const [selectedLines, setSelectedLines] = useState<number[]>([]);
  const [selectedSupplier, setSelectedSupplier] = useState("");
  const [selectedAmount, setSelectedAmount] = useState("");
  const [selectedInternalOrder, setSelectedInternalOrder] = useState("");
  const [workingItems, setWorkingItems] = useState<PurchaseOrderItem[]>([]);
  const [pageError, setPageError] = useState<string | null>(null);

  useEffect(() => {
    if (!order) return;
    const cached = readComprasPendingDraft(order.id);
    const itemsCopy = (cached?.items ?? order.items).map((item) => ({ ...item }));
    setWorkingItems(itemsCopy);
    const preselected = itemsCopy.filter(hasComprasAssignment).map((item) => item.line);
    setSelectedLines(preselected);
    setSelectedSupplier("");
    setSelectedAmount("");
    setSelectedInternalOrder("");
  }, [order?.id]);

  if (!canOperate) {
    return (
      <div className="rounded-[18px] border border-slate-200 bg-white px-5 py-4 text-sm text-slate-600">
        No tienes permisos para ver esta pantalla.
      </div>
    );
  }

  function syncFormFromSelection(nextItems: PurchaseOrderItem[], nextLines: number[]) {
    const selected = nextItems.filter((item) => nextLines.includes(item.line));
    const first = selected[0];
    setSelectedSupplier(
      selected.length > 0 && selected.every((item) => (item.supplier ?? "") === (first?.supplier ?? ""))
        ? first?.supplier ?? ""
        : "",
    );
    setSelectedAmount(
      selected.length > 0 && selected.every((item) => (item.budget ?? null) === (first?.budget ?? null))
        ? first?.budget?.toString() ?? ""
        : "",
    );
    setSelectedInternalOrder(
      selected.length > 0 &&
        selected.every((item) => (item.internalOrder ?? "") === (first?.internalOrder ?? ""))
        ? first?.internalOrder ?? ""
        : "",
    );
  }

  function toggleLine(line: number, checked: boolean) {
    setSelectedLines((current) => {
      const next = checked ? [...new Set([...current, line])] : current.filter((value) => value !== line);
      syncFormFromSelection(workingItems, next);
      return next;
    });
  }

  function toggleAll(checked: boolean) {
    const next = checked ? workingItems.map((item) => item.line) : [];
    setSelectedLines(next);
    syncFormFromSelection(workingItems, next);
  }

  function applySelection() {
    if (!selectedLines.length) {
      setPageError("Selecciona al menos un item antes de aplicar.");
      return;
    }

    setPageError(null);
    setWorkingItems((current) =>
      current.map((item) =>
        selectedLines.includes(item.line)
          ? {
              ...item,
              supplier: selectedSupplier.trim() || undefined,
              budget:
                selectedAmount.trim() === ""
                  ? undefined
                  : Number.isFinite(Number(selectedAmount))
                    ? Number(selectedAmount)
                    : undefined,
              internalOrder: selectedInternalOrder.trim() || undefined,
            }
          : item,
      ),
    );
  }

  function undoItem(line: number) {
    if (!order) return;
    const original = order.items.find((item) => item.line === line);
    if (!original) return;
    setWorkingItems((current) => current.map((item) => (item.line === line ? { ...original } : item)));
  }

  function handleSaveDraft() {
    if (!order) return;
    const currentDraft = readComprasPendingDraft(order.id);
    saveComprasPendingDraft(order.id, {
      items: workingItems,
      confirmed: currentDraft?.confirmed ?? false,
      processName: currentDraft?.processName,
      processArea: currentDraft?.processArea,
    });
    navigate(`/workflow/compras/${order.id}`);
  }

  return (
    <div className="mx-auto max-w-6xl space-y-6 pb-6 pt-4">
      <section className="flex flex-wrap items-center justify-between gap-3 rounded-[22px] border border-slate-200 bg-white px-5 py-4">
        <div>
          <p className="text-[20px] font-semibold text-slate-900">Completar datos</p>
          <p className="mt-1 text-sm text-slate-600">
            Captura proveedor, monto y OC interna antes de confirmar la orden.
          </p>
        </div>
        {order ? (
          <Link
            to={`/workflow/compras/${order.id}`}
            className="inline-flex items-center rounded-2xl border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700"
          >
            <ArrowLeft size={16} className="mr-2" />
            Volver al PDF
          </Link>
        ) : null}
      </section>

      {pageError ? (
        <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
          {pageError}
        </div>
      ) : null}

      {!order ? (
        <div className="rounded-[18px] border border-slate-200 bg-white px-5 py-6 text-sm text-slate-500">
          La orden ya no esta disponible en Compras.
        </div>
      ) : (
        <section className="grid gap-5 xl:grid-cols-[0.9fr_1.1fr]">
          <article className="rounded-[22px] border border-slate-200 bg-white px-5 py-5">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <p className="text-[20px] font-semibold text-slate-900">{order.id}</p>
                <p className="mt-1 text-sm text-slate-600">
                  {order.requesterName} · {order.areaName}
                </p>
              </div>
              <StatusBadge
                label={isComprasDraftComplete(workingItems) ? "Completo" : "Faltan datos"}
                tone={isComprasDraftComplete(workingItems) ? "success" : "warning"}
              />
            </div>

            {order.clientNote ? (
              <div className="mt-5 rounded-[18px] bg-slate-100 px-4 py-4">
                <p className="text-sm font-medium text-slate-700">Observaciones</p>
                <p className="mt-2 text-sm text-slate-800">{order.clientNote}</p>
              </div>
            ) : null}

            <div className="mt-5 grid gap-4 lg:grid-cols-3">
              <label className="block">
                <span className="mb-2 block text-sm font-medium text-slate-700">Proveedor</span>
                <input
                  list="compras-suppliers"
                  value={selectedSupplier}
                  onChange={(event) => setSelectedSupplier(event.target.value)}
                  className="w-full border-0 border-b border-slate-500 bg-transparent px-0 py-2 text-[15px] text-slate-900 outline-none"
                />
                <datalist id="compras-suppliers">
                  {supplierOptions.map((option) => (
                    <option key={option} value={option} />
                  ))}
                </datalist>
              </label>
              <label className="block">
                <span className="mb-2 block text-sm font-medium text-slate-700">Monto total</span>
                <input
                  type="number"
                  min="0"
                  step="0.01"
                  value={selectedAmount}
                  onChange={(event) => setSelectedAmount(event.target.value)}
                  className="w-full border-0 border-b border-slate-500 bg-transparent px-0 py-2 text-[15px] text-slate-900 outline-none"
                />
              </label>
              <label className="block">
                <span className="mb-2 block text-sm font-medium text-slate-700">OC interna</span>
                <input
                  value={selectedInternalOrder}
                  onChange={(event) => setSelectedInternalOrder(event.target.value)}
                  className="w-full border-0 border-b border-slate-500 bg-transparent px-0 py-2 text-[15px] text-slate-900 outline-none"
                />
              </label>
            </div>

            <div className="mt-5 rounded-[18px] bg-slate-100 px-4 py-4">
              <label className="inline-flex items-center gap-2 text-sm font-medium text-slate-700">
                <input
                  type="checkbox"
                  checked={workingItems.length > 0 && selectedLines.length === workingItems.length}
                  onChange={(event) => toggleAll(event.target.checked)}
                />
                <span>Seleccionar todos</span>
              </label>
            </div>
          </article>

          <article className="rounded-[22px] border border-slate-200 bg-white px-5 py-5">
            <div className="space-y-3">
              {workingItems.map((item) => (
                <div
                  key={`${order.id}-${item.line}`}
                  className="rounded-[18px] border border-slate-200 bg-[#edf4f7] px-4 py-4"
                >
                  <div className="flex gap-3">
                    <input
                      type="checkbox"
                      checked={selectedLines.includes(item.line)}
                      onChange={(event) => toggleLine(item.line, event.target.checked)}
                      className="mt-1"
                    />
                    <div className="flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <p className="text-sm font-semibold text-slate-900">
                          Item {item.line} - {item.description}
                        </p>
                        {hasComprasAssignment(item) ? (
                          <>
                            <StatusBadge label="Completo" tone="success" />
                            <button
                              type="button"
                              onClick={() => undoItem(item.line)}
                              className="rounded-2xl border border-slate-300 bg-white px-3 py-1 text-xs font-medium text-slate-700"
                            >
                              Deshacer
                            </button>
                          </>
                        ) : null}
                      </div>
                      <p className="mt-1 text-xs text-slate-500">
                        {item.pieces} {item.unit} · {item.partNumber || "Sin parte"} · Cliente: {item.customer || "-"}
                      </p>
                      <div className="mt-3 grid gap-3 md:grid-cols-3">
                        <MiniField label="Proveedor" value={item.supplier || "-"} />
                        <MiniField
                          label="Monto"
                          value={item.budget != null ? `$${item.budget.toLocaleString("es-MX")}` : "-"}
                        />
                        <MiniField label="OC interna" value={item.internalOrder || "-"} />
                      </div>
                    </div>
                  </div>
                </div>
              ))}
            </div>

            <div className="mt-5 flex flex-wrap justify-end gap-3">
              <button
                type="button"
                onClick={applySelection}
                className="rounded-2xl border border-slate-900 bg-slate-900 px-4 py-2.5 text-sm font-medium text-white"
              >
                Aplicar
              </button>
              <button
                type="button"
                onClick={handleSaveDraft}
                className="rounded-2xl border border-slate-700 bg-[#f7f7f7] px-4 py-2.5 text-sm font-medium text-slate-800"
              >
                Guardar y volver al PDF
              </button>
            </div>
          </article>
        </section>
      )}
    </div>
  );
}

function MiniField({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-xs font-medium uppercase tracking-[0.16em] text-slate-500">{label}</p>
      <p className="mt-1 text-sm text-slate-800">{value}</p>
    </div>
  );
}
