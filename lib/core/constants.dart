import 'package:flutter/material.dart';

enum PurchaseOrderStatus {
  draft,
  pendingCompras,
  authorizedGerencia,
  paymentDone,
  orderPlaced,
  eta,
}

extension PurchaseOrderStatusX on PurchaseOrderStatus {
  String get label {
    switch (this) {
      case PurchaseOrderStatus.draft:
        return 'Borrador';
      case PurchaseOrderStatus.pendingCompras:
        return 'Por confirmar (Compras)';
      case PurchaseOrderStatus.authorizedGerencia:
        return 'Autorizado por Gerencia General';
      case PurchaseOrderStatus.paymentDone:
        return 'Pago realizado';
      case PurchaseOrderStatus.orderPlaced:
        return 'Orden realizada';
      case PurchaseOrderStatus.eta:
        return 'Fecha estimada de entrega';
    }
  }

  IconData get icon {
    switch (this) {
      case PurchaseOrderStatus.draft:
        return Icons.edit_note;
      case PurchaseOrderStatus.pendingCompras:
        return Icons.playlist_add_check_circle_outlined;
      case PurchaseOrderStatus.authorizedGerencia:
        return Icons.verified_user;
      case PurchaseOrderStatus.paymentDone:
        return Icons.payments_outlined;
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
      case PurchaseOrderStatus.authorizedGerencia:
        return scheme.secondary;
      case PurchaseOrderStatus.paymentDone:
        return scheme.tertiary;
      case PurchaseOrderStatus.orderPlaced:
        return scheme.primaryFixed;
      case PurchaseOrderStatus.eta:
        return scheme.tertiaryFixed;
    }
  }
}

enum PurchaseOrderUrgency { urgente, alta, media, baja }

extension PurchaseOrderUrgencyX on PurchaseOrderUrgency {
  String get label {
    switch (this) {
      case PurchaseOrderUrgency.urgente:
        return 'Urgente';
      case PurchaseOrderUrgency.alta:
        return 'Alta';
      case PurchaseOrderUrgency.media:
        return 'Media';
      case PurchaseOrderUrgency.baja:
        return 'Baja';
    }
  }
}

const trackingButtonLabel = 'Seguimiento';

const defaultStatusFlow = <PurchaseOrderStatus>[
  PurchaseOrderStatus.pendingCompras,
  PurchaseOrderStatus.authorizedGerencia,
  PurchaseOrderStatus.paymentDone,
  PurchaseOrderStatus.orderPlaced,
  PurchaseOrderStatus.eta,
];
