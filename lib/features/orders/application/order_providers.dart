import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/domain/shared_quote.dart';

bool _awaitingProfile(Ref ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return false;
  return ref.watch(currentUserProfileProvider).value == null;
}

final userOrdersProvider = StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersForUser(uid);
});

final userOrdersPagedProvider =
    StreamProvider.autoDispose.family<List<PurchaseOrder>, int>((ref, limit) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersForUser(uid, limit: limit);
});

final allOrdersProvider = StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
  if (_awaitingProfile(ref)) {
    return const Stream.empty();
  }
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final isDireccionGeneral = isDireccionGeneralLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isDireccionGeneral) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchAllOrders();
});

final allOrdersPagedProvider =
    StreamProvider.autoDispose.family<List<PurchaseOrder>, int>((ref, limit) {
  if (_awaitingProfile(ref)) {
    return const Stream.empty();
  }
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final isDireccionGeneral = isDireccionGeneralLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isDireccionGeneral) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchAllOrders(limit: limit);
});

final orderEventsProvider =
    StreamProvider.autoDispose.family<List<PurchaseOrderEvent>, String>((ref, orderId) {
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchEvents(orderId);
});
final orderByIdProvider =
    Provider.autoDispose.family<PurchaseOrder?, String>((ref, orderId) {
  final orders = ref.watch(userOrdersProvider).value;
  if (orders == null) return null;
  for (final order in orders) {
    if (order.id == orderId) {
      return order;
    }
  }
  return null;
});

final orderByIdStreamProvider =
    StreamProvider.autoDispose.family<PurchaseOrder?, String>((ref, orderId) {
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrderById(orderId);
});

final pendingComprasOrdersProvider =
    StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
  if (_awaitingProfile(ref)) {
    return const Stream.empty();
  }
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final isCompras = isComprasLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isCompras) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersByStatus(PurchaseOrderStatus.pendingCompras);
});

final pendingComprasOrdersPagedProvider =
    StreamProvider.autoDispose.family<List<PurchaseOrder>, int>((ref, limit) {
  if (_awaitingProfile(ref)) {
    return const Stream.empty();
  }
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final isCompras = isComprasLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isCompras) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersByStatus(PurchaseOrderStatus.pendingCompras, limit: limit);
});

final cotizacionesOrdersProvider =
    StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
  if (_awaitingProfile(ref)) {
    return const Stream.empty();
  }
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final isCompras = isComprasLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isCompras) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersByStatus(PurchaseOrderStatus.cotizaciones);
});

final cotizacionesOrdersPagedProvider =
    StreamProvider.autoDispose.family<List<PurchaseOrder>, int>((ref, limit) {
  if (_awaitingProfile(ref)) {
    return const Stream.empty();
  }
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final isCompras = isComprasLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isCompras) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersByStatus(PurchaseOrderStatus.cotizaciones, limit: limit);
});

final sharedQuotesProvider = StreamProvider.autoDispose<List<SharedQuote>>((ref) {
  if (_awaitingProfile(ref)) {
    return const Stream.empty();
  }
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return Stream.value(const <SharedQuote>[]);
  }
  final isCompras = isComprasLabel(user.areaDisplay);
  final isDireccionGeneral = isDireccionGeneralLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isCompras && !isDireccionGeneral) {
    return Stream.value(const <SharedQuote>[]);
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchSharedQuotes();
});

final sharedQuoteByIdProvider =
    StreamProvider.autoDispose.family<SharedQuote?, String>((ref, quoteId) {
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchSharedQuoteById(quoteId);
});

final pendingDireccionOrdersProvider =
    StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
  if (_awaitingProfile(ref)) {
    return const Stream.empty();
  }
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final isDireccionGeneral = isDireccionGeneralLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isDireccionGeneral) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersByStatus(PurchaseOrderStatus.authorizedGerencia);
});

final pendingDireccionOrdersPagedProvider =
    StreamProvider.autoDispose.family<List<PurchaseOrder>, int>((ref, limit) {
  if (_awaitingProfile(ref)) {
    return const Stream.empty();
  }
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final isDireccionGeneral = isDireccionGeneralLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isDireccionGeneral) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersByStatus(PurchaseOrderStatus.authorizedGerencia, limit: limit);
});

final pendingEtaOrdersProvider = StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
  if (_awaitingProfile(ref)) {
    return const Stream.empty();
  }
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final isCompras = isComprasLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isCompras) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersByStatus(PurchaseOrderStatus.paymentDone);
});

final pendingEtaOrdersPagedProvider =
    StreamProvider.autoDispose.family<List<PurchaseOrder>, int>((ref, limit) {
  if (_awaitingProfile(ref)) {
    return const Stream.empty();
  }
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final isCompras = isComprasLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isCompras) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersByStatus(PurchaseOrderStatus.paymentDone, limit: limit);
});

final contabilidadOrdersProvider =
    StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
  if (_awaitingProfile(ref)) {
    return const Stream.empty();
  }
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final isContabilidad = isContabilidadLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isContabilidad) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersByStatus(PurchaseOrderStatus.contabilidad);
});

final contabilidadOrdersPagedProvider =
    StreamProvider.autoDispose.family<List<PurchaseOrder>, int>((ref, limit) {
  if (_awaitingProfile(ref)) {
    return const Stream.empty();
  }
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final isContabilidad = isContabilidadLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isContabilidad) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersByStatus(PurchaseOrderStatus.contabilidad, limit: limit);
});

final almacenOrdersProvider = StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
  if (_awaitingProfile(ref)) {
    return const Stream.empty();
  }
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final isAlmacen = isAlmacenLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isAlmacen) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersByStatus(PurchaseOrderStatus.almacen);
});

final almacenOrdersPagedProvider =
    StreamProvider.autoDispose.family<List<PurchaseOrder>, int>((ref, limit) {
  if (_awaitingProfile(ref)) {
    return const Stream.empty();
  }
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final isAlmacen = isAlmacenLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isAlmacen) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersByStatus(PurchaseOrderStatus.almacen, limit: limit);
});

final rejectedOrdersProvider = StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersForUser(uid).map((orders) {
    return orders
        .where((order) {
          final reason = order.lastReturnReason;
          return order.status == PurchaseOrderStatus.draft &&
              reason != null &&
              reason.trim().isNotEmpty;
        })
        .toList();
  });
});

final rejectedOrdersPagedProvider =
    StreamProvider.autoDispose.family<List<PurchaseOrder>, int>((ref, limit) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersForUser(uid, limit: limit).map((orders) {
    return orders
        .where((order) {
          final reason = order.lastReturnReason;
          return order.status == PurchaseOrderStatus.draft &&
              reason != null &&
              reason.trim().isNotEmpty;
        })
        .toList();
  });
});
