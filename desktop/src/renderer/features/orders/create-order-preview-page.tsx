import { useEffect, useMemo, useState } from "react";
import { ArrowLeft } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { submitPurchaseOrder } from "@/features/orders/create-order-service";
import { hasComprasAccess, hasDireccionApprovalAccess } from "@/lib/access-control";
import {
  buildOrderPdfBytes,
  type BuildOrderPdfInput,
} from "@/features/orders/order-pdf-service";
import {
  clearCreateOrderFormDraft,
  clearCreateOrderPreviewDraft,
  readCreateOrderPreviewDraft,
} from "@/features/orders/create-order-preview-state";
import { Button } from "@/components/ui/button";
import { useSessionStore } from "@/store/session-store";

function buildDraftPdfInput(): BuildOrderPdfInput | null {
  const draft = readCreateOrderPreviewDraft();
  if (!draft) return null;

  return {
    company: draft.company ?? "chabely",
    fileLabel: "requisicion_preview",
    order: {
      id: "",
      requesterName: draft.requester.name,
      areaName: draft.requester.areaDisplay,
      urgency: draft.urgency,
      status: "draft",
      items: draft.items.map((item) => ({
        line: item.line,
        pieces: item.pieces,
        partNumber: item.partNumber,
        description: item.description,
        quantity: item.pieces,
        unit: item.unit,
        customer: item.customer,
        supplier: item.supplier,
        reviewFlagged: false,
        isArrivalRegistered: false,
        isNotPurchased: false,
        requiresFulfillment: true,
        isResolved: false,
      })),
      clientNote: draft.notes,
      urgentJustification: draft.urgentJustification,
      createdAt: draft.createdAt,
      updatedAt: draft.createdAt,
      requestedDeliveryDate: draft.requestedDeliveryDate,
      paymentReceiptUrls: [],
      facturaPdfUrls: [],
      previewMode: true,
      suppressCreatedTime: true,
    },
  };
}

export function CreateOrderPreviewPage() {
  const navigate = useNavigate();
  const profile = useSessionStore((state) => state.profile);
  const [pdfUrl, setPdfUrl] = useState<string | null>(null);
  const [pdfBytes, setPdfBytes] = useState<Uint8Array | null>(null);
  const [isLoadingPdf, setIsLoadingPdf] = useState(true);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [pageError, setPageError] = useState<string | null>(null);
  const draft = useMemo(() => readCreateOrderPreviewDraft(), []);

  useEffect(() => {
    const input = buildDraftPdfInput();
    if (!input) {
      setPageError("No hay datos para revisar.");
      setIsLoadingPdf(false);
      return;
    }

    let revokedUrl: string | null = null;
    let active = true;

    void (async () => {
      try {
        const bytes = await buildOrderPdfBytes(input);
        if (!active) return;
        const blob = new Blob([Uint8Array.from(bytes)], { type: "application/pdf" });
        revokedUrl = URL.createObjectURL(blob);
        setPdfBytes(bytes);
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
  }, []);

  async function handleSubmit() {
    if (!draft) {
      setPageError("No hay datos para enviar.");
      return;
    }

    setPageError(null);
    setIsSubmitting(true);
    try {
      await submitPurchaseOrder({
        requester: draft.requester,
        urgency: draft.urgency,
        requestedDeliveryDate: new Date(draft.requestedDeliveryDate),
        notes: draft.notes,
        urgentJustification: draft.urgentJustification,
        items: draft.items,
      });
      clearCreateOrderFormDraft();
      clearCreateOrderPreviewDraft();
      navigate(
        hasComprasAccess(profile) || hasDireccionApprovalAccess(profile) ? "/workflow/authorize" : "/",
      );
    } catch (error) {
      setPageError(error instanceof Error ? error.message : "No se pudo enviar la requisicion.");
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <div className="flex min-h-screen flex-col bg-[#d3d9e0] text-slate-900">
      <section className="sticky top-0 z-20 flex flex-wrap items-center justify-between gap-3 border-b border-slate-300 bg-white/94 px-5 py-4 shadow-sm backdrop-blur">
        <div className="flex gap-3">
          <Button type="button" variant="secondary" onClick={() => navigate("/orders/create")}>
            <ArrowLeft size={16} />
            Editar
          </Button>
        </div>
      </section>

      {pageError ? (
        <div className="mx-5 mt-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
          {pageError}
        </div>
      ) : null}

      <section className="flex-1 overflow-hidden bg-white">
        {isLoadingPdf ? (
          <div className="flex h-[calc(100vh-138px)] items-center justify-center text-sm text-slate-500">
            Generando PDF...
          </div>
        ) : pdfUrl ? (
          <iframe
            title="Vista previa PDF"
            src={pdfUrl}
            className="h-[calc(100vh-138px)] w-full bg-white"
          />
        ) : (
          <div className="flex h-[calc(100vh-138px)] items-center justify-center text-sm text-slate-500">
            No se pudo cargar la vista previa.
          </div>
        )}
      </section>

      <section className="sticky bottom-0 z-20 border-t border-slate-300 bg-white/94 px-5 py-4 backdrop-blur">
        <button
          type="button"
          onClick={handleSubmit}
          disabled={isSubmitting || !draft}
          className="app-button-primary w-full shadow-[0_18px_40px_rgba(15,23,42,0.16)]"
        >
          {isSubmitting ? "Enviando..." : "Enviar orden"}
        </button>
      </section>
    </div>
  );
}
