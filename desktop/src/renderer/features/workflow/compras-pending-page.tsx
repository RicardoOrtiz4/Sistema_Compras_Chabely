import { useMemo, useState } from "react";
import { Download, FileText, Search } from "lucide-react";
import { Link } from "react-router-dom";
import { hasComprasAccess } from "@/lib/access-control";
import { useRtdbValue } from "@/lib/firebase/hooks";
import { buildOrderCsv, downloadTextFile } from "@/lib/downloads";
import {
  mapOrders,
  type PurchaseOrderEvent,
  type PurchaseOrderRecord,
} from "@/features/orders/orders-data";
import { getOrderStatusLabel } from "@/features/orders/order-status";
import { useSessionStore } from "@/store/session-store";
import { StatusBadge } from "@/shared/ui/status-badge";

type UrgencyFilter = "all" | "normal" | "urgente";

function formatDuration(ms?: number) {
  if (!ms || ms <= 0) return "0 min";
  const totalMinutes = Math.max(Math.round(ms / 60000), 0);
  if (totalMinutes < 60) return `${totalMinutes} min`;
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  return minutes > 0 ? `${hours} h ${minutes} min` : `${hours} h`;
}

function latestEventToStatus(events: PurchaseOrderEvent[], status: string) {
  return [...events]
    .reverse()
    .find((event) => (event.toStatus ?? "").trim() === status);
}

function buildSearch(order: PurchaseOrderRecord) {
  return [
    order.id,
    order.requesterName,
    order.areaName,
    order.clientNote ?? "",
    order.urgentJustification ?? "",
    ...order.items.map((item) => item.description),
    ...order.items.map((item) => item.partNumber ?? ""),
    ...order.items.map((item) => item.customer ?? ""),
    ...order.items.map((item) => item.supplier ?? ""),
  ]
    .join(" ")
    .toLowerCase();
}

function exportOrderCsv(order: PurchaseOrderRecord) {
  downloadTextFile(buildOrderCsv(order), `orden_compra_${order.id}.csv`, "text/csv");
}

export function ComprasPendingPage() {
  const profile = useSessionStore((state) => state.profile);
  const canOperate = hasComprasAccess(profile);
  const ordersState = useRtdbValue("purchaseOrders", mapOrders, canOperate);

  const [search, setSearch] = useState("");
  const [urgencyFilter, setUrgencyFilter] = useState<UrgencyFilter>("all");

  const orders = useMemo(
    () =>
      (ordersState.data ?? [])
        .filter((order) => order.status === "sourcing")
        .filter((order) => (urgencyFilter === "all" ? true : order.urgency === urgencyFilter))
        .filter((order) => {
          const normalizedSearch = search.trim().toLowerCase();
          return normalizedSearch ? buildSearch(order).includes(normalizedSearch) : true;
        })
        .sort((left, right) => (right.updatedAt ?? 0) - (left.updatedAt ?? 0)),
    [ordersState.data, search, urgencyFilter],
  );

  if (!canOperate) {
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
            <p className="text-[20px] font-semibold text-slate-900">Compras</p>
            <p className="mt-1 text-sm text-slate-600">
              Revisa el PDF, completa datos de proveedor y manda la orden al dashboard.
            </p>
          </div>
          <StatusBadge label={`${orders.length} orden(es) en preparacion`} tone="warning" />
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

      <section className="space-y-4">
        {ordersState.isLoading ? (
          <div className="rounded-[18px] border border-slate-200 bg-white px-5 py-6 text-sm text-slate-500">
            Cargando ordenes...
          </div>
        ) : ordersState.error ? (
          <div className="rounded-[18px] border border-red-200 bg-red-50 px-5 py-6 text-sm text-red-700">
            No se pudo leer el modulo: {ordersState.error}
          </div>
        ) : !orders.length ? (
          <div className="rounded-[18px] border border-slate-200 bg-white px-5 py-6 text-sm text-slate-500">
            No hay ordenes pendientes en Compras.
          </div>
        ) : (
          orders.map((order) => {
            const sender = latestEventToStatus(order.events, "sourcing");
            return (
              <article
                key={order.id}
                className="rounded-[22px] border border-slate-200 bg-white px-5 py-5"
              >
                <p className="text-[18px] font-semibold text-slate-900">Folio: {order.id}</p>
                <p className="mt-2 text-sm text-slate-600">
                  {order.requesterName} · {order.areaName}
                </p>

                <div className="mt-3 flex flex-wrap gap-2">
                  <StatusBadge
                    label={order.urgency === "urgente" ? "Urgente" : "Normal"}
                    tone={order.urgency === "urgente" ? "danger" : "neutral"}
                  />
                  <StatusBadge label={getOrderStatusLabel(order.status)} tone="info" />
                </div>

                {order.urgentJustification ? (
                  <p className="mt-3 text-sm text-red-700">{order.urgentJustification}</p>
                ) : null}

                <div className="mt-3 space-y-1 text-sm text-slate-500">
                  <p>Tiempo en Revision operativa: {formatDuration(order.statusDurations.intakeReview)}</p>
                  <p>Enviada por: {sender?.byRole || sender?.byUserId || "No disponible"}</p>
                </div>

                <div className="mt-4 flex flex-wrap justify-end gap-2">
                  <Link
                    to={`/workflow/compras/${order.id}`}
                    className="inline-flex items-center rounded-2xl border border-slate-700 bg-[#f7f7f7] px-3 py-2 text-sm font-medium text-slate-800"
                  >
                    <FileText size={15} className="mr-2" />
                    Ver PDF
                  </Link>
                  <button
                    type="button"
                    onClick={() => exportOrderCsv(order)}
                    className="inline-flex items-center rounded-2xl border border-slate-300 bg-slate-100 px-3 py-2 text-sm font-medium text-slate-700"
                  >
                    <Download size={15} className="mr-2" />
                    Descargar CSV
                  </button>
                </div>
              </article>
            );
          })
        )}
      </section>
    </div>
  );
}
