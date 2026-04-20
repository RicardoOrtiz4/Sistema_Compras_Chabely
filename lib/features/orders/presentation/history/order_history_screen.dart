import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/history/order_history_shared.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_pdf_preload_gate.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_urgency_controls.dart';

class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen> {
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

  void _loadMore() {
    setState(() => _limit += orderPageSizeStep);
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(userOrdersProvider);
    final compactAppBar = useCompactOrderModuleAppBar(context);

    return Scaffold(
      appBar: AppBar(
        title: ordersAsync.when(
          data: (orders) {
            final historyOrders = _historyOrders(orders);
            final counts = OrderUrgencyCounts.fromOrders(historyOrders);
            return compactAppBar
                ? const Text('Historial de mis ordenes')
                : OrderModuleAppBarTitle(
                    title: 'Historial de mis ordenes',
                    counts: counts,
                    filter: _urgencyFilter,
                    onSelected: _setUrgencyFilter,
                    trailing: _HistoryRejectionFilterButton(
                      filter: _rejectionFilter,
                      onSelected: _setRejectionFilter,
                    ),
                  );
          },
          loading: () => const Text('Historial de mis ordenes'),
          error: (_, __) => const Text('Historial de mis ordenes'),
        ),
        bottom: !compactAppBar
            ? null
            : ordersAsync.maybeWhen(
                data: (orders) => PreferredSize(
                  preferredSize: const Size.fromHeight(60),
                  child: OrderModuleAppBarBottom(
                    counts: OrderUrgencyCounts.fromOrders(_historyOrders(orders)),
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
      body: ordersAsync.when(
        data: (orders) {
          final historyOrders = _historyOrders(orders);
          if (historyOrders.isEmpty) {
            return const HistoryEmptyState(
              icon: Icons.history_toggle_off_outlined,
              title: 'Aun no tienes ordenes en historial',
              message:
                  'Aqui apareceran tus ordenes cerradas y tambien las rechazadas para consulta historica.',
            );
          }

          _searchCache.retainFor(historyOrders);
          final filtered = _resolveVisibleOrders(historyOrders);
          final visibleOrders = filtered.take(_limit).toList(growable: false);
          final showLoadMore = filtered.length > visibleOrders.length;

          final content = Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _HistorySearchBar(
                  controller: _searchController,
                  searchQuery: _searchQuery,
                  onChanged: _updateSearch,
                  onClear: _clearSearch,
                  hintText: 'Buscar por folio, nota, proveedor o fecha',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 720;
                    final overview = _HistoryOverviewCard(
                      title: 'Ordenes cerradas',
                      message:
                          'Aqui ves requisiciones cerradas y rechazadas, incluidas las resueltas de forma parcial o sin compra.',
                      count: historyOrders.length,
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
                          overview,
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: dateFilter,
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: overview),
                        const SizedBox(width: 12),
                        dateFilter,
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: visibleOrders.isEmpty
                    ? const HistoryEmptyState(
                        icon: Icons.search_off_outlined,
                        title: 'No hay ordenes con esos filtros',
                        message:
                            'Prueba con otro texto, cambia el rango o vuelve al filtro de urgencia total.',
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
                          return HistoryOrderCard(order: visibleOrders[index]);
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
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            'Error: ${reportError(error, stack, context: 'OrderHistoryScreen')}',
          ),
        ),
      ),
    );
  }

  List<PurchaseOrder> _historyOrders(List<PurchaseOrder> orders) {
    return orders.where(isUnifiedHistoryOrder).toList(growable: false);
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
        .where((order) => matchesOrderUrgencyFilter(order, _urgencyFilter))
        .where((order) => matchesHistoryRejectionFilter(order, _rejectionFilter))
        .where((order) => matchesOrderCreatedDateRange(order, _createdDateRangeFilter))
        .where(
          (order) => orderMatchesSearch(
            order,
            _searchQuery,
            cache: _searchCache,
          ),
        )
        .toList(growable: false);

    _cachedSourceOrders = orders;
    _cachedVisibleKey = key;
    _cachedVisibleOrders = resolved;
    return resolved;
  }

  String _visibleOrdersKey() {
    return '${_urgencyFilter.name}|'
        '${_rejectionFilter.name}|'
        '${_createdDateRangeFilter?.start.millisecondsSinceEpoch ?? ''}|'
        '${_createdDateRangeFilter?.end.millisecondsSinceEpoch ?? ''}|'
        '${_searchQuery.trim().toLowerCase()}';
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

class _HistorySearchBar extends StatelessWidget {
  const _HistorySearchBar({
    required this.controller,
    required this.searchQuery,
    required this.onChanged,
    required this.onClear,
    required this.hintText,
  });

  final TextEditingController controller;
  final String searchQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: hintText,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: searchQuery.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: onClear,
              ),
      ),
      onChanged: onChanged,
    );
  }
}

class _HistoryOverviewCard extends StatelessWidget {
  const _HistoryOverviewCard({
    required this.title,
    required this.message,
    required this.count,
  });

  final String title;
  final String message;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: const Icon(Icons.inventory_2_outlined),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(message, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            count.toString(),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
