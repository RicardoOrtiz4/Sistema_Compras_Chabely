import { useEffect, useMemo, useState } from "react";
import { ArrowLeft } from "lucide-react";
import { Link, useNavigate, useParams } from "react-router-dom";
import {
  buildOrderPdfBytes,
  type BuildOrderPdfInput,
} from "@/features/orders/order-pdf-service";
import { mapOrders, type PurchaseOrderRecord } from "@/features/orders/orders-data";
import {
  authorizeOrderToCompras,
  returnOrderToRequester,
} from "@/features/workflow/authorize-orders-service";
import { hasComprasAccess, hasDireccionApprovalAccess } from "@/lib/access-control";
import { useRtdbValue } from "@/lib/firebase/hooks";
import { useBrandingStore } from "@/store/branding-store";
import { useSessionStore } from "@/store/session-store";
import { Snackbar } from "@/shared/ui/snackbar";

function buildPdfInput(
  order: PurchaseOrderRecord,
  company: "chabely" | "acerpro",
  overrides?: {
    authorizedByName?: string;
    authorizedByArea?: string;
  },
): BuildOrderPdfInput {
  return {
    company,
    fileLabel: "autorizacion_requisicion",
    order: {
      ...order,
      authorizedByName: overrides?.authorizedByName ?? order.authorizedByName,
      authorizedByArea: overrides?.authorizedByArea ?? order.authorizedByArea,
      paymentReceiptUrls: order.paymentReceiptUrls ?? [],
      facturaPdfUrls: order.facturaPdfUrls ?? [],
    },
  };
}

export function AuthorizeOrderPdfPage() {
  const params = useParams();
  const navigate = useNavigate();
  const orderId = params.orderId ?? "";
  const profile = useSessionStore((state) => state.profile);
  const company = useBrandingStore((state) => state.company);
  const canAuthorize = hasComprasAccess(profile) || hasDireccionApprovalAccess(profile);
  const ordersState = useRtdbValue("purchaseOrders", mapOrders, canAuthorize && Boolean(orderId));
  const order = (ordersState.data ?? []).find((item) => item.id === orderId && item.status === "intakeReview");

  const [pdfUrl, setPdfUrl] = useState<string | null>(null);
  const [isLoadingPdf, setIsLoadingPdf] = useState(true);
  const [pageError, setPageError] = useState<string | null>(null);
  const [authorizedPreview, setAuthorizedPreview] = useState(false);
  const [authorizedName, setAuthorizedName] = useState<string | null>(null);
  const [authorizedArea, setAuthorizedArea] = useState<string | null>(null);
  const [busyAction, setBusyAction] = useState<"reject" | "authorize" | "send" | null>(null);

  const effectiveAuthorizedName = authorizedPreview
    ? authorizedName
    : order?.authorizedByName?.trim() || null;
  const effectiveAuthorizedArea = authorizedPreview
    ? authorizedArea
    : order?.authorizedByArea?.trim() || null;
  const isAuthorized = useMemo(
    () => Boolean(effectiveAuthorizedName?.trim()),
    [effectiveAuthorizedName],
  );

  useEffect(() => {
    if (!pageError) return;
    const timer = window.setTimeout(() => setPageError(null), 3600);
    return () => window.clearTimeout(timer);
  }, [pageError]);

  useEffect(() => {
    if (!order) {
      setPdfUrl(null);
      setIsLoadingPdf(false);
      return;
    }

    let revokedUrl: string | null = null;
    let active = true;
    setPdfUrl(null);
    setPageError(null);
    setIsLoadingPdf(true);

    void (async () => {
      try {
        const bytes = await buildOrderPdfBytes(
          buildPdfInput(order, company, {
            authorizedByName: effectiveAuthorizedName ?? undefined,
            authorizedByArea: effectiveAuthorizedArea ?? undefined,
          }),
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
      if (revokedUrl) {
        URL.revokeObjectURL(revokedUrl);
      }
    };
  }, [company, effectiveAuthorizedArea, effectiveAuthorizedName, order]);

  async function handleAuthorizePreview() {
    if (!profile || isAuthorized) return;
    setBusyAction("authorize");
    try {
      setAuthorizedPreview(true);
      setAuthorizedName(profile.name.trim() || profile.id);
      setAuthorizedArea(profile.areaDisplay.trim() || null);
    } finally {
      setBusyAction(null);
    }
  }

  async function handleReject() {
    if (!profile || !order) return;
    const reason = window.prompt("Motivo para rechazar la requisicion:")?.trim() ?? "";
    if (!reason) return;

    setPageError(null);
    setBusyAction("reject");
    try {
      await returnOrderToRequester(order, profile, reason);
      navigate("/workflow/authorize", {
        replace: true,
        state: { notice: "Orden enviada a rechazadas." },
      });
    } catch (error) {
      setPageError(error instanceof Error ? error.message : "No se pudo rechazar la requisicion.");
    } finally {
      setBusyAction(null);
    }
  }

  async function handleSendToCompras() {
    if (!profile || !order || !isAuthorized) return;

    setPageError(null);
    setBusyAction("send");
    try {
      await authorizeOrderToCompras(order, profile);
      navigate("/workflow/authorize", {
        replace: true,
        state: { notice: "Orden enviada a Compras." },
      });
    } catch (error) {
      setPageError(
        error instanceof Error ? error.message : "No se pudo mandar la requisicion a Compras.",
      );
    } finally {
      setBusyAction(null);
    }
  }

  if (!canAuthorize) {
    return (
      <div className="rounded-[18px] border border-slate-200 bg-white px-5 py-4 text-sm text-slate-600">
        No tienes permisos para ver esta pantalla.
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col bg-[#d3d9e0] text-slate-900">
      <section className="sticky top-0 z-20 flex items-center justify-between gap-3 border-b border-slate-300 bg-white/94 px-5 py-4 shadow-sm backdrop-blur">
        <div className="flex items-center gap-3">
          <Link
            to="/workflow/authorize"
            className="inline-flex items-center rounded-2xl border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700"
          >
            <ArrowLeft size={16} className="mr-2" />
            Volver
          </Link>
          <div>
            <p className="text-sm text-slate-500">Requisicion enviada</p>
            <p className="text-base font-semibold text-slate-900">{orderId}</p>
          </div>
        </div>
      </section>

      <section className="flex-1 overflow-hidden bg-white">
        {ordersState.isLoading || isLoadingPdf ? (
          <div className="flex h-[calc(100vh-153px)] items-center justify-center text-sm text-slate-500">
            Generando PDF...
          </div>
        ) : !order ? (
          <div className="flex h-[calc(100vh-153px)] items-center justify-center px-6 text-sm text-slate-500">
            La orden ya no esta disponible en Autorizaciones.
          </div>
        ) : pdfUrl ? (
          <iframe
            title={`Requisicion ${order.id}`}
            src={`${pdfUrl}#zoom=95`}
            className="h-[calc(100vh-153px)] w-full bg-white"
          />
        ) : (
          <div className="flex h-[calc(100vh-153px)] items-center justify-center px-6 text-sm text-slate-500">
            No se pudo cargar la vista previa.
          </div>
        )}
      </section>

      <section className="sticky bottom-0 z-20 border-t border-slate-300 bg-white/94 px-5 py-4 backdrop-blur">
        <div className="mx-auto flex w-full max-w-[980px] flex-wrap justify-center gap-4">
          <button
            type="button"
            onClick={() => void handleReject()}
            disabled={!order || busyAction !== null}
            className="min-w-[220px] rounded-2xl border border-red-700 bg-white px-6 py-3 text-sm font-medium text-red-700 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {busyAction === "reject" ? "Rechazando..." : "Rechazar"}
          </button>
          <button
            type="button"
            onClick={() => void handleAuthorizePreview()}
            disabled={!order || !profile || isAuthorized || busyAction !== null}
            className="min-w-[220px] rounded-2xl border border-slate-900 bg-slate-900 px-6 py-3 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
          >
            {busyAction === "authorize" ? "Autorizando..." : isAuthorized ? "Autorizada" : "Autorizar"}
          </button>
          <button
            type="button"
            onClick={() => void handleSendToCompras()}
            disabled={!order || !isAuthorized || busyAction !== null}
            className="min-w-[220px] rounded-2xl border border-emerald-700 bg-emerald-700 px-6 py-3 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
          >
            {busyAction === "send" ? "Enviando..." : "Mandar a compras"}
          </button>
        </div>
      </section>
      <Snackbar message={pageError} tone="error" />
    </div>
  );
}
