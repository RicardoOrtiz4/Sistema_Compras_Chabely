import { useEffect, useMemo, useState } from "react";
import { ArrowLeft } from "lucide-react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { buildOrderPdfBytes, type BuildOrderPdfInput } from "@/features/orders/order-pdf-service";
import { mapOrders, type PurchaseOrderItem, type PurchaseOrderRecord } from "@/features/orders/orders-data";
import {
  clearComprasPendingDraft,
  readComprasPendingDraft,
  saveComprasPendingDraft,
} from "@/features/workflow/compras-pending-state";
import {
  hasComprasAssignment,
  isComprasDraftComplete,
  processOrderToDashboard,
  returnOrderToRequester,
} from "@/features/workflow/authorize-orders-service";
import { hasComprasAccess } from "@/lib/access-control";
import { useRtdbValue } from "@/lib/firebase/hooks";
import { useBrandingStore } from "@/store/branding-store";
import { useSessionStore } from "@/store/session-store";

function buildPdfInput(
  order: PurchaseOrderRecord,
  company: "chabely" | "acerpro",
  items: PurchaseOrderItem[],
  processName?: string,
  processArea?: string,
): BuildOrderPdfInput {
  const totalBudget = items.reduce((sum, item) => sum + (item.budget ?? 0), 0);
  const supplierBudgets = items.reduce<Record<string, number>>((acc, item) => {
    const supplier = item.supplier?.trim();
    if (!supplier || item.budget == null) return acc;
    acc[supplier] = (acc[supplier] ?? 0) + item.budget;
    return acc;
  }, {});
  const uniqueSuppliers = [...new Set(items.map((item) => item.supplier?.trim() ?? "").filter(Boolean))];
  const uniqueInternalOrders = [
    ...new Set(items.map((item) => item.internalOrder?.trim() ?? "").filter(Boolean)),
  ];

  return {
    company,
    fileLabel: "compras_preview",
    order: {
      ...order,
      items,
      supplier: uniqueSuppliers.length === 1 ? uniqueSuppliers[0] : undefined,
      internalOrder: uniqueInternalOrders.length === 1 ? uniqueInternalOrders[0] : undefined,
      budget: totalBudget || undefined,
      supplierBudgets: Object.keys(supplierBudgets).length ? supplierBudgets : undefined,
      processByName: processName ?? order.processByName,
      processByArea: processArea ?? order.processByArea,
    },
  };
}

export function ComprasPendingPdfPage() {
  const params = useParams();
  const orderId = params.orderId ?? "";
  const navigate = useNavigate();
  const profile = useSessionStore((state) => state.profile);
  const company = useBrandingStore((state) => state.company);
  const canOperate = hasComprasAccess(profile);
  const ordersState = useRtdbValue("purchaseOrders", mapOrders, canOperate && Boolean(orderId));
  const order = (ordersState.data ?? []).find((item) => item.id === orderId && item.status === "sourcing");

  const [pdfUrl, setPdfUrl] = useState<string | null>(null);
  const [isLoadingPdf, setIsLoadingPdf] = useState(true);
  const [pageError, setPageError] = useState<string | null>(null);
  const [busyAction, setBusyAction] = useState<"confirm" | "send" | "return" | null>(null);
  const [returnComment, setReturnComment] = useState("");
  const [refreshSalt, setRefreshSalt] = useState(0);

  const draft = useMemo(() => (order ? readComprasPendingDraft(order.id) : null), [order?.id, refreshSalt]);
  const effectiveItems = draft?.items ?? order?.items ?? [];
  const confirmed = draft?.confirmed ?? false;
  const processName = draft?.processName;
  const processArea = draft?.processArea;

  useEffect(() => {
    if (!order) {
      setIsLoadingPdf(false);
      return;
    }

    let revokedUrl: string | null = null;
    let active = true;
    setIsLoadingPdf(true);
    setPageError(null);

    void (async () => {
      try {
        const bytes = await buildOrderPdfBytes(
          buildPdfInput(order, company, effectiveItems, processName, processArea),
        );
        if (!active) return;
        const blob = new Blob([Uint8Array.from(bytes)], { type: "application/pdf" });
        revokedUrl = URL.createObjectURL(blob);
        setPdfUrl(revokedUrl);
      } catch (error) {
        if (!active) return;
        setPageError(error instanceof Error ? error.message : "No se pudo generar el PDF.");
      } finally {
        if (active) {
          setIsLoadingPdf(false);
        }
      }
    })();

    return () => {
      active = false;
      if (revokedUrl) URL.revokeObjectURL(revokedUrl);
    };
  }, [company, effectiveItems, order, processArea, processName]);

  if (!canOperate) {
    return (
      <div className="rounded-[18px] border border-slate-200 bg-white px-5 py-4 text-sm text-slate-600">
        No tienes permisos para ver esta pantalla.
      </div>
    );
  }

  async function handleConfirm() {
    if (!profile || !order) return;
    const nextDraft = {
      items: effectiveItems,
      confirmed: true,
      processName: profile.name.trim() || profile.id,
      processArea: profile.areaDisplay.trim() || undefined,
    };
    setBusyAction("confirm");
    saveComprasPendingDraft(order.id, nextDraft);
    setRefreshSalt((current) => current + 1);
    setBusyAction(null);
  }

  async function handleSend() {
    if (!profile || !order) return;
    if (!isComprasDraftComplete(effectiveItems)) {
      setPageError("Todos los renglones deben tener proveedor y monto antes de enviarse.");
      return;
    }

    setPageError(null);
    setBusyAction("send");
    try {
      await processOrderToDashboard(order, profile, effectiveItems);
      clearComprasPendingDraft(order.id);
      navigate("/purchase-packets");
    } catch (error) {
      setPageError(error instanceof Error ? error.message : "No se pudo mandar la orden al dashboard.");
    } finally {
      setBusyAction(null);
    }
  }

  async function handleReturn() {
    if (!profile || !order) return;
    if (!returnComment.trim()) {
      setPageError("Ingresa un motivo antes de regresar la orden.");
      return;
    }

    setPageError(null);
    setBusyAction("return");
    try {
      await returnOrderToRequester({ ...order, items: effectiveItems }, profile, returnComment);
      clearComprasPendingDraft(order.id);
      navigate("/workflow/compras");
    } catch (error) {
      setPageError(error instanceof Error ? error.message : "No se pudo regresar la orden.");
    } finally {
      setBusyAction(null);
    }
  }

  return (
    <div className="flex min-h-screen flex-col bg-[#d3d9e0] text-slate-900">
      <section className="sticky top-0 z-20 flex flex-wrap items-center justify-between gap-3 border-b border-slate-300 bg-white/94 px-5 py-4 shadow-sm backdrop-blur">
        <div className="flex flex-wrap gap-3">
          <Link
            to="/workflow/compras"
            className="inline-flex items-center rounded-2xl border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700"
          >
            <ArrowLeft size={16} className="mr-2" />
            Volver
          </Link>
          {order ? (
            <Link
              to={`/workflow/compras/${order.id}/data`}
              className="inline-flex items-center rounded-2xl border border-slate-700 bg-white px-4 py-2 text-sm font-medium text-slate-800"
            >
              {draft ? "Editar datos" : "Completar datos"}
            </Link>
          ) : null}
        </div>
      </section>

      {pageError ? (
        <div className="mx-5 mt-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
          {pageError}
        </div>
      ) : null}

      <section className="flex-1 overflow-hidden bg-white">
        {ordersState.isLoading || isLoadingPdf ? (
          <div className="flex h-[calc(100vh-232px)] items-center justify-center text-sm text-slate-500">
            Generando PDF...
          </div>
        ) : !order ? (
          <div className="flex h-[calc(100vh-232px)] items-center justify-center text-sm text-slate-500">
            La orden ya no esta disponible en Compras.
          </div>
        ) : pdfUrl ? (
          <iframe
            title="Vista previa Compras"
            src={pdfUrl}
            className="h-[calc(100vh-232px)] w-full bg-white"
          />
        ) : (
          <div className="flex h-[calc(100vh-232px)] items-center justify-center text-sm text-slate-500">
            No se pudo cargar la vista previa.
          </div>
        )}
      </section>

      <section className="sticky bottom-0 z-20 space-y-4 border-t border-slate-300 bg-white/94 px-5 py-4 backdrop-blur">
        {order ? (
          <textarea
            value={returnComment}
            onChange={(event) => setReturnComment(event.target.value)}
            rows={2}
            placeholder="Motivo para regresar a correccion"
            className="w-full resize-none rounded-[18px] border border-slate-300 bg-white px-4 py-3 text-sm text-slate-900 outline-none"
          />
        ) : null}
        <div className="flex flex-wrap justify-end gap-3">
          <button
            type="button"
            onClick={handleReturn}
            disabled={!order || busyAction !== null}
            className="rounded-2xl border border-red-700 bg-white px-4 py-2.5 text-sm font-medium text-red-700 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {busyAction === "return" ? "Regresando..." : "Rechazar"}
          </button>
          <button
            type="button"
            onClick={handleConfirm}
            disabled={!order || !isComprasDraftComplete(effectiveItems) || confirmed || busyAction !== null}
            className="rounded-2xl border border-slate-900 bg-slate-900 px-4 py-2.5 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
          >
            {busyAction === "confirm" ? "Confirmando..." : confirmed ? "Confirmado" : "Confirmar"}
          </button>
          <button
            type="button"
            onClick={handleSend}
            disabled={!order || !confirmed || !isComprasDraftComplete(effectiveItems) || busyAction !== null}
            className="rounded-2xl border border-green-700 bg-green-700 px-4 py-2.5 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
          >
            {busyAction === "send" ? "Enviando..." : "Mandar al dashboard"}
          </button>
        </div>
      </section>
    </div>
  );
}
