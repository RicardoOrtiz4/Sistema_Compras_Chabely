import { useMemo, useState } from "react";
import { hasReportsAccess } from "@/lib/access-control";
import { useRtdbValue } from "@/lib/firebase/hooks";
import { mapOrders, type PurchaseOrderRecord } from "@/features/orders/orders-data";
import { useSessionStore } from "@/store/session-store";
import { StatusBadge } from "@/shared/ui/status-badge";

type QuickRange = "all" | "today" | "sevenDays" | "thirtyDays" | "thisMonth";
type DateRange = { start: Date; end: Date };
type ReportItem = { label: string; value: string; order: number };
type MonthBucket = { date: Date; ordersCount: number };
type ReportsData = {
  totalOrders: number;
  activeOrders: number;
  completedOrders: number;
  rejectedOrders: number;
  urgentOrders: number;
  ordersWithSupplier: number;
  supplierItems: ReportItem[];
  monthlyTrendBuckets: MonthBucket[];
};

function parseDateInput(value: string) {
  if (!value.trim()) return null;
  const parsed = new Date(`${value}T00:00:00`);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function formatDateLabel(date: Date) {
  return new Intl.DateTimeFormat("es-MX", { dateStyle: "medium" }).format(date);
}

function isRejectedOrder(order: PurchaseOrderRecord) {
  const isRejectedDraft = order.status === "draft" && (Boolean(order.lastReturnReason?.trim()) || order.returnCount > 0);
  const isRejectedPendingAcknowledgment = isRejectedDraft && !order.rejectionAcknowledgedAt;
  return isRejectedDraft || isRejectedPendingAcknowledgment;
}

function matchesRange(timestamp: number | undefined, range: DateRange | null) {
  if (!range) return true;
  if (!timestamp) return false;
  const date = new Date(timestamp);
  const start = new Date(range.start.getFullYear(), range.start.getMonth(), range.start.getDate());
  const end = new Date(range.end.getFullYear(), range.end.getMonth(), range.end.getDate() + 1);
  return date >= start && date < end;
}

function buildSupplierItems(orders: PurchaseOrderRecord[]) {
  const totals = new Map<string, number>();
  for (const order of orders) {
    const seen = new Set<string>();
    const directSupplier = order.supplier?.trim() ?? "";
    if (directSupplier) seen.add(directSupplier);
    for (const item of order.items) {
      const supplier = item.supplier?.trim() ?? "";
      if (supplier) seen.add(supplier);
    }
    for (const supplier of seen) totals.set(supplier, (totals.get(supplier) ?? 0) + 1);
  }
  return [...totals.entries()]
    .map(([label, count]) => ({ label, value: `${count} ord`, order: count }))
    .sort((left, right) => right.order - left.order);
}

function buildMonthlyTrendBuckets(now: Date, orders: PurchaseOrderRecord[]) {
  const buckets = new Map<string, MonthBucket>();
  for (let offset = 5; offset >= 0; offset -= 1) {
    const date = new Date(now.getFullYear(), now.getMonth() - offset, 1);
    const key = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
    buckets.set(key, { date, ordersCount: 0 });
  }
  for (const order of orders) {
    if (!order.createdAt) continue;
    const createdAt = new Date(order.createdAt);
    const key = `${createdAt.getFullYear()}-${String(createdAt.getMonth() + 1).padStart(2, "0")}`;
    const bucket = buckets.get(key);
    if (bucket) bucket.ordersCount += 1;
  }
  return [...buckets.values()];
}

function buildReportsData(orders: PurchaseOrderRecord[], now: Date, range: DateRange | null): ReportsData {
  const filteredOrders = orders.filter((order) => matchesRange(order.createdAt, range));
  const rejectedOrders = filteredOrders.filter(isRejectedOrder);
  const completedOrders = filteredOrders.filter((order) => order.status === "eta");
  const activeOrders = filteredOrders.filter((order) => order.status !== "eta" && !isRejectedOrder(order));
  const urgentOrders = filteredOrders.filter((order) => order.urgency === "urgente");
  const ordersWithSupplier = filteredOrders.filter((order) => {
    if (order.supplier?.trim()) return true;
    return order.items.some((item) => item.supplier?.trim());
  }).length;

  return {
    totalOrders: filteredOrders.length,
    activeOrders: activeOrders.length,
    completedOrders: completedOrders.length,
    rejectedOrders: rejectedOrders.length,
    urgentOrders: urgentOrders.length,
    ordersWithSupplier,
    supplierItems: buildSupplierItems(filteredOrders),
    monthlyTrendBuckets: buildMonthlyTrendBuckets(now, filteredOrders),
  };
}

function rangeLabel(range: DateRange | null, quickRange: QuickRange) {
  if (range) return `${formatDateLabel(range.start)} - ${formatDateLabel(range.end)}`;
  switch (quickRange) {
    case "today":
      return "Hoy";
    case "sevenDays":
      return "7 dias";
    case "thirtyDays":
      return "30 dias";
    case "thisMonth":
      return "Este mes";
    default:
      return "Todo el historial";
  }
}

function effectiveQuickRange(now: Date, quickRange: QuickRange): DateRange | null {
  switch (quickRange) {
    case "today":
      return { start: new Date(now.getFullYear(), now.getMonth(), now.getDate()), end: new Date(now.getFullYear(), now.getMonth(), now.getDate()) };
    case "sevenDays":
      return { start: new Date(now.getFullYear(), now.getMonth(), now.getDate() - 6), end: new Date(now.getFullYear(), now.getMonth(), now.getDate()) };
    case "thirtyDays":
      return { start: new Date(now.getFullYear(), now.getMonth(), now.getDate() - 29), end: new Date(now.getFullYear(), now.getMonth(), now.getDate()) };
    case "thisMonth":
      return { start: new Date(now.getFullYear(), now.getMonth(), 1), end: new Date(now.getFullYear(), now.getMonth() + 1, 0) };
    default:
      return null;
  }
}

export function ReportsPage() {
  const profile = useSessionStore((state) => state.profile);
  const ordersState = useRtdbValue("purchaseOrders", mapOrders, Boolean(profile));
  const [quickRange, setQuickRange] = useState<QuickRange>("all");
  const [manualStart, setManualStart] = useState("");
  const [manualEnd, setManualEnd] = useState("");

  const canView = hasReportsAccess(profile);
  const now = useMemo(() => new Date(), []);
  const manualRange = useMemo(() => {
    const start = parseDateInput(manualStart);
    const end = parseDateInput(manualEnd);
    if (!start || !end) return null;
    return start <= end ? { start, end } : { start: end, end: start };
  }, [manualEnd, manualStart]);
  const range = manualRange ?? effectiveQuickRange(now, quickRange);
  const data = useMemo(() => buildReportsData(ordersState.data ?? [], now, range), [ordersState.data, now, range]);

  if (!canView) {
    return <div className="app-card text-sm text-slate-600">No tienes permisos para ver reportes.</div>;
  }

  return (
    <div className="app-page">
      <section className="app-card">
        <div className="mb-5 flex justify-end">
          <StatusBadge label={rangeLabel(range, quickRange)} tone="info" />
        </div>

        <div className="flex flex-wrap gap-3">
          {([
            ["all", "Todo el historial"],
            ["today", "Hoy"],
            ["sevenDays", "7 dias"],
            ["thirtyDays", "30 dias"],
            ["thisMonth", "Este mes"],
          ] as Array<[QuickRange, string]>).map(([value, label]) => (
            <button key={value} type="button" onClick={() => { setQuickRange(value); setManualStart(""); setManualEnd(""); }} className={`app-chip-toggle ${quickRange === value && !manualRange ? "app-chip-toggle-active" : ""}`}>
              {label}
            </button>
          ))}
        </div>

        <div className="mt-5 grid gap-3 md:grid-cols-[1fr_1fr_auto]">
          <label className="block">
            <span className="mb-2 block text-sm font-medium text-slate-700">Desde</span>
            <input type="date" value={manualStart} onChange={(event) => setManualStart(event.target.value)} className="app-input" />
          </label>
          <label className="block">
            <span className="mb-2 block text-sm font-medium text-slate-700">Hasta</span>
            <input type="date" value={manualEnd} onChange={(event) => setManualEnd(event.target.value)} className="app-input" />
          </label>
          <div className="flex items-end">
            <button type="button" onClick={() => { setQuickRange("all"); setManualStart(""); setManualEnd(""); }} className="app-button-secondary">
              Limpiar
            </button>
          </div>
        </div>
      </section>

      {ordersState.isLoading ? (
        <section className="app-card text-sm text-slate-500">Cargando reportes...</section>
      ) : ordersState.error ? (
        <section className="app-card text-sm text-red-700">No se pudieron cargar los reportes: {ordersState.error}</section>
      ) : (
        <>
          <section className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
            <KpiCard title="Ordenes" value={data.totalOrders} subtitle="registradas en el rango" tone="blue" />
            <KpiCard title="Activas" value={data.activeOrders} subtitle="siguen en flujo" tone="green" />
            <KpiCard title="Finalizadas" value={data.completedOrders} subtitle="cerradas correctamente" tone="emerald" />
            <KpiCard title="Rechazadas" value={data.rejectedOrders} subtitle="devueltas o canceladas" tone="red" />
            <KpiCard title="Urgentes" value={data.urgentOrders} subtitle="prioridad alta" tone="amber" />
            <KpiCard title="Con proveedor" value={data.ordersWithSupplier} subtitle="ya asignadas" tone="sky" />
          </section>

          <section className="grid gap-5 xl:grid-cols-[0.9fr_1.1fr]">
            <TopSuppliersCard data={data} />
            <OrdersTrendCard data={data} />
          </section>
        </>
      )}
    </div>
  );
}

function KpiCard({
  title,
  value,
  subtitle,
  tone,
}: {
  title: string;
  value: number;
  subtitle: string;
  tone: "blue" | "green" | "emerald" | "red" | "amber" | "sky";
}) {
  const toneClass = {
    blue: "bg-blue-50 text-blue-700",
    green: "bg-green-50 text-green-700",
    emerald: "bg-emerald-50 text-emerald-700",
    red: "bg-red-50 text-red-700",
    amber: "bg-amber-50 text-amber-700",
    sky: "bg-sky-50 text-sky-700",
  }[tone];

  return (
    <article className="app-card">
      <div className={`inline-flex rounded-2xl px-3 py-2 text-sm font-semibold ${toneClass}`}>{title}</div>
      <p className="mt-5 text-4xl font-black text-slate-900">{value}</p>
      <p className="mt-2 text-sm text-slate-500">{subtitle}</p>
    </article>
  );
}

function TopSuppliersCard({ data }: { data: ReportsData }) {
  const maxValue = data.supplierItems[0]?.order ?? 1;
  return (
    <article className="app-card">
      <h4 className="text-xl font-semibold text-slate-900">Top proveedores por orden</h4>
      <p className="mt-2 text-sm text-slate-500">Ordenes acumuladas por proveedor en el rango.</p>
      <div className="mt-4 inline-flex rounded-2xl bg-blue-50 px-4 py-3 text-sm font-semibold text-blue-700">Total con proveedor: {data.ordersWithSupplier}</div>
      <div className="mt-5 space-y-4">
        {data.supplierItems.length === 0 ? (
          <p className="text-sm text-slate-500">Sin proveedores en el rango.</p>
        ) : (
          data.supplierItems.slice(0, 8).map((item, index) => (
            <div key={item.label}>
              <div className="flex items-center gap-3">
                <div className="flex h-8 w-8 items-center justify-center rounded-full bg-blue-50 text-sm font-bold text-blue-700">{index + 1}</div>
                <div className="flex-1"><p className="font-semibold text-slate-900">{item.label}</p></div>
                <p className="text-sm font-semibold text-slate-500">{item.value}</p>
              </div>
              <div className="mt-3 overflow-hidden rounded-full bg-slate-200">
                <div className="h-2 rounded-full bg-blue-500" style={{ width: `${Math.max((item.order / maxValue) * 100, 6)}%` }} />
              </div>
            </div>
          ))
        )}
      </div>
    </article>
  );
}

function OrdersTrendCard({ data }: { data: ReportsData }) {
  const maxValue = Math.max(...data.monthlyTrendBuckets.map((bucket) => bucket.ordersCount), 1);
  const totalOrders = data.monthlyTrendBuckets.reduce((sum, bucket) => sum + bucket.ordersCount, 0);

  return (
    <article className="app-card">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h4 className="text-xl font-semibold text-slate-900">Tendencia de ordenes</h4>
          <p className="mt-2 text-sm text-slate-500">Ultimos 6 meses de ordenes registradas.</p>
        </div>
        <StatusBadge label={`Total ordenes: ${totalOrders}`} tone="info" />
      </div>
      <div className="mt-8 grid h-64 grid-cols-6 items-end gap-4">
        {data.monthlyTrendBuckets.map((bucket) => (
          <div key={`${bucket.date.getFullYear()}-${bucket.date.getMonth() + 1}`} className="flex h-full flex-col justify-end">
            <div className="mb-3 text-center text-xs font-semibold text-slate-500">{bucket.ordersCount}</div>
            <div className="flex h-full items-end rounded-t-3xl bg-slate-100 p-2">
              <div className="w-full rounded-t-2xl bg-blue-500" style={{ height: `${Math.max((bucket.ordersCount / maxValue) * 100, bucket.ordersCount > 0 ? 12 : 0)}%` }} />
            </div>
            <div className="mt-3 text-center text-xs font-semibold text-slate-500">
              {new Intl.DateTimeFormat("es-MX", { month: "short" }).format(bucket.date)}
            </div>
          </div>
        ))}
      </div>
    </article>
  );
}
