import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/features/orders/data/order_local_snapshot_store.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/order_dashboard_counts.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/domain/supplier_quote.dart';
import 'package:sistema_compras/features/orders/domain/supplier_quote_history_entry.dart';

bool _awaitingProfile(Ref ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return false;
  return ref.watch(currentUserProfileProvider).value == null;
}

const _sessionCacheDuration = Duration(minutes: 4);
const _sharedOrderDataScope = sharedCompanyDataId;
final _sessionSnapshotCache = <String, Object?>{};

String _orderSnapshotKey(String scope, String orderId) =>
    '$scope:orderById:$orderId';
String _orderEventsSnapshotKey(String scope, String orderId) =>
    '$scope:orderEvents:$orderId';

String _companyCacheScope(Ref ref) => _sharedOrderDataScope;

String _companyScopeFromKey(String key) {
  final scopeEnd = key.indexOf(':');
  return scopeEnd == -1 ? key : key.substring(0, scopeEnd);
}

String _cacheScope(Ref ref) {
  final company = _companyCacheScope(ref);
  final userId = ref.watch(currentUserIdProvider) ?? 'guest';
  return '$company:$userId';
}

String _profileCacheScope(Ref ref, AppUser user) {
  return '${_cacheScope(ref)}:${user.role}:${user.areaDisplay.trim().toLowerCase()}';
}

void clearOrderSessionSnapshotCache() {
  _sessionSnapshotCache.clear();
}

void _cacheProviderForSession(
  Ref ref, {
  Duration duration = _sessionCacheDuration,
}) {
  final link = ref.keepAlive();
  Timer? timer;

  ref.onCancel(() {
    timer = Timer(duration, link.close);
  });
  ref.onResume(() {
    timer?.cancel();
    timer = null;
  });
  ref.onDispose(() {
    timer?.cancel();
  });
}

String _orderSignature(PurchaseOrder order) {
  final updatedAt = order.updatedAt?.millisecondsSinceEpoch ?? 0;
  final createdAt = order.createdAt?.millisecondsSinceEpoch ?? 0;
  final itemsSignature = order.items
      .map((item) {
        final estimatedDate = item.estimatedDate?.millisecondsSinceEpoch ?? 0;
        final deliveryEtaDate = item.deliveryEtaDate?.millisecondsSinceEpoch ?? 0;
        final sentToContabilidadAt =
            item.sentToContabilidadAt?.millisecondsSinceEpoch ?? 0;
        return [
          item.line.toString(),
          item.quoteId ?? '',
          item.quoteStatus.name,
          estimatedDate.toString(),
          deliveryEtaDate.toString(),
          sentToContabilidadAt.toString(),
          item.internalOrder ?? '',
          item.reviewFlagged ? '1' : '0',
          item.reviewComment ?? '',
          item.receivedQuantity?.toString() ?? '',
          item.receivedComment ?? '',
        ].join('^');
      })
      .join('~');
  return [
    order.id,
    order.companyId ?? '',
    order.status.name,
    updatedAt.toString(),
    createdAt.toString(),
    order.returnCount.toString(),
    order.direccionReturnCount.toString(),
    order.items.length.toString(),
    itemsSignature,
  ].join('|');
}

bool _sameOrderList(List<PurchaseOrder> a, List<PurchaseOrder> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (_orderSignature(a[index]) != _orderSignature(b[index])) {
      return false;
    }
  }
  return true;
}

bool _sameOrder(PurchaseOrder? a, PurchaseOrder? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  return _orderSignature(a) == _orderSignature(b);
}

String _eventSignature(PurchaseOrderEvent event) {
  final timestamp = event.timestamp?.millisecondsSinceEpoch ?? 0;
  return [
    event.id,
    event.type ?? '',
    event.fromStatus?.name ?? '',
    event.toStatus?.name ?? '',
    timestamp.toString(),
    event.byUser,
    event.byRole,
    event.comment ?? '',
    event.itemsSnapshot.length.toString(),
  ].join('|');
}

bool _sameEventList(List<PurchaseOrderEvent> a, List<PurchaseOrderEvent> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (_eventSignature(a[index]) != _eventSignature(b[index])) {
      return false;
    }
  }
  return true;
}

String _supplierQuoteSignature(SupplierQuote quote) {
  final updatedAt = quote.updatedAt?.millisecondsSinceEpoch ?? 0;
  final approvedAt = quote.approvedAt?.millisecondsSinceEpoch ?? 0;
  return [
    quote.id,
    quote.status.name,
    quote.version.toString(),
    updatedAt.toString(),
    approvedAt.toString(),
    quote.items.length.toString(),
    quote.links.length.toString(),
  ].join('|');
}

bool _sameSupplierQuoteList(List<SupplierQuote> a, List<SupplierQuote> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (_supplierQuoteSignature(a[index]) != _supplierQuoteSignature(b[index])) {
      return false;
    }
  }
  return true;
}

bool _sameDashboardCounts(OrderDashboardCounts? a, OrderDashboardCounts? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  return a.pendingCompras == b.pendingCompras &&
      a.cotizaciones == b.cotizaciones &&
      a.cotizacionesReadyToSend == b.cotizacionesReadyToSend &&
      a.pendingDireccion == b.pendingDireccion &&
      a.pendingEta == b.pendingEta &&
      a.contabilidad == b.contabilidad &&
      a.rejected == b.rejected &&
      a.hasRemoteCounters == b.hasRemoteCounters;
}

bool _isRejectedDraftOrder(PurchaseOrder order) {
  final reason = order.lastReturnReason;
  return order.status == PurchaseOrderStatus.draft &&
      reason != null &&
      reason.trim().isNotEmpty;
}

bool _isGlobalMonitoringOrder(PurchaseOrder order) {
  return _isRejectedDraftOrder(order) || order.isAwaitingRequesterReceipt;
}

List<PurchaseOrder> _filterRejectedDraftOrders(List<PurchaseOrder> orders) {
  return orders.where(_isRejectedDraftOrder).toList(growable: false);
}

List<PurchaseOrder> _filterGlobalMonitoringOrders(List<PurchaseOrder> orders) {
  return orders.where(_isGlobalMonitoringOrder).toList(growable: false);
}

bool _isUserInProcessOrder(PurchaseOrder order) {
  return order.status != PurchaseOrderStatus.draft &&
      !order.isRequesterReceiptConfirmed;
}

List<PurchaseOrder> _filterContabilidadOrders(List<PurchaseOrder> orders) {
  return orders
      .where((order) => order.status == PurchaseOrderStatus.contabilidad)
      .toList(growable: false);
}

Stream<List<PurchaseOrder>> _withCachedOrders({
  required String key,
  required Stream<List<PurchaseOrder>> source,
}) async* {
  final scope = _companyScopeFromKey(key);
  List<PurchaseOrder>? lastEmitted;
  final cached = _sessionSnapshotCache[key];
  if (cached is List<PurchaseOrder>) {
    lastEmitted = cached;
    yield cached;
  } else {
    final persisted = await OrderLocalSnapshotStore.readOrders(key);
    if (persisted != null) {
      final snapshot = List<PurchaseOrder>.unmodifiable(persisted);
      _sessionSnapshotCache[key] = snapshot;
      lastEmitted = snapshot;
      yield snapshot;
    }
  }

  await for (final orders in source) {
    final snapshot = List<PurchaseOrder>.unmodifiable(orders);
    _sessionSnapshotCache[key] = snapshot;
    for (final order in snapshot) {
      _sessionSnapshotCache[_orderSnapshotKey(scope, order.id)] = order;
    }
    unawaited(OrderLocalSnapshotStore.writeOrders(key, orders));
    if (lastEmitted != null && _sameOrderList(lastEmitted, snapshot)) {
      continue;
    }
    lastEmitted = snapshot;
    yield snapshot;
  }
}

Stream<List<SupplierQuote>> _withCachedSupplierQuotes({
  required String key,
  required Stream<List<SupplierQuote>> source,
}) async* {
  List<SupplierQuote>? lastEmitted;
  final cached = _sessionSnapshotCache[key];
  if (cached is List<SupplierQuote>) {
    lastEmitted = cached;
    yield cached;
  } else {
    final persisted = await OrderLocalSnapshotStore.readSupplierQuotes(key);
    if (persisted != null) {
      final snapshot = List<SupplierQuote>.unmodifiable(persisted);
      _sessionSnapshotCache[key] = snapshot;
      lastEmitted = snapshot;
      yield snapshot;
    }
  }

  await for (final quotes in source) {
    final snapshot = List<SupplierQuote>.unmodifiable(quotes);
    _sessionSnapshotCache[key] = snapshot;
    unawaited(OrderLocalSnapshotStore.writeSupplierQuotes(key, quotes));
    if (lastEmitted != null && _sameSupplierQuoteList(lastEmitted, snapshot)) {
      continue;
    }
    lastEmitted = snapshot;
    yield snapshot;
  }
}

Stream<OrderDashboardCounts?> _withCachedDashboardCounts({
  required String key,
  required Stream<OrderDashboardCounts?> source,
}) async* {
  OrderDashboardCounts? lastEmitted;
  final cached = _sessionSnapshotCache[key];
  if (cached is OrderDashboardCounts) {
    lastEmitted = cached;
    yield cached;
  } else {
    final persisted = await OrderLocalSnapshotStore.readDashboardCounts(key);
    if (persisted != null) {
      _sessionSnapshotCache[key] = persisted;
      lastEmitted = persisted;
      yield persisted;
    }
  }

  await for (final counts in source) {
    if (counts != null) {
      _sessionSnapshotCache[key] = counts;
      unawaited(OrderLocalSnapshotStore.writeDashboardCounts(key, counts));
    }
    if (_sameDashboardCounts(lastEmitted, counts)) {
      continue;
    }
    lastEmitted = counts;
    yield counts;
  }
}

Stream<PurchaseOrder?> _withCachedOrderById({
  required String scope,
  required String orderId,
  required Stream<PurchaseOrder?> source,
}) async* {
  final cacheKey = _orderSnapshotKey(scope, orderId);
  PurchaseOrder? lastEmitted;
  final cached = _sessionSnapshotCache[cacheKey];
  if (cached is PurchaseOrder) {
    lastEmitted = cached;
    yield cached;
  }

  await for (final order in source) {
    if (order != null) {
      _sessionSnapshotCache[cacheKey] = order;
    } else {
      _sessionSnapshotCache.remove(cacheKey);
    }
    if (_sameOrder(lastEmitted, order)) {
      continue;
    }
    lastEmitted = order;
    yield order;
  }
}

Stream<List<PurchaseOrderEvent>> _withCachedOrderEvents({
  required String scope,
  required String orderId,
  required Stream<List<PurchaseOrderEvent>> source,
}) async* {
  final cacheKey = _orderEventsSnapshotKey(scope, orderId);
  List<PurchaseOrderEvent>? lastEmitted;
  final cached = _sessionSnapshotCache[cacheKey];
  if (cached is List<PurchaseOrderEvent>) {
    lastEmitted = cached;
    yield cached;
  }

  await for (final events in source) {
    final snapshot = List<PurchaseOrderEvent>.unmodifiable(events);
    _sessionSnapshotCache[cacheKey] = snapshot;
    if (lastEmitted != null && _sameEventList(lastEmitted, snapshot)) {
      continue;
    }
    lastEmitted = snapshot;
    yield snapshot;
  }
}

final userOrdersProvider = StreamProvider.autoDispose<List<PurchaseOrder>>((
  ref,
) {
  _cacheProviderForSession(ref);
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return _withCachedOrders(
    key: '${_cacheScope(ref)}:userOrders:$uid',
    source: repository.watchOrdersForUser(uid),
  );
});

final userOrdersPagedProvider = StreamProvider.autoDispose
    .family<List<PurchaseOrder>, int>((ref, limit) {
      _cacheProviderForSession(ref);
      final uid = ref.watch(currentUserIdProvider);
      if (uid == null) {
        return Stream.value(const <PurchaseOrder>[]);
      }
      final repository = ref.watch(purchaseOrderRepositoryProvider);
      return _withCachedOrders(
        key: '${_cacheScope(ref)}:userOrdersPaged:$uid:$limit',
        source: repository.watchOrdersForUser(uid, limit: limit),
      );
    });

final allOrdersProvider = StreamProvider.autoDispose<List<PurchaseOrder>>((
  ref,
) {
  _cacheProviderForSession(ref);
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
  final cacheScope = _profileCacheScope(ref, user);
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return _withCachedOrders(
    key: '$cacheScope:allOrders',
    source: repository.watchAllOrders(),
  );
});

final historyAllOrdersProvider = StreamProvider.autoDispose<List<PurchaseOrder>>((
  ref,
) {
  _cacheProviderForSession(ref);
  if (_awaitingProfile(ref)) {
    return const Stream.empty();
  }
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final isDireccionGeneral = isDireccionGeneralLabel(user.areaDisplay);
  final isCompras = isComprasLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isDireccionGeneral && !isCompras) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final cacheScope = _profileCacheScope(ref, user);
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return _withCachedOrders(
    key: '$cacheScope:historyAllOrders',
    source: repository.watchAllOrders(),
  );
});

final monitoringOrdersProvider = StreamProvider.autoDispose<List<PurchaseOrder>>(
  (ref) {
    _cacheProviderForSession(ref);
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
    final cacheScope = _profileCacheScope(ref, user);
    final repository = ref.watch(purchaseOrderRepositoryProvider);
    return _withCachedOrders(
      key: '$cacheScope:monitoringOrders',
      source: repository.watchAllOrders(),
    );
  },
);

final allOrdersPagedProvider = StreamProvider.autoDispose
    .family<List<PurchaseOrder>, int>((ref, limit) {
      _cacheProviderForSession(ref);
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
      final cacheScope = _profileCacheScope(ref, user);
      final repository = ref.watch(purchaseOrderRepositoryProvider);
      return _withCachedOrders(
        key: '$cacheScope:allOrdersPaged:$limit',
        source: repository.watchAllOrders(limit: limit),
      );
    });

final orderEventsProvider = StreamProvider.autoDispose
    .family<List<PurchaseOrderEvent>, String>((ref, orderId) {
      _cacheProviderForSession(ref);
      final repository = ref.watch(purchaseOrderRepositoryProvider);
      return _withCachedOrderEvents(
        scope: _companyCacheScope(ref),
        orderId: orderId,
        source: repository.watchEvents(orderId),
      );
    });
final orderByIdStreamProvider = StreamProvider.autoDispose
    .family<PurchaseOrder?, String>((ref, orderId) {
      _cacheProviderForSession(ref);
      final repository = ref.watch(purchaseOrderRepositoryProvider);
      return _withCachedOrderById(
        scope: _companyCacheScope(ref),
        orderId: orderId,
        source: repository.watchOrderById(orderId),
      );
    });

final pendingComprasOrdersProvider =
    StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
      _cacheProviderForSession(ref);
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
      final cacheScope = _profileCacheScope(ref, user);
      final repository = ref.watch(purchaseOrderRepositoryProvider);
      return _withCachedOrders(
        key: '$cacheScope:pendingComprasOrders',
        source: repository.watchOrdersByStatus(
          PurchaseOrderStatus.pendingCompras,
        ),
      );
    });

final pendingComprasOrdersPagedProvider = StreamProvider.autoDispose
    .family<List<PurchaseOrder>, int>((ref, limit) {
      _cacheProviderForSession(ref);
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
      final cacheScope = _profileCacheScope(ref, user);
      final repository = ref.watch(purchaseOrderRepositoryProvider);
      return _withCachedOrders(
        key: '$cacheScope:pendingComprasOrdersPaged:$limit',
        source: repository.watchOrdersByStatus(
          PurchaseOrderStatus.pendingCompras,
          limit: limit,
        ),
      );
    });

final cotizacionesOrdersProvider =
    StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
      _cacheProviderForSession(ref);
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
      final cacheScope = _profileCacheScope(ref, user);
      final repository = ref.watch(purchaseOrderRepositoryProvider);
      return _withCachedOrders(
        key: '$cacheScope:cotizacionesOrders',
        source: repository.watchOrdersByStatus(
          PurchaseOrderStatus.cotizaciones,
        ),
      );
    });

final dataCompleteOrdersProvider =
    StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
      _cacheProviderForSession(ref);
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
      final cacheScope = _profileCacheScope(ref, user);
      final repository = ref.watch(purchaseOrderRepositoryProvider);
      return _withCachedOrders(
        key: '$cacheScope:dataCompleteOrders',
        source: repository.watchOrdersByStatus(
          PurchaseOrderStatus.dataComplete,
        ),
      );
    });

final operationalOrdersProvider =
    StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
      _cacheProviderForSession(ref);
      if (_awaitingProfile(ref)) {
        return const Stream.empty();
      }
      final user = ref.watch(currentUserProfileProvider).value;
      if (user == null) {
        return Stream.value(const <PurchaseOrder>[]);
      }
      final isCompras = isComprasLabel(user.areaDisplay);
      final isDireccionGeneral = isDireccionGeneralLabel(user.areaDisplay);
      final isContabilidad = isContabilidadLabel(user.areaDisplay);
      if (!isAdminRole(user.role) &&
          !isCompras &&
          !isDireccionGeneral &&
          !isContabilidad) {
        return Stream.value(const <PurchaseOrder>[]);
      }
      final cacheScope = _profileCacheScope(ref, user);
      final repository = ref.watch(purchaseOrderRepositoryProvider);
      return _withCachedOrders(
        key: '$cacheScope:operationalOrders',
        source: repository.watchAllOrders(),
      );
    });

final cotizacionesOrdersPagedProvider = StreamProvider.autoDispose
    .family<List<PurchaseOrder>, int>((ref, limit) {
      _cacheProviderForSession(ref);
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
      final cacheScope = _profileCacheScope(ref, user);
      final repository = ref.watch(purchaseOrderRepositoryProvider);
      return _withCachedOrders(
        key: '$cacheScope:cotizacionesOrdersPaged:$limit',
        source: repository.watchOrdersByStatus(
          PurchaseOrderStatus.cotizaciones,
          limit: limit,
        ),
      );
    });

final supplierQuotesProvider = StreamProvider.autoDispose<List<SupplierQuote>>((
  ref,
) {
  _cacheProviderForSession(ref);
  if (_awaitingProfile(ref)) {
    return const Stream.empty();
  }
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return Stream.value(const <SupplierQuote>[]);
  }
  final isCompras = isComprasLabel(user.areaDisplay);
  final isDireccionGeneral = isDireccionGeneralLabel(user.areaDisplay);
  final isContabilidad = isContabilidadLabel(user.areaDisplay);
  if (!isAdminRole(user.role) &&
      !isCompras &&
      !isDireccionGeneral &&
      !isContabilidad) {
    return Stream.value(const <SupplierQuote>[]);
  }
  final cacheScope = _profileCacheScope(ref, user);
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return _withCachedSupplierQuotes(
    key: '$cacheScope:supplierQuotes',
    source: repository.watchSupplierQuotes(),
  );
});

final supplierQuoteByIdProvider = StreamProvider.autoDispose
    .family<SupplierQuote?, String>((ref, quoteId) {
      _cacheProviderForSession(ref);
      final repository = ref.watch(purchaseOrderRepositoryProvider);
      return repository.watchSupplierQuoteById(quoteId);
    });

final supplierQuoteHistoryProvider = StreamProvider.autoDispose
    .family<List<SupplierQuoteHistoryEntry>, String>((ref, quoteId) {
      final repository = ref.watch(purchaseOrderRepositoryProvider);
      return repository.watchSupplierQuoteHistory(quoteId);
    });

final supplierQuotesByOrderIdProvider = Provider.autoDispose
    .family<AsyncValue<List<SupplierQuote>>, String>((ref, orderId) {
      final quotesAsync = ref.watch(supplierQuotesProvider);
      return quotesAsync.whenData(
        (quotes) => quotes
            .where((quote) => quote.orderIds.contains(orderId))
            .toList(growable: false),
      );
    });

final pendingEtaOrdersProvider =
    StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
      _cacheProviderForSession(ref);
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
      final cacheScope = _profileCacheScope(ref, user);
      final repository = ref.watch(purchaseOrderRepositoryProvider);
      return _withCachedOrders(
        key: '$cacheScope:pendingEtaOrders',
        source: repository.watchOrdersByStatus(PurchaseOrderStatus.paymentDone),
      );
    });

final pendingEtaOrdersPagedProvider = StreamProvider.autoDispose
    .family<List<PurchaseOrder>, int>((ref, limit) {
      _cacheProviderForSession(ref);
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
      final cacheScope = _profileCacheScope(ref, user);
      final repository = ref.watch(purchaseOrderRepositoryProvider);
      return _withCachedOrders(
        key: '$cacheScope:pendingEtaOrdersPaged:$limit',
        source: repository.watchOrdersByStatus(
          PurchaseOrderStatus.paymentDone,
          limit: limit,
        ),
      );
    });

final contabilidadOrdersProvider =
    StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
      _cacheProviderForSession(ref);
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
      final cacheScope = _profileCacheScope(ref, user);
      final repository = ref.watch(purchaseOrderRepositoryProvider);
      return _withCachedOrders(
        key: '$cacheScope:contabilidadOrders',
        source: repository.watchAllOrders().map(_filterContabilidadOrders),
      );
    });

final contabilidadOrdersPagedProvider = StreamProvider.autoDispose
    .family<List<PurchaseOrder>, int>((ref, limit) {
      _cacheProviderForSession(ref);
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
      final cacheScope = _profileCacheScope(ref, user);
      final repository = ref.watch(purchaseOrderRepositoryProvider);
      return _withCachedOrders(
        key: '$cacheScope:contabilidadOrdersPaged:$limit',
        source: repository.watchAllOrders().map((orders) {
          final filtered = _filterContabilidadOrders(orders);
          if (limit <= 0 || filtered.length <= limit) {
            return filtered;
          }
          return filtered.take(limit).toList(growable: false);
        }),
      );
    });

final rejectedOrdersProvider = StreamProvider.autoDispose<List<PurchaseOrder>>((
  ref,
) {
  _cacheProviderForSession(ref);
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return _withCachedOrders(
    key: '${_cacheScope(ref)}:rejectedOrders:$uid',
    source: repository.watchOrdersForUser(uid).map(_filterRejectedDraftOrders),
  );
});

final globalActionMonitoringOrdersProvider =
    StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
      _cacheProviderForSession(ref);
      if (_awaitingProfile(ref)) {
        return const Stream.empty();
      }
      final user = ref.watch(currentUserProfileProvider).value;
      if (user == null) {
        return Stream.value(const <PurchaseOrder>[]);
      }
      final isCompras = isComprasLabel(user.areaDisplay);
      final isDireccionGeneral = isDireccionGeneralLabel(user.areaDisplay);
      if (!isAdminRole(user.role) && !isCompras && !isDireccionGeneral) {
        return Stream.value(const <PurchaseOrder>[]);
      }
      final cacheScope = _profileCacheScope(ref, user);
      final repository = ref.watch(purchaseOrderRepositoryProvider);
      return _withCachedOrders(
        key: '$cacheScope:globalActionMonitoringOrders',
        source: repository.watchAllOrders().map(_filterGlobalMonitoringOrders),
      );
    });

final rejectedOrdersPagedProvider = StreamProvider.autoDispose
    .family<List<PurchaseOrder>, int>((ref, limit) {
      _cacheProviderForSession(ref);
      final uid = ref.watch(currentUserIdProvider);
      if (uid == null) {
        return Stream.value(const <PurchaseOrder>[]);
      }
      final repository = ref.watch(purchaseOrderRepositoryProvider);
      return _withCachedOrders(
        key: '${_cacheScope(ref)}:rejectedOrdersPaged:$uid:$limit',
        source: repository.watchOrdersForUser(uid).map((orders) {
          final rejected = _filterRejectedDraftOrders(orders);
          if (limit <= 0 || rejected.length <= limit) {
            return rejected;
          }
          return rejected.take(limit).toList(growable: false);
        }),
      );
    });

final homeDashboardCountsProvider =
    StreamProvider.autoDispose<OrderDashboardCounts?>((ref) {
      _cacheProviderForSession(ref);
      final repository = ref.watch(purchaseOrderRepositoryProvider);
      final uid = ref.watch(currentUserIdProvider);
      return _withCachedDashboardCounts(
        key: '${_cacheScope(ref)}:homeDashboardCounts:${uid ?? 'guest'}',
        source: repository.watchDashboardCounts(userId: uid),
      );
    });

AsyncValue<int> _countFromDashboardOrOrders(
  Ref ref, {
  required int Function(OrderDashboardCounts counts) selector,
  required ProviderListenable<AsyncValue<List<PurchaseOrder>>> fallbackProvider,
}) {
  final countsAsync = ref.watch(homeDashboardCountsProvider);
  final counts = countsAsync.valueOrNull;
  if (counts?.hasRemoteCounters == true) {
    return countsAsync.whenData((value) => value == null ? 0 : selector(value));
  }
  final ordersAsync = ref.watch(fallbackProvider);
  return ordersAsync.whenData((orders) => orders.length);
}

final pendingComprasCountProvider = Provider.autoDispose<AsyncValue<int>>((
  ref,
) {
  return _countFromDashboardOrOrders(
    ref,
    selector: (counts) => counts.pendingCompras,
    fallbackProvider: pendingComprasOrdersProvider,
  );
});

final cotizacionesCountProvider = Provider.autoDispose<AsyncValue<int>>((ref) {
  return _countFromDashboardOrOrders(
    ref,
    selector: (counts) => counts.cotizaciones,
    fallbackProvider: cotizacionesOrdersProvider,
  );
});

final cotizacionesModuleCountProvider = Provider.autoDispose<AsyncValue<int>>((
  ref,
) {
  final pendingOrdersAsync = ref.watch(cotizacionesOrdersProvider);
  final dashboardOrdersAsync = ref.watch(dataCompleteOrdersProvider);
  final quotesAsync = ref.watch(supplierQuotesProvider);

  if (pendingOrdersAsync.hasError) {
    return AsyncValue<int>.error(
      pendingOrdersAsync.error!,
      pendingOrdersAsync.stackTrace ?? StackTrace.current,
    );
  }
  if (dashboardOrdersAsync.hasError) {
    return AsyncValue<int>.error(
      dashboardOrdersAsync.error!,
      dashboardOrdersAsync.stackTrace ?? StackTrace.current,
    );
  }
  if (quotesAsync.hasError) {
    return AsyncValue<int>.error(
      quotesAsync.error!,
      quotesAsync.stackTrace ?? StackTrace.current,
    );
  }

  final pendingOrders = pendingOrdersAsync.valueOrNull;
  final dashboardOrders = dashboardOrdersAsync.valueOrNull;
  final quotes = quotesAsync.valueOrNull;
  if (pendingOrders == null || dashboardOrders == null || quotes == null) {
    return const AsyncValue<int>.loading();
  }

  final pendingCount = pendingOrders.length;
  final dashboardCount = dashboardOrders.where(_orderNeedsSupplierQuote).length;
  final activeQuotes = quotes
      .where(
        (quote) =>
            quote.status == SupplierQuoteStatus.draft ||
            quote.status == SupplierQuoteStatus.rejected,
      )
      .length;
  return AsyncValue<int>.data(pendingCount + dashboardCount + activeQuotes);
});

final cotizacionesReadyToSendCountProvider =
    Provider.autoDispose<AsyncValue<int>>((ref) {
      final quotesAsync = ref.watch(supplierQuotesProvider);
      return quotesAsync.whenData(
        (quotes) => quotes
            .where(
              (quote) =>
                  quote.status == SupplierQuoteStatus.draft &&
                  quote.items.isNotEmpty &&
                  quote.links.isNotEmpty,
            )
            .length,
      );
    });

final pendingDireccionCountProvider = Provider.autoDispose<AsyncValue<int>>((ref) {
  final quotesAsync = ref.watch(supplierQuotesProvider);
  return quotesAsync.whenData(
    (quotes) => quotes
        .where((quote) => quote.status == SupplierQuoteStatus.pendingDireccion)
        .length,
  );
});

final pendingDireccionBundleCountProvider =
    Provider.autoDispose<AsyncValue<int>>((ref) {
      final quotesAsync = ref.watch(supplierQuotesProvider);
      return quotesAsync.whenData(
        (quotes) => quotes
            .where(
              (quote) => quote.status == SupplierQuoteStatus.pendingDireccion,
            )
            .length,
      );
    });

final pendingEtaCountProvider = Provider.autoDispose<AsyncValue<int>>((ref) {
  final quotesAsync = ref.watch(supplierQuotesProvider);
  final ordersAsync = ref.watch(operationalOrdersProvider);

  if (quotesAsync.hasError) {
    return AsyncValue<int>.error(
      quotesAsync.error!,
      quotesAsync.stackTrace ?? StackTrace.current,
    );
  }
  if (ordersAsync.hasError) {
    return AsyncValue<int>.error(
      ordersAsync.error!,
      ordersAsync.stackTrace ?? StackTrace.current,
    );
  }

  final quotes = quotesAsync.valueOrNull;
  final orders = ordersAsync.valueOrNull;
  if (quotes == null || orders == null) {
    return const AsyncValue<int>.loading();
  }

  final ordersById = {
    for (final order in orders) order.id: order,
  };
  final pendingCount = quotes.where((quote) {
    if (quote.status != SupplierQuoteStatus.approved) return false;
    for (final orderId in quote.orderIds) {
      final order = ordersById[orderId];
      if (order == null) continue;
      final hasPendingEta = order.items.any(
        (item) =>
            (item.quoteId?.trim() ?? '') == quote.id &&
            item.quoteStatus == PurchaseOrderItemQuoteStatus.approved &&
            item.deliveryEtaDate == null,
      );
      if (hasPendingEta) return true;
    }
    return false;
  }).length;

  return AsyncValue<int>.data(pendingCount);
});

final userInProcessOrdersCountProvider = Provider.autoDispose<AsyncValue<int>>((
  ref,
) {
  final ordersAsync = ref.watch(userOrdersProvider);
  return ordersAsync.whenData(
    (orders) => orders.where(_isUserInProcessOrder).length,
  );
});

final contabilidadCountProvider = Provider.autoDispose<AsyncValue<int>>((ref) {
  return _countFromDashboardOrOrders(
    ref,
    selector: (counts) => counts.contabilidad,
    fallbackProvider: contabilidadOrdersProvider,
  );
});

final monitoringOrdersCountProvider = Provider.autoDispose<AsyncValue<int>>((
  ref,
) {
  final ordersAsync = ref.watch(monitoringOrdersProvider);
  return ordersAsync.whenData(
    (orders) => orders.where(_isMonitoringVisibleOrder).length,
  );
});

final rejectedCountProvider = Provider.autoDispose<AsyncValue<int>>((ref) {
  return _countFromDashboardOrOrders(
    ref,
    selector: (counts) => counts.rejected,
    fallbackProvider: rejectedOrdersProvider,
  );
});

final globalActionMonitoringCountProvider = Provider.autoDispose<AsyncValue<int>>((
  ref,
) {
  final ordersAsync = ref.watch(globalActionMonitoringOrdersProvider);
  return ordersAsync.whenData((orders) => orders.length);
});

bool _orderNeedsSupplierQuote(PurchaseOrder order) {
  if (order.items.isEmpty) return false;
  return order.items.any((item) {
    final supplier = (item.supplier ?? '').trim();
    final budget = item.budget ?? 0;
    final missingAssignment = supplier.isEmpty || budget <= 0;
    final missingQuote =
        item.quoteId == null ||
        item.quoteStatus == PurchaseOrderItemQuoteStatus.rejected;
    return missingAssignment || missingQuote;
  });
}

bool _isMonitoringVisibleOrder(PurchaseOrder order) {
  if (!order.isDraft) return true;
  final reason = order.lastReturnReason?.trim() ?? '';
  return order.status == PurchaseOrderStatus.draft &&
      (reason.isNotEmpty || order.returnCount > 0);
}
