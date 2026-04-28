import type { AppUser } from "@/store/session-store";
import {
  isComprasLabel,
  isContraloriaLabel,
  isDireccionGeneralLabel,
  isPlaneacionProduccionLabel,
} from "@/lib/area-labels";

export function hasAdminAccess(user: AppUser | null) {
  return user?.role === "administrador" || user?.role === "admin";
}

export function hasComprasAccess(user: AppUser | null) {
  return hasAdminAccess(user) || isComprasLabel(user?.areaDisplay);
}

export function hasDireccionApprovalAccess(user: AppUser | null) {
  return (
    hasAdminAccess(user) ||
    isDireccionGeneralLabel(user?.areaDisplay) ||
    isContraloriaLabel(user?.areaDisplay)
  );
}

export function hasReportsAccess(user: AppUser | null) {
  return hasComprasAccess(user) || hasDireccionApprovalAccess(user);
}

export function canAssignClientsToOrderItems(user: AppUser | null) {
  return (
    hasAdminAccess(user) ||
    isPlaneacionProduccionLabel(user?.areaDisplay) ||
    isComprasLabel(user?.areaDisplay) ||
    isDireccionGeneralLabel(user?.areaDisplay) ||
    isContraloriaLabel(user?.areaDisplay)
  );
}
