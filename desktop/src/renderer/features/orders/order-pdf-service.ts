import * as fontkit from "fontkit";
import { PDFDocument, rgb, type PDFFont, type PDFImage, type PDFPage } from "pdf-lib";
import { getDownloadURL, ref as storageRef, uploadBytes } from "firebase/storage";
import { storage } from "@/lib/firebase/client";
import { brandingFor, type CompanyBranding, type CompanyId } from "@/lib/branding";
import type { PurchaseOrderItem, PurchaseOrderRecord } from "@/features/orders/orders-data";

export type BuildOrderPdfInput = {
  order: Pick<
    PurchaseOrderRecord,
    | "id"
    | "requesterName"
    | "areaName"
    | "urgency"
    | "status"
    | "items"
    | "clientNote"
    | "urgentJustification"
    | "supplier"
    | "authorizedByName"
    | "authorizedByArea"
    | "authorizedAt"
    | "processByName"
    | "processByArea"
    | "processAt"
    | "createdAt"
    | "updatedAt"
    | "requestedDeliveryDate"
    | "etaDate"
    | "materialArrivedAt"
    | "requesterReceivedAt"
    | "paymentReceiptUrls"
    | "facturaPdfUrls"
  > & {
    internalOrder?: string;
    budget?: number;
    supplierBudgets?: Record<string, number>;
    previewMode?: boolean;
    suppressCreatedTime?: boolean;
  };
  company: CompanyId;
  fileLabel: string;
};

type PdfColumn = {
  label: string;
  width: number;
  align?: "left" | "center" | "right";
  value: (item: PurchaseOrderItem, order: BuildOrderPdfInput["order"]) => string;
};

const pageSize = { width: 841.88976, height: 595.27559 };
const pageMargin = 20;
const contentWidth = pageSize.width - pageMargin * 2;
const rowHeight = 16.9375;
const itemRowsPerPage = 9;
const lineColor = rgb(0.38, 0.38, 0.38);
const fillGray = rgb(0.68, 0.68, 0.68);
const textGray = rgb(0.42, 0.42, 0.42);
const compactSectionGap = 8;
const pdfBaseFontPath = "/fonts/arial.ttf";
const pdfBoldFontPath = "/fonts/arialbd.ttf";

function hexColor(hex: string) {
  const normalized = hex.replace("#", "");
  const parsed = Number.parseInt(normalized, 16);
  return rgb(((parsed >> 16) & 255) / 255, ((parsed >> 8) & 255) / 255, (parsed & 255) / 255);
}

function fitText(text: string, maxLength: number) {
  const normalized = text.replace(/\s+/g, " ").trim();
  if (normalized.length <= maxLength) return normalized;
  return `${normalized.slice(0, Math.max(0, maxLength - 3))}...`;
}

function wrapText(text: string, maxChars: number, maxLines = 2) {
  const normalized = text.replace(/\s+/g, " ").trim();
  if (!normalized) return [""];

  const words = normalized.split(" ");
  const lines: string[] = [];
  let current = "";

  for (const word of words) {
    const next = current ? `${current} ${word}` : word;
    if (next.length <= maxChars) {
      current = next;
      continue;
    }

    if (current) {
      lines.push(current);
      current = word;
    } else {
      lines.push(word.slice(0, maxChars));
      current = word.slice(maxChars);
    }

    if (lines.length >= maxLines) break;
  }

  if (lines.length < maxLines && current) {
    lines.push(current);
  }

  if (lines.length === maxLines && normalized.length > lines.join(" ").length) {
    lines[maxLines - 1] = fitText(lines[maxLines - 1], maxChars);
  }

  return lines.slice(0, maxLines);
}

function drawText(
  page: PDFPage,
  text: string,
  x: number,
  y: number,
  font: PDFFont,
  size: number,
  color = rgb(0, 0, 0),
) {
  page.drawText(text, { x, y, font, size, color });
}

function drawAlignedText(
  page: PDFPage,
  text: string,
  x: number,
  y: number,
  width: number,
  font: PDFFont,
  size: number,
  align: "left" | "center" | "right" = "left",
  color = rgb(0, 0, 0),
) {
  const measured = font.widthOfTextAtSize(text, size);
  const drawX =
    align === "right"
      ? x + Math.max(0, width - measured - 4)
      : align === "center"
        ? x + Math.max(0, (width - measured) / 2)
        : x + 4;
  drawText(page, text, drawX, y, font, size, color);
}

function drawWrappedText(
  page: PDFPage,
  text: string,
  x: number,
  y: number,
  width: number,
  font: PDFFont,
  size: number,
  maxLines = 2,
  color = rgb(0, 0, 0),
) {
  const maxChars = Math.max(10, Math.floor(width / (size * 0.62)));
  const lines = wrapText(text, maxChars, maxLines);
  lines.forEach((line, index) => {
    drawText(page, line, x, y - index * (size + 2), font, size, color);
  });
}

function formatDate(value?: number, includeTime = false) {
  if (!value) return "";
  return new Intl.DateTimeFormat("es-MX", {
    dateStyle: "short",
    ...(includeTime ? { timeStyle: "short" } : {}),
  }).format(new Date(value));
}

function currencyLabel(value?: number) {
  if (value == null) return "";
  return new Intl.NumberFormat("es-MX", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  }).format(value);
}

function normalizeItems(items: PurchaseOrderItem[]) {
  return [...items].sort((left, right) => {
    const supplierCompare = normalizeGroupValue(left.supplier).localeCompare(
      normalizeGroupValue(right.supplier),
      "es",
    );
    if (supplierCompare !== 0) return supplierCompare;

    const customerCompare = normalizeGroupValue(left.customer).localeCompare(
      normalizeGroupValue(right.customer),
      "es",
    );
    if (customerCompare !== 0) return customerCompare;

    return left.line - right.line;
  });
}

function normalizeGroupValue(value?: string) {
  return (value ?? "").trim().toLowerCase().replace(/\s+/g, " ");
}

async function fetchLogoBytes(branding: CompanyBranding) {
  const response = await fetch(branding.logoPath);
  if (!response.ok) {
    throw new Error(`No se pudo cargar el logo ${branding.logoPath}.`);
  }
  return new Uint8Array(await response.arrayBuffer());
}

async function fetchFontBytes(path: string) {
  const response = await fetch(path);
  if (!response.ok) {
    throw new Error(`No se pudo cargar la fuente ${path}.`);
  }
  return new Uint8Array(await response.arrayBuffer());
}

function acerproRefLine(branding: CompanyBranding) {
  const ref = branding.pdfRefCode.trim();
  const rev = branding.pdfRevision?.trim() ?? "";
  return rev ? `${ref} ${rev}.` : ref;
}

function drawHeader(
  page: PDFPage,
  branding: CompanyBranding,
  logo: PDFImage,
  fonts: { regular: PDFFont; bold: PDFFont },
  pageNumber: number,
  pageCount: number,
) {
  const titleBarColor = hexColor(branding.pdfTitleBarColor);
  const accentColor = hexColor(branding.pdfAccentColor);
  const y = pageSize.height - pageMargin - 66;
  const isAcerpro = branding.id === "acerpro";
  const logoX = pageMargin + 6;
  const logoY = y + (isAcerpro ? 14 : 8);
  const logoWidth = isAcerpro ? 58 : 64;
  const logoHeight = isAcerpro ? 44 : 50;
  const rightX = pageMargin + contentWidth - 116;
  const headerCenterX = logoX + logoWidth + 28;
  const headerCenterWidth = rightX - 8 - headerCenterX;

  page.drawRectangle({
    x: pageMargin,
    y,
    width: contentWidth,
    height: 66,
    borderColor: lineColor,
    borderWidth: 0.8,
  });

  page.drawImage(logo, {
    x: logoX,
    y: logoY,
    width: logoWidth,
    height: logoHeight,
  });

  drawAlignedText(page, branding.pdfHeaderLine1, headerCenterX, y + 46, headerCenterWidth, fonts.bold, 8, "center");
  drawAlignedText(page, branding.pdfHeaderLine2, headerCenterX, y + 34, headerCenterWidth, fonts.bold, 9, "center");

  page.drawRectangle({
    x: headerCenterX,
    y: y + 10,
    width: headerCenterWidth,
    height: 19.17188,
    color: titleBarColor,
  });
  drawAlignedText(page, branding.pdfTitle, headerCenterX, y + 16, headerCenterWidth, fonts.bold, 10, "center", rgb(1, 1, 1));
  page.drawRectangle({
    x: headerCenterX,
    y: y + 8,
    width: headerCenterWidth,
    height: 2,
    color: accentColor,
  });

  drawAlignedText(page, `HOJA ${pageNumber} DE ${pageCount}`, rightX, y + 42, 112, fonts.regular, 8, "right");
  const refLabel =
    branding.id === "acerpro" || branding.id === "chabely"
      ? acerproRefLine(branding)
      : `REF: ${branding.pdfRefCode}`;
  drawAlignedText(page, refLabel, rightX, y + 28, 112, fonts.regular, 8, "right");
  if (branding.id !== "acerpro" && branding.id !== "chabely" && branding.pdfRevision?.trim()) {
    drawAlignedText(page, `REV: ${branding.pdfRevision}`, rightX, y + 16, 112, fonts.regular, 8, "right");
  }
}

function drawLabeledBox(
  page: PDFPage,
  label: string,
  value: string,
  x: number,
  y: number,
  width: number,
  height: number,
  fonts: { regular: PDFFont; bold: PDFFont },
) {
  page.drawRectangle({
    x,
    y,
    width,
    height,
    borderColor: lineColor,
    borderWidth: 0.8,
  });
  drawText(page, `${label}:`, x + 6, y + height - 13, fonts.bold, 8);
  const valueX = label === "PROCESO" ? x + 52 : x + 122;
  const valueWidth = label === "PROCESO" ? width - 58 : width - 128;
  drawWrappedText(page, value, valueX, y + height - 13, valueWidth, fonts.regular, 8, 2);
}

function drawUrgencyCheckbox(
  page: PDFPage,
  label: string,
  checked: boolean,
  x: number,
  y: number,
  fonts: { regular: PDFFont; bold: PDFFont },
) {
  page.drawRectangle({
    x,
    y,
    width: 12,
    height: 12,
    borderColor: lineColor,
    borderWidth: 0.8,
  });
  if (checked) {
    drawText(page, "X", x + 3.2, y + 2.4, fonts.bold, 8);
  }
  drawText(page, label, x + 16, y + 3, fonts.regular, 8);
}

function drawMetaSection(
  page: PDFPage,
  order: BuildOrderPdfInput["order"],
  fonts: { regular: PDFFont; bold: PDFFont },
) {
  const y = pageSize.height - pageMargin - 66 - compactSectionGap - 94.8125;
  const rightX = pageMargin + 585.88976;

  page.drawRectangle({
    x: pageMargin,
    y,
    width: contentWidth,
    height: 94.8125,
    borderColor: lineColor,
    borderWidth: 0.8,
  });

  drawLabeledBox(page, "NOMBRE DEL SOLICITANTE", order.requesterName, pageMargin + 8, y + 57.875, 573.88976, 20.9375, fonts);
  drawLabeledBox(page, "PROCESO", order.areaName, pageMargin + 8, y + 30.9375, 573.88976, 20.9375, fonts);

  drawText(page, "URGENCIA:", pageMargin + 8, y + 20.5, fonts.bold, 8);
  drawUrgencyCheckbox(page, "NORMAL", order.urgency !== "urgente", pageMargin + 8, y + 4, fonts);
  drawUrgencyCheckbox(page, "URGENTE", order.urgency === "urgente", pageMargin + 72.22656, y + 4, fonts);
  if (order.urgency === "urgente" && order.urgentJustification?.trim()) {
    drawText(page, "Justificacion:", pageMargin + 141.33984, y + 7, fonts.regular, 8);
    drawWrappedText(page, order.urgentJustification.trim(), pageMargin + 191.33984, y + 7, 364, fonts.regular, 8, 2);
  }

  page.drawRectangle({
    x: rightX,
    y: y + 6,
    width: 200,
    height: 72.8125,
    borderColor: lineColor,
    borderWidth: 0.8,
  });

  page.drawRectangle({
    x: rightX + 6,
    y: y + 57.875,
    width: 188,
    height: 16.9375,
    borderColor: lineColor,
    borderWidth: 0.8,
  });
  drawText(page, "No.", rightX + 12, y + 63, fonts.bold, 8);
  drawText(page, order.id.trim() || "", rightX + 44, y + 63, fonts.regular, 8);

  page.drawRectangle({
    x: rightX + 6,
    y: y + 34.90625,
    width: 188,
    height: 16.9375,
    borderColor: lineColor,
    borderWidth: 0.8,
  });
  const createdLabel = order.suppressCreatedTime
    ? formatDate(order.createdAt, false)
    : formatDate(order.createdAt, true);
  drawText(page, "FECHA DE CREACION:", rightX + 12, y + 40, fonts.bold, 7.6);
  drawText(page, createdLabel, rightX + 98, y + 40, fonts.regular, 7.6);

  page.drawRectangle({
    x: rightX + 6,
    y: y + 11.9375,
    width: 188,
    height: 16.9375,
    borderColor: lineColor,
    borderWidth: 0.8,
  });
  drawText(page, "FECHA MAXIMA SOLICITADA:", rightX + 12, y + 17.5, fonts.bold, 7.2);
  drawText(page, formatDate(order.requestedDeliveryDate, false), rightX + 118, y + 17.5, fonts.regular, 7.6);
}

function shouldShowCostColumn(order: BuildOrderPdfInput["order"]) {
  if (order.items.some((item) => item.budget != null)) return true;
  if (order.supplierBudgets && Object.keys(order.supplierBudgets).length > 0) return true;
  return order.budget != null;
}

function totalCostForPdf(order: BuildOrderPdfInput["order"]) {
  const itemTotal = order.items.reduce((sum, item) => sum + (item.budget ?? 0), 0);
  if (itemTotal > 0) return itemTotal;
  if (order.supplierBudgets) {
    const supplierTotal = Object.values(order.supplierBudgets).reduce((sum, value) => sum + value, 0);
    if (supplierTotal > 0) return supplierTotal;
  }
  return order.budget ?? 0;
}

function resolvePdfColumns(order: BuildOrderPdfInput["order"], showCost: boolean): PdfColumn[] {
  const hasPartNumber = order.items.some((item) => item.partNumber?.trim());
  const hasCustomer = order.items.some((item) => item.customer?.trim());
  const hasInternalOrder =
    Boolean(order.internalOrder?.trim()) || order.items.some((item) => item.internalOrder?.trim());
  const hasSupplier =
    Boolean(order.supplier?.trim()) || order.items.some((item) => item.supplier?.trim());
  const hasEta = Boolean(order.etaDate);

  const columns: PdfColumn[] = [
    { label: "ITEM", width: 0.4, align: "center", value: (item) => String(item.line) },
  ];

  if (hasPartNumber) {
    columns.push({
      label: "NO. DE PARTE",
      width: 1.1,
      value: (item) => item.partNumber?.trim() || "",
    });
  }

  columns.push({
    label: "DESCRIPCION",
    width: 2.4,
    value: (item) => item.description.trim(),
  });
  columns.push({
    label: "CANTIDAD",
    width: 0.7,
    align: "center",
    value: (item) => String(item.pieces),
  });
  columns.push({
    label: "UNIDAD DE MEDIDA",
    width: 0.9,
    align: "center",
    value: (item) => item.unit.trim(),
  });

  if (hasInternalOrder) {
    columns.push({
      label: "OC INTERNA",
      width: 1.0,
      value: (item, currentOrder) => (item.internalOrder ?? currentOrder.internalOrder ?? "").trim(),
    });
  }

  if (hasSupplier) {
    columns.push({
      label: "PROVEEDOR",
      width: 1.0,
      value: (item, currentOrder) => (item.supplier ?? currentOrder.supplier ?? "").trim(),
    });
  }

  if (hasCustomer) {
    columns.push({
      label: "CLIENTE",
      width: 1.0,
      value: (item) => item.customer?.trim() || "",
    });
  }

  if (hasEta) {
    columns.push({
      label: "FECHA ESTIMADA DE ENTREGA",
      width: 1.1,
      align: "center",
      value: (_, currentOrder) => formatDate(currentOrder.etaDate, false),
    });
  }

  if (showCost) {
    columns.push({
      label: "COSTO",
      width: 0.9,
      align: "right",
      value: (item) => (item.budget == null ? "" : `$${currencyLabel(item.budget)}`),
    });
  }

  return columns;
}

function drawSectionTitle(
  page: PDFPage,
  title: string,
  y: number,
  fonts: { bold: PDFFont },
  options?: { compact?: boolean; textColor?: ReturnType<typeof rgb> },
) {
  const compact = options?.compact ?? false;
  const height = compact ? 13.5 : 13.5;
  page.drawRectangle({
    x: pageMargin,
    y,
    width: contentWidth,
    height,
    color: fillGray,
  });
  drawText(
    page,
    title,
    pageMargin + 8,
    y + (compact ? 3.5 : 4.8),
    fonts.bold,
    compact ? 7.5 : 8,
    options?.textColor ?? rgb(0, 0, 0),
  );
}

function drawItemsTable(
  page: PDFPage,
  order: BuildOrderPdfInput["order"],
  pageItems: PurchaseOrderItem[],
  fonts: { regular: PDFFont; bold: PDFFont },
  tableTop: number,
  isLastPage: boolean,
) {
  const showCost = shouldShowCostColumn(order);
  const columns = resolvePdfColumns(order, showCost);
  const totalFlex = columns.reduce((sum, column) => sum + column.width, 0);
  const scaledColumns = columns.map((column) => ({
    ...column,
    widthPoints: (column.width / totalFlex) * contentWidth,
  }));

  const headerHeight = 13.5;
  const headerTop = tableTop;
  const tableHeight = headerHeight + pageItems.length * rowHeight;
  page.drawRectangle({
    x: pageMargin,
    y: headerTop,
    width: contentWidth,
    height: tableHeight,
    borderColor: lineColor,
    borderWidth: 0.8,
  });

  let cursorX = pageMargin;
  page.drawRectangle({
    x: pageMargin,
    y: headerTop + tableHeight - headerHeight,
    width: contentWidth,
    height: headerHeight,
    color: fillGray,
  });
  scaledColumns.forEach((column, index) => {
    if (index > 0) {
      page.drawLine({
        start: { x: cursorX, y: headerTop },
        end: { x: cursorX, y: headerTop + tableHeight },
        thickness: 0.8,
        color: lineColor,
      });
    }
    page.drawRectangle({
      x: cursorX,
      y: headerTop + tableHeight - headerHeight,
      width: column.widthPoints,
      height: headerHeight,
      color: fillGray,
    });
    drawAlignedText(
      page,
      column.label,
      cursorX,
      headerTop + tableHeight - 9.6,
      column.widthPoints,
      fonts.bold,
      6.6,
      "center",
      rgb(0, 0, 0),
    );
    cursorX += column.widthPoints;
  });

  page.drawLine({
    start: { x: pageMargin, y: headerTop + tableHeight - headerHeight },
    end: { x: pageMargin + contentWidth, y: headerTop + tableHeight - headerHeight },
    thickness: 0.8,
    color: lineColor,
  });

  let rowTop = headerTop + tableHeight - headerHeight;
  for (const item of pageItems) {
    cursorX = pageMargin;
    scaledColumns.forEach((column) => {
      const value = column.value(item, order);
      if (column.label === "DESCRIPCION") {
        drawWrappedText(page, value, cursorX + 4, rowTop - 14, column.widthPoints - 8, fonts.regular, 7, 2);
      } else {
        drawAlignedText(
          page,
          fitText(value, 28),
          cursorX,
          rowTop - 14,
          column.widthPoints,
          fonts.regular,
          7,
          column.align ?? "left",
        );
      }
      cursorX += column.widthPoints;
    });
    rowTop -= rowHeight;
    page.drawLine({
      start: { x: pageMargin, y: rowTop },
      end: { x: pageMargin + contentWidth, y: rowTop },
      thickness: 0.8,
      color: lineColor,
    });
  }

  let bottomY = rowTop;

  if (isLastPage && showCost) {
    const lastColumn = scaledColumns[scaledColumns.length - 1];
    const totalWidth = lastColumn.widthPoints;
    const totalX = pageMargin + contentWidth - totalWidth;
    page.drawRectangle({
      x: totalX,
      y: bottomY - 20,
      width: totalWidth,
      height: 18,
      color: rgb(0.92, 0.92, 0.92),
      borderColor: lineColor,
      borderWidth: 0.8,
    });
    drawAlignedText(
      page,
      `TOTAL A PAGAR: $${currencyLabel(totalCostForPdf(order))}`,
      totalX,
      bottomY - 14,
      totalWidth,
      fonts.bold,
      7,
      "right",
    );
    bottomY -= 20;
  }

  return bottomY;
}

function drawObservations(
  page: PDFPage,
  order: BuildOrderPdfInput["order"],
  fonts: { regular: PDFFont; bold: PDFFont },
  topY: number,
) {
  const notes = order.clientNote?.trim() || "";
  if (!notes) return;

  drawSectionTitle(page, "OBSERVACIONES", topY - 15.82031, { bold: fonts.bold }, { textColor: rgb(0, 0, 0) });
  page.drawRectangle({
    x: pageMargin,
    y: topY - 56.57812,
    width: contentWidth,
    height: 40.75781,
    borderColor: lineColor,
    borderWidth: 0.8,
  });
  drawWrappedText(page, notes, pageMargin + 6, topY - 34, contentWidth - 12, fonts.regular, 8, 4);
}

function drawSignatureBox(
  page: PDFPage,
  label: string,
  name: string,
  area: string | undefined,
  x: number,
  y: number,
  width: number,
  fonts: { regular: PDFFont; bold: PDFFont },
) {
  page.drawRectangle({
    x,
    y,
    width,
    height: 31.82031,
    borderColor: lineColor,
    borderWidth: 0.8,
  });
  drawText(page, label, x + 6, y + 19.5, fonts.bold, 7);
  if (area?.trim()) {
    drawAlignedText(page, area.trim().toUpperCase(), x + 6, y + 19.5, width - 12, fonts.bold, 7, "right");
  }
  if (name.trim()) {
    drawWrappedText(page, name.trim(), x + 6, y + 8, width - 12, fonts.regular, 8, 2);
  }
}

function drawSignatures(
  page: PDFPage,
  order: BuildOrderPdfInput["order"],
  fonts: { regular: PDFFont; bold: PDFFont },
  topY: number,
) {
  drawSectionTitle(page, "FIRMAS", topY - 13.5, { bold: fonts.bold }, { compact: true, textColor: rgb(0, 0, 0) });
  const gap = 8;
  const width = (contentWidth - gap * 2) / 3;
  const y = topY - 47.64062;
  drawSignatureBox(page, "SOLICITÓ", order.requesterName, undefined, pageMargin, y, width, fonts);
  drawSignatureBox(page, "PROCESO", order.processByName?.trim() || "", order.processByArea, pageMargin + width + gap, y, width, fonts);
  drawSignatureBox(page, "AUTORIZÓ", order.authorizedByName?.trim() || "", order.authorizedByArea, pageMargin + (width + gap) * 2, y, width, fonts);
}

export async function buildOrderPdfBytes(input: BuildOrderPdfInput) {
  const branding = brandingFor(input.company ?? "chabely");
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const regular = await pdf.embedFont(await fetchFontBytes(pdfBaseFontPath));
  const bold = await pdf.embedFont(await fetchFontBytes(pdfBoldFontPath));
  const logo = await pdf.embedPng(await fetchLogoBytes(branding));

  const items = normalizeItems(input.order.items);
  const pageCount = Math.max(1, Math.ceil(Math.max(1, items.length) / itemRowsPerPage));
  const chunkedItems =
    items.length > 0
      ? Array.from({ length: pageCount }, (_, index) =>
          items.slice(index * itemRowsPerPage, (index + 1) * itemRowsPerPage),
        )
      : [[]];

  chunkedItems.forEach((pageItems, index) => {
    const page = pdf.addPage([pageSize.width, pageSize.height]);
    if (index === 0) {
      drawHeader(page, branding, logo, { regular, bold }, index + 1, pageCount);
      drawMetaSection(page, input.order, { regular, bold });
    }

    const firstPageMetaY = pageSize.height - pageMargin - 66 - compactSectionGap - 94.8125;
    const firstPageTableTop =
      firstPageMetaY -
      compactSectionGap -
      (13.5 + pageItems.length * rowHeight);

    const tableBottomY = drawItemsTable(
      page,
      input.order,
      pageItems,
      { regular, bold },
      index === 0 ? firstPageTableTop : pageSize.height - pageMargin - 29.32031,
      index === chunkedItems.length - 1,
    );

    if (index === chunkedItems.length - 1) {
      const signaturesTopY = 72.5;
      let nextTopY = signaturesTopY + 56;
      if (input.order.clientNote?.trim()) {
        drawObservations(page, input.order, { regular, bold }, nextTopY);
      }
      drawSignatures(page, input.order, { regular, bold }, signaturesTopY);
    }
  });

  return pdf.save();
}

export async function uploadOrderPdf(input: BuildOrderPdfInput) {
  const bytes = await buildOrderPdfBytes(input);
  const fileName = `${input.fileLabel}_${Date.now()}.pdf`;
  const fileRef = storageRef(storage, `purchase_orders/${input.order.id}/${fileName}`);
  await uploadBytes(fileRef, bytes, {
    contentType: "application/pdf",
    customMetadata: {
      orderId: input.order.id,
      status: input.order.status,
      company: input.company,
    },
  });
  return getDownloadURL(fileRef);
}
