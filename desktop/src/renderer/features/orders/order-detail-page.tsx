import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useRtdbValue } from "@/lib/firebase/hooks";
import {
  isArrivalPendingConfirmation,
  isRequesterReceiptConfirmed,
  mapOrders,
  requesterReceiptStatusLabel,
} from "@/features/orders/orders-data";
import { getEventTypeLabel, getOrderStatusLabel } from "@/features/orders/order-status";
import { confirmRequesterReceived } from "@/features/workflow/packet-follow-up-service";
import { buildOrderCsv, downloadTextFile, openExternalUrl } from "@/lib/downloads";
import { StatusBadge } from "@/shared/ui/status-badge";
import { useSessionStore } from "@/store/session-store";
import { Snackbar } from "@/shared/ui/snackbar";

function formatDateTime(value?: number) {
  if (!value) return "Sin fecha";
  return new Intl.DateTimeFormat("es-MX", {
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(value));
}

export function OrderDetailPage() {
  const params = useParams();
  const profile = useSessionStore((state) => state.profile);
  const orderId = params.orderId ?? "";
  const ordersState = useRtdbValue("purchaseOrders", mapOrders, Boolean(orderId));
  const order = (ordersState.data ?? []).find((item) => item.id === orderId);

  const [actionError, setActionError] = useState<string | null>(null);
  const [actionMessage, setActionMessage] = useState<string | null>(null);
  const [isConfirming, setIsConfirming] = useState(false);

  const canConfirmReceipt = order
    ? Boolean(profile) &&
      order.requesterId === profile?.id &&
      order.status === "eta" &&
      !isRequesterReceiptConfirmed(order) &&
      isArrivalPendingConfirmation(order)
    : false;

  async function handleConfirmReceipt() {
    if (!order || !profile) return;
    setActionError(null);
    setActionMessage(null);
    setIsConfirming(true);
    try {
      await confirmRequesterReceived(order, profile);
      setActionMessage("Recibido confirmado por el solicitante.");
    } catch (error) {
      setActionError(error instanceof Error ? error.message : "No se pudo confirmar el recibido.");
    } finally {
      setIsConfirming(false);
    }
  }

  useEffect(() => {
    if (!actionError) return;
    const timer = window.setTimeout(() => setActionError(null), 3600);
    return () => window.clearTimeout(timer);
  }, [actionError]);

  useEffect(() => {
    if (!actionMessage) return;
    const timer = window.setTimeout(() => setActionMessage(null), 3600);
    return () => window.clearTimeout(timer);
  }, [actionMessage]);

  return (
    <div className="app-page">
      {ordersState.isLoading ? (
        <div className="app-card text-sm text-slate-500">Cargando detalle...</div>
      ) : ordersState.error ? (
        <div className="app-card text-sm text-red-700">No se pudo cargar la orden: {ordersState.error}</div>
      ) : !order ? (
        <div className="app-card text-sm text-slate-500">No se encontro la orden.</div>
      ) : (
        <>
          <section className="grid gap-5 2xl:grid-cols-[0.95fr_1.05fr]">
            <article className="app-card">
              <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                <div>
                  <h4 className="text-xl font-semibold text-slate-900">{order.id}</h4>
                  <p className="mt-1 text-sm text-slate-500">{getOrderStatusLabel(order.status)}</p>
                </div>
                <div className="flex flex-wrap gap-2">
                  <StatusBadge
                    label={order.urgency === "urgente" ? "Urgente" : "Normal"}
                    tone={order.urgency === "urgente" ? "danger" : "info"}
                  />
                  <Link to="/orders/history" className="app-button-secondary">
                    Volver al historial
                  </Link>
                </div>
              </div>

              <div className="mt-4 flex flex-wrap gap-2">
                <StatusBadge label={requesterReceiptStatusLabel(order)} tone="neutral" />
                {order.facturaPdfUrls.length ? (
                  <StatusBadge label={`${order.facturaPdfUrls.length} factura(s)`} tone="info" />
                ) : null}
                {order.paymentReceiptUrls.length ? (
                  <StatusBadge label={`${order.paymentReceiptUrls.length} recibo(s)`} tone="success" />
                ) : null}
              </div>

              <div className="mt-5 flex flex-col gap-3 sm:flex-row sm:flex-wrap">
                <button
                  type="button"
                  onClick={() =>
                    downloadTextFile(buildOrderCsv(order), `orden_compra_${order.id}.csv`, "text/csv")
                  }
                  className="app-button-secondary"
                >
                  Descargar CSV
                </button>
                <Link to={`/orders/history/${order.id}/print`} className="app-button-secondary">
                  Vista imprimible
                </Link>
                {order.pdfUrl ? (
                  <button
                    type="button"
                    onClick={() => openExternalUrl(order.pdfUrl ?? "")}
                    className="app-button-secondary"
                  >
                    Abrir PDF
                  </button>
                ) : null}
              </div>

              <dl className="mt-5 grid gap-4 text-sm sm:grid-cols-2">
                <InfoLine label="Solicitante" value={order.requesterName} />
                <InfoLine label="Area" value={order.areaName} />
                <InfoLine label="Proveedor" value={order.supplier ?? "Sin proveedor"} />
                <InfoLine label="Creada" value={formatDateTime(order.createdAt)} />
                <InfoLine label="Actualizada" value={formatDateTime(order.updatedAt)} />
                <InfoLine label="Fecha requerida" value={formatDateTime(order.requestedDeliveryDate)} />
                <InfoLine label="ETA general" value={formatDateTime(order.etaDate)} />
                <InfoLine label="Material recibido" value={formatDateTime(order.materialArrivedAt)} />
                <InfoLine label="Solicitante confirmo" value={formatDateTime(order.requesterReceivedAt)} />
              </dl>

              {canConfirmReceipt ? (
                <button
                  type="button"
                  onClick={() => void handleConfirmReceipt()}
                  disabled={isConfirming}
                  className="app-button-primary mt-5"
                >
                  {isConfirming ? "Confirmando..." : "Confirmar recibido"}
                </button>
              ) : null}

              {order.clientNote ? (
                <div className="app-card-muted mt-5">
                  <p className="font-semibold text-slate-900">Observaciones</p>
                  <p className="mt-2 text-sm text-slate-700">{order.clientNote}</p>
                </div>
              ) : null}

              {order.urgentJustification ? (
                <div className="mt-4 rounded-2xl bg-red-50 p-4 text-sm text-red-700">
                  <p className="font-semibold text-red-900">Justificacion de urgencia</p>
                  <p className="mt-2">{order.urgentJustification}</p>
                </div>
              ) : null}
            </article>

            <article className="app-card">
              <h4 className="text-xl font-semibold text-slate-900">Renglones capturados</h4>

              <div className="mt-5 space-y-3">
                {order.items.map((item) => (
                  <article key={`${order.id}-${item.line}`} className="app-card-muted">
                    <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                      <div>
                        <p className="text-sm font-semibold text-slate-900">Linea {item.line}</p>
                        <p className="mt-1 text-sm text-slate-700">{item.description}</p>
                      </div>
                      <StatusBadge label={`${item.pieces} ${item.unit}`} tone="neutral" />
                    </div>
                    <div className="mt-4 grid gap-3 text-sm sm:grid-cols-2">
                      <InfoLine label="Parte" value={item.partNumber || "-"} />
                      <InfoLine label="Cliente" value={item.customer || "-"} />
                      <InfoLine label="ETA" value={formatDateTime(item.deliveryEtaDate)} />
                      <InfoLine label="Llegada" value={formatDateTime(item.arrivedAt)} />
                      <InfoLine label="OC interna" value={item.internalOrder || "-"} />
                      <InfoLine label="Proveedor" value={item.supplier || "-"} />
                    </div>
                  </article>
                ))}
              </div>
            </article>
          </section>

          {(order.facturaPdfUrls.length || order.paymentReceiptUrls.length) ? (
            <section className="grid gap-5 lg:grid-cols-2">
              <LinksCard title="Facturas" links={order.facturaPdfUrls} emptyLabel="No hay links de factura." />
              <LinksCard
                title="Recibos de pago"
                links={order.paymentReceiptUrls}
                emptyLabel="No hay links de recibo."
              />
            </section>
          ) : null}

          <section className="app-card">
            <h4 className="text-xl font-semibold text-slate-900">Historial de eventos</h4>

            <div className="mt-5 space-y-3">
              {order.events.length ? (
                order.events.map((event) => (
                  <article key={event.id} className="app-card-muted">
                    <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                      <div>
                        <p className="text-sm font-semibold text-slate-900">{getEventTypeLabel(event.type)}</p>
                        <p className="mt-1 text-xs text-slate-500">
                          {getOrderStatusLabel(event.fromStatus ?? "")} {"->"}{" "}
                          {getOrderStatusLabel(event.toStatus ?? "")}
                        </p>
                      </div>
                      <p className="text-xs text-slate-500">{formatDateTime(event.timestamp)}</p>
                    </div>
                    <p className="mt-3 text-sm text-slate-700">
                      Actor: {event.byRole || event.byUserId || "Sistema"}
                    </p>
                    {event.comment ? <p className="mt-2 text-sm text-slate-600">{event.comment}</p> : null}
                  </article>
                ))
              ) : (
                <p className="text-sm text-slate-500">Esta orden aun no tiene eventos registrados.</p>
              )}
            </div>
          </section>
        </>
      )}
      <Snackbar message={actionError} tone="error" />
      <Snackbar message={actionMessage} tone="success" />
    </div>
  );
}

function InfoLine({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-slate-500">{label}</dt>
      <dd className="mt-1 font-medium text-slate-900">{value}</dd>
    </div>
  );
}

function LinksCard({
  title,
  links,
  emptyLabel,
}: {
  title: string;
  links: string[];
  emptyLabel: string;
}) {
  return (
    <article className="app-card">
      <h4 className="text-xl font-semibold text-slate-900">{title}</h4>
      <div className="mt-4 space-y-3">
        {links.length ? (
          links.map((url) => (
            <a
              key={url}
              href={url}
              target="_blank"
              rel="noreferrer"
              className="block break-all text-sm text-blue-700 underline"
            >
              {url}
            </a>
          ))
        ) : (
          <p className="text-sm text-slate-500">{emptyLabel}</p>
        )}
      </div>
    </article>
  );
}
