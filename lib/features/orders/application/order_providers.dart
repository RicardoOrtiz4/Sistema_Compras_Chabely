import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import 'package:sistema_compras/core/access_control.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/order_dashboard_counts.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/purchase_packets/application/purchase_packet_use_cases.dart';
import 'package:sistema_compras/features/purchase_packets/domain/purchase_packet_domain.dart';

bool _awaitingProfile(Ref ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return false;
  return ref.watch(currentUserProfileProvider).value == null;
}

const _sessionCacheDuration = Duration(minutes: 4);
const _sharedOrderDataScope = sharedCompanyDataId;
final _sessionSnapshotCache = <String, Object?>{};
final _intakeReviewTransitionHiddenOrderIds = <String>{};
final _sourcingTransitionHiddenOrderIds = <String>{};

bool get useManualOrderRefreshOnWindowsRelease => false;

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

void markPendingComprasOrdersAsMoved(Iterable<String> orderIds) {
  _intakeReviewTransitionHiddenOrderIds.addAll(
    orderIds.map((id) => id.trim()).where((id) => id.isNotEmpty),
  );
}

void unmarkPendingComprasOrdersAsMoved(Iterable<String> orderIds) {
  for (final orderId in orderIds.map((id) => id.trim()).where((id) => id.isNotEmpty)) {
    _intakeReviewTransitionHiddenOrderIds.remove(orderId);
  }
}

void markCotizacionesOrdersAsMoved(Iterable<String> orderIds) {
  _sourcingTransitionHiddenOrderIds.addAll(
    orderIds.map((id) => id.trim()).where((id) => id.isNotEmpty),
  );
}

void unmarkCotizacionesOrdersAsMoved(Iterable<String> orderIds) {
  for (final orderId in orderIds.map((id) => id.trim()).where((id) => id.isNotEmpty)) {
    _sourcingTransitionHiddenOrderIds.remove(orderId);
  }
}

void refreshOrderModuleDataFromContainer(
  ProviderContainer container, {
  Iterable<String> orderIds = const <String>[],
}) {
  clearOrderSessionSnapshotCache();

  container.invalidate(userOrdersProvider);
  container.invalidate(allOrdersProvider);
  container.invalidate(historyAllOrdersProvider);
  container.invalidate(monitoringOrdersProvider);
  container.invalidate(operationalOrdersProvider);
  container.invalidate(intakeReviewOrdersProvider);
  container.invalidate(sourcingOrdersProvider);
  container.invalidate(readyForApprovalOrdersProvider);
  container.invalidate(rejectedOrdersProvider);
  container.invalidate(rejectedAllOrdersProvider);
  container.invalidate(homeDashboardCountsProvider);

  for (final orderId in orderIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet()) {
    container.invalidate(orderByIdStreamProvider(orderId));
    container.invalidate(orderEventsProvider(orderId));
  }
}

void refreshOrderModuleTransitionDataFromContainer(
  ProviderContainer container, {
  Iterable<String> orderIds = const <String>[],
}) {
  clearOrderSessionSnapshotCache();

  container.invalidate(userOrdersProvider);
  container.invalidate(_sharedAllOrdersProvider);
  container.invalidate(allOrdersProvider);
  container.invalidate(historyAllOrdersProvider);
  container.invalidate(operationalOrdersProvider);
  container.invalidate(intakeReviewOrdersProvider);
  container.invalidate(sourcingOrdersProvider);
  container.invalidate(readyForApprovalOrdersProvider);
  container.invalidate(rejectedOrdersProvider);
  container.invalidate(rejectedAllOrdersProvider);
  container.invalidate(homeDashboardCountsProvider);

  for (final orderId in orderIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet()) {
    container.invalidate(orderByIdStreamProvider(orderId));
    container.invalidate(orderEventsProvider(orderId));
  }
}

void refreshOrderModuleData(
  WidgetRef ref, {
  Iterable<String> orderIds = const <String>[],
}) {
  clearOrderSessionSnapshotCache();

  ref.invalidate(userOrdersProvider);
  ref.invalidate(allOrdersProvider);
  ref.invalidate(historyAllOrdersProvider);
  ref.invalidate(monitoringOrdersProvider);
  ref.invalidate(operationalOrdersProvider);
  ref.invalidate(intakeReviewOrdersProvider);
  ref.invalidate(sourcingOrdersProvider);
  ref.invalidate(readyForApprovalOrdersProvider);
  ref.invalidate(rejectedOrdersProvider);
  ref.invalidate(rejectedAllOrdersProvider);
  ref.invalidate(homeDashboardCountsProvider);

  for (final orderId in orderIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet()) {
    ref.invalidate(orderByIdStreamProvider(orderId));
    ref.invalidate(orderEventsProvider(orderId));
  }
}

void refreshOrderModuleTransitionData(
  WidgetRef ref, {
  Iterable<String> orderIds = const <String>[],
}) {
  clearOrderSessionSnapshotCache();

  ref.invalidate(userOrdersProvider);
  ref.invalidate(_sharedAllOrdersProvider);
  ref.invalidate(allOrdersProvider);
  ref.invalidate(historyAllOrdersProvider);
  ref.invalidate(operationalOrdersProvider);
  ref.invalidate(intakeReviewOrdersProvider);
  ref.invalidate(sourcingOrdersProvider);
  ref.invalidate(readyForApprovalOrdersProvider);
  ref.invalidate(rejectedOrdersProvider);
  ref.invalidate(rejectedAllOrdersProvider);
  ref.invalidate(homeDashboardCountsProvider);

  for (final orderId in orderIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet()) {
    ref.invalidate(orderByIdStreamProvider(orderId));
    ref.invalidate(orderEventsProvider(orderId));
  }
}

void refreshRequesterReceiptWorkflowData(
  WidgetRef ref, {
  Iterable<String> orderIds = const <String>[],
}) {
  clearOrderSessionSnapshotCache();

  ref.invalidate(userOrdersProvider);
  ref.invalidate(homeDashboardCountsProvider);

  for (final orderId in orderIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet()) {
    ref.invalidate(orderByIdStreamProvider(orderId));
    ref.invalidate(orderEventsProvider(orderId));
  }
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
  final itemsSignature = ([...order.items]..sort((left, right) => left.line.compareTo(right.line)))
      .map((item) {
        final estimatedDate = item.estimatedDate?.millisecondsSinceEpoch ?? 0;
        final deliveryEtaDate = item.deliveryEtaDate?.millisecondsSinceEpoch ?? 0;
        final sentToContabilidadAt =
            item.sentToContabilidadAt?.millisecondsSinceEpoch ?? 0;
        final arrivedAt = item.arrivedAt?.millisecondsSinceEpoch ?? 0;
        final notPurchasedAt =
            item.notPurchasedAt?.millisecondsSinceEpoch ?? 0;
        return [
          item.line.toString(),
          item.pieces.toString(),
          item.partNumber,
          item.description,
          item.quantity.toString(),
          item.unit,
          item.customer ?? '',
          item.supplier ?? '',
          item.budget?.toString() ?? '',
          item.internalOrder ?? '',
          estimatedDate.toString(),
          deliveryEtaDate.toString(),
          sentToContabilidadAt.toString(),
          arrivedAt.toString(),
          item.arrivedByName ?? '',
          item.arrivedByArea ?? '',
          item.reviewFlagged ? '1' : '0',
          item.reviewComment ?? '',
          item.notPurchasedReason ?? '',
          notPurchasedAt.toString(),
          item.notPurchasedByName ?? '',
          item.notPurchasedByArea ?? '',
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
    order.lastReturnReason ?? '',
    order.lastReturnFromStatus?.name ?? '',
    order.rejectionAcknowledgedAt?.millisecondsSinceEpoch.toString() ?? '',
    order.lastReviewDurationMs?.toString() ?? '',
    order.returnCount.toString(),
    order.requesterId,
    order.requesterName,
    order.areaId,
    order.areaName,
    order.urgency.name,
    order.clientNote ?? '',
    order.urgentJustification ?? '',
    order.supplier ?? '',
    order.internalOrder ?? '',
    order.budget?.toString() ?? '',
    (order.supplierBudgets.entries.toList()
          ..sort((left, right) => left.key.compareTo(right.key)))
        .map((entry) => '${entry.key}=${entry.value}')
        .join(','),
    order.requestedDeliveryDate?.millisecondsSinceEpoch.toString() ?? '',
    order.etaDate?.millisecondsSinceEpoch.toString() ?? '',
    order.facturaPdfUrl ?? '',
    order.facturaPdfUrls.join(','),
    order.pdfUrl ?? '',
    order.authorizedByName ?? '',
    order.authorizedByArea ?? '',
    order.authorizedAt?.millisecondsSinceEpoch.toString() ?? '',
    order.processByName ?? '',
    order.processByArea ?? '',
    order.processAt?.millisecondsSinceEpoch.toString() ?? '',
    order.resubmissionDates
        .map((date) => date.millisecondsSinceEpoch.toString())
        .join(','),
    (order.statusDurations.entries.toList()
          ..sort((left, right) => left.key.compareTo(right.key)))
        .map((entry) => '${entry.key}=${entry.value}')
        .join(','),
    order.statusEnteredAt?.millisecondsSinceEpoch.toString() ?? '',
    order.contabilidadName ?? '',
    order.contabilidadArea ?? '',
    order.facturaUploadedAt?.millisecondsSinceEpoch.toString() ?? '',
    order.materialArrivedAt?.millisecondsSinceEpoch.toString() ?? '',
    order.materialArrivedName ?? '',
    order.materialArrivedArea ?? '',
    order.completedAt?.millisecondsSinceEpoch.toString() ?? '',
    order.requesterReceivedAt?.millisecondsSinceEpoch.toString() ?? '',
    order.requesterReceivedName ?? '',
    order.requesterReceivedArea ?? '',
    order.requesterReceiptAutoConfirmed ? '1' : '0',
    order.isDraft ? '1' : '0',
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

bool _sameDashboardCounts(OrderDashboardCounts? a, OrderDashboardCounts? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  return a.intakeReview == b.intakeReview &&
      a.sourcing == b.sourcing &&
      a.sourcingReadyToSend == b.sourcingReadyToSend &&
      a.pendingDireccion == b.pendingDireccion &&
      a.pendingEta == b.pendingEta &&
      a.contabilidad == b.contabilidad &&
      a.hasRemoteCounters == b.hasRemoteCounters;
}

bool _isRejectedDraftOrder(PurchaseOrder order) {
  return order.isRejectedDraft;
}

List<PurchaseOrder> _filterRejectedDraftOrders(List<PurchaseOrder> orders) {
  return orders.where(_isRejectedDraftOrder).toList(growable: false);
}

int _countRejectedOrdersPendingAcknowledgment(List<PurchaseOrder> orders) {
  return orders.where((order) => order.isRejectedPendingAcknowledgment).length;
}

bool _isUserInProcessOrder(PurchaseOrder order) {
  return order.status != PurchaseOrderStatus.draft && !order.isWorkflowFinished;
}

List<PurchaseOrder> _filterOrdersByStatus(
  List<PurchaseOrder> orders,
  PurchaseOrderStatus status,
) {
  return orders
      .where((order) => order.status == status)
      .toList(growable: false);
}

List<PurchaseOrder> _filterPendingComprasOrdersWithTransitionExclusions(
  List<PurchaseOrder> orders,
) {
  final visible = <PurchaseOrder>[];
  final presentOrderIds = <String>{};

  for (final order in orders) {
    presentOrderIds.add(order.id);
    final isVisiblePendingOrder = order.status == PurchaseOrderStatus.intakeReview;
    if (!isVisiblePendingOrder) {
      _intakeReviewTransitionHiddenOrderIds.remove(order.id);
      continue;
    }
    if (_intakeReviewTransitionHiddenOrderIds.contains(order.id)) {
      continue;
    }
    visible.add(order);
  }

  _intakeReviewTransitionHiddenOrderIds.removeWhere(
    (orderId) => !presentOrderIds.contains(orderId),
  );

  return visible;
}

List<PurchaseOrder> _filterCotizacionesOrdersWithTransitionExclusions(
  List<PurchaseOrder> orders,
) {
  final visible = <PurchaseOrder>[];
  final presentOrderIds = <String>{};

  for (final order in orders) {
    presentOrderIds.add(order.id);
    if (order.status != PurchaseOrderStatus.sourcing) {
      _sourcingTransitionHiddenOrderIds.remove(order.id);
      continue;
    }
    if (_sourcingTransitionHiddenOrderIds.contains(order.id)) {
      continue;
    }
    visible.add(order);
  }

  _sourcingTransitionHiddenOrderIds.removeWhere(
    (orderId) => !presentOrderIds.contains(orderId),
  );

  return visible;
}

Stream<List<PurchaseOrder>> _withCachedOrders({
  required String key,
  required Stream<List<PurchaseOrder>> source,
}) async* {
  if (useManualOrderRefreshOnWindowsRelease) {
    yield* _withLiveOrders(source);
    return;
  }
  final scope = _companyScopeFromKey(key);
  List<PurchaseOrder>? lastEmitted;

  await for (final orders in source) {
    final snapshot = List<PurchaseOrder>.unmodifiable(orders);
    _sessionSnapshotCache[key] = snapshot;
    for (final order in snapshot) {
      _sessionSnapshotCache[_orderSnapshotKey(scope, order.id)] = order;
    }
    if (lastEmitted != null && _sameOrderList(lastEmitted, snapshot)) {
      continue;
    }
    lastEmitted = snapshot;
    yield snapshot;
  }
}

Stream<List<PurchaseOrder>> _withLiveOrders(Stream<List<PurchaseOrder>> source) async* {
  await for (final orders in source) {
    yield List<PurchaseOrder>.unmodifiable(orders);
  }
}

List<PurchaseOrder> _filterOrdersByStatusLimited(
  List<PurchaseOrder> orders,
  PurchaseOrderStatus status, {
  int? limit,
}) {
  final filtered = _filterOrdersByStatus(orders, status);
  if (limit == null || limit <= 0 || filtered.length <= limit) {
    return filtered;
  }
  return filtered.take(limit).toList(growable: false);
}

Stream<OrderDashboardCounts?> _withCachedDashboardCounts({
  required String key,
  required Stream<OrderDashboardCounts?> source,
}) async* {
  if (useManualOrderRefreshOnWindowsRelease) {
    yield* source;
    return;
  }
  OrderDashboardCounts? lastEmitted;

  await for (final counts in source) {
    if (counts != null) {
      _sessionSnapshotCache[key] = counts;
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
  if (useManualOrderRefreshOnWindowsRelease) {
    yield* source;
    return;
  }
  final cacheKey = _orderSnapshotKey(scope, orderId);
  PurchaseOrder? lastEmitted;

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
  if (useManualOrderRefreshOnWindowsRelease) {
    await for (final events in source) {
      yield List<PurchaseOrderEvent>.unmodifiable(events);
    }
    return;
  }
  final cacheKey = _orderEventsSnapshotKey(scope, orderId);
  List<PurchaseOrderEvent>? lastEmitted;

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
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  if (!canViewOperationalOrders(user)) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final ordersAsync = ref.watch(_sharedAllOrdersProvider);
  return ordersAsync.when(
    data: (orders) => Stream.value(orders),
    loading: () => const Stream.empty(),
    error: (_, __) => Stream.value(const <PurchaseOrder>[]),
  );
});

final historyAllOrdersProvider = StreamProvider.autoDispose<List<PurchaseOrder>>((
  ref,
) {
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  if (!canViewGlobalHistory(user)) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final ordersAsync = ref.watch(_sharedAllOrdersProvider);
  return ordersAsync.when(
    data: (orders) => Stream.value(orders),
    loading: () => const Stream.empty(),
    error: (_, __) => Stream.value(const <PurchaseOrder>[]),
  );
});

final monitoringOrdersProvider = StreamProvider.autoDispose<List<PurchaseOrder>>(
  (ref) {
    final user = ref.watch(currentUserProfileProvider).value;
    if (user == null) {
      return Stream.value(const <PurchaseOrder>[]);
    }
    if (!canViewMonitoring(user)) {
      return Stream.value(const <PurchaseOrder>[]);
    }
    final ordersAsync = ref.watch(_sharedAllOrdersProvider);
    return ordersAsync.when(
      data: (orders) => Stream.value(orders),
      loading: () => const Stream.empty(),
      error: (_, __) => Stream.value(const <PurchaseOrder>[]),
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
      if (!canViewOperationalOrders(user)) {
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

final _sharedAllOrdersProvider = StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
  _cacheProviderForSession(ref);
  if (_awaitingProfile(ref)) {
    return const Stream.empty();
  }
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) {
    return Stream.value(const <PurchaseOrder>[]);
  }
  final cacheScope = _profileCacheScope(ref, user);
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  if (useManualOrderRefreshOnWindowsRelease) {
    return _withLiveOrders(repository.watchAllOrders());
  }
  return _withCachedOrders(
    key: '$cacheScope:sharedAllOrders',
    source: repository.watchAllOrders(),
  );
});

final intakeReviewOrdersProvider =
    StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
      final user = ref.watch(currentUserProfileProvider).value;
      if (user == null || !hasAuthorizeOrdersAccess(user)) {
        return Stream.value(const <PurchaseOrder>[]);
      }
      final ordersAsync = ref.watch(_sharedAllOrdersProvider);
      return ordersAsync.when(
        data: (orders) => Stream.value(
          _filterPendingComprasOrdersWithTransitionExclusions(orders),
        ),
        loading: () => const Stream.empty(),
        error: (_, __) => Stream.value(const <PurchaseOrder>[]),
      );
    });

final intakeReviewOrdersPagedProvider = StreamProvider.autoDispose
    .family<List<PurchaseOrder>, int>((ref, limit) {
      final ordersAsync = ref.watch(intakeReviewOrdersProvider);
      return ordersAsync.when(
        data: (orders) => Stream.value(
          _filterOrdersByStatusLimited(
            orders,
            PurchaseOrderStatus.intakeReview,
            limit: limit,
          ),
        ),
        loading: () => const Stream.empty(),
        error: (_, __) => Stream.value(const <PurchaseOrder>[]),
      );
    });

final sourcingOrdersProvider =
    StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
      final user = ref.watch(currentUserProfileProvider).value;
      if (user == null || !hasComprasAccess(user)) {
        return Stream.value(const <PurchaseOrder>[]);
      }
      final ordersAsync = ref.watch(_sharedAllOrdersProvider);
      return ordersAsync.when(
        data: (orders) => Stream.value(
          _filterCotizacionesOrdersWithTransitionExclusions(orders),
        ),
        loading: () => const Stream.empty(),
        error: (_, __) => Stream.value(const <PurchaseOrder>[]),
      );
    });

final readyForApprovalOrdersProvider =
    StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
      final user = ref.watch(currentUserProfileProvider).value;
      if (user == null || !hasComprasAccess(user)) {
        return Stream.value(const <PurchaseOrder>[]);
      }
      final ordersAsync = ref.watch(_sharedAllOrdersProvider);
      return ordersAsync.when(
        data: (orders) => Stream.value(
          _filterOrdersByStatus(orders, PurchaseOrderStatus.readyForApproval),
        ),
        loading: () => const Stream.empty(),
        error: (_, __) => Stream.value(const <PurchaseOrder>[]),
      );
    });

final operationalOrdersProvider =
    StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
      final user = ref.watch(currentUserProfileProvider).value;
      if (user == null) {
        return Stream.value(const <PurchaseOrder>[]);
      }
      if (!canViewOperationalOrders(user)) {
        return Stream.value(const <PurchaseOrder>[]);
      }
      final ordersAsync = ref.watch(_sharedAllOrdersProvider);
      return ordersAsync.when(
        data: (orders) => Stream.value(orders),
        loading: () => const Stream.empty(),
        error: (_, __) => Stream.value(const <PurchaseOrder>[]),
      );
    });

final sourcingOrdersPagedProvider = StreamProvider.autoDispose
    .family<List<PurchaseOrder>, int>((ref, limit) {
      final ordersAsync = ref.watch(sourcingOrdersProvider);
      return ordersAsync.when(
        data: (orders) => Stream.value(
          _filterOrdersByStatusLimited(
            orders,
            PurchaseOrderStatus.sourcing,
            limit: limit,
          ),
        ),
        loading: () => const Stream.empty(),
        error: (_, __) => Stream.value(const <PurchaseOrder>[]),
      );
    });

final pendingEtaOrdersProvider =
    StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
      final user = ref.watch(currentUserProfileProvider).value;
      if (user == null || !hasEtaAccess(user)) {
        return Stream.value(const <PurchaseOrder>[]);
      }
      final ordersAsync = ref.watch(_sharedAllOrdersProvider);
      return ordersAsync.when(
        data: (orders) => Stream.value(
          _filterOrdersByStatus(orders, PurchaseOrderStatus.paymentDone),
        ),
        loading: () => const Stream.empty(),
        error: (_, __) => Stream.value(const <PurchaseOrder>[]),
      );
    });

final pendingEtaOrdersPagedProvider = StreamProvider.autoDispose
    .family<List<PurchaseOrder>, int>((ref, limit) {
      final ordersAsync = ref.watch(pendingEtaOrdersProvider);
      return ordersAsync.when(
        data: (orders) => Stream.value(
          _filterOrdersByStatusLimited(
            orders,
            PurchaseOrderStatus.paymentDone,
            limit: limit,
          ),
        ),
        loading: () => const Stream.empty(),
        error: (_, __) => Stream.value(const <PurchaseOrder>[]),
      );
    });

final contabilidadOrdersProvider =
    StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
      final user = ref.watch(currentUserProfileProvider).value;
      if (user == null || !hasFacturasEvidenciasAccess(user)) {
        return Stream.value(const <PurchaseOrder>[]);
      }
      final ordersAsync = ref.watch(_sharedAllOrdersProvider);
      return ordersAsync.when(
        data: (orders) => Stream.value(
          _filterOrdersByStatus(orders, PurchaseOrderStatus.contabilidad),
        ),
        loading: () => const Stream.empty(),
        error: (_, __) => Stream.value(const <PurchaseOrder>[]),
      );
    });

final contabilidadOrdersPagedProvider = StreamProvider.autoDispose
    .family<List<PurchaseOrder>, int>((ref, limit) {
      final ordersAsync = ref.watch(contabilidadOrdersProvider);
      return ordersAsync.when(
        data: (orders) => Stream.value(
          _filterOrdersByStatusLimited(
            orders,
            PurchaseOrderStatus.contabilidad,
            limit: limit,
          ),
        ),
        loading: () => const Stream.empty(),
        error: (_, __) => Stream.value(const <PurchaseOrder>[]),
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

final rejectedAllOrdersProvider =
    StreamProvider.autoDispose<List<PurchaseOrder>>((ref) {
      final user = ref.watch(currentUserProfileProvider).value;
      if (user == null) {
        return Stream.value(const <PurchaseOrder>[]);
      }
      if (!canViewGlobalRejected(user)) {
        return Stream.value(const <PurchaseOrder>[]);
      }
      final ordersAsync = ref.watch(_sharedAllOrdersProvider);
      return ordersAsync.when(
        data: (orders) => Stream.value(_filterRejectedDraftOrders(orders)),
        loading: () => const Stream.empty(),
        error: (_, __) => Stream.value(const <PurchaseOrder>[]),
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
  if (!useManualOrderRefreshOnWindowsRelease &&
      counts?.hasRemoteCounters == true) {
    return countsAsync.whenData((value) => value == null ? 0 : selector(value));
  }
  final ordersAsync = ref.watch(fallbackProvider);
  return ordersAsync.whenData((orders) => orders.length);
}

final intakeReviewCountProvider = Provider.autoDispose<AsyncValue<int>>((
  ref,
) {
  return _countFromDashboardOrOrders(
    ref,
    selector: (counts) => counts.intakeReview,
    fallbackProvider: intakeReviewOrdersProvider,
  );
});

final sourcingCountProvider = Provider.autoDispose<AsyncValue<int>>((ref) {
  return _countFromDashboardOrOrders(
    ref,
    selector: (counts) => counts.sourcing,
    fallbackProvider: sourcingOrdersProvider,
  );
});

final sourcingModuleCountProvider = Provider.autoDispose<AsyncValue<int>>((
  ref,
) {
  final pendingAsync = ref.watch(sourcingOrdersProvider);
  final dashboardAsync = ref.watch(readyForApprovalOrdersProvider);
  return pendingAsync.whenData(
    (pendingOrders) =>
        pendingOrders.length + (dashboardAsync.valueOrNull?.length ?? 0),
  );
});

final sourcingDashboardTabCountProvider =
    Provider.autoDispose<AsyncValue<int>>((ref) {
      final ordersAsync = ref.watch(readyForApprovalOrdersProvider);
      return ordersAsync.whenData((orders) => orders.length);
    });

final sourcingReadyToSendCountProvider =
    Provider.autoDispose<AsyncValue<int>>((ref) {
      final ordersAsync = ref.watch(readyForApprovalOrdersProvider);
      return ordersAsync.whenData((orders) => orders.length);
    });

final pendingDireccionCountProvider = Provider.autoDispose<AsyncValue<int>>((ref) {
  return _countFromDashboardOrOrders(
    ref,
    selector: (counts) => counts.pendingDireccion,
    fallbackProvider: readyForApprovalOrdersProvider,
  );
});

final pendingDireccionBundleCountProvider =
    Provider.autoDispose<AsyncValue<int>>((ref) {
      return const AsyncValue<int>.data(0);
    });

final pendingEtaCountProvider = Provider.autoDispose<AsyncValue<int>>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null || !hasEtaAccess(user)) {
    return const AsyncValue<int>.data(0);
  }
  final packetsAsync = ref.watch(packetBundlesProvider);
  final ordersAsync = ref.watch(allOrdersProvider);
  return packetsAsync.whenData((bundles) {
    final orders = ordersAsync.valueOrNull;
    if (orders == null) return 0;
    final ordersById = <String, PurchaseOrder>{
      for (final order in orders) order.id: order,
    };
    return bundles
        .where((bundle) => bundle.packet.status == PurchasePacketStatus.executionReady)
        .where((bundle) => _bundleHasPendingEtaWork(bundle, ordersById))
        .length;
  });
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

bool _bundleHasPendingEtaWork(
  PacketBundle bundle,
  Map<String, PurchaseOrder> ordersById,
) {
  for (final packetItem in bundle.packet.itemRefs) {
    final order = ordersById[packetItem.orderId];
    if (order == null) continue;
    final orderItem = _resolvePacketOrderItem(order, packetItem);
    if (orderItem == null || !orderItem.requiresFulfillment) continue;
    if (orderItem.deliveryEtaDate == null || orderItem.sentToContabilidadAt == null) {
      return true;
    }
  }
  return false;
}

PurchaseOrderItem? _resolvePacketOrderItem(
  PurchaseOrder order,
  PacketItemRef packetItem,
) {
  for (final item in order.items) {
    if (packetItem.lineNumber > 0 && item.line == packetItem.lineNumber) {
      return item;
    }
  }
  final fallbackLine = _packetItemLineFromId(packetItem.itemId);
  if (fallbackLine == null) return null;
  for (final item in order.items) {
    if (item.line == fallbackLine) return item;
  }
  return null;
}

int? _packetItemLineFromId(String rawItemId) {
  final trimmed = rawItemId.trim();
  if (trimmed.startsWith('line_')) {
    return int.tryParse(trimmed.substring(5));
  }
  return int.tryParse(trimmed);
}

final rejectedCountProvider = Provider.autoDispose<AsyncValue<int>>((ref) {
  final ordersAsync = ref.watch(rejectedOrdersProvider);
  return ordersAsync.whenData(_countRejectedOrdersPendingAcknowledgment);
});

bool _isMonitoringVisibleOrder(PurchaseOrder order) {
  return !order.isDraft && !order.isWorkflowFinished;
}
