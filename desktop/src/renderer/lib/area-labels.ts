export const adminAreaLabel = "Sistemas Informaticos (SIN)";
export const direccionGeneralLabel = "Direccion General (DIG)";
export const contraloriaLabel = "Contraloria";
export const comprasLabel = "Compras";
export const planeacionProduccionLabel = "Planeacion y Control de la Produccion (PPR)";
export const contabilidadLabel = "Contabilidad";
export const tesoreriaLabel = "Tesoreria";
export const nominasLabel = "Nominas";

export function normalizeAreaLabel(value?: string | null) {
  if (!value) return "";
  const trimmed = value.trim();
  if (!trimmed) return "";

  const lower = trimmed.toLowerCase();
  if (["administrador", "admin", "sistemas", "sistemas informaticos", "sistemas informaticos (sin)", "sin"].includes(lower)) {
    return adminAreaLabel;
  }
  if (["gerencia general", "gerencia", "direccion", "direccion general", "direccion general (dig)", "dig"].includes(lower)) {
    return direccionGeneralLabel;
  }
  if (["contraloria", "contralor", "ctl"].includes(lower)) {
    return contraloriaLabel;
  }
  if (["compras", "com"].includes(lower)) {
    return comprasLabel;
  }
  if (["planeacion y control de la produccion", "planeacion y control de la produccion (ppr)", "ppr"].includes(lower)) {
    return planeacionProduccionLabel;
  }
  if (lower === "contabilidad") return contabilidadLabel;
  if (lower === "tesoreria") return tesoreriaLabel;
  if (lower === "nominas") return nominasLabel;
  return trimmed;
}

export function isDireccionGeneralLabel(value?: string | null) {
  return normalizeAreaLabel(value) === direccionGeneralLabel;
}

export function isContraloriaLabel(value?: string | null) {
  return normalizeAreaLabel(value) === contraloriaLabel;
}

export function isComprasLabel(value?: string | null) {
  return normalizeAreaLabel(value) === comprasLabel;
}

export function isPlaneacionProduccionLabel(value?: string | null) {
  return normalizeAreaLabel(value) === planeacionProduccionLabel;
}
