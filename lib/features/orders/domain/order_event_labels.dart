import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';

bool isReturnOrderEvent(PurchaseOrderEvent event) {
  return (event.type ?? '').trim().toLowerCase() == 'return';
}

List<PurchaseOrderEvent> sortOrderEventsByTime(
  Iterable<PurchaseOrderEvent> events, {
  bool descending = false,
}) {
  final sorted = events.toList();
  sorted.sort((a, b) {
    final aMs = a.timestamp?.millisecondsSinceEpoch ?? 0;
    final bMs = b.timestamp?.millisecondsSinceEpoch ?? 0;
    final compare = aMs.compareTo(bMs);
    if (compare != 0) {
      return descending ? -compare : compare;
    }
    return descending ? b.id.compareTo(a.id) : a.id.compareTo(b.id);
  });
  return sorted;
}

int? returnSequenceForEvent(
  Iterable<PurchaseOrderEvent> events,
  PurchaseOrderEvent target,
) {
  if (!isReturnOrderEvent(target)) return null;
  final sorted = sortOrderEventsByTime(events);
  var count = 0;
  for (final event in sorted) {
    if (!isReturnOrderEvent(event)) continue;
    count++;
    if (event.id == target.id) return count;
  }
  return null;
}

String returnEventTitle(
  Iterable<PurchaseOrderEvent> events,
  PurchaseOrderEvent event,
) {
  final sequence = returnSequenceForEvent(events, event);
  if (sequence == null || sequence <= 0) return 'Regreso';
  return 'Regreso $sequence';
}

String orderEventTransitionLabel(PurchaseOrderEvent event) {
  final fromLabel = event.fromStatus?.label ?? 'Inicio';
  final toLabel = event.toStatus?.label ?? 'Sin estatus';
  return '$fromLabel -> $toLabel';
}

String returnStageLabel(PurchaseOrderStatus? status) {
  switch (status) {
    case PurchaseOrderStatus.pendingCompras:
      return 'Compras';
    case PurchaseOrderStatus.cotizaciones:
      return 'Cotizaciones';
    case PurchaseOrderStatus.dataComplete:
      return 'Datos completos';
    case PurchaseOrderStatus.authorizedGerencia:
      return 'Direccion General';
    case PurchaseOrderStatus.paymentDone:
      return 'En proceso';
    case PurchaseOrderStatus.contabilidad:
      return 'Contabilidad';
    case PurchaseOrderStatus.orderPlaced:
      return 'Orden realizada';
    case PurchaseOrderStatus.eta:
      return 'Orden finalizada';
    case PurchaseOrderStatus.draft:
      return 'Solicitante';
    case null:
      return 'Inicio';
  }
}
