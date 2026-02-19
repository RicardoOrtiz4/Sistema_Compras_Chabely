import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/domain/shared_quote.dart';

final userOrdersProvider = StreamProvider<List<PurchaseOrder>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return const Stream.empty();
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersForUser(uid);
});

final allOrdersProvider = StreamProvider<List<PurchaseOrder>>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return const Stream.empty();
  }
  final isDireccionGeneral = isDireccionGeneralLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isDireccionGeneral) {
    return const Stream.empty();
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchAllOrders();
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

final orderByIdStreamProvider = StreamProvider.family<PurchaseOrder?, String>((ref, orderId) {
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrderById(orderId);
});

final pendingComprasOrdersProvider = StreamProvider<List<PurchaseOrder>>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return const Stream.empty();
  }
  final isCompras = isComprasLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isCompras) {
    return const Stream.empty();
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersByStatus(PurchaseOrderStatus.pendingCompras);
});

final cotizacionesOrdersProvider = StreamProvider<List<PurchaseOrder>>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return const Stream.empty();
  }
  final isCompras = isComprasLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isCompras) {
    return const Stream.empty();
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersByStatus(PurchaseOrderStatus.cotizaciones);
});

final sharedQuotesProvider = StreamProvider<List<SharedQuote>>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return const Stream.empty();
  }
  final isCompras = isComprasLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isCompras) {
    return const Stream.empty();
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchSharedQuotes();
});

final sharedQuoteByIdProvider =
    StreamProvider.family<SharedQuote?, String>((ref, quoteId) {
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchSharedQuoteById(quoteId);
});

final pendingDireccionOrdersProvider = StreamProvider<List<PurchaseOrder>>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return const Stream.empty();
  }
  final isDireccionGeneral = isDireccionGeneralLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isDireccionGeneral) {
    return const Stream.empty();
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersByStatus(PurchaseOrderStatus.authorizedGerencia);
});

final pendingEtaOrdersProvider = StreamProvider<List<PurchaseOrder>>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return const Stream.empty();
  }
  final isCompras = isComprasLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isCompras) {
    return const Stream.empty();
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersByStatus(PurchaseOrderStatus.paymentDone);
});

final contabilidadOrdersProvider = StreamProvider<List<PurchaseOrder>>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return const Stream.empty();
  }
  final isContabilidad = isContabilidadLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isContabilidad) {
    return const Stream.empty();
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersByStatus(PurchaseOrderStatus.contabilidad);
});

final almacenOrdersProvider = StreamProvider<List<PurchaseOrder>>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return const Stream.empty();
  }
  final isAlmacen = isAlmacenLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isAlmacen) {
    return const Stream.empty();
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.watchOrdersByStatus(PurchaseOrderStatus.almacen);
});

final rejectedOrdersProvider = StreamProvider<List<PurchaseOrder>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return const Stream.empty();
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
