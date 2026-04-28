import {
  adminAreaLabel,
  comprasLabel,
  contabilidadLabel,
  contraloriaLabel,
  direccionGeneralLabel,
  nominasLabel,
  normalizeAreaLabel,
  planeacionProduccionLabel,
  tesoreriaLabel,
} from "@/lib/area-labels";

export type AdminUserRecord = {
  id: string;
  name: string;
  email: string;
  role: string;
  areaId: string;
  areaName: string;
  areaDisplay: string;
  isActive: boolean;
};

export type AreaOption = {
  id: string;
  name: string;
};

export const adminAreaId = adminAreaLabel;

export const roleLabels: Record<string, string> = {
  admin: "Administrador",
  administrador: "Administrador",
  usuario: "Usuario",
};

export const requiredAreaOptions: AreaOption[] = [
  { id: direccionGeneralLabel, name: direccionGeneralLabel },
  { id: contraloriaLabel, name: contraloriaLabel },
  { id: comprasLabel, name: comprasLabel },
  { id: "Sistema de Gestión de Calidad (SGC)", name: "Sistema de Gestión de Calidad (SGC)" },
  { id: "Ventas (VEN)", name: "Ventas (VEN)" },
  { id: "Desarrollo y Nuevos Proyectos (DNP)", name: "Desarrollo y Nuevos Proyectos (DNP)" },
  { id: "Ingenieria de Manufactura (IMA)", name: "Ingenieria de Manufactura (IMA)" },
  { id: planeacionProduccionLabel, name: planeacionProduccionLabel },
  { id: "Produccion (PRO)", name: "Produccion (PRO)" },
  { id: "Control de Calidad (CCA)", name: "Control de Calidad (CCA)" },
  { id: "Almacenes (ALM)", name: "Almacenes (ALM)" },
  { id: "Mantenimiento (MAN)", name: "Mantenimiento (MAN)" },
  { id: "Recursos Humanos (RHU)", name: "Recursos Humanos (RHU)" },
  { id: "Seguridad e Higiene (EHS)", name: "Seguridad e Higiene (EHS)" },
  { id: contabilidadLabel, name: contabilidadLabel },
  { id: tesoreriaLabel, name: tesoreriaLabel },
  { id: nominasLabel, name: nominasLabel },
];

export function mergeAreaOptions(areaId: string, areaName: string) {
  const fallbackId = areaId.trim();
  if (!fallbackId) {
    return requiredAreaOptions;
  }

  if (requiredAreaOptions.some((area) => area.id === fallbackId)) {
    return requiredAreaOptions;
  }

  return [{ id: fallbackId, name: areaName.trim() || fallbackId }, ...requiredAreaOptions];
}

export function mapAdminUsers(value: unknown): AdminUserRecord[] {
  if (!value || typeof value !== "object") {
    return [];
  }

  const users: AdminUserRecord[] = [];
  for (const [id, raw] of Object.entries(value as Record<string, unknown>)) {
    if (!raw || typeof raw !== "object") continue;
    const data = raw as Record<string, unknown>;

    const name = firstNonEmptyString(data, ["name", "displayName", "fullName", "nombre"]) || "Sin nombre";
    const email = firstNonEmptyString(data, ["email", "mail", "userEmail"]);
    const areaId = firstNonEmptyString(data, ["areaId", "departmentId", "area"]);
    const areaName = firstNonEmptyString(data, ["areaName", "departmentName", "areaLabel"]) || areaId;

    users.push({
      id,
      name,
      email,
      role: firstNonEmptyString(data, ["role"]) || "usuario",
      areaId,
      areaName,
      areaDisplay: normalizeAreaLabel(areaName || areaId),
      isActive: data.isActive !== false,
    });
  }

  return users.sort((a, b) => a.name.localeCompare(b.name, "es"));
}

function firstNonEmptyString(data: Record<string, unknown>, keys: string[]) {
  for (const key of keys) {
    const raw = data[key];
    if (typeof raw === "string" && raw.trim()) {
      return raw.trim();
    }
  }
  return "";
}
