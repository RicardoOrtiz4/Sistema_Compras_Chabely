import { useMemo, useState } from "react";
import { hasReportsAccess } from "@/lib/access-control";
import { useRtdbValue } from "@/lib/firebase/hooks";
import { buildMonitoringCsv, downloadTextFile } from "@/lib/downloads";
import { getOrderStatusLabel } from "@/features/orders/order-status";
import {
  buildMonitoringRows,
  formatMonitoringDuration,
  isMonitorableOrder,
  requesterReceiptStatusLabel,
  type MonitoringRow,
} from "@/features/orders/monitoring-support";
import { mapOrders } from "@/features/orders/orders-data";
import { useSessionStore } from "@/store/session-store";
import { StatusBadge } from "@/shared/ui/status-badge";

type UrgencyFilter = "all" | "normal" | "urgente";

function formatDateTime(value?: number) {
  if (!value) return "";
  return new Intl.DateTimeFormat("es-MX", { dateStyle: "short", timeStyle: "short" }).format(new Date(value));
}

function mapUsers(value: unknown) {
  if (!value || typeof value !== "object") return {} as Record<string, string>;
  const result: Record<string, string> = {};
  for (const [uid, raw] of Object.entries(value as Record<string, unknown>)) {
    if (!raw || typeof raw !== "object") continue;
    const data = raw as Record<string, unknown>;
    const name = typeof data.name === "string" && data.name.trim() ? data.name.trim() : uid;
    result[uid] = name;
  }
  return result;
}

export function OrderMonitoringPage() {
  const profile = useSessionStore((state) => state.profile);
  const ordersState = useRtdbValue("purchaseOrders", mapOrders, Boolean(profile));
  const usersState = useRtdbValue("users", mapUsers, Boolean(profile));
  const [urgencyFilter, setUrgencyFilter] = useState<UrgencyFilter>("all");

  const canView = hasReportsAccess(profile);
  const orders = ordersState.data ?? [];
  const actorNamesById = usersState.data ?? {};

  const activeOrders = useMemo(
    () =>
      orders
        .filter(isMonitorableOrder)
        .filter((order) => (urgencyFilter === "all" ? true : order.urgency === urgencyFilter))
        .sort((left, right) => (right.updatedAt ?? right.createdAt ?? 0) - (left.updatedAt ?? left.createdAt ?? 0)),
    [orders, urgencyFilter],
  );

  const rows = useMemo(() => activeOrders.flatMap((order) => buildMonitoringRows(order, actorNamesById)), [activeOrders, actorNamesById]);

  if (!canView) {
    return <div className="app-card text-sm text-slate-600">No tienes permisos para ver monitoreo.</div>;
  }

  return (
    <div className="app-page">
      <section className="app-card">
        <div className="mb-5 flex justify-end">
          <StatusBadge label={`${activeOrders.length} orden(es) activas`} tone="info" />
        </div>

        <div className="flex flex-wrap gap-3">
          {(["all", "normal", "urgente"] as UrgencyFilter[]).map((value) => (
            <button key={value} type="button" onClick={() => setUrgencyFilter(value)} className={`app-chip-toggle ${urgencyFilter === value ? "app-chip-toggle-active" : ""}`}>
              {value === "all" ? "Todas" : value === "normal" ? "Normal" : "Urgente"}
            </button>
          ))}
          <button
            type="button"
            onClick={() =>
              downloadTextFile(
                buildMonitoringCsv(rows),
                `monitoreo_ordenes_${new Date().toISOString().slice(0, 16).replace(/[:T]/g, "_")}.csv`,
                "text/csv",
              )
            }
            disabled={!rows.length}
            className="app-button-secondary"
          >
            Exportar CSV
          </button>
        </div>
      </section>

      <section className="app-card">
        {ordersState.isLoading || usersState.isLoading ? (
          <div className="text-sm text-slate-500">Cargando monitoreo...</div>
        ) : ordersState.error || usersState.error ? (
          <div className="text-sm text-red-600">No se pudo cargar monitoreo: {ordersState.error ?? usersState.error}</div>
        ) : rows.length === 0 ? (
          <div className="text-sm text-slate-500">No hay ordenes actuales con ese filtro.</div>
        ) : (
          <div className="space-y-3">
            {rows.map((row) => (
              <MonitoringCard key={`${row.order.id}-${row.status}-${row.enteredAt ?? 0}`} row={row} />
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

function MonitoringCard({ row }: { row: MonitoringRow }) {
  return (
    <article className={`rounded-2xl border p-4 ${row.isCurrent ? "border-blue-200 bg-blue-50" : "border-slate-200 bg-slate-50"}`}>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="text-sm font-semibold text-slate-900">{row.order.id}</p>
          <p className="mt-1 text-xs text-slate-500">{row.order.requesterName} · {row.order.areaName}</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <StatusBadge label={row.order.urgency === "urgente" ? "Urgente" : "Normal"} tone={row.order.urgency === "urgente" ? "danger" : "neutral"} />
          <StatusBadge label={row.isCurrent ? `${getOrderStatusLabel(row.status)} (actual)` : getOrderStatusLabel(row.status)} tone={row.isCurrent ? "info" : "neutral"} />
        </div>
      </div>

      <div className="mt-4 grid gap-3 md:grid-cols-2 xl:grid-cols-4 text-sm">
        <Info label="Estado actual" value={requesterReceiptStatusLabel(row.order)} />
        <Info label="Tiempo" value={formatMonitoringDuration(row.elapsedMs)} />
        <Info label="Actuo" value={row.actor} />
        <Info label="Fecha / hora" value={formatDateTime(row.enteredAt) || "Sin fecha"} />
      </div>
    </article>
  );
}

function Info({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-xs font-medium uppercase tracking-[0.18em] text-slate-500">{label}</p>
      <p className="mt-1 text-sm font-medium text-slate-800">{value}</p>
    </div>
  );
}
