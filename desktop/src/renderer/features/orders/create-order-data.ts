export type OrderUrgency = "normal" | "urgente";

export type OrderDraftItem = {
  line: number;
  pieces: number;
  partNumber: string;
  description: string;
  quantity: number;
  unit: string;
  customer?: string;
  supplier?: string;
};

const csvHeaderAliases: Record<string, keyof ParsedCsvItem> = {
  folio: "line",
  linea: "line",
  line: "line",
  renglon: "line",
  item: "line",
  piezas: "quantity",
  pieza: "quantity",
  noparte: "partNumber",
  noParte: "partNumber",
  nparte: "partNumber",
  numeroparte: "partNumber",
  partnumber: "partNumber",
  parte: "partNumber",
  sku: "partNumber",
  descripcion: "description",
  description: "description",
  concepto: "description",
  articulo: "description",
  material: "description",
  cantidad: "quantity",
  quantity: "quantity",
  qty: "quantity",
  unidad: "unit",
  unit: "unit",
  uom: "unit",
  cliente: "customer",
  customer: "customer",
  proyecto: "customer",
  obra: "customer",
  proveedor: "supplier",
  supplier: "supplier",
};

type ParsedCsvItem = {
  line?: string;
  partNumber?: string;
  description?: string;
  quantity?: string;
  unit?: string;
  customer?: string;
  supplier?: string;
};

export type PartnerEntry = {
  id: string;
  name: string;
};

export const orderUnitOptions = [
  "PZA",
  "KG",
  "LT",
  "GAL",
  "M",
  "CM",
  "MM",
  "PULG",
  "PAQ",
  "CAJA",
  "JGO",
] as const;

export function emptyOrderItem(line: number): OrderDraftItem {
  return {
    line,
    pieces: 1,
    partNumber: "",
    description: "",
    quantity: 1,
    unit: "PZA",
  };
}

export function mapPartners(value: unknown): PartnerEntry[] {
  if (!value || typeof value !== "object") {
    return [];
  }

  const items: PartnerEntry[] = [];
  for (const [key, raw] of Object.entries(value as Record<string, unknown>)) {
    if (!raw || typeof raw !== "object") continue;
    const data = raw as Record<string, unknown>;

    if (typeof data.name === "string" && data.name.trim()) {
      items.push({ id: key, name: data.name.trim() });
      continue;
    }

    for (const [legacyKey, legacyRaw] of Object.entries(data)) {
      if (!legacyRaw || typeof legacyRaw !== "object") continue;
      const legacy = legacyRaw as Record<string, unknown>;
      if (typeof legacy.name !== "string" || !legacy.name.trim()) continue;
      items.push({
        id: `${key}/${legacyKey}`,
        name: legacy.name.trim(),
      });
    }
  }

  return items.sort((a, b) => a.name.localeCompare(b.name, "es"));
}

export function parseOrderCsv(content: string): OrderDraftItem[] {
  const rows = parseCsvRows(content.replace(/^\uFEFF/, ""));
  if (!rows.length) {
    throw new Error("El CSV esta vacio.");
  }

  const rawHeader = rows[0].map((cell) => cell.trim());
  const headerMap = new Map<keyof ParsedCsvItem, number>();
  for (let index = 0; index < rawHeader.length; index += 1) {
    const normalized = normalizeHeader(rawHeader[index]);
    const canonical = csvHeaderAliases[normalized];
    if (canonical) {
      headerMap.set(canonical, index);
    }
  }

  if (!headerMap.has("description")) {
    throw new Error('Falta la columna "descripcion" en el CSV.');
  }
  if (!headerMap.has("quantity")) {
    throw new Error('Falta la columna "cantidad" en el CSV.');
  }

  const items: OrderDraftItem[] = [];
  for (let rowIndex = 1; rowIndex < rows.length; rowIndex += 1) {
    const row = rows[rowIndex];
    if (row.every((cell) => !cell.trim())) continue;

    const description = cleanCell(readCsvCell(row, headerMap, "description"));
    if (!description) continue;

    const pieces = parseQuantity(readCsvCell(row, headerMap, "quantity")) ?? 1;
    const unit = cleanCell(readCsvCell(row, headerMap, "unit")).toUpperCase() || "PZA";

    items.push({
      line: items.length + 1,
      pieces,
      quantity: pieces,
      description,
      unit,
      partNumber: cleanCell(readCsvCell(row, headerMap, "partNumber")),
      customer: cleanCell(readCsvCell(row, headerMap, "customer")) || undefined,
      supplier: cleanCell(readCsvCell(row, headerMap, "supplier")) || undefined,
    });
  }

  if (!items.length) {
    throw new Error("El CSV no contiene articulos validos.");
  }

  return items;
}

function normalizeHeader(value: string) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z0-9]/g, "")
    .toLowerCase();
}

function cleanCell(value: string) {
  return value.trim().replace(/^"(.*)"$/, "$1").trim();
}

function parseQuantity(value: string) {
  const normalized = value.trim().replace(",", ".");
  if (!normalized) return undefined;
  const parsed = Number(normalized);
  if (!Number.isFinite(parsed) || parsed <= 0) return undefined;
  return Math.max(1, Math.round(parsed));
}

function readCsvCell(
  row: string[],
  headerMap: Map<keyof ParsedCsvItem, number>,
  key: keyof ParsedCsvItem,
) {
  const index = headerMap.get(key);
  if (index == null || index >= row.length) return "";
  return row[index] ?? "";
}

function parseCsvRows(content: string) {
  const delimiter = guessDelimiter(content);
  const rows: string[][] = [];
  let currentCell = "";
  let currentRow: string[] = [];
  let inQuotes = false;

  for (let index = 0; index < content.length; index += 1) {
    const char = content[index];
    const nextChar = content[index + 1];

    if (char === '"') {
      if (inQuotes && nextChar === '"') {
        currentCell += '"';
        index += 1;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }

    if (!inQuotes && char === delimiter) {
      currentRow.push(currentCell);
      currentCell = "";
      continue;
    }

    if (!inQuotes && (char === "\n" || char === "\r")) {
      if (char === "\r" && nextChar === "\n") {
        index += 1;
      }
      currentRow.push(currentCell);
      if (currentRow.some((cell) => cell.trim())) {
        rows.push(currentRow);
      }
      currentCell = "";
      currentRow = [];
      continue;
    }

    currentCell += char;
  }

  if (currentCell.length > 0 || currentRow.length > 0) {
    currentRow.push(currentCell);
    if (currentRow.some((cell) => cell.trim())) {
      rows.push(currentRow);
    }
  }

  return rows;
}

function guessDelimiter(content: string) {
  const firstLine = content
    .split(/\r?\n/)
    .find((line) => line.trim().length > 0) ?? content;
  const commaCount = (firstLine.match(/,/g) ?? []).length;
  const semicolonCount = (firstLine.match(/;/g) ?? []).length;
  const tabCount = (firstLine.match(/\t/g) ?? []).length;
  if (tabCount > semicolonCount && tabCount > commaCount) {
    return "\t";
  }
  return semicolonCount > commaCount ? ";" : ",";
}
