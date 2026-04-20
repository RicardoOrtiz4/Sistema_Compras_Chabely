import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/access_control.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/core/widgets/searchable_select.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/history/order_history_shared.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_pdf_preload_gate.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_urgency_controls.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

class OrderHistoryAllScreen extends ConsumerStatefulWidget {
  const OrderHistoryAllScreen({super.key});

  @override
  ConsumerState<OrderHistoryAllScreen> createState() =>
      _OrderHistoryAllScreenState();
}

class _OrderHistoryAllScreenState extends ConsumerState<OrderHistoryAllScreen> {
  final OrderSearchCache _searchCache = OrderSearchCache();
  final TextEditingController _searchController = TextEditingController();

  Timer? _searchDebounce;
  List<PurchaseOrder>? _cachedSourceOrders;
  List<PurchaseOrder>? _cachedVisibleOrders;
  String? _cachedVisibleKey;
  String _searchQuery = '';
  OrderUrgencyFilter _urgencyFilter = OrderUrgencyFilter.all;
  HistoryRejectionFilter _rejectionFilter = HistoryRejectionFilter.all;
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

  void _setUrgencyFilter(OrderUrgencyFilter filter) {
    setState(() {
      _urgencyFilter = filter;
      _limit = defaultOrderPageSize;
    });
  }

  void _setRejectionFilter(HistoryRejectionFilter filter) {
    setState(() {
      _rejectionFilter = filter;
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

  Future<void> _pickArea(List<PurchaseOrder> orders) async {
    final selected = await showSearchableSelect(
      context: context,
      title: 'Filtrar por area',
      options: buildHistoryAreaOptions(orders),
    );
    if (selected == null || !mounted) return;

    final requesterOptions = buildHistoryRequesterOptions(
      orders.where((order) => order.areaName.trim() == selected).toList(growable: false),
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

  Future<void> _pickRequester(List<PurchaseOrder> orders) async {
    final selected = await showSearchableSelect(
      context: context,
      title: 'Filtrar por solicitante',
      options: buildHistoryRequesterOptions(_areaScopedOrders(orders)),
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
    final profileAsync = ref.watch(currentUserProfileProvider);
    final ordersAsync = ref.watch(historyAllOrdersProvider);
    final user = profileAsync.value;
    final canViewAll = canViewGlobalHistory(user);
    final compactAppBar = useCompactOrderModuleAppBar(context);

    if (profileAsync.isLoading) {
      return const Scaffold(body: AppSplash());
    }

    return Scaffold(
      appBar: AppBar(
        title: ordersAsync.when(
          data: (orders) {
            final historyOrders = orders.where(isUnifiedHistoryOrder).toList(growable: false);
            final counts = OrderUrgencyCounts.fromOrders(historyOrders);
            return compactAppBar
                ? const Text('Historial general')
                : OrderModuleAppBarTitle(
                    title: 'Historial general',
                    counts: counts,
                    filter: _urgencyFilter,
                    onSelected: _setUrgencyFilter,
                    trailing: _HistoryRejectionFilterButton(
                      filter: _rejectionFilter,
                      onSelected: _setRejectionFilter,
                    ),
                  );
          },
          loading: () => const Text('Historial general'),
          error: (_, __) => const Text('Historial general'),
        ),
        bottom: !compactAppBar
            ? null
            : ordersAsync.maybeWhen(
                data: (orders) => PreferredSize(
                  preferredSize: const Size.fromHeight(60),
                  child: OrderModuleAppBarBottom(
                    counts: OrderUrgencyCounts.fromOrders(
                      orders.where(isUnifiedHistoryOrder).toList(growable: false),
                    ),
                    filter: _urgencyFilter,
                    onSelected: _setUrgencyFilter,
                    trailing: _HistoryRejectionFilterButton(
                      filter: _rejectionFilter,
                      onSelected: _setRejectionFilter,
                    ),
                  ),
                ),
                orElse: () => null,
              ),
      ),
      body: !canViewAll
          ? const HistoryEmptyState(
              icon: Icons.lock_outline,
              title: 'Sin permiso para este historial',
              message:
                  'Solo perfiles operativos y administrativos pueden revisar el historial general.',
            )
          : _HistoryAllBody(
              searchController: _searchController,
              searchQuery: _searchQuery,
              urgencyFilter: _urgencyFilter,
              createdDateRangeFilter: _createdDateRangeFilter,
              selectedArea: _selectedArea,
              selectedRequester: _selectedRequester,
              rejectionFilter: _rejectionFilter,
              limit: _limit,
              searchCache: _searchCache,
              searchDebounce: _searchDebounce,
              cachedSourceOrders: _cachedSourceOrders,
              cachedVisibleOrders: _cachedVisibleOrders,
              cachedVisibleKey: _cachedVisibleKey,
              onUpdateSearch: _updateSearch,
              onClearSearch: _clearSearch,
              onSetUrgencyFilter: _setUrgencyFilter,
              onSetRejectionFilter: _setRejectionFilter,
              onPickCreatedDateFilter: _pickCreatedDateFilter,
              onClearCreatedDateFilter: _clearCreatedDateFilter,
              onPickArea: _pickArea,
              onClearArea: _clearArea,
              onPickRequester: _pickRequester,
              onClearRequester: _clearRequester,
              onLoadMore: _loadMore,
              onCacheUpdate: (orders, visible, key) {
                _cachedSourceOrders = orders;
                _cachedVisibleOrders = visible;
                _cachedVisibleKey = key;
              },
            ),
    );
  }

  List<PurchaseOrder> _areaScopedOrders(List<PurchaseOrder> orders) {
    final selectedArea = _selectedArea;
    if (selectedArea == null) return orders;
    return orders
        .where((order) => order.areaName.trim() == selectedArea)
        .toList(growable: false);
  }
}

class _HistoryRejectionFilterButton extends StatelessWidget {
  const _HistoryRejectionFilterButton({
    required this.filter,
    required this.onSelected,
  });

  final HistoryRejectionFilter filter;
  final ValueChanged<HistoryRejectionFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<HistoryRejectionFilter>(
      initialValue: filter,
      onSelected: onSelected,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: HistoryRejectionFilter.all,
          child: Text('Todas'),
        ),
        PopupMenuItem(
          value: HistoryRejectionFilter.rejectedOnly,
          child: Text('Rechazadas'),
        ),
        PopupMenuItem(
          value: HistoryRejectionFilter.rejectedAcknowledged,
          child: Text('Enteradas'),
        ),
        PopupMenuItem(
          value: HistoryRejectionFilter.rejectedPendingAcknowledgment,
          child: Text('No enteradas'),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt_outlined,
              size: 18,
              color: theme.colorScheme.onSurface,
            ),
            const SizedBox(width: 8),
            Text(_labelForHistoryRejectionFilter(filter)),
            const SizedBox(width: 6),
            Icon(
              Icons.arrow_drop_down,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

String _labelForHistoryRejectionFilter(HistoryRejectionFilter filter) {
  switch (filter) {
    case HistoryRejectionFilter.all:
      return 'Todas';
    case HistoryRejectionFilter.rejectedOnly:
      return 'Rechazadas';
    case HistoryRejectionFilter.rejectedAcknowledged:
      return 'Enteradas';
    case HistoryRejectionFilter.rejectedPendingAcknowledgment:
      return 'No enteradas';
  }
}

class _HistoryAllBody extends ConsumerWidget {
  const _HistoryAllBody({
    required this.searchController,
    required this.searchQuery,
    required this.urgencyFilter,
    required this.rejectionFilter,
    required this.createdDateRangeFilter,
    required this.selectedArea,
    required this.selectedRequester,
    required this.limit,
    required this.searchCache,
    required this.searchDebounce,
    required this.cachedSourceOrders,
    required this.cachedVisibleOrders,
    required this.cachedVisibleKey,
    required this.onUpdateSearch,
    required this.onClearSearch,
    required this.onSetUrgencyFilter,
    required this.onSetRejectionFilter,
    required this.onPickCreatedDateFilter,
    required this.onClearCreatedDateFilter,
    required this.onPickArea,
    required this.onClearArea,
    required this.onPickRequester,
    required this.onClearRequester,
    required this.onLoadMore,
    required this.onCacheUpdate,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final OrderUrgencyFilter urgencyFilter;
  final HistoryRejectionFilter rejectionFilter;
  final DateTimeRange? createdDateRangeFilter;
  final String? selectedArea;
  final String? selectedRequester;
  final int limit;
  final OrderSearchCache searchCache;
  final Timer? searchDebounce;
  final List<PurchaseOrder>? cachedSourceOrders;
  final List<PurchaseOrder>? cachedVisibleOrders;
  final String? cachedVisibleKey;
  final ValueChanged<String> onUpdateSearch;
  final VoidCallback onClearSearch;
  final ValueChanged<OrderUrgencyFilter> onSetUrgencyFilter;
  final ValueChanged<HistoryRejectionFilter> onSetRejectionFilter;
  final Future<void> Function() onPickCreatedDateFilter;
  final VoidCallback onClearCreatedDateFilter;
  final Future<void> Function(List<PurchaseOrder> orders) onPickArea;
  final VoidCallback onClearArea;
  final Future<void> Function(List<PurchaseOrder> orders) onPickRequester;
  final VoidCallback onClearRequester;
  final VoidCallback onLoadMore;
  final void Function(
    List<PurchaseOrder> sourceOrders,
    List<PurchaseOrder> visibleOrders,
    String key,
  )
  onCacheUpdate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(historyAllOrdersProvider);
    return ordersAsync.when(
        data: (orders) {
          final historyOrders = _historyOrders(orders);
          if (historyOrders.isEmpty) {
            return const HistoryEmptyState(
              icon: Icons.history_toggle_off_outlined,
              title: 'No hay ordenes en el historial general',
              message:
                  'El historial general se llena cuando las ordenes ya quedaron cerradas o fueron rechazadas.',
            );
          }

          searchCache.retainFor(historyOrders);
          final filtered = _resolveVisibleOrders(historyOrders);
          final visibleOrders = filtered.take(limit).toList(growable: false);
          final showLoadMore = filtered.length > visibleOrders.length;
          final areaOptions = buildHistoryAreaOptions(historyOrders);
          final requesterOptions = buildHistoryRequesterOptions(
            _areaScopedOrders(historyOrders),
          );

          final content = Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    labelText: 'Buscar por folio, solicitante, area o proveedor',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: searchQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: onClearSearch,
                          ),
                  ),
                  onChanged: onUpdateSearch,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _GeneralHistoryOverviewCard(
                  totalOrders: historyOrders.length,
                  totalAreas: areaOptions.length,
                  totalRequesters: buildHistoryRequesterOptions(historyOrders).length,
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
                      _SelectableHistoryFilter(
                        label: selectedArea ?? 'Area',
                        icon: Icons.apartment_outlined,
                        onTap: () => onPickArea(historyOrders),
                      ),
                      if (selectedArea != null)
                        TextButton(
                          onPressed: onClearArea,
                          child: const Text('Limpiar area'),
                        ),
                      _SelectableHistoryFilter(
                        label: selectedRequester ?? 'Solicitante',
                        icon: Icons.person_search_outlined,
                        onTap: requesterOptions.isEmpty
                            ? null
                            : () => onPickRequester(historyOrders),
                      ),
                      if (selectedRequester != null)
                        TextButton(
                          onPressed: onClearRequester,
                          child: const Text('Limpiar solicitante'),
                        ),
                      OrderDateRangeFilterButton(
                        selectedRange: createdDateRangeFilter,
                        onPickDate: onPickCreatedDateFilter,
                        onClearDate: onClearCreatedDateFilter,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: visibleOrders.isEmpty
                    ? const HistoryEmptyState(
                        icon: Icons.filter_alt_off_outlined,
                        title: 'No hay ordenes para ese cruce de filtros',
                        message:
                            'Intenta limpiar el area, el solicitante o el texto de busqueda.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: visibleOrders.length + (showLoadMore ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index >= visibleOrders.length) {
                            return Center(
                              child: OutlinedButton.icon(
                                onPressed: onLoadMore,
                                icon: const Icon(Icons.expand_more),
                                label: const Text('Ver mas'),
                              ),
                            );
                          }
                          return HistoryOrderCard(
                            order: visibleOrders[index],
                            includeRequester: true,
                            includeArea: true,
                          );
                        },
                      ),
              ),
            ],
          );

          return OrderPdfPreloadGate(
            orders: visibleOrders,
            enabled: searchDebounce == null && searchQuery.trim().isEmpty,
            child: content,
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            'Error: ${reportError(error, stack, context: 'OrderHistoryAllScreen')}',
          ),
        ),
    );
  }

  List<PurchaseOrder> _historyOrders(List<PurchaseOrder> orders) {
    return orders.where(isUnifiedHistoryOrder).toList(growable: false);
  }

  List<PurchaseOrder> _areaScopedOrders(List<PurchaseOrder> orders) {
    final selectedArea = this.selectedArea;
    if (selectedArea == null) return orders;
    return orders
        .where((order) => order.areaName.trim() == selectedArea)
        .toList(growable: false);
  }

  List<PurchaseOrder> _resolveVisibleOrders(List<PurchaseOrder> orders) {
    final key = _visibleOrdersKey();
    final cached = cachedVisibleOrders;
    if (cached != null &&
        identical(cachedSourceOrders, orders) &&
        cachedVisibleKey == key) {
      return cached;
    }

    final resolved = orders
        .where((order) => matchesOrderUrgencyFilter(order, urgencyFilter))
        .where((order) => matchesHistoryRejectionFilter(order, rejectionFilter))
        .where((order) => matchesOrderCreatedDateRange(order, createdDateRangeFilter))
        .where((order) {
          final selectedArea = this.selectedArea;
          if (selectedArea == null) return true;
          return order.areaName.trim() == selectedArea;
        })
        .where((order) {
          final selectedRequester = this.selectedRequester;
          if (selectedRequester == null) return true;
          return order.requesterName.trim() == selectedRequester;
        })
        .where(
          (order) => orderMatchesSearch(
            order,
            searchQuery,
            cache: searchCache,
          ),
        )
        .toList(growable: false);

    onCacheUpdate(orders, resolved, key);
    return resolved;
  }

  String _visibleOrdersKey() {
    return '${urgencyFilter.name}|'
        '${rejectionFilter.name}|'
        '${createdDateRangeFilter?.start.millisecondsSinceEpoch ?? ''}|'
        '${createdDateRangeFilter?.end.millisecondsSinceEpoch ?? ''}|'
        '${selectedArea ?? ''}|'
        '${selectedRequester ?? ''}|'
        '${searchQuery.trim().toLowerCase()}';
  }
}

class _SelectableHistoryFilter extends StatelessWidget {
  const _SelectableHistoryFilter({
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

class _GeneralHistoryOverviewCard extends StatelessWidget {
  const _GeneralHistoryOverviewCard({
    required this.totalOrders,
    required this.totalAreas,
    required this.totalRequesters,
  });

  final int totalOrders;
  final int totalAreas;
  final int totalRequesters;

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
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        children: [
          _OverviewMetric(label: 'Ordenes', value: totalOrders.toString()),
          _OverviewMetric(label: 'Areas', value: totalAreas.toString()),
          _OverviewMetric(
            label: 'Solicitantes',
            value: totalRequesters.toString(),
          ),
        ],
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
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
