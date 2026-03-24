import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/order_event_labels.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/monitoring/monitoring_pdf_view_screen.dart';
import 'package:sistema_compras/features/orders/presentation/monitoring/order_monitoring_support.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_urgency_controls.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

class OrderMonitoringScreen extends ConsumerStatefulWidget {
  const OrderMonitoringScreen({super.key});

  @override
  ConsumerState<OrderMonitoringScreen> createState() =>
      _OrderMonitoringScreenState();
}

class _OrderMonitoringScreenState extends ConsumerState<OrderMonitoringScreen> {
  bool _exportingCsv = false;
  bool _exportingPdf = false;
  late final TextEditingController _searchController;
  final OrderSearchCache _searchCache = OrderSearchCache();
  Timer? _searchDebounce;
  String _searchQuery = '';
  OrderUrgencyFilter _urgencyFilter = OrderUrgencyFilter.all;
  DateTimeRange? _createdDateRangeFilter;

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

  void _updateSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _searchDebounce = null;
      setState(() => _searchQuery = value);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = null;
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  void _setUrgencyFilter(OrderUrgencyFilter filter) {
    setState(() => _urgencyFilter = filter);
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
    });
  }

  void _clearCreatedDateFilter() {
    if (_createdDateRangeFilter == null) return;
    setState(() => _createdDateRangeFilter = null);
  }

  Future<Map<String, List<PurchaseOrderEvent>>> _loadEventsForOrders(
    List<PurchaseOrder> orders,
  ) async {
    final repository = ref.read(purchaseOrderRepositoryProvider);
    final entries = await Future.wait(
      [
        for (final order in orders)
          repository.watchEvents(order.id).first.then(
                (events) => MapEntry(order.id, events),
              ),
      ],
    );
    return {
      for (final entry in entries) entry.key: entry.value,
    };
  }

  Future<void> _handleExportCsv(
    List<PurchaseOrder> monitorableOrders,
    Map<String, String> actorNamesById,
  ) async {
    if (_exportingCsv) return;
    setState(() => _exportingCsv = true);
    final now = DateTime.now();
    try {
      final eventsByOrder = await _loadEventsForOrders(monitorableOrders);
      final quotes = await ref.read(supplierQuotesProvider.future);
      await exportMonitoringCsv(
        context,
        orders: monitorableOrders,
        now: now,
        eventsByOrder: eventsByOrder,
        quotes: quotes,
        actorNamesById: actorNamesById,
      );
    } finally {
      if (mounted) {
        setState(() => _exportingCsv = false);
      }
    }
  }

  Future<void> _handleExportPdf(
    List<PurchaseOrder> monitorableOrders,
    CompanyBranding branding,
    Map<String, String> actorNamesById,
  ) async {
    if (_exportingPdf) return;
    setState(() => _exportingPdf = true);
    final now = DateTime.now();
    try {
      final eventsByOrder = await _loadEventsForOrders(monitorableOrders);
      final quotes = await ref.read(supplierQuotesProvider.future);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MonitoringPdfViewScreen(
            orders: monitorableOrders,
            now: now,
            companyName: branding.displayName,
            scopeLabel: _reportScopeLabel(monitorableOrders.length),
            eventsByOrder: eventsByOrder,
            quotes: quotes,
            actorNamesById: actorNamesById,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exportingPdf = false);
      }
    }
  }

  String _reportScopeLabel(int visibleCount) {
    return 'Visibles: $visibleCount | Monitoreo operativo';
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProfileProvider);
    final branding = ref.watch(currentBrandingProvider);
    final usersAsync = ref.watch(allUsersProvider);
    final user = userAsync.value;

    if (userAsync.isLoading || user == null) {
      return const Scaffold(body: AppSplash());
    }

    final canView = isAdminRole(user.role) || isComprasLabel(user.areaDisplay);
    final ordersAsync = ref.watch(monitoringOrdersProvider);
    final actorNamesById = _actorNamesById(usersAsync.valueOrNull);

    return Scaffold(
      appBar: AppBar(title: const Text('Monitoreo')),
      body: !canView
          ? const Center(
              child: Text('No tienes permisos para ver el monitoreo.'),
            )
          : ordersAsync.when(
              data: (orders) {
                final monitorable = orders
                    .where(isMonitorableOrder)
                    .toList(growable: false);
                _searchCache.retainFor(monitorable);

                final trimmedQuery = _searchQuery.trim();
                final searchedMonitorable = trimmedQuery.isEmpty
                    ? monitorable
                    : monitorable
                        .where(
                          (order) => orderMatchesSearch(
                            order,
                            trimmedQuery,
                            cache: _searchCache,
                            includeDates: false,
                          ),
                        )
                        .toList(growable: false);
                final scopedMonitorable = searchedMonitorable
                    .where(
                      (order) => matchesOrderCreatedDateRange(
                        order,
                        _createdDateRangeFilter,
                      ),
                    )
                    .toList(growable: false);
                final filteredMonitorable = scopedMonitorable
                    .where((order) => matchesOrderUrgencyFilter(order, _urgencyFilter))
                    .toList(growable: false);
                final normalOrders = scopedMonitorable
                    .where((order) => order.urgency == PurchaseOrderUrgency.normal)
                    .length;
                final urgentOrders = scopedMonitorable
                    .where((order) => order.urgency == PurchaseOrderUrgency.urgente)
                    .length;
                final hasActiveFilters =
                    trimmedQuery.isNotEmpty || _createdDateRangeFilter != null;

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 720;
                        final searchField = TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            labelText:
                                'Buscar por folio (000001), solicitante, area, proveedor...',
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
                    const SizedBox(height: 16),
                    _MonitoringSummaryBar(
                      totalCount: monitorable.length,
                      visibleCount: filteredMonitorable.length,
                      normalCount: normalOrders,
                      urgentCount: urgentOrders,
                      selectedFilter: _urgencyFilter,
                      onSelectedFilter: _setUrgencyFilter,
                      onExportCsv: _exportingCsv
                          ? null
                          : () => _handleExportCsv(
                                filteredMonitorable,
                                actorNamesById,
                              ),
                      onExportPdf: _exportingPdf
                          ? null
                          : () => _handleExportPdf(
                                filteredMonitorable,
                                branding,
                                actorNamesById,
                              ),
                      exportingCsv: _exportingCsv,
                      exportingPdf: _exportingPdf,
                    ),
                    const SizedBox(height: 16),
                    _MonitoringRecentActivitySection(
                      orders: filteredMonitorable,
                      actorNamesById: actorNamesById,
                      hasActiveFilters: hasActiveFilters || _urgencyFilter != OrderUrgencyFilter.all,
                    ),
                  ],
                );
              },
              loading: () => const AppSplash(),
              error: (error, stack) => Center(
                child: Text(
                  'Error: ${reportError(error, stack, context: 'OrderMonitoringScreen')}',
                ),
              ),
            ),
    );
  }
}

Map<String, String> _actorNamesById(List<AppUser>? users) {
  if (users == null || users.isEmpty) return const <String, String>{};
  return <String, String>{
    for (final user in users)
      user.id: user.name.trim().isEmpty ? user.id : user.name.trim(),
  };
}

String _actorLabel(
  PurchaseOrderEvent event,
  Map<String, String> actorNamesById,
) {
  final resolvedName = actorNamesById[event.byUser] ?? event.byUser;
  final role = event.byRole.trim();
  if (role.isEmpty) return resolvedName;
  return '$resolvedName | $role';
}

class _MonitoringSummaryBar extends StatelessWidget {
  const _MonitoringSummaryBar({
    required this.totalCount,
    required this.visibleCount,
    required this.normalCount,
    required this.urgentCount,
    required this.selectedFilter,
    required this.onSelectedFilter,
    required this.onExportCsv,
    required this.onExportPdf,
    required this.exportingCsv,
    required this.exportingPdf,
  });

  final int totalCount;
  final int visibleCount;
  final int normalCount;
  final int urgentCount;
  final OrderUrgencyFilter selectedFilter;
  final ValueChanged<OrderUrgencyFilter> onSelectedFilter;
  final VoidCallback? onExportCsv;
  final VoidCallback? onExportPdf;
  final bool exportingCsv;
  final bool exportingPdf;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Monitoreo operativo',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '$visibleCount de $totalCount ordenes monitorizadas activas.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          FilterChip(
            avatar: const Icon(Icons.inventory_2_outlined, size: 18),
            label: Text('$totalCount activas'),
            selected: selectedFilter == OrderUrgencyFilter.all,
            onSelected: (_) => onSelectedFilter(OrderUrgencyFilter.all),
          ),
          FilterChip(
            avatar: const Icon(Icons.remove_circle_outline, size: 18),
            label: Text('$normalCount normales'),
            selected: selectedFilter == OrderUrgencyFilter.normal,
            onSelected: (_) => onSelectedFilter(OrderUrgencyFilter.normal),
          ),
          FilterChip(
            avatar: const Icon(Icons.priority_high_outlined, size: 18),
            label: Text('$urgentCount urgentes'),
            selected: selectedFilter == OrderUrgencyFilter.urgente,
            onSelected: (_) => onSelectedFilter(OrderUrgencyFilter.urgente),
          ),
          FilledButton.icon(
            onPressed: onExportCsv,
            icon: exportingCsv
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.table_view_outlined),
            label: const Text('CSV'),
          ),
          FilledButton.tonalIcon(
            onPressed: onExportPdf,
            icon: exportingPdf
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF'),
          ),
        ],
      ),
    );
  }
}

class _MonitoringRecentActivitySection extends ConsumerStatefulWidget {
  const _MonitoringRecentActivitySection({
    required this.orders,
    required this.actorNamesById,
    required this.hasActiveFilters,
  });

  final List<PurchaseOrder> orders;
  final Map<String, String> actorNamesById;
  final bool hasActiveFilters;

  @override
  ConsumerState<_MonitoringRecentActivitySection> createState() =>
      _MonitoringRecentActivitySectionState();
}

class _MonitoringRecentActivitySectionState
    extends ConsumerState<_MonitoringRecentActivitySection> {
  final Set<String> _expandedOrderIds = <String>{};

  void _toggleOrder(String orderId) {
    setState(() {
      if (_expandedOrderIds.contains(orderId)) {
        _expandedOrderIds.remove(orderId);
      } else {
        _expandedOrderIds.add(orderId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final orderActivities = <_RecentMonitoringOrderActivity>[];
    var loadingCount = 0;
    var errorCount = 0;

    for (final order in widget.orders) {
      final eventsAsync = ref.watch(orderEventsProvider(order.id));
      eventsAsync.when(
        data: (events) {
          final sortedEvents = newestEventsFirst(events)
              .where((event) => event.timestamp != null)
              .toList(growable: false);
          if (sortedEvents.isNotEmpty) {
            orderActivities.add(
              _RecentMonitoringOrderActivity(
                order: order,
                events: sortedEvents,
              ),
            );
          }
        },
        loading: () {
          loadingCount++;
        },
        error: (_, __) {
          errorCount++;
        },
      );
    }

    orderActivities.sort((a, b) {
      final aMs = a.events.first.timestamp?.millisecondsSinceEpoch ?? 0;
      final bMs = b.events.first.timestamp?.millisecondsSinceEpoch ?? 0;
      return bMs.compareTo(aMs);
    });
    final recentOrders = orderActivities.take(12).toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Actividad reciente',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Ordenes con movimientos recientes. Abre una para revisar su historial sin tanto texto corrido.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MonitoringInfoPill(
                  icon: Icons.inventory_2_outlined,
                  label: '${widget.orders.length} ordenes monitoreadas',
                ),
                if (recentOrders.isNotEmpty)
                  _MonitoringInfoPill(
                    icon: Icons.bolt_outlined,
                    label: '${recentOrders.length} con actividad reciente',
                  ),
                if (loadingCount > 0)
                  _MonitoringInfoPill(
                    icon: Icons.sync_outlined,
                    label: 'Actualizando $loadingCount historial(es)',
                  ),
                if (errorCount > 0)
                  _MonitoringInfoPill(
                    icon: Icons.error_outline,
                    label: '$errorCount historial(es) con error',
                    highlighted: true,
                  ),
              ],
            ),
            if (loadingCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Actualizando actividad...',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            if (widget.orders.isEmpty)
              _EmptyMonitoringState(
                icon: widget.hasActiveFilters
                    ? Icons.filter_alt_off_outlined
                    : Icons.monitor_heart_outlined,
                message: widget.hasActiveFilters
                    ? 'No hay ordenes con ese filtro.'
                    : 'No hay ordenes monitorizables en este momento.',
              )
            else if (recentOrders.isEmpty && loadingCount > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (recentOrders.isEmpty)
              const _EmptyMonitoringState(
                icon: Icons.history_toggle_off_outlined,
                message: 'Aun no hay eventos registrados.',
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  final activity = recentOrders[index];
                  return _MonitoringRecentOrderTile(
                    activity: activity,
                    actorNamesById: widget.actorNamesById,
                    expanded: _expandedOrderIds.contains(activity.order.id),
                    onToggle: () => _toggleOrder(activity.order.id),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemCount: recentOrders.length,
              ),
            if (errorCount > 0) ...[
              const SizedBox(height: 12),
              Text(
                'No se pudieron cargar $errorCount historiales.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MonitoringRecentOrderTile extends StatelessWidget {
  const _MonitoringRecentOrderTile({
    required this.activity,
    required this.actorNamesById,
    required this.expanded,
    required this.onToggle,
  });

  final _RecentMonitoringOrderActivity activity;
  final Map<String, String> actorNamesById;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final order = activity.order;
    final latestEvent = activity.events.first;
    final latestAction = isReturnOrderEvent(latestEvent)
        ? returnEventTitle(activity.events, latestEvent)
        : 'Movimiento';
    final now = DateTime.now();
    final currentElapsed = currentStatusElapsed(order, now);
    final latestComment = latestEvent.comment?.trim() ?? '';

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.id,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${order.requesterName} | ${order.areaName}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _MonitoringInfoPill(
                              icon: order.urgency == PurchaseOrderUrgency.urgente
                                  ? Icons.priority_high_outlined
                                  : Icons.remove_circle_outline,
                              label: order.urgency.label,
                            ),
                            _MonitoringInfoPill(
                              icon: order.status.icon,
                              label: order.status.label,
                            ),
                            _MonitoringInfoPill(
                              icon: Icons.timer_outlined,
                              label: formatMonitoringDuration(currentElapsed),
                            ),
                            _MonitoringInfoPill(
                              icon: Icons.history_outlined,
                              label: '${activity.events.length} movimientos',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$latestAction: ${orderEventTransitionLabel(latestEvent)}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          latestEvent.timestamp!.toFullDateTime(),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (latestComment.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              latestComment,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                  ),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemBuilder: (context, index) {
                    final event = activity.events[index];
                    return _MonitoringRecentMovementTile(
                      event: event,
                      allEvents: activity.events,
                      actorNamesById: actorNamesById,
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemCount: activity.events.length,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MonitoringRecentMovementTile extends StatelessWidget {
  const _MonitoringRecentMovementTile({
    required this.event,
    required this.allEvents,
    required this.actorNamesById,
  });

  final PurchaseOrderEvent event;
  final List<PurchaseOrderEvent> allEvents;
  final Map<String, String> actorNamesById;

  @override
  Widget build(BuildContext context) {
    final action = isReturnOrderEvent(event)
        ? returnEventTitle(allEvents, event)
        : 'Movimiento';
    final transition = orderEventTransitionLabel(event);
    final comment = event.comment?.trim() ?? '';
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            action,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MonitoringInfoPill(
                icon: Icons.swap_horiz_outlined,
                label: transition,
              ),
              _MonitoringInfoPill(
                icon: Icons.person_outline,
                label: _actorLabel(event, actorNamesById),
              ),
              _MonitoringInfoPill(
                icon: Icons.schedule_outlined,
                label: event.timestamp!.toFullDateTime(),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isReturnOrderEvent(event)
                    ? scheme.errorContainer
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isReturnOrderEvent(event) ? 'Motivo' : 'Comentario',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    comment,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MonitoringInfoPill extends StatelessWidget {
  const _MonitoringInfoPill({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = highlighted
        ? scheme.errorContainer
        : scheme.surfaceContainerHighest;
    final foreground = highlighted
        ? scheme.onErrorContainer
        : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlighted
              ? scheme.error.withValues(alpha: 0.24)
              : scheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMonitoringState extends StatelessWidget {
  const _EmptyMonitoringState({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(icon, size: 40),
          const SizedBox(height: 12),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _RecentMonitoringOrderActivity {
  const _RecentMonitoringOrderActivity({
    required this.order,
    required this.events,
  });

  final PurchaseOrder order;
  final List<PurchaseOrderEvent> events;
}
