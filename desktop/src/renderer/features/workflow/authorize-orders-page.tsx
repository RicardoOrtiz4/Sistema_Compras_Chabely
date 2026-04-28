import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { CalendarDays, Search, X } from "lucide-react";
import { hasComprasAccess, hasDireccionApprovalAccess } from "@/lib/access-control";
import { useRtdbValue } from "@/lib/firebase/hooks";
import { mapOrders, type PurchaseOrderRecord } from "@/features/orders/orders-data";
import { getOrderStatusLabel } from "@/features/orders/order-status";
import {
  authorizeOrderToCompras,
  returnOrderToRequester,
} from "@/features/workflow/authorize-orders-service";
import { useSessionStore } from "@/store/session-store";
import { StatusBadge } from "@/shared/ui/status-badge";

type UrgencyFilter = "all" | "normal" | "urgente";
type BusyAction = "authorize" | "return" | "accept-all" | null;

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

function summarizeItems(order: PurchaseOrderRecord) {
  const totalPieces = order.items.reduce((sum, item) => sum + (item.pieces || 0), 0);
  return `${order.items.length} articulo(s) | ${totalPieces} pieza(s)`;
}

function urgencyLine(order: PurchaseOrderRecord) {
  const justification = order.urgentJustification?.trim() ?? "";
  if (!justification) {
    return `Urgencia: ${order.urgency === "urgente" ? "Urgente" : "Normal"}`;
  }
  return `Urgencia: Urgente | ${justification}`;
}

export function AuthorizeOrdersPage() {
  const profile = useSessionStore((state) => state.profile);
  const canAuthorize = hasComprasAccess(profile) || hasDireccionApprovalAccess(profile);
  const ordersState = useRtdbValue("purchaseOrders", mapOrders, canAuthorize);

  const [urgencyFilter, setUrgencyFilter] = useState<UrgencyFilter>("all");
  const [search, setSearch] = useState("");
  const [createdFrom, setCreatedFrom] = useState<Date | null>(null);
  const [createdTo, setCreatedTo] = useState<Date | null>(null);
  const [returnComments, setReturnComments] = useState<Record<string, string>>({});
  const [busyOrderId, setBusyOrderId] = useState<string | null>(null);
  const [busyAction, setBusyAction] = useState<BusyAction>(null);
  const [pageError, setPageError] = useState<string | null>(null);

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

  async function handleAuthorize(order: PurchaseOrderRecord) {
    if (!profile) return;
    setPageError(null);
    setBusyOrderId(order.id);
    setBusyAction("authorize");
    try {
      await authorizeOrderToCompras(order, profile);
    } catch (error) {
      setPageError(error instanceof Error ? error.message : "No se pudo enviar la orden a Compras.");
    } finally {
      setBusyOrderId(null);
      setBusyAction(null);
    }
  }

  async function handleReturn(order: PurchaseOrderRecord) {
    if (!profile) return;
    const comment = returnComments[order.id]?.trim() ?? "";
    if (!comment) {
      setPageError("Ingresa el motivo del regreso antes de devolver la orden.");
      return;
    }

    setPageError(null);
    setBusyOrderId(order.id);
    setBusyAction("return");
    try {
      await returnOrderToRequester(order, profile, comment);
      setReturnComments((current) => ({ ...current, [order.id]: "" }));
    } catch (error) {
      setPageError(error instanceof Error ? error.message : "No se pudo regresar la orden.");
    } finally {
      setBusyOrderId(null);
      setBusyAction(null);
    }
  }

  async function handleAcceptAll() {
    if (!profile || !orders.length) return;
    const confirmed = window.confirm(
      `Se enviaran ${orders.length} orden(es) visibles a Compras. Usalo solo si ya revisaste el lote completo.`,
    );
    if (!confirmed) return;

    setPageError(null);
    setBusyOrderId(null);
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
            <div className="flex flex-wrap gap-2">
              <StatusBadge label={`${orders.length} pendiente(s)`} tone="info" />
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

          <div className="inline-flex overflow-hidden rounded-full border border-slate-500 bg-white">
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

          <div className="grid gap-3 lg:grid-cols-[minmax(0,1fr)_180px_180px]">
            <label className="relative block">
              <Search
                size={16}
                className="pointer-events-none absolute left-0 top-1/2 -translate-y-1/2 text-slate-500"
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

            <label className="rounded-[18px] bg-slate-100 px-4 py-3">
              <span className="mb-2 flex items-center gap-2 text-sm font-medium text-slate-700">
                <CalendarDays size={15} />
                Desde
              </span>
              <input
                type="date"
                value={formatDateInputValue(createdFrom)}
                onChange={(event) => setCreatedFrom(parseDateInputValue(event.target.value))}
                className="w-full border-0 bg-transparent px-0 text-sm text-slate-900 outline-none"
              />
            </label>

            <label className="rounded-[18px] bg-slate-100 px-4 py-3">
              <span className="mb-2 flex items-center gap-2 text-sm font-medium text-slate-700">
                <CalendarDays size={15} />
                Hasta
              </span>
              <input
                type="date"
                value={formatDateInputValue(createdTo)}
                onChange={(event) => setCreatedTo(parseDateInputValue(event.target.value))}
                className="w-full border-0 bg-transparent px-0 text-sm text-slate-900 outline-none"
              />
            </label>
          </div>
        </div>

        {pageError ? (
          <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
            {pageError}
          </div>
        ) : null}
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
            const busy = busyOrderId === order.id;
            const returnComment = returnComments[order.id] ?? order.lastReturnReason ?? "";

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
                    <p
                      className={[
                        "mt-1 text-sm",
                        order.urgentJustification?.trim() ? "font-medium text-red-700" : "text-slate-700",
                      ].join(" ")}
                    >
                      {urgencyLine(order)}
                    </p>
                  </div>
                  <div className="flex flex-wrap gap-2 lg:justify-end">
                    <StatusBadge label={getOrderStatusLabel(order.status)} tone="info" />
                    <StatusBadge
                      label={order.urgency === "urgente" ? "Urgente" : "Normal"}
                      tone={order.urgency === "urgente" ? "danger" : "neutral"}
                    />
                  </div>
                </div>

                <div className="mt-4 grid gap-3 md:grid-cols-3">
                  <InfoBox label="Creada" value={formatDateTime(order.createdAt)} />
                  <InfoBox label="Actualizada" value={formatDateTime(order.updatedAt)} />
                  <InfoBox label="Articulos" value={summarizeItems(order)} />
                </div>

                {order.clientNote ? (
                  <div className="mt-4 rounded-[18px] bg-slate-50 px-4 py-4">
                    <p className="text-sm font-medium text-slate-700">Observaciones</p>
                    <p className="mt-2 text-sm text-slate-800">{order.clientNote}</p>
                  </div>
                ) : null}

                <div className="mt-4 rounded-[18px] bg-slate-50 px-4 py-4">
                  <p className="text-xs font-medium uppercase tracking-[0.16em] text-slate-500">
                    Resumen de articulos
                  </p>
                  <div className="mt-3 space-y-2">
                    {order.items.slice(0, 3).map((item) => (
                      <div
                        key={`${order.id}-${item.line}`}
                        className="flex flex-col gap-1 border-b border-slate-200 pb-2 last:border-b-0 last:pb-0 md:flex-row md:items-start md:justify-between"
                      >
                        <div>
                          <p className="text-sm font-medium text-slate-900">
                            Articulo {item.line}: {item.description}
                          </p>
                          <p className="mt-1 text-xs text-slate-500">
                            No. de parte: {item.partNumber || "-"} | Cliente: {item.customer || "-"}
                          </p>
                        </div>
                        <p className="text-sm text-slate-700">
                          {item.pieces} {item.unit}
                        </p>
                      </div>
                    ))}
                    {order.items.length > 3 ? (
                      <p className="text-xs text-slate-500">
                        {order.items.length - 3} articulo(s) mas en el PDF de la requisicion.
                      </p>
                    ) : null}
                  </div>
                </div>

                <div className="mt-4">
                  <label className="mb-2 block text-sm font-medium text-slate-700">
                    Motivo para regresar a correccion
                  </label>
                  <textarea
                    value={returnComment}
                    onChange={(event) =>
                      setReturnComments((current) => ({ ...current, [order.id]: event.target.value }))
                    }
                    rows={3}
                    className="w-full resize-none border-0 border-b border-slate-500 bg-transparent px-0 py-2 text-[15px] text-slate-900 outline-none"
                  />
                </div>

                <div className="mt-5 flex flex-col gap-3 sm:flex-row sm:flex-wrap">
                  <Link
                    to={`/orders/history/${order.id}/print`}
                    className="inline-flex items-center justify-center rounded-2xl border border-slate-700 bg-white px-4 py-2.5 text-sm font-medium text-slate-800"
                  >
                    Ver PDF
                  </Link>
                  <button
                    type="button"
                    onClick={() => handleReturn(order)}
                    disabled={busy || busyAction === "accept-all"}
                    className="rounded-2xl border border-red-700 bg-red-700 px-4 py-2.5 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
                  >
                    {busy && busyAction === "return" ? "Regresando..." : "Regresar al solicitante"}
                  </button>
                  <button
                    type="button"
                    onClick={() => handleAuthorize(order)}
                    disabled={busy || busyAction === "accept-all"}
                    className="rounded-2xl border border-slate-900 bg-slate-900 px-4 py-2.5 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
                  >
                    {busy && busyAction === "authorize" ? "Enviando..." : "Mandar a Compras"}
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

function InfoBox({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-[18px] bg-slate-50 px-4 py-4">
      <p className="text-xs font-medium uppercase tracking-[0.16em] text-slate-500">{label}</p>
      <p className="mt-2 text-sm font-medium text-slate-900">{value}</p>
    </div>
  );
}
