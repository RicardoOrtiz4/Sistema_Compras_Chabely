import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_pdf_preload_gate.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_summary_lines.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

_HistoryViewState _historyViewState = const _HistoryViewState();

class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen> {
  PurchaseOrderStatus? statusFilter;
  PurchaseOrderUrgency? urgencyFilter;
  DateTimeRange? dateRange;
  List<PurchaseOrder>? _cachedSourceOrders;
  String? _cachedVisibleKey;
  List<PurchaseOrder>? _cachedVisibleOrders;

  late final TextEditingController _searchController;
  final OrderSearchCache _searchCache = OrderSearchCache();
  Timer? _searchDebounce;
  String _searchQuery = '';
  int _limit = defaultOrderPageSize;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    final snapshot = _historyViewState;
    statusFilter = snapshot.statusFilter;
    urgencyFilter = snapshot.urgencyFilter;
    dateRange = snapshot.dateRange;
    _searchQuery = snapshot.searchQuery;
    _limit = snapshot.limit;
    _searchController.text = snapshot.searchQuery;
  }

  @override
  void dispose() {
    _historyViewState = _HistoryViewState(
      statusFilter: statusFilter,
      urgencyFilter: urgencyFilter,
      dateRange: dateRange,
      searchQuery: _searchQuery,
      limit: _limit,
    );
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

  void _loadMore() {
    setState(() => _limit += orderPageSizeStep);
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(userOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de ordenes'),
      ),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return _EmptyHistory(
              onCreate: () => guardedPush(context, '/orders/create'),
            );
          }

          _searchCache.retainFor(orders);
          final filtered = _resolveVisibleOrders(orders);
          final visibleOrders = filtered.take(_limit).toList(growable: false);
          final showLoadMore = filtered.length > visibleOrders.length;

          final content = Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText:
                        'Buscar por folio (000001), solicitante, cliente, fecha...',
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
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'Las limpiezas se ejecutan de forma anual mediante un programa externo. '
                  'Considera respaldar las ordenes finalizadas si las necesitas.',
                ),
              ),
              const SizedBox(height: 8),
              _FiltersBar(
                statusFilter: statusFilter,
                urgencyFilter: urgencyFilter,
                dateRange: dateRange,
                onStatusChanged: (value) =>
                    setState(() => statusFilter = value),
                onUrgencyChanged: (value) =>
                    setState(() => urgencyFilter = value),
                onDateRangeChanged: (range) =>
                    setState(() => dateRange = range),
                onClear: () => setState(() {
                  statusFilter = null;
                  urgencyFilter = null;
                  dateRange = null;
                }),
              ),
              Expanded(
                child: visibleOrders.isEmpty
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _EmptyResults(
                            onClear: () => setState(() {
                              statusFilter = null;
                              urgencyFilter = null;
                              dateRange = null;
                            }),
                          ),
                          if (showLoadMore) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _loadMore,
                              icon: const Icon(Icons.expand_more),
                              label: const Text('Ver mas'),
                            ),
                          ],
                        ],
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
                          final order = visibleOrders[index];
                          return _OrderHistoryCard(order: order);
                        },
                      ),
              ),
            ],
          );
          return OrderPdfPreloadGate(
            orders: visibleOrders,
            enabled:
                !_hasPendingSearch &&
                !_hasActiveFilters &&
                _searchQuery.trim().isEmpty,
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

  List<PurchaseOrder> _resolveVisibleOrders(List<PurchaseOrder> orders) {
    final key = _visibleOrdersKey();
    final cached = _cachedVisibleOrders;
    if (cached != null &&
        identical(_cachedSourceOrders, orders) &&
        _cachedVisibleKey == key) {
      return cached;
    }

    final resolved = orders
        .where(_isHistoryVisible)
        .where(_filterOrder)
        .where(
          (order) =>
              orderMatchesSearch(order, _searchQuery, cache: _searchCache),
        )
        .toList(growable: false);
    _cachedSourceOrders = orders;
    _cachedVisibleKey = key;
    _cachedVisibleOrders = resolved;
    return resolved;
  }

  String _visibleOrdersKey() {
    final buffer = StringBuffer()
      ..write(statusFilter?.name ?? '')
      ..write('|')
      ..write(urgencyFilter?.name ?? '')
      ..write('|')
      ..write(dateRange?.start.millisecondsSinceEpoch ?? '')
      ..write('|')
      ..write(dateRange?.end.millisecondsSinceEpoch ?? '')
      ..write('|')
      ..write(_searchQuery.trim().toLowerCase());
    return buffer.toString();
  }

  bool _filterOrder(PurchaseOrder order) {
    final statusOk = statusFilter == null || order.status == statusFilter;
    final urgencyOk = urgencyFilter == null || order.urgency == urgencyFilter;

    final dateOk =
        dateRange == null ||
        (order.createdAt != null &&
            order.createdAt!.isAfter(
              dateRange!.start.subtract(const Duration(days: 1)),
            ) &&
            order.createdAt!.isBefore(
              dateRange!.end.add(const Duration(days: 1)),
            ));

    return statusOk && urgencyOk && dateOk;
  }

  bool get _hasPendingSearch => _searchDebounce != null;

  bool get _hasActiveFilters =>
      statusFilter != null || urgencyFilter != null || dateRange != null;

  bool _isHistoryVisible(PurchaseOrder order) {
    switch (order.status) {
      case PurchaseOrderStatus.cotizaciones:
      case PurchaseOrderStatus.authorizedGerencia:
      case PurchaseOrderStatus.paymentDone:
      case PurchaseOrderStatus.contabilidad:
      case PurchaseOrderStatus.almacen:
      case PurchaseOrderStatus.eta:
        return true;

      case PurchaseOrderStatus.draft:
      case PurchaseOrderStatus.pendingCompras:
      case PurchaseOrderStatus.orderPlaced:
        return false;
    }
  }
}

class _HistoryViewState {
  const _HistoryViewState({
    this.statusFilter,
    this.urgencyFilter,
    this.dateRange,
    this.searchQuery = '',
    this.limit = defaultOrderPageSize,
  });

  final PurchaseOrderStatus? statusFilter;
  final PurchaseOrderUrgency? urgencyFilter;
  final DateTimeRange? dateRange;
  final String searchQuery;
  final int limit;
}

class _FiltersBar extends StatelessWidget {
  const _FiltersBar({
    required this.statusFilter,
    required this.urgencyFilter,
    required this.dateRange,
    required this.onStatusChanged,
    required this.onUrgencyChanged,
    required this.onDateRangeChanged,
    required this.onClear,
  });

  final PurchaseOrderStatus? statusFilter;
  final PurchaseOrderUrgency? urgencyFilter;
  final DateTimeRange? dateRange;

  final ValueChanged<PurchaseOrderStatus?> onStatusChanged;
  final ValueChanged<PurchaseOrderUrgency?> onUrgencyChanged;
  final ValueChanged<DateTimeRange?> onDateRangeChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    const statusOptions = [
      PurchaseOrderStatus.cotizaciones,
      PurchaseOrderStatus.authorizedGerencia,
      PurchaseOrderStatus.paymentDone,
      PurchaseOrderStatus.contabilidad,
      PurchaseOrderStatus.almacen,
      PurchaseOrderStatus.eta,
    ];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 600;
          final fieldWidth = isNarrow ? constraints.maxWidth : 220.0;
          final urgencyWidth = isNarrow ? constraints.maxWidth : 200.0;
          final dateButtonWidth = isNarrow ? constraints.maxWidth : null;

          return Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: fieldWidth,
                child: DropdownButtonFormField<PurchaseOrderStatus?>(
                  initialValue: statusFilter,
                  decoration: const InputDecoration(labelText: 'Estado'),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<PurchaseOrderStatus?>(
                      value: null,
                      child: Text('Todos'),
                    ),
                    ...statusOptions.map(
                      (status) => DropdownMenuItem<PurchaseOrderStatus?>(
                        value: status,
                        child: Text(
                          status.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: onStatusChanged,
                ),
              ),
              SizedBox(
                width: urgencyWidth,
                child: DropdownButtonFormField<PurchaseOrderUrgency?>(
                  initialValue: urgencyFilter,
                  decoration: const InputDecoration(labelText: 'Urgencia'),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<PurchaseOrderUrgency?>(
                      value: null,
                      child: Text('Todas'),
                    ),
                    ...PurchaseOrderUrgency.values.map(
                      (urgency) => DropdownMenuItem<PurchaseOrderUrgency?>(
                        value: urgency,
                        child: Text(
                          urgency.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: onUrgencyChanged,
                ),
              ),
              SizedBox(
                width: dateButtonWidth,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 365),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      currentDate: DateTime.now(),
                      initialDateRange: dateRange,
                    );
                    onDateRangeChanged(picked);
                  },
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    dateRange == null
                        ? 'Rango de fechas'
                        : '${dateRange!.start.toShortDate()} - ${dateRange!.end.toShortDate()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              TextButton(
                onPressed: onClear,
                child: const Text('Limpiar filtros'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox, size: 48),
            const SizedBox(height: 12),
            const Text('Aun no hay ordenes registradas'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onCreate,
              child: const Text('Crear primera orden'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 48),
            const SizedBox(height: 12),
            const Text('No hay ordenes con esos filtros.'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onClear,
              child: const Text('Limpiar filtros'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderHistoryCard extends StatelessWidget {
  const _OrderHistoryCard({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    final resendCount = order.returnCount;
    final resendLabel = resendCount <= 0
        ? null
        : (resendCount == 1 ? 'Reenviada' : 'Reenviada x$resendCount');

    final canRepeat = order.status == PurchaseOrderStatus.eta;
    final copyRoute =
        '/orders/create?copyFromId=${Uri.encodeComponent(order.id)}';

    final createdLabel = order.createdAt?.toFullDateTime() ?? 'Pendiente';

    return Card(
      child: InkWell(
        onTap: () => guardedPush(context, '/orders/${order.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(label: Text(order.urgency.label)),
                  if (resendLabel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade400),
                      ),
                      child: Text(
                        resendLabel,
                        style: TextStyle(
                          color: Colors.red.shade800,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Estado: ${order.status.label}'),
              const SizedBox(height: 8),

              OrderSummaryLines(
                order: order,
                includeClientNote: true,
                emptyLabel: 'Sin detalles.',
              ),

              const SizedBox(height: 8),
              Text('Creada: $createdLabel'),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _statusProgress(order.status)),
              const SizedBox(height: 12),
              if (canRepeat) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => guardedPush(context, copyRoute),
                    icon: const Icon(Icons.content_copy_outlined),
                    label: const Text('Volver a generar'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  double _statusProgress(PurchaseOrderStatus status) {
    final normalized = status == PurchaseOrderStatus.orderPlaced
        ? PurchaseOrderStatus.eta
        : status;
    final index = defaultStatusFlow.indexOf(normalized);
    if (index == -1) return 0;
    return (index + 1) / defaultStatusFlow.length;
  }
}
