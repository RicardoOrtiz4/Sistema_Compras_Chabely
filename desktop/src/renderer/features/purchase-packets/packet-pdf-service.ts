import * as fontkit from "fontkit";
import { PDFDocument, rgb, type PDFFont, type PDFImage, type PDFPage } from "pdf-lib";
import { brandingFor, type CompanyId } from "@/lib/branding";

export type PacketPdfItem = {
  orderId: string;
  lineNumber: number;
  description: string;
  quantity: number;
  unit: string;
  internalOrder?: string;
  amount: number;
};

export type BuildPacketPdfInput = {
  company: CompanyId;
  supplier: string;
  orderIds: string[];
  items: PacketPdfItem[];
  totalAmount: number;
  issuedAt: number;
  folio?: string;
};

const pageSize = { width: 841.88976, height: 595.27559 };
const margin = 20;
const contentWidth = pageSize.width - margin * 2;
const borderColor = rgb(0.35, 0.35, 0.35);
const softFill = rgb(0.96, 0.97, 0.985);
const fontPath = "/fonts/arial.ttf";
const boldFontPath = "/fonts/arialbd.ttf";
const firstPageRows = 10;
const nextPageRows = 16;

async function fetchBytes(path: string) {
  const response = await fetch(path);
  if (!response.ok) throw new Error(`No se pudo cargar ${path}.`);
  return new Uint8Array(await response.arrayBuffer());
}

function hexColor(hex: string) {
  const normalized = hex.replace("#", "");
  const parsed = Number.parseInt(normalized, 16);
  return rgb(((parsed >> 16) & 255) / 255, ((parsed >> 8) & 255) / 255, (parsed & 255) / 255);
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
  align: "left" | "center" | "right",
  color = rgb(0, 0, 0),
) {
  const measured = font.widthOfTextAtSize(text, size);
  const nextX =
    align === "right"
      ? x + Math.max(0, width - measured - 4)
      : align === "center"
        ? x + Math.max(0, (width - measured) / 2)
        : x + 4;
  drawText(page, text, nextX, y, font, size, color);
}

function formatDateTime(value: number) {
  return new Intl.DateTimeFormat("es-MX", { dateStyle: "short", timeStyle: "short" }).format(
    new Date(value),
  );
}

function amountLabel(value: number) {
  return new Intl.NumberFormat("es-MX", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  }).format(value);
}

function titleColorFor(hex: string) {
  const normalized = hex.replace("#", "");
  const parsed = Number.parseInt(normalized, 16);
  const red = (parsed >> 16) & 255;
  const green = (parsed >> 8) & 255;
  const blue = parsed & 255;
  const luminance = (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255;
  return luminance < 0.45 ? rgb(1, 1, 1) : rgb(0, 0, 0);
}

function splitItems(items: PacketPdfItem[]) {
  if (items.length <= firstPageRows) return [items];
  const chunks: PacketPdfItem[][] = [items.slice(0, firstPageRows)];
  let index = firstPageRows;
  while (index < items.length) {
    chunks.push(items.slice(index, index + nextPageRows));
    index += nextPageRows;
  }
  return chunks;
}

function drawHeader(
  page: PDFPage,
  logo: PDFImage,
  fonts: { regular: PDFFont; bold: PDFFont },
  input: BuildPacketPdfInput,
  titleBarColor: ReturnType<typeof rgb>,
  titleTextColor: ReturnType<typeof rgb>,
) {
  const y = pageSize.height - margin - 58;
  page.drawRectangle({
    x: margin,
    y,
    width: contentWidth,
    height: 58,
    borderColor,
    borderWidth: 0.8,
  });

  page.drawImage(logo, {
    x: margin + 8,
    y: y + 7,
    width: 88,
    height: 44,
  });

  page.drawRectangle({
    x: margin + 110,
    y,
    width: contentWidth - 110 - 118,
    height: 58,
    borderColor,
    borderWidth: 0.8,
  });
  page.drawRectangle({
    x: margin + 110,
    y: y + 36,
    width: contentWidth - 110 - 118,
    height: 22,
    color: titleBarColor,
  });
  drawAlignedText(
    page,
    "COTIZACION GENERAL POR PROVEEDOR",
    margin + 110,
    y + 43,
    contentWidth - 110 - 118,
    fonts.bold,
    12,
    "center",
    titleTextColor,
  );
  drawAlignedText(page, brandingFor(input.company).pdfHeaderLine1, margin + 110, y + 22, contentWidth - 110 - 118, fonts.bold, 8, "center");
  drawAlignedText(page, brandingFor(input.company).pdfHeaderLine2, margin + 110, y + 10, contentWidth - 110 - 118, fonts.regular, 8, "center");

  page.drawRectangle({
    x: margin + contentWidth - 118,
    y,
    width: 118,
    height: 58,
    borderColor,
    borderWidth: 0.8,
  });
  drawAlignedText(page, "FOLIO", margin + contentWidth - 118, y + 34, 118, fonts.bold, 8, "center");
  drawAlignedText(
    page,
    input.folio?.trim() || "SE ASIGNARA AL ENVIAR",
    margin + contentWidth - 118,
    y + 16,
    118,
    fonts.regular,
    8,
    "center",
  );
}

function drawSectionTitle(
  page: PDFPage,
  title: string,
  y: number,
  font: PDFFont,
  background: ReturnType<typeof rgb>,
  foreground: ReturnType<typeof rgb>,
) {
  page.drawRectangle({
    x: margin,
    y,
    width: contentWidth,
    height: 18,
    color: background,
  });
  drawText(page, title, margin + 10, y + 6, font, 10, foreground);
}

function drawInfoRow(
  page: PDFPage,
  label: string,
  value: string,
  x: number,
  y: number,
  width: number,
  fonts: { regular: PDFFont; bold: PDFFont },
  showRightBorder = true,
) {
  if (showRightBorder) {
    page.drawLine({
      start: { x: x + width, y },
      end: { x: x + width, y: y + 42 },
      thickness: 0.8,
      color: borderColor,
    });
  }
  drawText(page, label, x + 10, y + 27, fonts.bold, 8);
  drawText(page, value, x + 10, y + 11, fonts.regular, 9);
}

function drawTable(
  page: PDFPage,
  items: PacketPdfItem[],
  fonts: { regular: PDFFont; bold: PDFFont },
  titleBarColor: ReturnType<typeof rgb>,
  titleTextColor: ReturnType<typeof rgb>,
  top: number,
) {
  const rowHeight = 22;
  const colWidths = [88, 300, 70, 64, 82, 97];
  const headers = ["Orden / Item", "Descripcion", "Cantidad", "Unidad", "OC interna", "Monto"];

  page.drawRectangle({
    x: margin,
    y: top + items.length * rowHeight,
    width: contentWidth,
    height: rowHeight,
    color: titleBarColor,
  });

  let cursorX = margin;
  headers.forEach((header, index) => {
    const width = colWidths[index];
    page.drawRectangle({
      x: cursorX,
      y: top + items.length * rowHeight,
      width,
      height: rowHeight,
      borderColor,
      borderWidth: 0.8,
    });
    drawAlignedText(page, header, cursorX, top + items.length * rowHeight + 7, width, fonts.bold, 8, "center", titleTextColor);
    cursorX += width;
  });

  items.forEach((item, index) => {
    const rowY = top + (items.length - index - 1) * rowHeight;
    const rowFill = index % 2 === 0 ? rgb(1, 1, 1) : softFill;
    page.drawRectangle({
      x: margin,
      y: rowY,
      width: contentWidth,
      height: rowHeight,
      color: rowFill,
      borderColor,
      borderWidth: 0.8,
    });

    let x = margin;
    const values = [
      `${item.orderId} / #${item.lineNumber}`,
      item.description,
      String(item.quantity),
      item.unit,
      item.internalOrder?.trim() || "-",
      `$${amountLabel(item.amount)}`,
    ];

    values.forEach((value, valueIndex) => {
      const width = colWidths[valueIndex];
      page.drawRectangle({ x, y: rowY, width, height: rowHeight, borderColor, borderWidth: 0.8 });
      drawAlignedText(
        page,
        value.length > 54 && valueIndex === 1 ? `${value.slice(0, 51)}...` : value,
        x,
        rowY + 7,
        width,
        fonts.regular,
        8,
        valueIndex === 5 ? "right" : valueIndex >= 2 ? "center" : "left",
      );
      x += width;
    });
  });
}

export async function buildPacketPdfBytes(input: BuildPacketPdfInput) {
  const branding = brandingFor(input.company);
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const regular = await pdf.embedFont(await fetchBytes(fontPath));
  const bold = await pdf.embedFont(await fetchBytes(boldFontPath));
  const logo = await pdf.embedPng(await fetchBytes(branding.logoPath));
  const titleBarColor = hexColor(branding.pdfTitleBarColor);
  const titleTextColor = titleColorFor(branding.pdfTitleBarColor);
  const accentColor = hexColor(branding.pdfAccentColor);
  const itemChunks = splitItems(input.items);

  itemChunks.forEach((chunk, index) => {
    const page = pdf.addPage([pageSize.width, pageSize.height]);

    if (index === 0) {
      drawHeader(page, logo, { regular, bold }, input, titleBarColor, titleTextColor);

      page.drawRectangle({
        x: margin,
        y: 485,
        width: contentWidth,
        height: 28,
        borderColor,
        borderWidth: 0.8,
        color: softFill,
      });
      drawText(page, "Fecha y hora de emision", margin + 10, 495, bold, 9);
      drawAlignedText(
        page,
        formatDateTime(input.issuedAt),
        margin + 200,
        495,
        contentWidth - 210,
        regular,
        9,
        "right",
      );

      page.drawRectangle({
        x: margin,
        y: 414,
        width: contentWidth,
        height: 56,
        color: accentColor,
        borderColor,
        borderWidth: 1,
      });
      drawText(page, "TOTAL A PAGAR", margin + 18, 448, bold, 16, rgb(1, 1, 1));
      drawText(page, `$${amountLabel(input.totalAmount)}`, margin + 18, 424, bold, 28, rgb(1, 1, 1));

      drawSectionTitle(page, "DATOS GENERALES", 386, bold, titleBarColor, titleTextColor);

      page.drawRectangle({
        x: margin,
        y: 344,
        width: contentWidth,
        height: 42,
        borderColor,
        borderWidth: 0.8,
      });
      drawInfoRow(page, "PROVEEDOR", input.supplier, margin, 344, 280, { regular, bold });
      drawInfoRow(
        page,
        "ORDENES INVOLUCRADAS",
        input.orderIds.join(", "),
        margin + 280,
        344,
        contentWidth - 280 - 110,
        { regular, bold },
      );
      drawInfoRow(page, "ITEMS", `${input.items.length}`, margin + contentWidth - 110, 344, 110, { regular, bold }, false);

      drawSectionTitle(page, "DETALLE DE ARTICULOS", 318, bold, titleBarColor, titleTextColor);
      drawTable(page, chunk, { regular, bold }, titleBarColor, titleTextColor, 98);
      return;
    }

    drawHeader(page, logo, { regular, bold }, input, titleBarColor, titleTextColor);
    drawSectionTitle(page, "DETALLE DE ARTICULOS", pageSize.height - margin - 88, bold, titleBarColor, titleTextColor);
    drawTable(page, chunk, { regular, bold }, titleBarColor, titleTextColor, pageSize.height - margin - 110 - chunk.length * 22);
  });

  return pdf.save();
}
