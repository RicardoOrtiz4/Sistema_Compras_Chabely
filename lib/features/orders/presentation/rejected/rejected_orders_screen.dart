import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_pdf_preload_gate.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_status_duration.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_urgency_controls.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

class RejectedOrdersScreen extends ConsumerStatefulWidget {
  const RejectedOrdersScreen({super.key});

  @override
  ConsumerState<RejectedOrdersScreen> createState() =>
      _RejectedOrdersScreenState();
}

class _RejectedOrdersScreenState extends ConsumerState<RejectedOrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _activeTabIndex = 0;
  OrderUrgencyFilter _pendingUrgencyFilter = OrderUrgencyFilter.all;
  OrderUrgencyFilter _acknowledgedUrgencyFilter = OrderUrgencyFilter.all;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    final nextIndex = _tabController.index;
    if (_activeTabIndex == nextIndex) return;
    setState(() => _activeTabIndex = nextIndex);
  }

  OrderUrgencyFilter get _activeUrgencyFilter => _activeTabIndex == 0
      ? _pendingUrgencyFilter
      : _acknowledgedUrgencyFilter;

  void _setPendingUrgencyFilter(OrderUrgencyFilter filter) {
    setState(() => _pendingUrgencyFilter = filter);
  }

  void _setAcknowledgedUrgencyFilter(OrderUrgencyFilter filter) {
    setState(() => _acknowledgedUrgencyFilter = filter);
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(rejectedOrdersProvider);
    final allOrders = ordersAsync.valueOrNull ?? const <PurchaseOrder>[];
    final pendingCount = allOrders
        .where((order) => order.isRejectedPendingAcknowledgment)
        .length;
    final acknowledgedCount = allOrders.length - pendingCount;

    final compactAppBar = useCompactOrderModuleAppBar(context);
    final pendingOrders = allOrders
        .where((order) => order.isRejectedPendingAcknowledgment)
        .toList(growable: false);
    final acknowledgedOrders = allOrders
        .where((order) => !order.isRejectedPendingAcknowledgment)
        .toList(growable: false);
    final activeOrders =
        _activeTabIndex == 0 ? pendingOrders : acknowledgedOrders;
    final activeCounts = OrderUrgencyCounts.fromOrders(activeOrders);

    return Scaffold(
      appBar: AppBar(
        title: compactAppBar
            ? const Text('Ordenes rechazadas')
            : OrderModuleAppBarTitle(
                title: 'Ordenes rechazadas',
                counts: activeCounts,
                filter: _activeUrgencyFilter,
                onSelected: _activeTabIndex == 0
                    ? _setPendingUrgencyFilter
                    : _setAcknowledgedUrgencyFilter,
              ),
        bottom: _RejectedOrdersAppBarBottom(
          controller: _tabController,
          compactAppBar: compactAppBar,
          counts: activeCounts,
          filter: _activeUrgencyFilter,
          onSelected: _activeTabIndex == 0
              ? _setPendingUrgencyFilter
              : _setAcknowledgedUrgencyFilter,
          pendingCount: pendingCount,
          acknowledgedCount: acknowledgedCount,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              guardedGo(context, '/home');
            }
          },
        ),
      ),
      body: ordersAsync.when(
        data: (orders) {
          final sortedOrders = List<PurchaseOrder>.from(orders)
            ..sort(_compareRejectedOrdersByRecency);
          final pendingOrders = sortedOrders
              .where((order) => order.isRejectedPendingAcknowledgment)
              .toList(growable: false);
          final acknowledgedOrders = sortedOrders
              .where((order) => !order.isRejectedPendingAcknowledgment)
              .toList(growable: false);

          return TabBarView(
            controller: _tabController,
            children: [
              _RejectedOrdersTabPane(
                key: const PageStorageKey<String>('rejected-pending'),
                orders: pendingOrders,
                emptyText:
                    'No hay ordenes rechazadas pendientes de enterado con ese filtro.',
                description:
                    'Aqui se concentran los rechazos que todavia no confirmas como enterados.',
                acknowledgedSection: false,
                urgencyFilter: _pendingUrgencyFilter,
              ),
              _RejectedOrdersTabPane(
                key: const PageStorageKey<String>('rejected-acknowledged'),
                orders: acknowledgedOrders,
                emptyText: 'No hay ordenes enteradas con ese filtro.',
                description:
                    'Aqui quedan las rechazadas que ya confirmaste como enteradas. Siguen disponibles para PDF y Copiar.',
                acknowledgedSection: true,
                urgencyFilter: _acknowledgedUrgencyFilter,
              ),
            ],
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            'Error: ${reportError(error, stack, context: 'RejectedOrdersScreen')}',
          ),
        ),
      ),
    );
  }
}

class _RejectedOrdersTabBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _RejectedOrdersTabBar({
    required this.controller,
    required this.pendingCount,
    required this.acknowledgedCount,
  });

  final TabController controller;
  final int pendingCount;
  final int acknowledgedCount;

  @override
  Size get preferredSize => const Size.fromHeight(kTextTabBarHeight);

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: controller,
      tabs: [
        Tab(text: 'No enteradas ($pendingCount)'),
        Tab(text: 'Enteradas ($acknowledgedCount)'),
      ],
    );
  }
}

class _RejectedOrdersAppBarBottom extends StatelessWidget
    implements PreferredSizeWidget {
  const _RejectedOrdersAppBarBottom({
    required this.controller,
    required this.compactAppBar,
    required this.counts,
    required this.filter,
    required this.onSelected,
    required this.pendingCount,
    required this.acknowledgedCount,
  });

  final TabController controller;
  final bool compactAppBar;
  final OrderUrgencyCounts counts;
  final OrderUrgencyFilter filter;
  final ValueChanged<OrderUrgencyFilter> onSelected;
  final int pendingCount;
  final int acknowledgedCount;

  @override
  Size get preferredSize => Size.fromHeight(
    kTextTabBarHeight + (compactAppBar ? 60 : 0),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (compactAppBar)
          OrderModuleAppBarBottom(
            counts: counts,
            filter: filter,
            onSelected: onSelected,
          ),
        _RejectedOrdersTabBar(
          controller: controller,
          pendingCount: pendingCount,
          acknowledgedCount: acknowledgedCount,
        ),
      ],
    );
  }
}

class _RejectedOrdersTabPane extends StatefulWidget {
  const _RejectedOrdersTabPane({
    required this.orders,
    required this.emptyText,
    required this.description,
    required this.acknowledgedSection,
    required this.urgencyFilter,
    super.key,
  });

  final List<PurchaseOrder> orders;
  final String emptyText;
  final String description;
  final bool acknowledgedSection;
  final OrderUrgencyFilter urgencyFilter;

  @override
  State<_RejectedOrdersTabPane> createState() => _RejectedOrdersTabPaneState();
}

class _RejectedOrdersTabPaneState extends State<_RejectedOrdersTabPane> {
  List<PurchaseOrder>? _cachedSourceOrders;
  String? _cachedVisibleKey;
  List<PurchaseOrder>? _cachedVisibleOrders;

  late final TextEditingController _searchController;
  final OrderSearchCache _searchCache = OrderSearchCache();
  Timer? _searchDebounce;
  String _searchQuery = '';
  DateTimeRange? _createdDateRangeFilter;
  int _limit = defaultOrderPageSize;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _RejectedOrdersTabPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urgencyFilter != widget.urgencyFilter) {
      _cachedVisibleKey = null;
      _cachedVisibleOrders = null;
      _limit = defaultOrderPageSize;
    }
  }

  void _updateSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _searchDebounce = null;
      setState(() {
        _searchQuery = value;
        _limit = defaultOrderPageSize;
      });
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = null;
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _limit = defaultOrderPageSize;
    });
  }

  Future<void> _pickCreatedDateFilter() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      currentDate: now,
      initialDateRange: _createdDateRangeFilter,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _createdDateRangeFilter = DateTimeRange(
        start: DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        ),
        end: DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
        ),
      );
      _limit = defaultOrderPageSize;
    });
  }

  void _clearCreatedDateFilter() {
    if (_createdDateRangeFilter == null) return;
    setState(() {
      _createdDateRangeFilter = null;
      _limit = defaultOrderPageSize;
    });
  }

  void _loadMore() {
    setState(() => _limit += orderPageSizeStep);
  }

  @override
  Widget build(BuildContext context) {
    _searchCache.retainFor(widget.orders);
    final filtered = _resolveVisibleOrders(widget.orders);
    final visibleOrders = filtered.take(_limit).toList(growable: false);
    final showLoadMore = filtered.length > visibleOrders.length;

    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 720;
              final searchField = TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Buscar por folio, solicitante o area',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _clearSearch,
                        ),
                ),
                onChanged: _updateSearch,
              );
              final dateFilter = OrderDateRangeFilterButton(
                selectedRange: _createdDateRangeFilter,
                onPickDate: _pickCreatedDateFilter,
                onClearDate: _clearCreatedDateFilter,
              );
              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchField,
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: dateFilter,
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 12),
                  dateFilter,
                ],
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(widget.description),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: visibleOrders.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.acknowledgedSection
                              ? Icons.task_alt_outlined
                              : Icons.notifications_active_outlined,
                          size: 44,
                        ),
                        const SizedBox(height: 12),
                        Text(widget.emptyText, textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: visibleOrders.length + (showLoadMore ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    if (index >= visibleOrders.length) {
                      return Center(
                        child: OutlinedButton.icon(
                          onPressed: _loadMore,
                          icon: const Icon(Icons.expand_more),
                          label: const Text('Ver mas'),
                        ),
                      );
                    }
                    return _RejectedOrderCard(
                      order: visibleOrders[index],
                      acknowledgedStyle: widget.acknowledgedSection,
                    );
                  },
                ),
        ),
      ],
    );

    return OrderPdfPreloadGate(
      orders: visibleOrders,
      enabled: _searchDebounce == null && _searchQuery.trim().isEmpty,
      child: content,
    );
  }

  List<PurchaseOrder> _resolveVisibleOrders(List<PurchaseOrder> orders) {
    final key = _visibleOrdersKey();
    final cached = _cachedVisibleOrders;
    if (cached != null &&
        identical(_cachedSourceOrders, orders) &&
        _cachedVisibleKey == key) {
      return cached;
    }

    final trimmedQuery = _searchQuery.trim();
    final resolved = trimmedQuery.isEmpty
        ? orders
        : orders
            .where(
              (order) => orderMatchesSearch(
                order,
                trimmedQuery,
                cache: _searchCache,
                includeDates: false,
              ),
            )
            .toList(growable: false);
    final dateFiltered = resolved
        .where(
          (order) =>
              matchesOrderCreatedDateRange(order, _createdDateRangeFilter),
        )
        .toList(growable: false);
    final urgencyFiltered = dateFiltered
        .where(
          (order) => matchesOrderUrgencyFilter(order, widget.urgencyFilter),
        )
        .toList(growable: false);

    _cachedSourceOrders = orders;
    _cachedVisibleKey = key;
    _cachedVisibleOrders = urgencyFiltered;
    return urgencyFiltered;
  }

  String _visibleOrdersKey() =>
      '${_searchQuery.trim().toLowerCase()}|${widget.urgencyFilter.name}|'
      '${_createdDateRangeFilter?.start.millisecondsSinceEpoch ?? ''}|'
      '${_createdDateRangeFilter?.end.millisecondsSinceEpoch ?? ''}';
}

class _RejectedOrderCard extends ConsumerStatefulWidget {
  const _RejectedOrderCard({
    required this.order,
    required this.acknowledgedStyle,
  });

  final PurchaseOrder order;
  final bool acknowledgedStyle;

  @override
  ConsumerState<_RejectedOrderCard> createState() => _RejectedOrderCardState();
}

class _RejectedOrderCardState extends ConsumerState<_RejectedOrderCard> {
  bool _acknowledging = false;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isAcknowledgedStyle = widget.acknowledgedStyle;
    final reason = (order.lastReturnReason ?? '').trim();
    final scheme = Theme.of(context).colorScheme;
    final eventsAsync = ref.watch(orderEventsProvider(order.id));
    final lastReturn = eventsAsync.maybeWhen(
      data: _lastReturnEvent,
      orElse: () => null,
    );
    final actorNamesById = {
      for (final user in ref.watch(allUsersProvider).valueOrNull ?? const <AppUser>[])
        user.id: user.name,
    };
    final previousStatusLabel = _rejectedFromLabel(
      order.lastReturnFromStatus ?? lastReturn?.fromStatus,
    );
    final cardColor = isAcknowledgedStyle ? Colors.green.shade50 : null;
    final cardBorderColor = isAcknowledgedStyle
        ? Colors.green.shade200
        : scheme.outlineVariant;
    final messageBackground = isAcknowledgedStyle
        ? Colors.green.shade100
        : scheme.errorContainer.withValues(alpha: 0.7);
    final messageBorderColor = isAcknowledgedStyle
        ? Colors.green.shade300
        : scheme.error.withValues(alpha: 0.35);
    final messageTextColor = isAcknowledgedStyle
        ? Colors.green.shade900
        : scheme.onErrorContainer;
    final statusChipBackground = isAcknowledgedStyle
        ? Colors.green.shade100
        : scheme.errorContainer.withValues(alpha: 0.5);
    final statusChipBorderColor = isAcknowledgedStyle
        ? Colors.green.shade300
        : scheme.error.withValues(alpha: 0.25);

    return Card(
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cardBorderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    'Rechazada por ${_rejectedActorLabel(lastReturn, actorNamesById)}',
                  ),
                ),
                Chip(
                  backgroundColor: statusChipBackground,
                  side: BorderSide(color: statusChipBorderColor),
                  avatar: Icon(
                    order.isRejectedPendingAcknowledgment
                        ? Icons.notifications_active_outlined
                        : Icons.task_alt_outlined,
                    size: 18,
                  ),
                  label: Text(
                    order.isRejectedPendingAcknowledgment
                        ? 'No enterada'
                        : 'Enterada ${order.rejectionAcknowledgedAt?.toShortDate() ?? ''}'
                              .trim(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: messageBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: messageBorderColor,
                ),
              ),
              child: Text(
                reason.isEmpty ? 'Sin comentario' : reason,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: messageTextColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 6),
            _RejectedReviewTimePill(
              order: order,
              previousStatusLabel: previousStatusLabel,
              eventsAsync: eventsAsync,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => guardedPdfPush(context, '/orders/${order.id}/pdf'),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Ver PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: () => guardedPush(
                    context,
                    _copyOrderLocation(order.id),
                  ),
                  icon: const Icon(Icons.content_copy_outlined),
                  label: const Text('Copiar'),
                ),
                if (order.isRejectedPendingAcknowledgment)
                  FilledButton.icon(
                    onPressed: _acknowledging
                        ? null
                        : () => _acknowledgeRejectedOrder(order),
                    icon: _acknowledging
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.task_alt_outlined),
                    label: const Text('Marcar como enterado'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _acknowledgeRejectedOrder(PurchaseOrder order) async {
    if (_acknowledging) return;
    setState(() => _acknowledging = true);
    try {
      await ref
          .read(purchaseOrderRepositoryProvider)
          .acknowledgeRejectedOrder(order.id);
      refreshOrderModuleData(ref, orderIds: <String>[order.id]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La orden rechazada se marco como enterada.'),
        ),
      );
    } catch (error, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo marcar como enterada: ${reportError(error, stack, context: 'RejectedOrdersScreen.acknowledge')}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _acknowledging = false);
      }
    }
  }
}

class _RejectedReviewTimePill extends StatelessWidget {
  const _RejectedReviewTimePill({
    required this.order,
    required this.previousStatusLabel,
    required this.eventsAsync,
  });

  final PurchaseOrder order;
  final String previousStatusLabel;
  final AsyncValue<List<PurchaseOrderEvent>> eventsAsync;

  @override
  Widget build(BuildContext context) {
    final explicitDuration = order.lastReviewDurationMs;
    final explicitPreviousStatus = order.lastReturnFromStatus;
    if (explicitDuration != null &&
        explicitDuration >= 0 &&
        explicitPreviousStatus != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusDurationPill(
            text:
                'Tiempo en revision: ${formatDurationLabel(Duration(milliseconds: explicitDuration))}',
            alignRight: true,
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
          ),
        ],
      );
    }

    return eventsAsync.when(
      data: (events) {
        final duration = _reviewDurationForLastReturn(events, order);
        if (duration == null) {
          return Text(
            'Tiempo en revision no disponible.',
            style: Theme.of(context).textTheme.bodySmall,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusDurationPill(
              text: 'Tiempo en revision: ${formatDurationLabel(duration)}',
              alignRight: true,
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

PurchaseOrderEvent? _lastReturnEvent(List<PurchaseOrderEvent> events) {
  PurchaseOrderEvent? latest;
  for (final event in events) {
    if (event.type == 'return') latest = event;
  }
  return latest;
}

int _compareRejectedOrdersByRecency(PurchaseOrder left, PurchaseOrder right) {
  final leftEpoch =
      (left.updatedAt ?? left.createdAt)?.millisecondsSinceEpoch ?? 0;
  final rightEpoch =
      (right.updatedAt ?? right.createdAt)?.millisecondsSinceEpoch ?? 0;
  return rightEpoch.compareTo(leftEpoch);
}

Duration? _reviewDurationForLastReturn(
  List<PurchaseOrderEvent> events,
  PurchaseOrder order,
) {
  final explicitReviewDurationMs = order.lastReviewDurationMs;
  if (explicitReviewDurationMs != null && explicitReviewDurationMs >= 0) {
    return Duration(milliseconds: explicitReviewDurationMs);
  }

  final lastReturn = _lastReturnEvent(events);
  final targetTimestamp = lastReturn?.timestamp;
  final previousStatus = order.lastReturnFromStatus ?? lastReturn?.fromStatus;
  if (previousStatus != null) {
    final committedMillis = order.statusDurations[previousStatus.name] ?? 0;
    if (committedMillis > 0) {
      return Duration(milliseconds: committedMillis);
    }
  }

  if (targetTimestamp == null) return null;

  if (previousStatus != null) {
    for (final event in events.reversed) {
      if (identical(event, lastReturn)) continue;
      if (event.toStatus != previousStatus || event.timestamp == null) continue;
      if (event.timestamp!.isAfter(targetTimestamp)) continue;
      final duration = targetTimestamp.difference(event.timestamp!);
      if (!duration.isNegative) return duration;
    }
  }

  final createdAt = order.createdAt;
  if (createdAt == null || createdAt.isAfter(targetTimestamp)) {
    return null;
  }
  final duration = targetTimestamp.difference(createdAt);
  return duration.isNegative ? null : duration;
}

String _rejectedByLabel(String? rawRole) {
  final normalized = normalizeAreaLabel((rawRole ?? '').trim());
  if (normalized.isEmpty) {
    return 'Sin registro';
  }
  if (isComprasLabel(normalized)) {
    return 'Operacion';
  }
  if (isDireccionGeneralLabel(normalized)) {
    return 'Validacion';
  }
  return normalized;
}

String _rejectedActorLabel(
  PurchaseOrderEvent? event,
  Map<String, String> actorNamesById,
) {
  if (event == null) return 'Sin registro';
  final actorId = event.byUser.trim();
  final actorName = actorId.isEmpty ? '' : (actorNamesById[actorId]?.trim() ?? actorId);
  final role = _rejectedByLabel(event.byRole);
  if (actorName.isEmpty) return role;
  if (role == 'Sin registro') return actorName;
  return '$actorName ($role)';
}

String _rejectedFromLabel(PurchaseOrderStatus? status) {
  switch (status) {
    case PurchaseOrderStatus.intakeReview:
      return PurchaseOrderStatus.intakeReview.label;
    case PurchaseOrderStatus.sourcing:
      return PurchaseOrderStatus.sourcing.label;
    case PurchaseOrderStatus.readyForApproval:
      return PurchaseOrderStatus.readyForApproval.label;
    case PurchaseOrderStatus.approvalQueue:
      return PurchaseOrderStatus.approvalQueue.label;
    case PurchaseOrderStatus.paymentDone:
      return PurchaseOrderStatus.paymentDone.label;
    case PurchaseOrderStatus.contabilidad:
      return PurchaseOrderStatus.contabilidad.label;
    case PurchaseOrderStatus.orderPlaced:
      return 'orden realizada';
    case PurchaseOrderStatus.eta:
      return 'orden finalizada';
    case PurchaseOrderStatus.draft:
    case null:
      return 'revision';
  }
}

String _copyOrderLocation(String orderId) {
  return Uri(
    path: '/orders/create',
    queryParameters: {'copyFromId': orderId},
  ).toString();
}
