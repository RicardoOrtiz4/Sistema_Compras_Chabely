import 'package:flutter/material.dart';

const intakeReviewLabel = 'Revision operativa';
const approvalQueueLabel = 'Validacion';
const executionPrepLabel = 'Preparacion';
const arrivalTrackingLabel = 'Seguimiento logistica';

enum PurchaseOrderStatus {
  draft,
  intakeReview,
  sourcing,
  readyForApproval,
  approvalQueue,
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
      case PurchaseOrderStatus.intakeReview:
        return intakeReviewLabel;
      case PurchaseOrderStatus.sourcing:
        return 'Preparacion';
      case PurchaseOrderStatus.readyForApproval:
        return 'Lista para ejecucion';
      case PurchaseOrderStatus.approvalQueue:
        return approvalQueueLabel;
      case PurchaseOrderStatus.paymentDone:
        return arrivalTrackingLabel;
      case PurchaseOrderStatus.contabilidad:
        return 'Cierre documental';
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
      case PurchaseOrderStatus.intakeReview:
        return Icons.playlist_add_check_circle_outlined;
      case PurchaseOrderStatus.sourcing:
        return Icons.request_quote_outlined;
      case PurchaseOrderStatus.readyForApproval:
        return Icons.fact_check_outlined;
      case PurchaseOrderStatus.approvalQueue:
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
      case PurchaseOrderStatus.intakeReview:
        return scheme.primary;
      case PurchaseOrderStatus.sourcing:
        return scheme.secondaryContainer;
      case PurchaseOrderStatus.readyForApproval:
        return scheme.secondary;
      case PurchaseOrderStatus.approvalQueue:
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
const int defaultOrderPageSize = 10;
const int orderPageSizeStep = 10;
const defaultStatusFlow = <PurchaseOrderStatus>[
  PurchaseOrderStatus.intakeReview,
  PurchaseOrderStatus.sourcing,
  PurchaseOrderStatus.readyForApproval,
  PurchaseOrderStatus.paymentDone,
  PurchaseOrderStatus.contabilidad,
  PurchaseOrderStatus.eta,
];
const adminRoles = {'administrador', 'admin'};
bool isAdminRole(String role) {
  return adminRoles.contains(role.toLowerCase());
}
