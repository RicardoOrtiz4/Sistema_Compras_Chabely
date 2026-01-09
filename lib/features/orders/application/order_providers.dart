import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';

final userOrdersProvider = StreamProvider<List<PurchaseOrder>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return const Stream.empty();
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersForUser(uid);
});

final orderEventsProvider =
    StreamProvider.family<List<PurchaseOrderEvent>, String>((ref, orderId) {
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchEvents(orderId);
});
final orderByIdProvider = Provider.family<PurchaseOrder?, String>((ref, orderId) {
  final orders = ref.watch(userOrdersProvider).value;
  if (orders == null) return null;
  for (final order in orders) {
    if (order.id == orderId) {
      return order;
    }
  }
  return null;
});
