import { useEffect, useMemo, useState } from "react";
import { CalendarDays, Search, X } from "lucide-react";
import { useLocation, useNavigate } from "react-router-dom";
import { hasComprasAccess, hasDireccionApprovalAccess } from "@/lib/access-control";
import { useRtdbValue } from "@/lib/firebase/hooks";
import { mapOrders, type PurchaseOrderRecord } from "@/features/orders/orders-data";
import { authorizeOrderToCompras } from "@/features/workflow/authorize-orders-service";
import { useSessionStore } from "@/store/session-store";
import { StatusBadge } from "@/shared/ui/status-badge";
import { Snackbar } from "@/shared/ui/snackbar";

type UrgencyFilter = "all" | "normal" | "urgente";
type BusyAction = "accept-all" | null;

function formatDateTime(value?: number) {
  if (!value) return "Sin fecha";
  return new Intl.DateTimeFormat("es-MX", { dateStyle: "short", timeStyle: "short" }).format(
    new Date(value),
  );
}

function formatDateInputValue(value: Date | null) {
  if (!value) return "";
  const year = value.getFullYear();
  const month = String(value.getMonth() + 1).padStart(2, "0");
  const day = String(value.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function parseDateInputValue(value: string) {
  if (!value.trim()) return null;
  const date = new Date(`${value}T00:00:00`);
  return Number.isNaN(date.getTime()) ? null : date;
}

function formatDateRangeLabel(start: Date | null, end: Date | null) {
  if (!start && !end) return "Rango de fechas";
  const formatter = new Intl.DateTimeFormat("es-MX", { dateStyle: "short" });
  if (start && end) {
    return `${formatter.format(start)} - ${formatter.format(end)}`;
  }
  if (start) return `Desde ${formatter.format(start)}`;
  return `Hasta ${formatter.format(end!)}`;
}

function sameOrAfter(date: number | undefined, start: Date | null) {
  if (!start) return true;
  if (!date) return false;
  return date >= start.getTime();
}

function sameOrBefore(date: number | undefined, end: Date | null) {
  if (!end) return true;
  if (!date) return false;
  const inclusiveEnd = new Date(end.getFullYear(), end.getMonth(), end.getDate(), 23, 59, 59, 999);
  return date <= inclusiveEnd.getTime();
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
  ]
    .join(" ")
    .toLowerCase();
}

function urgencyLine(order: PurchaseOrderRecord) {
  const justification = order.urgentJustification?.trim() ?? "";
  return justification;
}

function urgencyTone(order: PurchaseOrderRecord) {
  return order.urgency === "urgente" ? "danger" : "info";
}

export function AuthorizeOrdersPage() {
  const navigate = useNavigate();
  const location = useLocation();
  const profile = useSessionStore((state) => state.profile);
  const canAuthorize = hasComprasAccess(profile) || hasDireccionApprovalAccess(profile);
  const ordersState = useRtdbValue("purchaseOrders", mapOrders, canAuthorize);

  const [urgencyFilter, setUrgencyFilter] = useState<UrgencyFilter>("all");
  const [search, setSearch] = useState("");
  const [createdFrom, setCreatedFrom] = useState<Date | null>(null);
  const [createdTo, setCreatedTo] = useState<Date | null>(null);
  const [busyAction, setBusyAction] = useState<BusyAction>(null);
  const [pageError, setPageError] = useState<string | null>(null);
  const [pageNotice, setPageNotice] = useState<string | null>(null);
  const [dateFilterOpen, setDateFilterOpen] = useState(false);

  useEffect(() => {
    const state = location.state as { notice?: string } | null;
    if (state?.notice) {
      setPageNotice(state.notice);
      navigate(location.pathname, { replace: true });
    }
  }, [location.pathname, location.state, navigate]);

  useEffect(() => {
    if (!pageError) return;
    const timer = window.setTimeout(() => setPageError(null), 3600);
    return () => window.clearTimeout(timer);
  }, [pageError]);

  useEffect(() => {
    if (!pageNotice) return;
    const timer = window.setTimeout(() => setPageNotice(null), 3600);
    return () => window.clearTimeout(timer);
  }, [pageNotice]);

  const urgencyCounts = useMemo(() => {
    const intakeOrders = (ordersState.data ?? []).filter((order) => order.status === "intakeReview");
    return {
      all: intakeOrders.length,
      normal: intakeOrders.filter((order) => order.urgency === "normal").length,
      urgente: intakeOrders.filter((order) => order.urgency === "urgente").length,
    };
  }, [ordersState.data]);

  const orders = useMemo(
    () =>
      (ordersState.data ?? [])
        .filter((order) => order.status === "intakeReview")
        .filter((order) => (urgencyFilter === "all" ? true : order.urgency === urgencyFilter))
        .filter((order) => {
          const normalizedSearch = search.trim().toLowerCase();
          return normalizedSearch ? buildSearch(order).includes(normalizedSearch) : true;
        })
        .filter((order) => sameOrAfter(order.createdAt, createdFrom))
        .filter((order) => sameOrBefore(order.createdAt, createdTo))
        .sort((left, right) => (right.updatedAt ?? 0) - (left.updatedAt ?? 0)),
    [createdFrom, createdTo, ordersState.data, search, urgencyFilter],
  );

  if (!canAuthorize) {
    return (
      <div className="rounded-[18px] border border-slate-200 bg-white px-5 py-4 text-sm text-slate-600">
        No tienes permisos para ver esta pantalla.
      </div>
    );
  }

  async function handleAcceptAll() {
    if (!profile || !orders.length) return;
    const confirmed = window.confirm(
      `Se enviaran ${orders.length} orden(es) visibles a Compras. Usalo solo si ya revisaste el lote completo.`,
    );
    if (!confirmed) return;

    setPageError(null);
    setBusyAction("accept-all");
    try {
      for (const order of orders) {
        await authorizeOrderToCompras(order, profile);
      }
    } catch (error) {
      setPageError(
        error instanceof Error ? error.message : "No se pudieron autorizar todas las ordenes visibles.",
      );
    } finally {
      setBusyAction(null);
    }
  }

  return (
    <div className="space-y-5 pb-4">
      <section className="space-y-4">
        <div className="flex flex-col gap-4 rounded-[20px] border border-slate-200 bg-white px-5 py-5">
          <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
            <div>
              <p className="text-[20px] font-semibold text-slate-900">Autorizar ordenes</p>
              <p className="mt-1 text-sm text-slate-600">
                Revisa requisiciones pendientes y mandalas a Compras o regresalas a correccion.
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
              <button
                type="button"
                onClick={handleAcceptAll}
                disabled={!orders.length || busyAction === "accept-all"}
                className="rounded-2xl border border-emerald-700 bg-emerald-700 px-4 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
              >
                {busyAction === "accept-all" ? "Aceptando..." : "Aceptar todas"}
              </button>
            </div>
          </div>

          <div className="grid gap-3 lg:grid-cols-[minmax(0,1fr)_auto]">
            <label className="relative block">
              <Search
                size={16}
                className="pointer-events-none absolute left-0 top-[18px] text-slate-500"
              />
              <input
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                placeholder="Buscar por folio, solicitante, area o articulo"
                className="w-full border-0 border-b border-slate-500 bg-transparent py-2 pl-6 pr-8 text-[15px] text-slate-900 outline-none"
              />
              {search.trim() ? (
                <button
                  type="button"
                  onClick={() => setSearch("")}
                  className="absolute right-0 top-1/2 -translate-y-1/2 rounded-full p-1 text-slate-500 hover:bg-slate-100"
                  title="Limpiar busqueda"
                >
                  <X size={15} />
                </button>
              ) : null}
            </label>
            <div className="relative">
              <button
                type="button"
                onClick={() => setDateFilterOpen((current) => !current)}
                className="inline-flex min-h-[48px] items-center gap-2 rounded-[18px] border border-slate-300 bg-slate-100 px-4 py-3 text-sm font-medium text-slate-700"
              >
                <CalendarDays size={15} />
                <span>{formatDateRangeLabel(createdFrom, createdTo)}</span>
              </button>
              {dateFilterOpen ? (
                <div className="absolute right-0 top-[calc(100%+8px)] z-10 w-[290px] rounded-[20px] border border-slate-200 bg-white p-4 shadow-lg">
                  <div className="space-y-3">
                    <label className="block">
                      <span className="mb-2 block text-sm font-medium text-slate-700">Desde</span>
                      <input
                        type="date"
                        value={formatDateInputValue(createdFrom)}
                        onChange={(event) => setCreatedFrom(parseDateInputValue(event.target.value))}
                        className="w-full rounded-2xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-900 outline-none"
                      />
                    </label>
                    <label className="block">
                      <span className="mb-2 block text-sm font-medium text-slate-700">Hasta</span>
                      <input
                        type="date"
                        value={formatDateInputValue(createdTo)}
                        onChange={(event) => setCreatedTo(parseDateInputValue(event.target.value))}
                        className="w-full rounded-2xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-900 outline-none"
                      />
                    </label>
                    <div className="flex justify-end gap-2">
                      <button
                        type="button"
                        onClick={() => {
                          setCreatedFrom(null);
                          setCreatedTo(null);
                        }}
                        className="rounded-2xl border border-slate-300 bg-white px-3 py-2 text-sm font-medium text-slate-700"
                      >
                        Limpiar
                      </button>
                      <button
                        type="button"
                        onClick={() => setDateFilterOpen(false)}
                        className="rounded-2xl border border-slate-900 bg-slate-900 px-3 py-2 text-sm font-medium text-white"
                      >
                        Aplicar
                      </button>
                    </div>
                  </div>
                </div>
              ) : null}
            </div>
          </div>
        </div>

      </section>

      <section className="space-y-3">
        {ordersState.isLoading ? (
          <div className="rounded-[18px] border border-slate-200 bg-white px-5 py-6 text-sm text-slate-500">
            Cargando ordenes...
          </div>
        ) : ordersState.error ? (
          <div className="rounded-[18px] border border-red-200 bg-red-50 px-5 py-6 text-sm text-red-700">
            No se pudo leer el workflow: {ordersState.error}
          </div>
        ) : !orders.length ? (
          <div className="rounded-[18px] border border-slate-200 bg-white px-5 py-6 text-sm text-slate-500">
            No hay ordenes pendientes por autorizar.
          </div>
        ) : (
          orders.map((order) => {
            return (
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
                  <button
                    type="button"
                    onClick={() => navigate(`/workflow/authorize/${order.id}/pdf`)}
                    className="inline-flex cursor-pointer items-center justify-center rounded-2xl border border-slate-700 bg-white px-4 py-2.5 text-sm font-medium text-slate-800"
                  >
                    Ver PDF
                  </button>
                </div>
              </article>
            );
          })
        )}
      </section>
      <Snackbar message={pageError} tone="error" />
      <Snackbar message={pageNotice} tone="success" />
    </div>
  );
}
