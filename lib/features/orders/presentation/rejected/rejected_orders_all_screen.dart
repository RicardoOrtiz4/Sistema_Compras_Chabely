import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/access_control.dart';
import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/navigation_guard.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/core/widgets/searchable_select.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/history/order_history_shared.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_pdf_preload_gate.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_status_duration.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_urgency_controls.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

class RejectedOrdersAllScreen extends ConsumerStatefulWidget {
  const RejectedOrdersAllScreen({super.key});

  @override
  ConsumerState<RejectedOrdersAllScreen> createState() =>
      _RejectedOrdersAllScreenState();
}

class _RejectedOrdersAllScreenState
    extends ConsumerState<RejectedOrdersAllScreen>
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
    final profileAsync = ref.watch(currentUserProfileProvider);
    final ordersAsync = ref.watch(rejectedAllOrdersProvider);
    final user = profileAsync.value;
    final canViewAll = canViewGlobalRejected(user);
    final allOrders = ordersAsync.valueOrNull ?? const <PurchaseOrder>[];
    final pendingOrders = allOrders
        .where((order) => order.isRejectedPendingAcknowledgment)
        .toList(growable: false);
    final acknowledgedOrders = allOrders
        .where((order) => !order.isRejectedPendingAcknowledgment)
        .toList(growable: false);
    final activeOrders =
        _activeTabIndex == 0 ? pendingOrders : acknowledgedOrders;
    final compactAppBar = useCompactOrderModuleAppBar(context);

    if (profileAsync.isLoading) {
      return const Scaffold(body: AppSplash());
    }

    return Scaffold(
      appBar: AppBar(
        title: compactAppBar
            ? const Text('Rechazadas generales')
            : OrderModuleAppBarTitle(
                title: 'Rechazadas generales',
                counts: OrderUrgencyCounts.fromOrders(activeOrders),
                filter: _activeUrgencyFilter,
                onSelected: _activeTabIndex == 0
                    ? _setPendingUrgencyFilter
                    : _setAcknowledgedUrgencyFilter,
              ),
        bottom: _RejectedAllAppBarBottom(
          controller: _tabController,
          compactAppBar: compactAppBar,
          counts: OrderUrgencyCounts.fromOrders(activeOrders),
          filter: _activeUrgencyFilter,
          onSelected: _activeTabIndex == 0
              ? _setPendingUrgencyFilter
              : _setAcknowledgedUrgencyFilter,
          pendingCount: pendingOrders.length,
          acknowledgedCount: acknowledgedOrders.length,
        ),
      ),
      body: !canViewAll
          ? const HistoryEmptyState(
              icon: Icons.lock_outline,
              title: 'Sin permiso para esta vista',
              message:
                  'Solo perfiles operativos y administrativos pueden revisar las rechazadas generales.',
            )
          : ordersAsync.when(
              data: (orders) {
                final sortedOrders = List<PurchaseOrder>.from(orders)
                  ..sort(_compareRejectedOrdersByRecency);
                final pending = sortedOrders
                    .where((order) => order.isRejectedPendingAcknowledgment)
                    .toList(growable: false);
                final acknowledged = sortedOrders
                    .where((order) => !order.isRejectedPendingAcknowledgment)
                    .toList(growable: false);
                return TabBarView(
                  controller: _tabController,
                  children: [
                    _RejectedOrdersAllTabPane(
                      key: const PageStorageKey<String>('rejected-all-pending'),
                      orders: pending,
                      urgencyFilter: _pendingUrgencyFilter,
                      emptyText:
                          'No hay ordenes rechazadas no enteradas con ese filtro.',
                      description:
                          'Aqui ves los rechazos que aun no han sido marcados como enterados por sus solicitantes.',
                      acknowledgedSection: false,
                    ),
                    _RejectedOrdersAllTabPane(
                      key: const PageStorageKey<String>(
                        'rejected-all-acknowledged',
                      ),
                      orders: acknowledged,
                      urgencyFilter: _acknowledgedUrgencyFilter,
                      emptyText:
                          'No hay ordenes rechazadas enteradas con ese filtro.',
                      description:
                          'Aqui ves los rechazos que el usuario ya marco como enterados.',
                      acknowledgedSection: true,
                    ),
                  ],
                );
              },
              loading: () => const AppSplash(),
              error: (error, stack) => Center(
                child: Text(
                  'Error: ${reportError(error, stack, context: 'RejectedOrdersAllScreen')}',
                ),
              ),
            ),
    );
  }
}

class _RejectedAllAppBarBottom extends StatelessWidget
    implements PreferredSizeWidget {
  const _RejectedAllAppBarBottom({
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
  Size get preferredSize =>
      Size.fromHeight(kTextTabBarHeight + (compactAppBar ? 60 : 0));

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
        TabBar(
          controller: controller,
          tabs: [
            Tab(text: 'No enteradas ($pendingCount)'),
            Tab(text: 'Enteradas ($acknowledgedCount)'),
          ],
        ),
      ],
    );
  }
}

class _RejectedOrdersAllTabPane extends StatefulWidget {
  const _RejectedOrdersAllTabPane({
    required this.orders,
    required this.urgencyFilter,
    required this.emptyText,
    required this.description,
    required this.acknowledgedSection,
    super.key,
  });

  final List<PurchaseOrder> orders;
  final OrderUrgencyFilter urgencyFilter;
  final String emptyText;
  final String description;
  final bool acknowledgedSection;

  @override
  State<_RejectedOrdersAllTabPane> createState() =>
      _RejectedOrdersAllTabPaneState();
}

class _RejectedOrdersAllTabPaneState extends State<_RejectedOrdersAllTabPane> {
  final OrderSearchCache _searchCache = OrderSearchCache();
  final TextEditingController _searchController = TextEditingController();

  Timer? _searchDebounce;
  List<PurchaseOrder>? _cachedSourceOrders;
  List<PurchaseOrder>? _cachedVisibleOrders;
  String? _cachedVisibleKey;
  String _searchQuery = '';
  DateTimeRange? _createdDateRangeFilter;
  String? _selectedArea;
  String? _selectedRequester;
  int _limit = defaultOrderPageSize;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _RejectedOrdersAllTabPane oldWidget) {
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
        start: DateTime(picked.start.year, picked.start.month, picked.start.day),
        end: DateTime(picked.end.year, picked.end.month, picked.end.day),
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

  Future<void> _pickArea() async {
    final selected = await showSearchableSelect(
      context: context,
      title: 'Filtrar por area',
      options: buildHistoryAreaOptions(widget.orders),
    );
    if (selected == null || !mounted) return;
    final requesterOptions = buildHistoryRequesterOptions(
      widget.orders
          .where((order) => order.areaName.trim() == selected)
          .toList(growable: false),
    );
    setState(() {
      _selectedArea = selected;
      if (_selectedRequester != null &&
          !requesterOptions.contains(_selectedRequester)) {
        _selectedRequester = null;
      }
      _limit = defaultOrderPageSize;
    });
  }

  void _clearArea() {
    if (_selectedArea == null) return;
    setState(() {
      _selectedArea = null;
      _limit = defaultOrderPageSize;
    });
  }

  Future<void> _pickRequester() async {
    final selected = await showSearchableSelect(
      context: context,
      title: 'Filtrar por solicitante',
      options: buildHistoryRequesterOptions(_areaScopedOrders(widget.orders)),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedRequester = selected;
      _limit = defaultOrderPageSize;
    });
  }

  void _clearRequester() {
    if (_selectedRequester == null) return;
    setState(() {
      _selectedRequester = null;
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
    final areaOptions = buildHistoryAreaOptions(widget.orders);
    final requesterOptions = buildHistoryRequesterOptions(
      _areaScopedOrders(widget.orders),
    );

    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Buscar por folio, solicitante, area o proveedor',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: _clearSearch,
                    ),
            ),
            onChanged: _updateSearch,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _RejectedAllOverviewCard(
            totalOrders: widget.orders.length,
            totalAreas: areaOptions.length,
            totalRequesters: buildHistoryRequesterOptions(widget.orders).length,
            description: widget.description,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SelectableRejectedFilter(
                  label: _selectedArea ?? 'Area',
                  icon: Icons.apartment_outlined,
                  onTap: widget.orders.isEmpty ? null : _pickArea,
                ),
                if (_selectedArea != null)
                  TextButton(
                    onPressed: _clearArea,
                    child: const Text('Limpiar area'),
                  ),
                _SelectableRejectedFilter(
                  label: _selectedRequester ?? 'Solicitante',
                  icon: Icons.person_search_outlined,
                  onTap: requesterOptions.isEmpty ? null : _pickRequester,
                ),
                if (_selectedRequester != null)
                  TextButton(
                    onPressed: _clearRequester,
                    child: const Text('Limpiar solicitante'),
                  ),
                OrderDateRangeFilterButton(
                  selectedRange: _createdDateRangeFilter,
                  onPickDate: _pickCreatedDateFilter,
                  onClearDate: _clearCreatedDateFilter,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: visibleOrders.isEmpty
              ? HistoryEmptyState(
                  icon: widget.acknowledgedSection
                      ? Icons.task_alt_outlined
                      : Icons.notifications_active_outlined,
                  title: 'Sin resultados',
                  message: widget.emptyText,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                    return _GeneralRejectedOrderCard(
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

  List<PurchaseOrder> _areaScopedOrders(List<PurchaseOrder> orders) {
    final selectedArea = _selectedArea;
    if (selectedArea == null) return orders;
    return orders
        .where((order) => order.areaName.trim() == selectedArea)
        .toList(growable: false);
  }

  List<PurchaseOrder> _resolveVisibleOrders(List<PurchaseOrder> orders) {
    final key = _visibleOrdersKey();
    final cached = _cachedVisibleOrders;
    if (cached != null &&
        identical(_cachedSourceOrders, orders) &&
        _cachedVisibleKey == key) {
      return cached;
    }

    final resolved = orders
        .where((order) => matchesOrderUrgencyFilter(order, widget.urgencyFilter))
        .where(
          (order) => matchesOrderCreatedDateRange(order, _createdDateRangeFilter),
        )
        .where((order) {
          final selectedArea = _selectedArea;
          if (selectedArea == null) return true;
          return order.areaName.trim() == selectedArea;
        })
        .where((order) {
          final selectedRequester = _selectedRequester;
          if (selectedRequester == null) return true;
          return order.requesterName.trim() == selectedRequester;
        })
        .where(
          (order) => orderMatchesSearch(
            order,
            _searchQuery,
            cache: _searchCache,
          ),
        )
        .toList(growable: false);

    _cachedSourceOrders = orders;
    _cachedVisibleOrders = resolved;
    _cachedVisibleKey = key;
    return resolved;
  }

  String _visibleOrdersKey() {
    return '${widget.urgencyFilter.name}|'
        '${_createdDateRangeFilter?.start.millisecondsSinceEpoch ?? ''}|'
        '${_createdDateRangeFilter?.end.millisecondsSinceEpoch ?? ''}|'
        '${_selectedArea ?? ''}|'
        '${_selectedRequester ?? ''}|'
        '${_searchQuery.trim().toLowerCase()}';
  }
}

class _SelectableRejectedFilter extends StatelessWidget {
  const _SelectableRejectedFilter({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

class _RejectedAllOverviewCard extends StatelessWidget {
  const _RejectedAllOverviewCard({
    required this.totalOrders,
    required this.totalAreas,
    required this.totalRequesters,
    required this.description,
  });

  final int totalOrders;
  final int totalAreas;
  final int totalRequesters;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(description, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              _RejectedOverviewMetric(
                label: 'Ordenes',
                value: totalOrders.toString(),
              ),
              _RejectedOverviewMetric(
                label: 'Areas',
                value: totalAreas.toString(),
              ),
              _RejectedOverviewMetric(
                label: 'Solicitantes',
                value: totalRequesters.toString(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RejectedOverviewMetric extends StatelessWidget {
  const _RejectedOverviewMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _GeneralRejectedOrderCard extends ConsumerWidget {
  const _GeneralRejectedOrderCard({
    required this.order,
    required this.acknowledgedStyle,
  });

  final PurchaseOrder order;
  final bool acknowledgedStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final eventsAsync = ref.watch(orderEventsProvider(order.id));
    final lastReturn = eventsAsync.maybeWhen(
      data: _lastReturnEvent,
      orElse: () => null,
    );
    final actorNamesById = {
      for (final user in ref.watch(allUsersProvider).valueOrNull ?? const <AppUser>[])
        user.id: user.name,
    };
    final reason = (order.lastReturnReason ?? '').trim();
    final previousStatusLabel = _rejectedFromLabel(
      order.lastReturnFromStatus ?? lastReturn?.fromStatus,
    );
    final cardColor = acknowledgedStyle ? Colors.green.shade50 : null;
    final cardBorder = acknowledgedStyle
        ? Colors.green.shade200
        : scheme.outlineVariant;
    final infoBackground = acknowledgedStyle
        ? Colors.green.shade100
        : scheme.errorContainer.withValues(alpha: 0.7);
    final infoBorder = acknowledgedStyle
        ? Colors.green.shade300
        : scheme.error.withValues(alpha: 0.35);
    final infoText = acknowledgedStyle
        ? Colors.green.shade900
        : scheme.onErrorContainer;

    return Card(
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cardBorder),
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
                _RejectedInfoBadge(
                  label: 'Folio ${order.id}',
                  background: scheme.primaryContainer,
                  foreground: scheme.onPrimaryContainer,
                ),
                _RejectedInfoBadge(
                  label: order.urgency.label,
                  background: order.urgency == PurchaseOrderUrgency.urgente
                      ? scheme.errorContainer
                      : scheme.secondaryContainer,
                  foreground: order.urgency == PurchaseOrderUrgency.urgente
                      ? scheme.onErrorContainer
                      : scheme.onSecondaryContainer,
                ),
                _RejectedInfoBadge(
                  label: order.isRejectedPendingAcknowledgment
                      ? 'No enterada'
                      : 'Enterada ${order.rejectionAcknowledgedAt?.toShortDate() ?? ''}'
                            .trim(),
                  background: acknowledgedStyle
                      ? Colors.green.shade100
                      : scheme.errorContainer.withValues(alpha: 0.5),
                  foreground: acknowledgedStyle
                      ? Colors.green.shade900
                      : scheme.onErrorContainer,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Solicitante: ${order.requesterName}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text('Area: ${order.areaName}', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: infoBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: infoBorder),
              ),
              child: Text(
                reason.isEmpty ? 'Sin comentario' : reason,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: infoText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _RejectedReviewSummary(
              order: order,
              previousStatusLabel: previousStatusLabel,
              eventsAsync: eventsAsync,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _RejectedMetaText(
                  icon: Icons.event_outlined,
                  label: 'Creada: ${_dateTimeLabel(order.createdAt)}',
                ),
                _RejectedMetaText(
                  icon: Icons.assignment_return_outlined,
                  label:
                      'Rechazada por ${_rejectedActorLabel(lastReturn, actorNamesById)} desde $previousStatusLabel',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => guardedPush(context, '/orders/${order.id}'),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Detalle'),
                ),
                OutlinedButton.icon(
                  onPressed: () => guardedPdfPush(context, '/orders/${order.id}/pdf'),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Ver PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: () => guardedPush(
                    context,
                    historyCopyOrderLocation(order.id),
                  ),
                  icon: const Icon(Icons.content_copy_outlined),
                  label: const Text('Copiar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RejectedReviewSummary extends StatelessWidget {
  const _RejectedReviewSummary({
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
      return StatusDurationPill(
        text:
            'Tiempo en revision: ${formatDurationLabel(Duration(milliseconds: explicitDuration))}',
        alignRight: false,
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
        return StatusDurationPill(
          text: 'Tiempo en revision: ${formatDurationLabel(duration)}',
          alignRight: false,
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _RejectedInfoBadge extends StatelessWidget {
  const _RejectedInfoBadge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RejectedMetaText extends StatelessWidget {
  const _RejectedMetaText({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodySmall),
      ],
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

String _dateTimeLabel(DateTime? value) {
  if (value == null) return 'Sin fecha';
  return value.toFullDateTime();
}
