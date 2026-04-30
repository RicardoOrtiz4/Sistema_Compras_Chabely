import { Download, FileText, Search } from "lucide-react";
import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { hasComprasAccess } from "@/lib/access-control";
import { useRtdbValue } from "@/lib/firebase/hooks";
import { buildOrderCsv, downloadTextFile } from "@/lib/downloads";
import { mapOrders, type PurchaseOrderRecord } from "@/features/orders/orders-data";
import { useSessionStore } from "@/store/session-store";
import { StatusBadge } from "@/shared/ui/status-badge";

type UrgencyFilter = "all" | "normal" | "urgente";

function formatDuration(ms?: number) {
  if (!ms || ms <= 0) return "0 min";
  const totalSeconds = Math.max(Math.floor(ms / 1000), 0);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;

  if (hours > 0) {
    return `${hours} h ${minutes} min ${seconds} s`;
  }
  if (minutes > 0) {
    return `${minutes} min ${seconds} s`;
  }
  return `${seconds} s`;
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

function urgencyLine(order: PurchaseOrderRecord) {
  return order.urgentJustification?.trim() ?? "";
}

function urgencyTone(order: PurchaseOrderRecord) {
  return order.urgency === "urgente" ? "danger" : "info";
}

export function ComprasPendingPage() {
  const profile = useSessionStore((state) => state.profile);
  const canOperate = hasComprasAccess(profile);
  const ordersState = useRtdbValue("purchaseOrders", mapOrders, canOperate);

  const [search, setSearch] = useState("");
  const [urgencyFilter, setUrgencyFilter] = useState<UrgencyFilter>("all");

  const urgencyCounts = useMemo(() => {
    const sourcingOrders = (ordersState.data ?? []).filter((order) => order.status === "sourcing");
    return {
      all: sourcingOrders.length,
      normal: sourcingOrders.filter((order) => order.urgency === "normal").length,
      urgente: sourcingOrders.filter((order) => order.urgency === "urgente").length,
    };
  }, [ordersState.data]);

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
            <p className="text-[20px] font-semibold text-slate-900">Compras / Pendientes</p>
            <p className="mt-1 text-sm text-slate-600">
              Revisa el PDF, completa datos de proveedor y manda la orden al dashboard.
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            {([
              { key: "all", label: "Totales", count: urgencyCounts.all },
              { key: "normal", label: "Normales", count: urgencyCounts.normal },
              { key: "urgente", label: "Urgentes", count: urgencyCounts.urgente },
            ] as const).map((option) => {
              const active = urgencyFilter === option.key;
              return (
                <button
                  key={option.key}
                  type="button"
                  onClick={() => setUrgencyFilter(option.key)}
                  className={[
                    "rounded-full border px-4 py-2 text-sm font-medium transition",
                    active
                      ? "border-slate-900 bg-slate-900 text-white"
                      : "border-slate-400 bg-white text-slate-700 hover:bg-slate-50",
                  ].join(" ")}
                >
                  {option.label} ({option.count})
                </button>
              );
            })}
          </div>
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
          orders.map((order) => (
            <article
              key={order.id}
              className="rounded-[20px] border border-slate-200 bg-white px-5 py-5"
            >
              <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                <div>
                  <p className="text-[19px] font-semibold text-slate-900">Folio: {order.id}</p>
                  <p className="mt-2 text-sm text-slate-700">
                    Solicitante: {order.requesterName} | Area del solicitante: {order.areaName}
                  </p>
                  {urgencyLine(order) ? (
                    <p className="mt-1 text-sm font-medium text-red-700">{urgencyLine(order)}</p>
                  ) : null}
                </div>
                <div className="flex flex-wrap gap-2 lg:justify-end">
                  <StatusBadge
                    label={order.urgency === "urgente" ? "Urgente" : "Normal"}
                    tone={urgencyTone(order)}
                  />
                </div>
              </div>

              <div className="mt-5 flex flex-col gap-3 sm:flex-row sm:flex-wrap">
                <Link
                  to={`/workflow/compras/pendientes/${order.id}`}
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

              <div className="mt-4 flex justify-end">
                <p className="text-sm text-slate-500">
                  <span className="font-semibold text-slate-700">Tiempo en revision operativa:</span>{" "}
                  {formatDuration(order.statusDurations.intakeReview)}
                </p>
              </div>
            </article>
          ))
        )}
      </section>
    </div>
  );
}
