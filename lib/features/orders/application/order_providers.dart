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
import 'package:sistema_compras/features/orders/domain/shared_quote.dart';

bool _awaitingProfile(Ref ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return false;
  return ref.watch(currentUserProfileProvider).value == null;
}

const _sessionCacheDuration = Duration(minutes: 4);
final _sessionSnapshotCache = <String, Object?>{};

String _orderSnapshotKey(String scope, String orderId) =>
    '$scope:orderById:$orderId';
String _orderEventsSnapshotKey(String scope, String orderId) =>
    '$scope:orderEvents:$orderId';

String _companyCacheScope(Ref ref) => ref.watch(currentCompanyProvider).name;

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
  return [
    order.id,
    order.companyId ?? '',
    order.status.name,
    updatedAt.toString(),
    createdAt.toString(),
    order.returnCount.toString(),
    order.direccionReturnCount.toString(),
    (order.cotizacionReady ?? false).toString(),
    order.items.length.toString(),
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

String _sharedQuoteSignature(SharedQuote quote) {
  final updatedAt = quote.updatedAt?.millisecondsSinceEpoch ?? 0;
  final approvedAt = quote.approvedAt?.millisecondsSinceEpoch ?? 0;
  return [
    quote.id,
    quote.version.toString(),
    updatedAt.toString(),
    approvedAt.toString(),
    quote.needsUpdate.toString(),
    quote.orderIds.length.toString(),
    quote.approvedOrderIds.length.toString(),
    quote.pdfUrl,
  ].join('|');
}

bool _sameSharedQuoteList(List<SharedQuote> a, List<SharedQuote> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (_sharedQuoteSignature(a[index]) != _sharedQuoteSignature(b[index])) {
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
      a.almacen == b.almacen &&
      a.rejected == b.rejected &&
      a.hasRemoteCounters == b.hasRemoteCounters;
}

bool _isRejectedDraftOrder(PurchaseOrder order) {
  final reason = order.lastReturnReason;
  return order.status == PurchaseOrderStatus.draft &&
      reason != null &&
      reason.trim().isNotEmpty;
}

List<PurchaseOrder> _filterRejectedDraftOrders(List<PurchaseOrder> orders) {
  return orders.where(_isRejectedDraftOrder).toList(growable: false);
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

Stream<List<SharedQuote>> _withCachedSharedQuotes({
  required String key,
  required Stream<List<SharedQuote>> source,
}) async* {
  List<SharedQuote>? lastEmitted;
  final cached = _sessionSnapshotCache[key];
  if (cached is List<SharedQuote>) {
    lastEmitted = cached;
    yield cached;
  } else {
    final persisted = await OrderLocalSnapshotStore.readSharedQuotes(key);
    if (persisted != null) {
      final snapshot = List<SharedQuote>.unmodifiable(persisted);
      _sessionSnapshotCache[key] = snapshot;
      lastEmitted = snapshot;
      yield snapshot;
    }
  }

  await for (final quotes in source) {
    final snapshot = List<SharedQuote>.unmodifiable(quotes);
    _sessionSnapshotCache[key] = snapshot;
    unawaited(OrderLocalSnapshotStore.writeSharedQuotes(key, quotes));
    if (lastEmitted != null && _sameSharedQuoteList(lastEmitted, snapshot)) {
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

final comprasDashboardAllOrdersProvider =
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
        key: '$cacheScope:comprasDashboardAllOrders',
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

final sharedQuotesProvider = StreamProvider.autoDispose<List<SharedQuote>>((
  ref,
) {
  _cacheProviderForSession(ref);
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
  final cacheScope = _profileCacheScope(ref, user);
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return _withCachedSharedQuotes(
    key: '$cacheScope:sharedQuotes',
    source: repository.watchSharedQuotes(),
  );
});

final sharedQuoteByIdProvider = StreamProvider.autoDispose
    .family<SharedQuote?, String>((ref, quoteId) {
      _cacheProviderForSession(ref);
      final repository = ref.watch(purchaseOrderRepositoryProvider);
      return repository.watchSharedQuoteById(quoteId);
    });

final pendingDireccionOrdersProvider =
    StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
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
        key: '$cacheScope:pendingDireccionOrders',
        source: repository.watchOrdersByStatus(
          PurchaseOrderStatus.authorizedGerencia,
        ),
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
        source: repository.watchOrdersByStatus(
          PurchaseOrderStatus.contabilidad,
        ),
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
        source: repository.watchOrdersByStatus(
          PurchaseOrderStatus.contabilidad,
          limit: limit,
        ),
      );
    });

final almacenOrdersProvider = StreamProvider.autoDispose<List<PurchaseOrder>>((
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
  final isAlmacen = isAlmacenLabel(user.areaDisplay);
  if (!isAdminRole(user.role) && !isAlmacen) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final cacheScope = _profileCacheScope(ref, user);
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return _withCachedOrders(
    key: '$cacheScope:almacenOrders',
    source: repository.watchOrdersByStatus(PurchaseOrderStatus.almacen),
  );
});

final almacenOrdersPagedProvider = StreamProvider.autoDispose
    .family<List<PurchaseOrder>, int>((ref, limit) {
      _cacheProviderForSession(ref);
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
      final cacheScope = _profileCacheScope(ref, user);
      final repository = ref.watch(purchaseOrderRepositoryProvider);
      return _withCachedOrders(
        key: '$cacheScope:almacenOrdersPaged:$limit',
        source: repository.watchOrdersByStatus(
          PurchaseOrderStatus.almacen,
          limit: limit,
        ),
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
  final ordersAsync = ref.watch(cotizacionesOrdersProvider);
  final allOrdersAsync = ref.watch(comprasDashboardAllOrdersProvider);
  final bundlesAsync = ref.watch(sharedQuotesProvider);

  if (ordersAsync.hasError) {
    return AsyncValue<int>.error(
      ordersAsync.error!,
      ordersAsync.stackTrace ?? StackTrace.current,
    );
  }
  if (allOrdersAsync.hasError) {
    return AsyncValue<int>.error(
      allOrdersAsync.error!,
      allOrdersAsync.stackTrace ?? StackTrace.current,
    );
  }
  if (bundlesAsync.hasError) {
    return AsyncValue<int>.error(
      bundlesAsync.error!,
      bundlesAsync.stackTrace ?? StackTrace.current,
    );
  }

  final orders = ordersAsync.valueOrNull;
  final allOrders = allOrdersAsync.valueOrNull;
  final bundles = bundlesAsync.valueOrNull;
  if (orders == null || allOrders == null || bundles == null) {
    return const AsyncValue<int>.loading();
  }

  final pendingCount = orders.where((order) => order.cotizacionReady != true).length;
  final readyOrderIds = orders
      .where(_cotizacionesDashboardOrderReady)
      .map((order) => order.id)
      .toSet();
  final ordersById = {for (final order in allOrders) order.id: order};
  final bundlesCount = bundles.where((bundle) {
    if (bundle.orderIds.any(readyOrderIds.contains)) return true;
    return bundle.needsUpdate &&
        bundle.rejectedOrderIds.isNotEmpty &&
        bundle.orderIds.any(ordersById.containsKey);
  }).length;

  return AsyncValue<int>.data(pendingCount + bundlesCount);
});

final cotizacionesReadyToSendCountProvider =
    Provider.autoDispose<AsyncValue<int>>((ref) {
      final countsAsync = ref.watch(homeDashboardCountsProvider);
      final counts = countsAsync.valueOrNull;
      if (counts?.hasRemoteCounters == true) {
        return countsAsync.whenData(
          (value) => value?.cotizacionesReadyToSend ?? 0,
        );
      }
      final ordersAsync = ref.watch(cotizacionesOrdersProvider);
      return ordersAsync.whenData((orders) {
        var count = 0;
        for (final order in orders) {
          if (_orderReadyToSend(order)) {
            count += 1;
          }
        }
        return count;
      });
    });

final pendingDireccionCountProvider = Provider.autoDispose<AsyncValue<int>>((
  ref,
) {
  return _countFromDashboardOrOrders(
    ref,
    selector: (counts) => counts.pendingDireccion,
    fallbackProvider: pendingDireccionOrdersProvider,
  );
});

final pendingDireccionBundleCountProvider =
    Provider.autoDispose<AsyncValue<int>>((ref) {
      final ordersAsync = ref.watch(pendingDireccionOrdersProvider);
      final bundlesAsync = ref.watch(sharedQuotesProvider);

      if (ordersAsync.hasError) {
        return AsyncValue<int>.error(
          ordersAsync.error!,
          ordersAsync.stackTrace ?? StackTrace.current,
        );
      }
      if (bundlesAsync.hasError) {
        return AsyncValue<int>.error(
          bundlesAsync.error!,
          bundlesAsync.stackTrace ?? StackTrace.current,
        );
      }

      final orders = ordersAsync.valueOrNull;
      final bundles = bundlesAsync.valueOrNull;
      if (orders == null || bundles == null) {
        return const AsyncValue<int>.loading();
      }

      final ordersById = {for (final order in orders) order.id: order};
      final count = bundles.where((bundle) {
        if (bundle.needsUpdate) return false;
        return bundle.orderIds.any(
          (id) =>
              ordersById.containsKey(id) &&
              !bundle.approvedOrderIds.contains(id),
        );
      }).length;

      return AsyncValue<int>.data(count);
    });

final pendingEtaCountProvider = Provider.autoDispose<AsyncValue<int>>((ref) {
  return _countFromDashboardOrOrders(
    ref,
    selector: (counts) => counts.pendingEta,
    fallbackProvider: pendingEtaOrdersProvider,
  );
});

final contabilidadCountProvider = Provider.autoDispose<AsyncValue<int>>((ref) {
  return _countFromDashboardOrOrders(
    ref,
    selector: (counts) => counts.contabilidad,
    fallbackProvider: contabilidadOrdersProvider,
  );
});

final almacenCountProvider = Provider.autoDispose<AsyncValue<int>>((ref) {
  return _countFromDashboardOrOrders(
    ref,
    selector: (counts) => counts.almacen,
    fallbackProvider: almacenOrdersProvider,
  );
});

final rejectedCountProvider = Provider.autoDispose<AsyncValue<int>>((ref) {
  return _countFromDashboardOrOrders(
    ref,
    selector: (counts) => counts.rejected,
    fallbackProvider: rejectedOrdersProvider,
  );
});

bool _orderReadyToSend(PurchaseOrder order) {
  if (order.items.isEmpty) return false;
  if (!order.cotizacionLinks.any((link) => link.url.trim().isNotEmpty)) {
    return false;
  }
  return order.items.every((item) {
    final supplier = (item.supplier ?? '').trim();
    final budget = item.budget ?? 0;
    return supplier.isNotEmpty && budget > 0;
  });
}

bool _cotizacionesDashboardOrderReady(PurchaseOrder order) {
  if (order.items.isEmpty) return false;
  if (order.cotizacionReady != true) return false;
  return order.items.every((item) {
    final supplier = (item.supplier ?? '').trim();
    final budget = item.budget ?? 0;
    return supplier.isNotEmpty && budget > 0;
  });
}
