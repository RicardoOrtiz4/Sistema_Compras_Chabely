import { useMemo, useState } from "react";
import { FileText, Filter } from "lucide-react";
import { Link } from "react-router-dom";
import { hasComprasAccess, hasDireccionApprovalAccess } from "@/lib/access-control";
import { mapOrders } from "@/features/orders/orders-data";
import { type PacketBundleRecord, usePacketWorkflowData } from "@/features/purchase-packets/packet-data";
import { useRtdbValue } from "@/lib/firebase/hooks";
import { useSessionStore } from "@/store/session-store";
import { StatusBadge } from "@/shared/ui/status-badge";

type HistoryFilter = "all" | "rejected";

function formatDateTime(value?: number) {
  if (!value) return "Sin fecha";
  return new Intl.DateTimeFormat("es-MX", { dateStyle: "short", timeStyle: "short" }).format(
    new Date(value),
  );
}

function isRejectedBundle(bundle: PacketBundleRecord) {
  if (!bundle.decisions.length) return false;
  const latest = [...bundle.decisions].sort((a, b) => b.timestamp - a.timestamp)[0];
  return latest?.action === "return_for_rework";
}

export function PurchasePacketHistoryPage() {
  const profile = useSessionStore((state) => state.profile);
  const canUseModule = hasComprasAccess(profile) || hasDireccionApprovalAccess(profile);
  const ordersState = useRtdbValue("purchaseOrders", mapOrders, Boolean(profile));
  const packetState = usePacketWorkflowData(Boolean(profile), ordersState.data ?? []);
  const [filter, setFilter] = useState<HistoryFilter>("all");

  const history = useMemo(
    () =>
      packetState.data.packets
        .filter((bundle) => Boolean(bundle.packet.folio?.trim()))
        .filter((bundle) => (filter === "rejected" ? isRejectedBundle(bundle) : true))
        .sort(
          (left, right) =>
            (right.packet.submittedAt ?? right.packet.updatedAt ?? right.packet.createdAt ?? 0) -
            (left.packet.submittedAt ?? left.packet.updatedAt ?? left.packet.createdAt ?? 0),
        ),
    [filter, packetState.data.packets],
  );

  if (!canUseModule) {
    return (
      <div className="rounded-[18px] border border-slate-200 bg-white px-5 py-4 text-sm text-slate-600">
        No tienes permisos para ver esta pantalla.
      </div>
    );
  }

  return (
    <div className="space-y-6 pb-4">
      <section className="rounded-[22px] border border-slate-200 bg-white px-5 py-5">
        <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
          <div>
            <p className="text-[20px] font-semibold text-slate-900">
              Historial de PDFs de paquetes por proveedor
            </p>
            <p className="mt-1 text-sm text-slate-600">
              Consulta paquetes enviados a Direccion General y reabre su PDF cuando sea necesario.
            </p>
          </div>
          <StatusBadge label={`${history.length} registro(s)`} tone="info" />
        </div>

        <div className="mt-5 inline-flex overflow-hidden rounded-full border border-slate-500 bg-white">
          {[
            { key: "all", label: "Todos" },
            { key: "rejected", label: "Rechazados" },
          ].map((option) => {
            const active = filter === option.key;
            return (
              <button
                key={option.key}
                type="button"
                onClick={() => setFilter(option.key as HistoryFilter)}
                className={[
                  "inline-flex items-center px-5 py-2 text-sm font-medium transition",
                  active ? "bg-slate-900 text-white" : "bg-white text-slate-700 hover:bg-slate-50",
                ].join(" ")}
              >
                {option.key === "all" ? null : <Filter size={14} className="mr-2" />}
                {option.label}
              </button>
            );
          })}
        </div>
      </section>

      <section className="space-y-4">
        {packetState.isLoading || ordersState.isLoading ? (
          <div className="rounded-[18px] border border-slate-200 bg-white px-5 py-6 text-sm text-slate-500">
            Cargando historial...
          </div>
        ) : packetState.error || ordersState.error ? (
          <div className="rounded-[18px] border border-red-200 bg-red-50 px-5 py-6 text-sm text-red-700">
            No se pudo cargar el historial: {packetState.error ?? ordersState.error}
          </div>
        ) : !history.length ? (
          <div className="rounded-[18px] border border-slate-200 bg-white px-5 py-6 text-sm text-slate-500">
            Aun no hay PDFs de paquetes por proveedor enviados a Direccion General para este filtro.
          </div>
        ) : (
          history.map((bundle) => {
            const isRejected = isRejectedBundle(bundle);
            const issuedAt =
              bundle.packet.submittedAt ?? bundle.packet.updatedAt ?? bundle.packet.createdAt;

            return (
              <article
                key={bundle.packet.id}
                className="rounded-[22px] border border-slate-200 bg-white px-5 py-5"
              >
                <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
                  <div>
                    <p className="text-[18px] font-semibold text-slate-900">
                      {bundle.packet.folio ?? bundle.packet.id}
                    </p>
                    <p className="mt-1 text-sm text-slate-600">{bundle.packet.supplierName}</p>
                    <div className="mt-3 flex flex-wrap gap-2">
                      {isRejected ? (
                        <StatusBadge label="Rechazada" tone="danger" />
                      ) : (
                        <StatusBadge label="Enviada" tone="info" />
                      )}
                      <StatusBadge label={`${bundle.packet.itemRefs.length} item(s)`} tone="neutral" />
                    </div>
                  </div>

                  <Link
                    to={`/purchase-packets/${bundle.packet.id}/pdf`}
                    className="inline-flex items-center rounded-2xl border border-slate-700 bg-white px-3 py-2 text-sm font-medium text-slate-800"
                  >
                    <FileText size={15} className="mr-2" />
                    Ver PDF de paquete
                  </Link>
                </div>

                <div className="mt-4 flex flex-wrap gap-4 text-sm text-slate-600">
                  <span>Items: {bundle.packet.itemRefs.length}</span>
                  <span>Total: ${bundle.packet.totalAmount.toLocaleString("es-MX")}</span>
                  <span>Fecha: {formatDateTime(issuedAt)}</span>
                  <span>Estado: {isRejected ? "rechazada" : bundle.packet.status}</span>
                </div>

                {bundle.packet.evidenceUrls.length ? (
                  <div className="mt-4 flex flex-wrap gap-2">
                    {bundle.packet.evidenceUrls.map((url) => (
                      <a
                        key={url}
                        href={url}
                        target="_blank"
                        rel="noreferrer"
                        className="rounded-full border border-slate-300 bg-slate-50 px-3 py-1 text-sm text-slate-700"
                      >
                        Link
                      </a>
                    ))}
                  </div>
                ) : null}
              </article>
            );
          })
        )}
      </section>
    </div>
  );
}
