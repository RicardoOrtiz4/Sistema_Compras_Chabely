import { Link, useParams } from "react-router-dom";
import { useRtdbValue } from "@/lib/firebase/hooks";
import { mapOrders } from "@/features/orders/orders-data";
import { getOrderStatusLabel } from "@/features/orders/order-status";

function formatDateTime(value?: number) {
  if (!value) return "Sin fecha";
  return new Intl.DateTimeFormat("es-MX", {
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(value));
}

function formatDate(value?: number) {
  if (!value) return "Sin fecha";
  return new Intl.DateTimeFormat("es-MX", {
    dateStyle: "medium",
  }).format(new Date(value));
}

export function OrderPrintPage() {
  const params = useParams();
  const orderId = params.orderId ?? "";
  const ordersState = useRtdbValue("purchaseOrders", mapOrders, Boolean(orderId));
  const order = (ordersState.data ?? []).find((item) => item.id === orderId);

  return (
    <div className="mx-auto max-w-5xl space-y-6 bg-[linear-gradient(180deg,#f8fafc_0%,#ffffff_28%,#f8fafc_100%)] p-8 text-slate-900 print:max-w-none print:bg-white print:p-0">
      <div className="flex items-center justify-between print:hidden">
        <Link
          to={`/orders/history/${orderId}`}
          className="rounded-2xl border border-line bg-white px-4 py-2 text-sm font-medium text-slate-700"
        >
          Volver al detalle
        </Link>
        <button
          type="button"
          onClick={() => window.print()}
          className="rounded-2xl bg-slate-900 px-4 py-2 text-sm font-semibold text-white"
        >
          Imprimir / Guardar PDF
        </button>
      </div>

      {ordersState.isLoading ? (
        <div className="text-sm text-slate-500">Cargando orden...</div>
      ) : ordersState.error ? (
        <div className="text-sm text-red-600">No se pudo cargar la orden: {ordersState.error}</div>
      ) : !order ? (
        <div className="text-sm text-slate-500">No se encontro la orden.</div>
      ) : (
        <div className="overflow-hidden rounded-[32px] border border-slate-200 bg-white shadow-[0_24px_80px_rgba(15,23,42,0.08)] print:rounded-none print:border-0 print:shadow-none">
          <header className="bg-[linear-gradient(135deg,#0f172a_0%,#1e293b_58%,#334155_100%)] px-8 py-8 text-white">
            <div className="flex items-start justify-between gap-6">
              <div>
                <p className="text-xs font-semibold uppercase tracking-[0.32em] text-slate-300">
                  Sistema de Compras
                </p>
                <h1 className="mt-3 text-3xl font-semibold tracking-[0.02em]">Requisicion {order.id}</h1>
                <p className="mt-2 text-sm text-slate-300">{getOrderStatusLabel(order.status)}</p>
              </div>

              <div className="min-w-56 rounded-[24px] border border-white/15 bg-white/10 p-4 backdrop-blur-sm">
                <p className="text-xs uppercase tracking-[0.24em] text-slate-300">Emision</p>
                <p className="mt-2 text-lg font-semibold">{formatDate(order.createdAt ?? order.updatedAt)}</p>
                <p className="mt-2 text-sm text-slate-300">Actualizada: {formatDateTime(order.updatedAt ?? order.createdAt)}</p>
              </div>
            </div>
          </header>

          <div className="space-y-8 px-8 py-8">
            <section className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
              <InfoBlock label="Solicitante" value={order.requesterName} />
              <InfoBlock label="Area" value={order.areaName} />
              <InfoBlock label="Urgencia" value={order.urgency === "urgente" ? "Urgente" : "Normal"} />
              <InfoBlock label="Fecha requerida" value={formatDate(order.requestedDeliveryDate)} />
            </section>

            <section className="grid gap-6 xl:grid-cols-[1.1fr_0.9fr]">
              <article className="rounded-[28px] border border-slate-200 bg-slate-50 p-6">
                <p className="text-xs font-semibold uppercase tracking-[0.26em] text-slate-500">Resumen</p>
                <div className="mt-4 grid gap-4 md:grid-cols-2">
                  <SummaryRow label="Proveedor" value={order.supplier ?? "Sin proveedor"} />
                  <SummaryRow label="Autorizo" value={order.authorizedByName ?? "Pendiente"} />
                  <SummaryRow label="Compras" value={order.processByName ?? "Pendiente"} />
                  <SummaryRow label="ETA" value={formatDate(order.etaDate)} />
                </div>
              </article>

              <article className="rounded-[28px] border border-slate-200 bg-white p-6">
                <p className="text-xs font-semibold uppercase tracking-[0.26em] text-slate-500">Notas</p>
                <div className="mt-4 space-y-4 text-sm text-slate-700">
                  <div>
                    <p className="font-semibold text-slate-900">Observaciones</p>
                    <p className="mt-2 whitespace-pre-wrap">{order.clientNote || "Sin observaciones."}</p>
                  </div>
                  {order.urgentJustification ? (
                    <div>
                      <p className="font-semibold text-slate-900">Justificacion de urgencia</p>
                      <p className="mt-2 whitespace-pre-wrap">{order.urgentJustification}</p>
                    </div>
                  ) : null}
                </div>
              </article>
            </section>

            <section>
              <div className="flex items-center justify-between gap-4">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-[0.26em] text-slate-500">Detalle</p>
                  <h2 className="mt-2 text-xl font-semibold">Articulos</h2>
                </div>
                <div className="rounded-full bg-slate-100 px-4 py-2 text-sm font-medium text-slate-700">
                  {order.items.length} renglon(es)
                </div>
              </div>

              <div className="mt-4 overflow-hidden rounded-[28px] border border-slate-200">
                <table className="min-w-full border-collapse text-sm">
                  <thead className="bg-slate-900 text-slate-100">
                    <tr className="text-left">
                      <th className="px-4 py-3 font-semibold">Linea</th>
                      <th className="px-4 py-3 font-semibold">Descripcion</th>
                      <th className="px-4 py-3 font-semibold">Cantidad</th>
                      <th className="px-4 py-3 font-semibold">Unidad</th>
                      <th className="px-4 py-3 font-semibold">Parte</th>
                      <th className="px-4 py-3 font-semibold">Cliente</th>
                    </tr>
                  </thead>
                  <tbody>
                    {order.items.map((item, index) => (
                      <tr
                        key={`${order.id}-${item.line}`}
                        className={index % 2 === 0 ? "bg-white" : "bg-slate-50"}
                      >
                        <td className="px-4 py-3 align-top">{item.line}</td>
                        <td className="px-4 py-3 align-top">{item.description}</td>
                        <td className="px-4 py-3 align-top">{item.pieces}</td>
                        <td className="px-4 py-3 align-top">{item.unit}</td>
                        <td className="px-4 py-3 align-top">{item.partNumber || "-"}</td>
                        <td className="px-4 py-3 align-top">{item.customer || "-"}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>

            <footer className="border-t border-dashed border-slate-300 pt-6">
              <div className="grid gap-8 md:grid-cols-2">
                <SignatureBlock title="Solicitante" value={order.requesterName} />
                <SignatureBlock title="Autorizacion / Compras" value={order.authorizedByName ?? order.processByName ?? ""} />
              </div>
            </footer>
          </div>
        </div>
      )}
    </div>
  );
}

function InfoBlock({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-[24px] border border-slate-200 bg-white p-5">
      <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-500">{label}</p>
      <p className="mt-3 text-sm font-semibold text-slate-900">{value}</p>
    </div>
  );
}

function SummaryRow({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-xs uppercase tracking-[0.2em] text-slate-500">{label}</p>
      <p className="mt-2 text-sm font-medium text-slate-900">{value}</p>
    </div>
  );
}

function SignatureBlock({ title, value }: { title: string; value: string }) {
  return (
    <div className="pt-10">
      <div className="border-t border-slate-400 pt-3">
        <p className="text-sm font-semibold text-slate-900">{title}</p>
        <p className="mt-1 text-sm text-slate-600">{value || " "}</p>
      </div>
    </div>
  );
}
