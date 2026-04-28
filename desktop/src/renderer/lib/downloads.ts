import type { PurchaseOrderRecord } from "@/features/orders/orders-data";
import type { MonitoringRow } from "@/features/orders/monitoring-support";
import { getOrderStatusLabel } from "@/features/orders/order-status";

function triggerDownload(blob: Blob, fileName: string) {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = fileName;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function downloadTextFile(content: string, fileName: string, mimeType: string) {
  const withBom = mimeType === "text/csv" ? `\uFEFF${content}` : content;
  triggerDownload(new Blob([withBom], { type: `${mimeType};charset=utf-8` }), fileName);
}

export function openExternalUrl(url: string) {
  const trimmed = url.trim();
  if (!trimmed) return;
  window.open(trimmed, "_blank", "noopener,noreferrer");
}

function csvEscape(value: string | number | undefined | null) {
  const text = value == null ? "" : String(value);
  if (/[",\n]/.test(text)) {
    return `"${text.replace(/"/g, "\"\"")}"`;
  }
  return text;
}

function csvLine(values: Array<string | number | undefined | null>) {
  return values.map(csvEscape).join(",");
}

function formatDateOnly(value?: number) {
  if (!value) return "";
  return new Date(value).toISOString().slice(0, 10);
}

function formatDateTime(value?: number) {
  if (!value) return "";
  return new Intl.DateTimeFormat("es-MX", {
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(value));
}

function formatNumber(value?: number) {
  if (value == null) return "";
  return Number.isInteger(value) ? String(value) : String(value);
}

export function buildOrderCsv(order: PurchaseOrderRecord) {
  const lines = [
    csvLine(["folio", order.id]),
    csvLine(["solicitante", order.requesterName]),
    csvLine(["areaSolicitante", order.areaName]),
    csvLine(["urgencia", order.urgency]),
    csvLine(["justificacionUrgencia", order.urgentJustification ?? ""]),
    csvLine(["estadoActual", getOrderStatusLabel(order.status)]),
    csvLine(["autorizo", order.authorizedByName ?? ""]),
    csvLine(["areaAutorizo", order.authorizedByArea ?? ""]),
    csvLine(["procesoPor", order.processByName ?? ""]),
    csvLine(["areaProceso", order.processByArea ?? ""]),
    "",
    csvLine([
      "linea",
      "noParte",
      "descripcion",
      "piezas",
      "cantidad",
      "unidad",
      "cliente",
      "proveedor",
      "monto",
      "ocInterna",
      "fechaEstimada",
      "fechaEtaEntrega",
      "cantidadRecibida",
      "comentarioRecepcion",
      "marcadoNoComprable",
      "motivoNoComprable",
    ]),
    ...order.items.map((item) =>
      csvLine([
        item.line,
        item.partNumber,
        item.description,
        item.pieces,
        formatNumber(item.quantity),
        item.unit,
        item.customer ?? "",
        item.supplier ?? "",
        formatNumber(item.budget),
        item.internalOrder ?? "",
        formatDateOnly(item.estimatedDate),
        formatDateOnly(item.deliveryEtaDate),
        formatNumber(item.receivedQuantity),
        item.receivedComment ?? "",
        item.isNotPurchased ? "si" : "no",
        item.notPurchasedReason ?? "",
      ]),
    ),
  ];

  return lines.join("\n");
}

export function buildMonitoringCsv(rows: MonitoringRow[]) {
  const lines = [
    csvLine([
      "folio",
      "urgencia",
      "estadoActual",
      "solicitante",
      "area",
      "status",
      "tiempo",
      "actor",
      "fechaHora",
    ]),
    ...rows.map((row) =>
      csvLine([
        row.order.id,
        row.order.urgency,
        row.order.status,
        row.order.requesterName,
        row.order.areaName,
        row.status,
        row.elapsedMs,
        row.actor,
        formatDateTime(row.enteredAt),
      ]),
    ),
  ];

  return lines.join("\n");
}
