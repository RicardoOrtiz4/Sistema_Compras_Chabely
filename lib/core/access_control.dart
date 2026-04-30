import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';

const accountingStageLabel = 'Facturas y evidencia';

bool hasSignedInAccess(AppUser? user) => user != null;

bool hasAdminAccess(AppUser? user) => user != null && isAdminRole(user.role);

bool hasComprasAccess(AppUser? user) {
  return user != null &&
      (isAdminRole(user.role) || isComprasLabel(user.areaDisplay));
}

bool hasDireccionApprovalAccess(AppUser? user) {
  return user != null &&
      (isAdminRole(user.role) ||
          isDireccionGeneralLabel(user.areaDisplay) ||
          isContraloriaLabel(user.areaDisplay));
}

bool canAccessDireccionGeneralModule(AppUser? user) {
  return hasComprasAccess(user) || hasDireccionApprovalAccess(user);
}

bool hasAuthorizeOrdersAccess(AppUser? user) {
  return hasComprasAccess(user) || hasDireccionApprovalAccess(user);
}

bool hasEtaAccess(AppUser? user) {
  return user != null &&
      (isAdminRole(user.role) || isComprasLabel(user.areaDisplay));
}

bool hasFacturasEvidenciasAccess(AppUser? user) {
  return user != null &&
      (isAdminRole(user.role) ||
          isContabilidadLabel(user.areaDisplay) ||
          isComprasLabel(user.areaDisplay));
}

bool canManageUsers(AppUser? user) => hasAdminAccess(user);

bool canManageSuppliers(AppUser? user) {
  return user != null &&
      (isAdminRole(user.role) ||
          isComprasLabel(user.areaDisplay) ||
          isDireccionGeneralLabel(user.areaDisplay) ||
          isContraloriaLabel(user.areaDisplay));
}

bool canManageClients(AppUser? user) {
  return canManageSuppliers(user) ||
      (user != null && isPlaneacionProduccionLabel(user.areaDisplay));
}

bool canManagePartners(AppUser? user) {
  return canManageSuppliers(user) || canManageClients(user);
}

bool canAssignClientsToOrderItems(AppUser? user) {
  return user != null &&
      (isAdminRole(user.role) ||
          isPlaneacionProduccionLabel(user.areaDisplay) ||
          isComprasLabel(user.areaDisplay) ||
          isDireccionGeneralLabel(user.areaDisplay) ||
          isContraloriaLabel(user.areaDisplay));
}

bool canViewReports(AppUser? user) {
  return hasComprasAccess(user) || hasDireccionApprovalAccess(user);
}

bool canViewMonitoring(AppUser? user) {
  return hasComprasAccess(user) || hasDireccionApprovalAccess(user);
}

bool canViewGlobalHistory(AppUser? user) {
  return hasComprasAccess(user) || hasDireccionApprovalAccess(user);
}

bool canViewGlobalRejected(AppUser? user) {
  return hasComprasAccess(user) || hasDireccionApprovalAccess(user);
}

bool canViewOperationalOrders(AppUser? user) {
  return hasComprasAccess(user) || hasDireccionApprovalAccess(user);
}

bool canAccessPurchasePackets(AppUser? user) {
  return hasComprasAccess(user) || hasDireccionApprovalAccess(user);
}

bool canAccessRoute(AppUser? user, String location) {
  if (location == '/admin/users') return canManageUsers(user);
  if (location == '/partners/suppliers') return canManageSuppliers(user);
  if (location == '/partners/clients') return canManageClients(user);
  if (location == '/reports') return canViewReports(user);
  if (location == '/orders/authorize') return hasAuthorizeOrdersAccess(user);
  if (location == '/orders/compras') return hasComprasAccess(user);
  if (location == '/orders/compras/pendientes') return hasComprasAccess(user);
  if (location == '/orders/compras/dashboard') return hasComprasAccess(user);
  if (location == '/orders/compras/historial-pdfs') return hasComprasAccess(user);
  if (location == '/orders/direccion-general') {
    return canAccessDireccionGeneralModule(user);
  }
  if (location == '/orders/agregar-fecha-estimada') return hasEtaAccess(user);
  if (location == '/orders/facturas-evidencias') {
    return hasFacturasEvidenciasAccess(user);
  }
  if (location == '/purchase-packets') return canAccessPurchasePackets(user);
  if (location == '/orders/history/all') return canViewGlobalHistory(user);
  if (location == '/orders/rejected/all') return canViewGlobalRejected(user);
  if (location == '/orders/monitoring') return canViewMonitoring(user);
  return true;
}
