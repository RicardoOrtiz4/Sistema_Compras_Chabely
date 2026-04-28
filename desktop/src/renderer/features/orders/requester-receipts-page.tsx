import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { useRtdbValue } from "@/lib/firebase/hooks";
import {
  countFulfillmentItems,
  countResolvedItems,
  isArrivalPendingConfirmation,
  isRequesterReceiptConfirmed,
  mapOrders,
} from "@/features/orders/orders-data";
import { confirmRequesterReceived } from "@/features/workflow/packet-follow-up-service";
import { StatusBadge } from "@/shared/ui/status-badge";
import { useSessionStore } from "@/store/session-store";

function formatDateTime(value?: number) {
  if (!value) return "Sin fecha";
  return new Intl.DateTimeFormat("es-MX", {
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(value));
}

export function RequesterReceiptsPage() {
  const profile = useSessionStore((state) => state.profile);
  const ordersState = useRtdbValue("purchaseOrders", mapOrders, Boolean(profile));
  const [busyOrderId, setBusyOrderId] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [actionMessage, setActionMessage] = useState<string | null>(null);

  const orders = useMemo(
    () =>
      (ordersState.data ?? [])
        .filter((order) => order.requesterId === profile?.id)
        .filter(
          (order) =>
            order.status === "eta" &&
            !isRequesterReceiptConfirmed(order) &&
            isArrivalPendingConfirmation(order),
        )
        .sort((left, right) => (right.updatedAt ?? 0) - (left.updatedAt ?? 0)),
    [ordersState.data, profile?.id],
  );

  async function handleConfirm(orderId: string) {
    if (!profile) return;
    const order = (ordersState.data ?? []).find((item) => item.id === orderId);
    if (!order) return;
    const confirmed = window.confirm(
      "Esto cerrara la orden para ti y la movera al historial. Hazlo solo cuando realmente hayas recibido los items.",
    );
    if (!confirmed) return;

    setActionError(null);
    setActionMessage(null);
    setBusyOrderId(orderId);
    try {
      await confirmRequesterReceived(order, profile);
      setActionMessage(`Orden ${orderId} confirmada como recibida.`);
    } catch (error) {
      setActionError(error instanceof Error ? error.message : "No se pudo confirmar el recibido.");
    } finally {
      setBusyOrderId(null);
    }
  }

  return (
    <div className="space-y-5 pb-4">
      <section className="rounded-[20px] border border-slate-200 bg-white px-5 py-5">
        <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
          <div>
            <p className="text-[20px] font-semibold text-slate-900">Confirmar recibido</p>
            <p className="mt-1 text-sm text-slate-600">
              Cierra las ordenes cuya entrega ya fue registrada por Compras y estan esperando tu confirmacion.
            </p>
          </div>
          <StatusBadge label={`${orders.length} pendiente(s)`} tone="warning" />
        </div>

        {actionError ? (
          <div className="mt-5 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
            {actionError}
          </div>
        ) : null}
        {actionMessage ? (
          <div className="mt-5 rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-700">
            {actionMessage}
          </div>
        ) : null}
      </section>

      <section className="space-y-3">
        {ordersState.isLoading ? (
          <div className="rounded-[18px] border border-slate-200 bg-white px-5 py-6 text-sm text-slate-500">
            Cargando pendientes...
          </div>
        ) : ordersState.error ? (
          <div className="rounded-[18px] border border-red-200 bg-red-50 px-5 py-6 text-sm text-red-700">
            No se pudo cargar el modulo: {ordersState.error}
          </div>
        ) : !orders.length ? (
          <div className="rounded-[18px] border border-slate-200 bg-white px-5 py-6 text-sm text-slate-500">
            No tienes ordenes pendientes por confirmar.
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
                  <div className="mt-3 flex flex-wrap gap-2">
                    <StatusBadge
                      label={order.urgency === "urgente" ? "Urgente" : "Normal"}
                      tone={order.urgency === "urgente" ? "danger" : "neutral"}
                    />
                    <StatusBadge label="Pendiente de confirmacion" tone="warning" />
                  </div>
                </div>

                <div className="flex flex-wrap gap-2">
                  <Link
                    to={`/orders/history/${order.id}`}
                    className="rounded-2xl border border-slate-300 bg-white px-4 py-2.5 text-sm font-medium text-slate-700"
                  >
                    Ver detalle
                  </Link>
                  <button
                    type="button"
                    onClick={() => void handleConfirm(order.id)}
                    disabled={busyOrderId === order.id}
                    className="rounded-2xl border border-slate-900 bg-slate-900 px-4 py-2.5 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
                  >
                    {busyOrderId === order.id ? "Confirmando..." : "Confirmar recibido"}
                  </button>
                </div>
              </div>

              <div className="mt-4 rounded-[18px] bg-slate-50 px-4 py-4">
                <p className="text-sm text-slate-700">
                  Items llegados: {countResolvedItems(order)} | Pendientes de llegada:{" "}
                  {Math.max(countFulfillmentItems(order) - countResolvedItems(order), 0)}
                </p>
                <div className="mt-3 grid gap-3 text-sm md:grid-cols-3">
                  <Info label="Material llegado" value={formatDateTime(order.materialArrivedAt)} />
                  <Info label="Actualizada" value={formatDateTime(order.updatedAt)} />
                  <Info label="Items entregables" value={`${countFulfillmentItems(order)}`} />
                </div>
              </div>
            </article>
          ))
        )}
      </section>
    </div>
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
