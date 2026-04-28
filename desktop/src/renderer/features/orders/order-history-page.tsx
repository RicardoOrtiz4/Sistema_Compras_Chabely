import { useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { hasReportsAccess } from "@/lib/access-control";
import { useRtdbValue } from "@/lib/firebase/hooks";
import { type PurchaseOrderRecord, mapOrders } from "@/features/orders/orders-data";
import { getOrderStatusLabel } from "@/features/orders/order-status";
import { useSessionStore } from "@/store/session-store";
import { StatusBadge } from "@/shared/ui/status-badge";

type HistoryScope = "mine" | "all";
type UrgencyFilter = "all" | "normal" | "urgente";
type HistoryMode = "all" | "in-process" | "rejected";

function formatDateTime(value?: number) {
  if (!value) return "Sin fecha";
  return new Intl.DateTimeFormat("es-MX", {
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(value));
}

export function OrderHistoryPage() {
  const profile = useSessionStore((state) => state.profile);
  const ordersState = useRtdbValue("purchaseOrders", mapOrders, Boolean(profile));
  const [searchParams] = useSearchParams();
  const initialMode = (searchParams.get("mode") as HistoryMode | null) ?? "all";
  const [scope, setScope] = useState<HistoryScope>("mine");
  const [search, setSearch] = useState("");
  const [urgencyFilter, setUrgencyFilter] = useState<UrgencyFilter>("all");

  const canSeeAll = hasReportsAccess(profile);
  const orders = ordersState.data ?? [];

  const visibleOrders = useMemo(() => {
    let next = orders;

    if (scope === "mine" && profile) {
      next = next.filter((order) => order.requesterId === profile.id);
    }

    if (initialMode === "in-process") {
      next = next.filter((order) =>
        [
          "intakeReview",
          "sourcing",
          "readyForApproval",
          "approval_queue",
          "execution_ready",
          "contabilidad",
          "eta",
        ].includes(order.status),
      );
    }

    if (initialMode === "rejected") {
      next = next.filter((order) => order.status === "draft" && (order.returnCount ?? 0) > 0);
    }

    if (urgencyFilter !== "all") {
      next = next.filter((order) => order.urgency === urgencyFilter);
    }

    const normalizedSearch = search.trim().toLowerCase();
    if (normalizedSearch) {
      next = next.filter((order) => {
        const haystack = [
          order.id,
          order.requesterName,
          order.areaName,
          order.status,
          order.supplier ?? "",
          ...order.items.map((item) => item.description),
        ]
          .join(" ")
          .toLowerCase();
        return haystack.includes(normalizedSearch);
      });
    }

    return next;
  }, [initialMode, orders, profile, scope, search, urgencyFilter]);

  return (
    <div className="app-page">
      <section className="app-card">
        <div className="mb-5 flex justify-end">
          <StatusBadge label={`${visibleOrders.length} resultado(s)`} tone="info" />
        </div>

        <div className="grid gap-3 lg:grid-cols-[1fr_auto] xl:grid-cols-[1fr_auto_auto]">
          <input
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Buscar por folio, solicitante, area o articulo"
            className="app-input"
          />

          <select
            value={urgencyFilter}
            onChange={(event) => setUrgencyFilter(event.target.value as UrgencyFilter)}
            className="app-select w-full lg:min-w-[220px]"
          >
            <option value="all">Todas las urgencias</option>
            <option value="normal">Normal</option>
            <option value="urgente">Urgente</option>
          </select>

          <select
            value={scope}
            onChange={(event) => setScope(event.target.value as HistoryScope)}
            disabled={!canSeeAll}
            className="app-select w-full lg:min-w-[220px] disabled:bg-slate-100"
          >
            <option value="mine">Mis ordenes</option>
            <option value="all">Todas las ordenes</option>
          </select>
        </div>
      </section>

      <section className="app-card">
        {ordersState.isLoading ? (
          <div className="text-sm text-slate-500">Cargando ordenes...</div>
        ) : ordersState.error ? (
          <div className="text-sm text-red-600">No se pudo leer el historial: {ordersState.error}</div>
        ) : visibleOrders.length === 0 ? (
          <div className="text-sm text-slate-500">No hay ordenes que coincidan con el filtro actual.</div>
        ) : (
          <div className="space-y-3">
            {visibleOrders.map((order) => (
              <OrderHistoryRow key={order.id} order={order} />
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

function OrderHistoryRow({ order }: { order: PurchaseOrderRecord }) {
  return (
    <article className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p className="text-base font-semibold text-slate-900">{order.id}</p>
          <p className="mt-1 text-sm text-slate-500">
            {order.requesterName || "Sin solicitante"} · {order.areaName || "Sin area"}
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <StatusBadge
            label={order.urgency === "urgente" ? "Urgente" : "Normal"}
            tone={order.urgency === "urgente" ? "danger" : "neutral"}
          />
          <StatusBadge label={getOrderStatusLabel(order.status)} tone="info" />
        </div>
      </div>

      <div className="mt-4 flex flex-col gap-3 text-sm text-slate-500 sm:flex-row sm:items-center sm:justify-between">
        <span>{formatDateTime(order.updatedAt ?? order.createdAt)}</span>
        <Link to={`/orders/history/${order.id}`} className="app-button-secondary">
          Ver detalle
        </Link>
      </div>
    </article>
  );
}
