import 'package:flutter/material.dart';

enum PurchaseOrderStatus {
  draft,
  pendingCompras,
  cotizaciones,
  authorizedGerencia,
  paymentDone,
  contabilidad,
  almacen,
  orderPlaced,
  eta,
}

extension PurchaseOrderStatusX on PurchaseOrderStatus {
  String get label {
    switch (this) {
      case PurchaseOrderStatus.draft:
        return 'Requiere corrección';
      case PurchaseOrderStatus.pendingCompras:
        return 'Por confirmar (Compras)';
      case PurchaseOrderStatus.cotizaciones:
        return 'Cotizaciones';
      case PurchaseOrderStatus.authorizedGerencia:
        return 'En Dirección General';
      case PurchaseOrderStatus.paymentDone:
        return 'Pendiente de ETA';
      case PurchaseOrderStatus.contabilidad:
        return 'En Contabilidad';
      case PurchaseOrderStatus.almacen:
        return 'En Almacén';
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
      case PurchaseOrderStatus.authorizedGerencia:
        return Icons.verified_user;
      case PurchaseOrderStatus.paymentDone:
        return Icons.event_available_outlined;
      case PurchaseOrderStatus.contabilidad:
        return Icons.receipt_long_outlined;
      case PurchaseOrderStatus.almacen:
        return Icons.inventory_2_outlined;
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
      case PurchaseOrderStatus.authorizedGerencia:
        return scheme.secondary;
      case PurchaseOrderStatus.paymentDone:
        return scheme.tertiary;
      case PurchaseOrderStatus.contabilidad:
        return scheme.secondary;
      case PurchaseOrderStatus.almacen:
        return scheme.primaryFixed;
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

  Color color(ColorScheme scheme) {
    switch (this) {
      case PurchaseOrderUrgency.urgente:
        return scheme.error;
      case PurchaseOrderUrgency.alta:
        return Colors.orange;
      case PurchaseOrderUrgency.media:
        return scheme.primary;
      case PurchaseOrderUrgency.baja:
        return Colors.green;
    }
  }
}

const appLogoAsset = 'evidencias/LOGO CHABELY.png';
const int defaultOrderPageSize = 5;
const int orderPageSizeStep = 5;

const defaultStatusFlow = <PurchaseOrderStatus>[
  PurchaseOrderStatus.pendingCompras,
  PurchaseOrderStatus.cotizaciones,
  PurchaseOrderStatus.authorizedGerencia,
  PurchaseOrderStatus.paymentDone,
  PurchaseOrderStatus.contabilidad,
  PurchaseOrderStatus.almacen,
  PurchaseOrderStatus.eta,
];

const adminRoles = {'administrador', 'admin'};

bool isAdminRole(String role) {
  return adminRoles.contains(role.toLowerCase());
}
