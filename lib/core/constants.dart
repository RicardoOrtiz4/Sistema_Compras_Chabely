import 'package:flutter/material.dart';
enum PurchaseOrderStatus {
  draft,
  pendingCompras,
  cotizaciones,
  dataComplete,
  authorizedGerencia,
  paymentDone,
  contabilidad,
  orderPlaced,
  eta,
}
extension PurchaseOrderStatusX on PurchaseOrderStatus {
  String get label {
    switch (this) {
      case PurchaseOrderStatus.draft:
        return 'Requiere correccion';
      case PurchaseOrderStatus.pendingCompras:
        return 'Por confirmar';
      case PurchaseOrderStatus.cotizaciones:
        return 'Cotizaciones';
      case PurchaseOrderStatus.dataComplete:
        return 'Datos completos';
      case PurchaseOrderStatus.authorizedGerencia:
        return 'En Direccion General';
      case PurchaseOrderStatus.paymentDone:
        return 'En proceso';
      case PurchaseOrderStatus.contabilidad:
        return 'En Contabilidad';
      case PurchaseOrderStatus.orderPlaced:
        return 'Orden realizada';
      case PurchaseOrderStatus.eta:
        return 'Orden finalizada';
    }
  }
  IconData get icon {
    switch (this) {
      case PurchaseOrderStatus.draft:
        return Icons.edit_note;
      case PurchaseOrderStatus.pendingCompras:
        return Icons.playlist_add_check_circle_outlined;
      case PurchaseOrderStatus.cotizaciones:
        return Icons.request_quote_outlined;
      case PurchaseOrderStatus.dataComplete:
        return Icons.fact_check_outlined;
      case PurchaseOrderStatus.authorizedGerencia:
        return Icons.approval_outlined;
      case PurchaseOrderStatus.paymentDone:
        return Icons.sync_alt_outlined;
      case PurchaseOrderStatus.contabilidad:
        return Icons.receipt_long_outlined;
      case PurchaseOrderStatus.orderPlaced:
        return Icons.shopping_bag;
      case PurchaseOrderStatus.eta:
        return Icons.local_shipping_outlined;
    }
  }
  Color statusColor(ColorScheme scheme) {
    switch (this) {
      case PurchaseOrderStatus.draft:
        return scheme.outline;
      case PurchaseOrderStatus.pendingCompras:
        return scheme.primary;
      case PurchaseOrderStatus.cotizaciones:
        return scheme.secondaryContainer;
      case PurchaseOrderStatus.dataComplete:
        return scheme.secondary;
      case PurchaseOrderStatus.authorizedGerencia:
        return scheme.secondary;
      case PurchaseOrderStatus.paymentDone:
        return scheme.tertiary;
      case PurchaseOrderStatus.contabilidad:
        return scheme.secondary;
      case PurchaseOrderStatus.orderPlaced:
        return scheme.primaryFixed;
      case PurchaseOrderStatus.eta:
        return scheme.tertiaryFixed;
    }
  }
}
enum PurchaseOrderUrgency { normal, urgente }
extension PurchaseOrderUrgencyX on PurchaseOrderUrgency {
  String get label {
    switch (this) {
      case PurchaseOrderUrgency.normal:
        return 'Normal';
      case PurchaseOrderUrgency.urgente:
        return 'Urgente';
    }
  }
  Color color(ColorScheme scheme) {
    switch (this) {
      case PurchaseOrderUrgency.normal:
        return scheme.primary;
      case PurchaseOrderUrgency.urgente:
        return scheme.error;
    }
  }
}
const appLogoAsset = 'evidencias/LOGO CHABELY.png';
const int defaultOrderPageSize = 5;
const int orderPageSizeStep = 5;
const defaultStatusFlow = <PurchaseOrderStatus>[
  PurchaseOrderStatus.pendingCompras,
  PurchaseOrderStatus.cotizaciones,
  PurchaseOrderStatus.dataComplete,
  PurchaseOrderStatus.paymentDone,
  PurchaseOrderStatus.contabilidad,
  PurchaseOrderStatus.eta,
];
const adminRoles = {'administrador', 'admin'};
bool isAdminRole(String role) {
  return adminRoles.contains(role.toLowerCase());
}