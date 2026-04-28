import { useEffect, useMemo, useState } from "react";
import { ArrowLeft } from "lucide-react";
import { Link, useParams } from "react-router-dom";
import { useRtdbValue } from "@/lib/firebase/hooks";
import { useBrandingStore } from "@/store/branding-store";
import { type PacketBundleRecord, usePacketWorkflowData } from "@/features/purchase-packets/packet-data";
import { mapOrders } from "@/features/orders/orders-data";
import { buildPacketPdfBytes } from "@/features/purchase-packets/packet-pdf-service";
import {
  clearPacketPreviewDraft,
  readPacketPreviewDraft,
} from "@/features/purchase-packets/packet-pdf-preview-state";

function mapBundleToPdfInput(bundle: PacketBundleRecord, company: "chabely" | "acerpro") {
  return {
    company,
    supplier: bundle.packet.supplierName,
    orderIds: [...new Set(bundle.packet.itemRefs.map((item) => item.orderId))],
    items: bundle.packet.itemRefs.map((item) => ({
      orderId: item.orderId,
      lineNumber: item.lineNumber,
      description: item.description,
      quantity: item.quantity,
      unit: item.unit,
      internalOrder: undefined,
      amount: item.amount ?? 0,
    })),
    totalAmount: bundle.packet.totalAmount,
    evidenceUrls: bundle.packet.evidenceUrls,
    folio: bundle.packet.folio,
    issuedAt: bundle.packet.submittedAt ?? bundle.packet.updatedAt ?? bundle.packet.createdAt ?? Date.now(),
  };
}

export function PurchasePacketPreviewPage() {
  const params = useParams();
  const packetId = params.packetId ?? "";
  const company = useBrandingStore((state) => state.company);
  const ordersState = useRtdbValue("purchaseOrders", mapOrders, true);
  const packetState = usePacketWorkflowData(true, ordersState.data ?? []);

  const [pdfUrl, setPdfUrl] = useState<string | null>(null);
  const [pageError, setPageError] = useState<string | null>(null);
  const [isLoadingPdf, setIsLoadingPdf] = useState(true);

  const source = useMemo(() => {
    if (packetId) {
      const bundle = packetState.data.packets.find((item) => item.packet.id === packetId);
      return bundle ? mapBundleToPdfInput(bundle, company) : null;
    }
    return readPacketPreviewDraft();
  }, [company, packetId, packetState.data.packets]);

  useEffect(() => {
    let revokedUrl: string | null = null;
    let active = true;

    if (!source) {
      setPageError("No hay datos del paquete para mostrar.");
      setIsLoadingPdf(false);
      return;
    }

    setIsLoadingPdf(true);
    setPageError(null);

    void (async () => {
      try {
        const bytes = await buildPacketPdfBytes({
          company,
          supplier: source.supplier,
          orderIds: source.orderIds,
          items: source.items,
          totalAmount: source.totalAmount,
          issuedAt: source.issuedAt,
          folio: source.folio,
        });
        if (!active) return;
        const blob = new Blob([Uint8Array.from(bytes)], { type: "application/pdf" });
        revokedUrl = URL.createObjectURL(blob);
        setPdfUrl(revokedUrl);
      } catch (error) {
        if (!active) return;
        setPageError(error instanceof Error ? error.message : "No se pudo generar el PDF del paquete.");
      } finally {
        if (active) setIsLoadingPdf(false);
      }
    })();

    return () => {
      active = false;
      if (revokedUrl) URL.revokeObjectURL(revokedUrl);
      if (!packetId) clearPacketPreviewDraft();
    };
  }, [company, packetId, source]);

  return (
    <div className="flex min-h-screen flex-col bg-[#d3d9e0] text-slate-900">
      <section className="sticky top-0 z-20 flex flex-wrap items-center justify-between gap-3 border-b border-slate-300 bg-white/94 px-5 py-4 shadow-sm backdrop-blur">
        <div className="flex gap-3">
          <Link
            to="/purchase-packets"
            className="inline-flex items-center rounded-2xl border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700"
          >
            <ArrowLeft size={16} className="mr-2" />
            Volver
          </Link>
        </div>
      </section>

      {pageError ? (
        <div className="mx-5 mt-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
          {pageError}
        </div>
      ) : null}

      <section className="flex-1 overflow-hidden bg-white">
        {isLoadingPdf ? (
          <div className="flex h-[calc(100vh-90px)] items-center justify-center text-sm text-slate-500">
            Generando PDF...
          </div>
        ) : pdfUrl ? (
          <iframe title="Vista previa PDF paquete" src={pdfUrl} className="h-[calc(100vh-90px)] w-full bg-white" />
        ) : (
          <div className="flex h-[calc(100vh-90px)] items-center justify-center text-sm text-slate-500">
            No se pudo cargar la vista previa.
          </div>
        )}
      </section>
    </div>
  );
}
