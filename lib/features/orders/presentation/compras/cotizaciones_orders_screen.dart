import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/core/session_drafts.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/core/widgets/searchable_select.dart';

import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/application/create_order_controller.dart'; // <- OrderItemDraft
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_inline_view.dart';
import 'package:sistema_compras/features/orders/presentation/compras/supplier_quotes_dashboard_screen.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_pdf_preload_gate.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_rejection_history.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_status_duration.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_urgency_controls.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_csv_export.dart';
import 'package:sistema_compras/features/partners/data/partner_repository.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

class CotizacionesOrdersScreen extends ConsumerStatefulWidget {
  const CotizacionesOrdersScreen({this.initialTab = 0, super.key});

  final int initialTab;

  @override
  ConsumerState<CotizacionesOrdersScreen> createState() =>
      _CotizacionesOrdersScreenState();
}

class _CotizacionesOrdersScreenState
    extends ConsumerState<CotizacionesOrdersScreen>
    with SingleTickerProviderStateMixin {
  List<PurchaseOrder>? _cachedSourceOrders;
  String? _cachedVisibleKey;
  List<PurchaseOrder>? _cachedVisibleOrders;

  late final TextEditingController _searchController;
  late final TabController _tabController;
  final OrderSearchCache _searchCache = OrderSearchCache();
  Timer? _searchDebounce;
  String _searchQuery = '';
  OrderUrgencyFilter _urgencyFilter = OrderUrgencyFilter.all;
  DateTimeRange? _createdDateRangeFilter;
  int _limit = defaultOrderPageSize;
  late final int _initialTabIndex;
  late bool _dashboardActivated;
  late int _activeTabIndex;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _initialTabIndex = widget.initialTab < 0
        ? 0
        : (widget.initialTab > 1 ? 1 : widget.initialTab);
    _dashboardActivated = _initialTabIndex == 1;
    _activeTabIndex = _initialTabIndex;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: _initialTabIndex,
    )..addListener(_handleTabChange);
    if (!_dashboardActivated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _dashboardActivated) return;
        setState(() {
          _dashboardActivated = true;
        });
      });
    }
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabChange)
      ..dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _handleTabChange() {
    final nextIndex = _tabController.index;
    if (nextIndex == _activeTabIndex && (nextIndex != 1 || _dashboardActivated)) {
      return;
    }
    setState(() {
      _activeTabIndex = nextIndex;
      if (nextIndex == 1) {
        _dashboardActivated = true;
      }
    });
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
    setState(() {
      _urgencyFilter = filter;
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

  Future<void> _openOrderPreview(String orderId) async {
    final movedToDashboard = await runGuardedPdfNavigation<bool?>(
      'cotizacion-order-preview:$orderId',
      () => Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => _CotizacionOrderPreviewScreen(orderId: orderId),
        ),
      ),
    );
    if (!mounted || movedToDashboard != true) return;
    refreshOrderModuleTransitionData(ref, orderIds: <String>[orderId]);
    refreshQuoteWorkflowCounts(ref);
  }

  @override
  Widget build(BuildContext context) {
    final pendingOrdersAsync = _activeTabIndex == 0
        ? ref.watch(cotizacionesOrdersProvider)
        : null;
    final compactAppBar = useCompactOrderModuleAppBar(context);
    return Scaffold(
      appBar: AppBar(
        title: _activeTabIndex == 0
            ? pendingOrdersAsync!.when(
                data: (orders) {
                  return compactAppBar
                      ? const Text('Compras')
                      : OrderModuleAppBarTitle(
                          title: 'Compras',
                          counts: OrderUrgencyCounts.fromOrders(orders),
                          filter: _urgencyFilter,
                          onSelected: _setUrgencyFilter,
                        );
                },
                loading: () => const Text('Compras'),
                error: (_, __) => const Text('Compras'),
              )
            : const Text('Dashboard de compras'),
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
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(
            (compactAppBar && _activeTabIndex == 0 ? 60 : 0) + kTextTabBarHeight,
          ),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (compactAppBar && _activeTabIndex == 0)
                  pendingOrdersAsync!.maybeWhen(
                    data: (orders) {
                      return OrderModuleAppBarBottom(
                        counts: OrderUrgencyCounts.fromOrders(orders),
                      filter: _urgencyFilter,
                      onSelected: _setUrgencyFilter,
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),
              _CotizacionesTabBar(controller: _tabController),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _activeTabIndex == 0
              ? _buildPendientesTab()
              : const SizedBox.shrink(),
          _dashboardActivated
              ? const CotizacionesDashboardScreen(
                  mode: CotizacionesDashboardMode.compras,
                  embedded: true,
                )
              : const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _buildPendientesTab() {
    final ordersAsync = ref.watch(cotizacionesOrdersProvider);
    return ordersAsync.when(
      data: (orders) {

        _searchCache.retainFor(orders);
        final filteredOrders = _resolveVisibleOrders(orders);
        final visibleOrders = filteredOrders.take(_limit).toList(growable: false);
        final showLoadMore = filteredOrders.length > visibleOrders.length;

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
                      labelText: 'Buscar por folio (000001), solicitante, cliente...',
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
            const SizedBox(height: 12),
            Expanded(
              child: visibleOrders.isEmpty
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('No hay ordenes con ese filtro.'),
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
                        return _CotizacionOrderCard(
                          order: order,
                          onPreview: () => _openOrderPreview(order.id),
                          onDownloadCsv: () => exportOrderCsv(context, order),
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
      },
      loading: () => const AppSplash(),
      error: (error, stack) => Center(
        child: Text(
          'Error: ${reportError(error, stack, context: 'CotizacionesOrdersScreen')}',
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

    final trimmedQuery = _searchQuery.trim();
    final pendingOnly = orders;
    final resolved = trimmedQuery.isEmpty
        ? pendingOnly.toList(growable: false)
        : pendingOnly
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
        .where((order) => matchesOrderCreatedDateRange(order, _createdDateRangeFilter))
        .toList(growable: false);
    final urgencyFiltered = dateFiltered
        .where((order) => matchesOrderUrgencyFilter(order, _urgencyFilter))
        .toList(growable: false);
    _cachedSourceOrders = orders;
    _cachedVisibleKey = key;
    _cachedVisibleOrders = urgencyFiltered;
    return urgencyFiltered;
  }

  String _visibleOrdersKey() {
    final trimmedQuery = _searchQuery.trim().toLowerCase();
    return '$trimmedQuery|${_urgencyFilter.name}|'
        '${_createdDateRangeFilter?.start.millisecondsSinceEpoch ?? ''}|'
        '${_createdDateRangeFilter?.end.millisecondsSinceEpoch ?? ''}';
  }
}

class _CotizacionesTabBar extends StatelessWidget implements PreferredSizeWidget {
  const _CotizacionesTabBar({required this.controller});

  final TabController controller;

  @override
  Size get preferredSize => const Size.fromHeight(kTextTabBarHeight);

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: controller,
      tabs: [
        const Tab(text: 'Pendientes'),
        const Tab(text: 'Dashboard'),
      ],
    );
  }
}

bool _orderNeedsQuoteBatch(PurchaseOrder order) {
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

class _CotizacionOrderCard extends StatelessWidget {
  const _CotizacionOrderCard({
    required this.order,
    required this.onPreview,
    required this.onDownloadCsv,
  });

  final PurchaseOrder order;
  final VoidCallback onPreview;
  final VoidCallback onDownloadCsv;

  @override
  Widget build(BuildContext context) {
    final createdLabel = order.createdAt?.toFullDateTime() ?? 'Pendiente';
    final urgentJustification = (order.urgentJustification ?? '').trim();

    final returnCount = order.returnCount;
    final wasReturned =
        returnCount > 0 || ((order.lastReturnReason ?? '').trim().isNotEmpty);

    final resubmissions = order.resubmissionDates;

    return Card(
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
                _FolioPill(folio: order.id),
                _UrgencyPill(urgency: order.urgency),
                if (order.urgency == PurchaseOrderUrgency.urgente &&
                    urgentJustification.isNotEmpty)
                  Text(
                    urgentJustification,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.red.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (wasReturned)
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
                      returnCount > 1
                          ? 'Con historial de rechazo x$returnCount'
                          : 'Con historial de rechazo',
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
            Text('Solicitante / Area: ${order.requesterName} | ${order.areaName}'),
            Text('Creada: $createdLabel'),
            const SizedBox(height: 8),
            if (resubmissions.isNotEmpty)
              Text(
                'Ultima actualizacion despues de rechazo: '
                '${_formatResubmissionStamp(resubmissions.last, order.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 6),
            _CotizacionPendingTimePill(orderId: order.id),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPreview,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Revisar PDF'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDownloadCsv,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Descargar CSV'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CotizacionPendingTimePill extends ConsumerWidget {
  const _CotizacionPendingTimePill({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(orderEventsProvider(orderId));
    return eventsAsync.when(
      data: (events) {
        final duration = _timeInPendingCompras(events);
        if (duration == null) return const SizedBox.shrink();
        return StatusDurationPill(
          text:
              'Tiempo en autorizacion de requerimiento: ${formatDurationLabel(duration)}',
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _FolioPill extends StatelessWidget {
  const _FolioPill({required this.folio});

  final String folio;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.surfaceContainerHighest;
    final textColor = scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        folio,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _UrgencyPill extends StatelessWidget {
  const _UrgencyPill({required this.urgency});

  final PurchaseOrderUrgency urgency;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = urgency.color(scheme);
    final isDark =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        urgency.label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

Duration? _timeInPendingCompras(List<PurchaseOrderEvent> events) {
  if (events.isEmpty) return null;

  PurchaseOrderEvent? enterCotizaciones;
  for (final event in events.reversed) {
    if (event.toStatus == PurchaseOrderStatus.cotizaciones &&
        event.timestamp != null) {
      enterCotizaciones = event;
      break;
    }
  }
  if (enterCotizaciones == null) return null;

  final enterTimestamp = enterCotizaciones.timestamp!;
  PurchaseOrderEvent? enterPendiente;
  for (final event in events.reversed) {
    if (event.toStatus == PurchaseOrderStatus.pendingCompras &&
        event.timestamp != null &&
        !event.timestamp!.isAfter(enterTimestamp)) {
      enterPendiente = event;
      break;
    }
  }
  if (enterPendiente == null) return null;

  final duration = enterTimestamp.difference(enterPendiente.timestamp!);
  if (duration.isNegative) return null;
  return duration;
}

final DateFormat _resubmissionDateTimeFormat = DateFormat(
  'dd MMM yyyy - HH:mm',
);

String _formatResubmissionStamp(DateTime stamp, DateTime? createdAt) {
  return _resubmissionDateTimeFormat.format(stamp);
}


class _CotizacionOrderPreviewScreen extends ConsumerStatefulWidget {
  const _CotizacionOrderPreviewScreen({required this.orderId});

  final String orderId;

  @override
  ConsumerState<_CotizacionOrderPreviewScreen> createState() =>
      _CotizacionOrderPreviewScreenState();
}

class _CotizacionOrderPreviewScreenState
    extends ConsumerState<_CotizacionOrderPreviewScreen> {
  int _pdfRefreshTick = 0;
  PurchaseOrder? _overrideOrder;
  OrderPdfData? _overridePdfData;
  bool _isReturning = false;

  int _orderStamp(PurchaseOrder order) {
    return (order.updatedAt ?? order.createdAt)?.millisecondsSinceEpoch ?? 0;
  }

  PurchaseOrder _resolveOrder(PurchaseOrder base) {
    final override = _overrideOrder;
    if (override == null) return base;
    return _orderStamp(override) >= _orderStamp(base) ? override : base;
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdStreamProvider(widget.orderId));

    final actions = orderAsync.maybeWhen(
      data: (order) {
        if (order == null) return const <Widget>[];
        return [
          _CotizacionHistoryActionButton(
            order: order,
            onShowHistory: (events) => _showHistory(context, order, events),
          ),
        ];
      },
      orElse: () => const <Widget>[],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisar PDF'),
        actions: [
          ...actions,
        ],
      ),
      body: orderAsync.when(
        data: (order) {
          if (order == null) return const AppSplash();

          final resolvedOrder = _resolveOrder(order);
          final screenContext = context;

          final maxCorrectionsReached =
              resolvedOrder.returnCount >= _maxCorrections;

          return Column(
            children: [
              Expanded(
                child: _CotizacionPreviewPdfBody(
                  key: ValueKey(
                    '${resolvedOrder.id}-${resolvedOrder.updatedAt?.millisecondsSinceEpoch ?? 0}-$_pdfRefreshTick',
                  ),
                  order: resolvedOrder,
                  overridePdfData: _overridePdfData,
                ),
              ),
              if (maxCorrectionsReached)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    'Maximo de correcciones alcanzado. Crea otra requisicion.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (_, constraints) {
                    final completeButton = FilledButton(
                      onPressed: () async {
                        final shouldContinue = await _confirmOpenCompleteData(
                          screenContext,
                        );
                        if (!mounted || shouldContinue != true) return;
                        final navigator = Navigator.of(screenContext);
                        final result = await guardedPush<_CotizacionSaveResult>(
                          screenContext,
                          '/orders/cotizaciones/${resolvedOrder.id}',
                        );
                        if (!mounted) return;
                        if (result == null) return;
                        if (result.ready) {
                          refreshOrderModuleTransitionData(
                            ref,
                            orderIds: <String>[resolvedOrder.id],
                          );
                          refreshQuoteWorkflowCounts(ref);
                          navigator.pop(true);
                          return;
                        }
                        setState(() {
                          _overridePdfData = result.pdfData;
                          _pdfRefreshTick += 1;
                        });
                        ref.invalidate(orderByIdStreamProvider(order.id));
                      },
                      child: const Text('Completar datos'),
                    );
                    final backButton = OutlinedButton(
                      onPressed: _isReturning
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(
                                screenContext,
                              );
                              final navigator = Navigator.of(screenContext);
                              final confirmed = await _confirmReturnToPending(
                                screenContext,
                              );
                              if (!mounted || confirmed != true) return;
                              final actor = ref
                                  .read(currentUserProfileProvider)
                                  .value;
                              if (actor == null) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Perfil no disponible.'),
                                  ),
                                );
                                return;
                              }
                              setState(() => _isReturning = true);
                              try {
                                await ref
                                    .read(purchaseOrderRepositoryProvider)
                                    .returnToCompras(
                                      order: resolvedOrder,
                                      comment: '',
                                      items: resolvedOrder.items,
                                      actor: actor,
                                    );
                                if (!mounted) return;
                                navigator.pop();
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Orden ${resolvedOrder.id} regresada a autorizacion de requerimiento.',
                                    ),
                                  ),
                                );
                              } catch (error, stack) {
                                if (mounted) {
                                  final message = reportError(
                                    error,
                                    stack,
                                    context: 'CotizacionOrderPreview.return',
                                  );
                                  messenger.showSnackBar(
                                    SnackBar(content: Text(message)),
                                  );
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => _isReturning = false);
                                }
                              }
                            },
                      child: const Text(
                        'Regresar a autorizacion de requerimiento',
                      ),
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(child: backButton),
                            const SizedBox(width: 8),
                            Expanded(child: completeButton),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            'Error: ${reportError(error, stack, context: 'CotizacionOrderPreview')}',
          ),
        ),
      ),
    );
  }

  void _showHistory(
    BuildContext context,
    PurchaseOrder order,
    List<PurchaseOrderEvent> events,
  ) {
    final branding = ref.read(currentBrandingProvider);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: OrderRejectionHistory(
            branding: branding,
            order: order,
            events: events,
            showOriginalWithReturns: true,
          ),
        ),
      ),
    );
  }
}

Future<bool?> _confirmReturnToPending(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Confirmar regreso'),
      content: const Text(
        'Esta orden regresará a órdenes por confirmar y se borrará la persona que autorizó. ¿Deseas continuar?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Regresar'),
        ),
      ],
    ),
  );
}

Future<bool?> _confirmOpenCompleteData(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Continuar con compra'),
      content: const Text(
        'Para este punto ya debes contar con la compra externa del proveedor para continuar. ¿Deseas seguir?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Continuar'),
        ),
      ],
    ),
  );
}

class CotizacionOrderReviewScreen extends ConsumerStatefulWidget {
  const CotizacionOrderReviewScreen({
    required this.orderId,
    this.fromDashboard = false,
    super.key,
  });

  final String orderId;
  final bool fromDashboard;

  @override
  ConsumerState<CotizacionOrderReviewScreen> createState() =>
      _CotizacionOrderReviewScreenState();
}

class _CotizacionOrderReviewScreenState
    extends ConsumerState<CotizacionOrderReviewScreen> {
  final _itemInternalOrderController = TextEditingController();
  final TextEditingController _supplierController = TextEditingController();
  final TextEditingController _budgetController = TextEditingController();
  final Set<int> _selected = <int>{};

  final List<OrderItemDraft> _itemDrafts = [];

  bool _itemsPrefilled = false;

  @override
  void dispose() {
    _itemInternalOrderController.dispose();
    _supplierController.dispose();
    _budgetController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdStreamProvider(widget.orderId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Completar datos de compra'),
      ),
      body: orderAsync.when(
        data: (order) {
          if (order == null) return const AppSplash();

          final supplierOptions = ref.watch(userSupplierNamesProvider);

          final cachedDraft = SessionDraftStore.cotizacion(order.id);

          _syncItems(order, draftItems: cachedDraft?.items);

          final pending = _itemDrafts
              .where((item) => !_isCompleted(item))
              .length;
          final canContinue =
              _allSuppliersAssigned() && _allItemBudgetsAssigned();
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  children: [
                    Text(
                      '$pending artículos pendientes',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Selecciona los artículos pendientes y asigna proveedor y presupuesto. La OC interna se captura por artículo y es opcional en este paso.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _supplierController,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'Proveedor',
                                prefixIcon: Icon(Icons.local_shipping_outlined),
                              ),
                              onTap: () => _pickSupplier(supplierOptions),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _budgetController,
                              decoration: const InputDecoration(
                                labelText: 'Presupuesto por artículo',
                                prefixText: '\$ ',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.]'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _itemInternalOrderController,
                              decoration: const InputDecoration(
                                labelText: 'OC interna por articulo (opcional)',
                                prefixIcon: Icon(Icons.receipt_long_outlined),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton(
                                    onPressed: _selected.isEmpty
                                        ? null
                                        : _applySelection,
                                    child: const Text(
                                      'Aplicar a seleccionados',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SelectionToolbar(
                      total: _itemDrafts.length,
                      selected: _selected.length,
                      pending: pending,
                      onSelectPending: _toggleSelectPending,
                      onClear: _clearSelection,
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _itemDrafts.length; i++) ...[
                      _AssignmentItemCard(
                        item: _itemDrafts[i],
                        selected: _selected.contains(i),
                        enabled: !_isCompleted(_itemDrafts[i]),
                        onToggle: (value) =>
                            _toggleSelection(i, value ?? false),
                        onRevert: () => _revertItem(i),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 12),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(
                        onPressed: canContinue
                            ? () => _previewDraft(order)
                            : null,
                        child: const Text('Ver PDF'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            'Error: ${reportError(error, stack, context: 'CotizacionOrderReview')}',
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Envío
  // ---------------------------------------------------------------------------

  Future<void> _previewDraft(PurchaseOrder order) async {
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) {
      _showMessage('Perfil no disponible.');
      return;
    }
    try {
      final requesterProfile = await _resolveRequesterProfile(order);
      final draftPayload = _buildDraftData(order, actor.name);
      final pdfData = _buildPdfData(
        order,
        draftPayload,
        requesterName: _resolvedRequesterName(order, requesterProfile),
        requesterArea: _resolvedRequesterArea(order, requesterProfile),
        cacheSalt: DateTime.now().millisecondsSinceEpoch.toString(),
      );

      final confirmed = await runGuardedPdfNavigation<bool>(
        'cotizacion-draft-preview:${order.id}',
        () => Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => _CotizacionDraftPreviewScreen(
              pdfData: pdfData,
              submitLabel: 'Guardar y pasar a mesa de compras',
            ),
          ),
        ),
      );
      if (confirmed != true) return;

      markCotizacionesOrdersAsMoved(<String>[order.id]);
      final payload = await _persistApprovalData(
        order,
        actor.name,
        markReady: true,
      );
      final savedPdfData = _buildPdfData(
        order,
        payload,
        requesterName: _resolvedRequesterName(order, requesterProfile),
        requesterArea: _resolvedRequesterArea(order, requesterProfile),
      );
      if (!mounted) return;
      SessionDraftStore.clearCotizacion(order.id);
      refreshOrderModuleTransitionData(ref, orderIds: <String>[order.id]);
      refreshQuoteWorkflowCounts(ref);
      _showMessage(
        'Datos guardados. La orden ya quedo lista en Mesa de compras para agruparla y enviarla a Direccion General.',
      );
      Navigator.of(
        context,
      ).pop(_CotizacionSaveResult(pdfData: savedPdfData, ready: true));
    } catch (error, stack) {
      unmarkCotizacionesOrdersAsMoved(<String>[order.id]);
      if (!mounted) return;
      final message = reportError(
        error,
        stack,
        context: 'CotizacionOrderReview.save',
      );
      _showMessage(message);
    }
  }

  _CotizacionSaveData _buildDraftData(
    PurchaseOrder order,
    String reviewerName,
  ) {
    final trimmedReviewer = reviewerName.trim();
    final user = ref.read(currentUserProfileProvider).value;
    final reviewerArea = (user?.areaDisplay ?? '').trim();
    final fallbackName = (user?.name ?? '').trim();
    final fallbackArea = reviewerArea.isNotEmpty
        ? reviewerArea
        : (order.comprasReviewerArea ?? '').trim();

    final effectiveReviewerName = trimmedReviewer.isNotEmpty
        ? trimmedReviewer
        : (fallbackName.isNotEmpty
              ? fallbackName
              : (order.comprasReviewerName ?? 'Compras'));
    final effectiveReviewerArea = fallbackArea.isNotEmpty
        ? fallbackArea
        : (order.comprasReviewerArea ?? 'Compras');

    final supplierBudgets = _supplierBudgetsFromItems();
    final budget = _sumBudgets(supplierBudgets);
    return _CotizacionSaveData(
      supplierBudgets: supplierBudgets,
      budget: budget,
      reviewerName: effectiveReviewerName,
      reviewerArea: effectiveReviewerArea,
      items: List<OrderItemDraft>.from(_itemDrafts),
    );
  }

  OrderPdfData _buildPdfData(
    PurchaseOrder order,
    _CotizacionSaveData payload, {
    String? requesterName,
    String? requesterArea,
    String? cacheSalt,
  }) {
    final branding = ref.read(currentBrandingProvider);
    return buildPdfDataFromOrder(
      order,
      branding: branding,
      requesterName: requesterName,
      requesterArea: requesterArea,
      supplierBudgets: payload.supplierBudgets,
      budget: payload.budget,
      comprasReviewerName: payload.reviewerName,
      comprasReviewerArea: payload.reviewerArea,
      direccionGeneralName: order.direccionGeneralName,
      direccionGeneralArea: order.direccionGeneralArea,
      items: payload.items,
      cacheSalt: cacheSalt,
    );
  }

  Future<AppUser?> _resolveRequesterProfile(PurchaseOrder order) async {
    if (order.requesterName.trim().isNotEmpty) return null;
    final requesterId = order.requesterId.trim();
    if (requesterId.isEmpty) return null;
    return ref.read(profileRepositoryProvider).fetchProfile(requesterId);
  }

  String _resolvedRequesterName(PurchaseOrder order, AppUser? profile) {
    final orderName = order.requesterName.trim();
    if (orderName.isNotEmpty) return orderName;
    final profileName = profile?.name.trim() ?? '';
    if (profileName.isNotEmpty) return profileName;
    return order.requesterId.trim();
  }

  String _resolvedRequesterArea(PurchaseOrder order, AppUser? profile) {
    final orderArea = order.areaName.trim();
    if (orderArea.isNotEmpty) return orderArea;
    final profileArea = profile?.areaDisplay.trim() ?? '';
    if (profileArea.isNotEmpty) return profileArea;
    return order.areaId.trim();
  }

  Future<_CotizacionSaveData> _persistApprovalData(
    PurchaseOrder order,
    String reviewerName, {
    required bool markReady,
  }) async {
    final repo = ref.read(purchaseOrderRepositoryProvider);
    final payload = _buildDraftData(order, reviewerName);

    await repo.updateApprovalData(
      orderId: order.id,
      supplier: order.supplier,
      internalOrder: null,
      budget: payload.budget,
      supplierBudgets: payload.supplierBudgets,
      comprasReviewerName: payload.reviewerName,
      comprasReviewerArea: payload.reviewerArea,
      items: payload.items.map((item) => item.toModel()).toList(),
      markReady: markReady, comprasComment: '',
    );

    return payload;
  }

  // ---------------------------------------------------------------------------
  // Preview
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Validaciones
  // ---------------------------------------------------------------------------

  bool _allSuppliersAssigned() {
    return _itemDrafts.every((item) {
      final supplier = (item.supplier ?? '').trim();
      return supplier.isNotEmpty;
    });
  }

  // ---------------------------------------------------------------------------
  // Selección masiva / UI
  // ---------------------------------------------------------------------------

  bool _isCompleted(OrderItemDraft item) {
    final supplier = (item.supplier ?? '').trim();
    final budget = item.budget ?? 0;
    return supplier.isNotEmpty && budget > 0;
  }

  void _toggleSelection(int index, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(index);
      } else {
        _selected.remove(index);
      }
    });
  }

  void _toggleSelectPending(bool value) {
    setState(() {
      _selected.clear();
      if (value) {
        for (var i = 0; i < _itemDrafts.length; i++) {
          if (!_isCompleted(_itemDrafts[i])) {
            _selected.add(i);
          }
        }
      }
    });
  }

  void _clearSelection() {
    setState(() => _selected.clear());
  }

  Future<void> _pickSupplier(List<String> supplierOptions) async {
    final selected = await showSearchableSelect(
      context: context,
      title: 'Selecciona proveedor',
      options: supplierOptions,
      addLabel: 'Agregar proveedor',
      onAdd: _addSupplierFromSearch,
    );
    if (selected == null) return;
    setState(() => _supplierController.text = selected);
  }

  void _applySelection() {
    final supplier = _supplierController.text.trim();
    if (supplier.isEmpty) {
      _showMessage('Selecciona un proveedor.');
      return;
    }
    final budget = _parseBudget(_budgetController.text);
    if (budget == null || budget <= 0) {
      _showMessage('Ingresa un presupuesto válido.');
      return;
    }
    final internalOrder = _itemInternalOrderController.text.trim();

    setState(() {
      for (final index in _selected) {
        if (index < 0 || index >= _itemDrafts.length) continue;
        _itemDrafts[index] = _itemDrafts[index].copyWith(
          supplier: supplier,
          budget: budget,
          internalOrder: internalOrder.isEmpty ? null : internalOrder,
        );
      }
      _selected.clear();
      _supplierController.clear();
      _budgetController.clear();
      _itemInternalOrderController.clear();
    });
    _saveDraft(widget.orderId);
  }

  void _revertItem(int index) {
    setState(() {
      _itemDrafts[index] = _itemDrafts[index].copyWith(
        clearBudget: true,
        clearSupplier: true,
        clearInternalOrder: true,
      );
    });
    _saveDraft(widget.orderId);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------------------
  // Alta de proveedores
  // ---------------------------------------------------------------------------

  Future<String?> _addSupplierFromSearch(String query) async {
    final name = await _askNewSupplierName(query);
    if (name == null) return null;

    final confirmed = await _confirmPartnerCreation(
      type: PartnerType.supplier,
      name: name,
    );
    if (!confirmed) return null;

    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return null;

    final repo = ref.read(partnerRepositoryProvider);
    await repo.createPartner(uid: uid, type: PartnerType.supplier, name: name);
    return name;
  }

  Future<bool> _confirmPartnerCreation({
    required PartnerType type,
    required String name,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Crear ${type.label.toLowerCase()}'),
        content: Text('¿Confirmas crear ${type.label.toLowerCase()} "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<String?> _askNewSupplierName(String seed) async {
    final controller = TextEditingController(text: seed);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar proveedor'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Nombre del proveedor'),
          textInputAction: TextInputAction.done,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );

    controller.dispose();

    final trimmed = result?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  // ---------------------------------------------------------------------------
  // Sync items / budgets
  // ---------------------------------------------------------------------------

  void _syncItems(PurchaseOrder order, {List<OrderItemDraft>? draftItems}) {
    final source =
        (draftItems != null && draftItems.length == order.items.length)
        ? draftItems
        : order.items.map(OrderItemDraft.fromModel).toList();
    if (_itemsPrefilled && _itemDrafts.length == source.length) return;

    _itemDrafts
      ..clear()
      ..addAll(source);

    _itemsPrefilled = true;
  }

  void _saveDraft(String orderId) {
    SessionDraftStore.saveCotizacion(
      orderId,
      CotizacionDraft(
        items: List<OrderItemDraft>.from(_itemDrafts),
      ),
    );
  }

  _BudgetSummary _buildBudgetSummary() {
    final totals = <String, num>{};
    final missing = <String, int>{};

    for (final item in _itemDrafts) {
      final supplier = (item.supplier ?? '').trim();
      if (supplier.isEmpty) continue;

      final budget = item.budget;
      if (budget == null || budget <= 0) {
        missing[supplier] = (missing[supplier] ?? 0) + 1;
        continue;
      }

      totals[supplier] = (totals[supplier] ?? 0) + budget;
    }

    final total = totals.isEmpty ? null : _sumBudgets(totals);
    return _BudgetSummary(
      totals: totals,
      missingBySupplier: missing,
      total: total,
    );
  }

  Map<String, num> _supplierBudgetsFromItems() {
    return _buildBudgetSummary().totals;
  }

  bool _allItemBudgetsAssigned() {
    if (_itemDrafts.isEmpty) return false;
    for (final item in _itemDrafts) {
      final budget = item.budget;
      if (budget == null || budget <= 0) return false;
    }
    return true;
  }

  num? _sumBudgets(Map<String, num> budgets) {
    if (budgets.isEmpty) return null;
    var total = 0.0;
    for (final value in budgets.values) {
      total += value.toDouble();
    }
    return total;
  }
}

class _CotizacionPreviewPdfBody extends ConsumerWidget {
  const _CotizacionPreviewPdfBody({
    required this.order,
    required this.overridePdfData,
    super.key,
  });

  final PurchaseOrder order;
  final OrderPdfData? overridePdfData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(currentBrandingProvider);
    final pdfData =
        overridePdfData ?? buildPdfDataFromOrder(order, branding: branding);
    return OrderPdfInlineView(data: pdfData);
  }
}

class _CotizacionHistoryActionButton extends ConsumerWidget {
  const _CotizacionHistoryActionButton({
    required this.order,
    required this.onShowHistory,
  });

  final PurchaseOrder order;
  final ValueChanged<List<PurchaseOrderEvent>> onShowHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (order.returnCount <= 0) {
      return IconButton(
        icon: const Icon(Icons.history),
        tooltip: 'Historial de cambios',
        onPressed: null,
      );
    }

    final eventsAsync = ref.watch(orderEventsProvider(order.id));
    return eventsAsync.when(
      data: (events) {
        final canShow = events.any((event) => event.type == 'return');
        return IconButton(
          icon: const Icon(Icons.history),
          tooltip: 'Historial de cambios',
          onPressed: canShow ? () => onShowHistory(events) : null,
        );
      },
      loading: () => IconButton(
        icon: const Icon(Icons.history),
        tooltip: 'Historial de cambios',
        onPressed: null,
      ),
      error: (_, __) => IconButton(
        icon: const Icon(Icons.history),
        tooltip: 'Historial de cambios',
        onPressed: null,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Helpers globales
// -----------------------------------------------------------------------------

num? _parseBudget(String raw) {
  final cleaned = raw.replaceAll(',', '').trim();
  if (cleaned.isEmpty) return null;
  return num.tryParse(cleaned);
}

String _formatBudget(num value) {
  final formatter = NumberFormat('#,##0.##');
  return '\$${formatter.format(value)}';
}

const int _maxCorrections = 3;

class _BudgetSummary {
  const _BudgetSummary({
    required this.totals,
    required this.missingBySupplier,
    required this.total,
  });

  final Map<String, num> totals;
  final Map<String, int> missingBySupplier;
  final num? total;
}

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({
    required this.total,
    required this.selected,
    required this.pending,
    required this.onSelectPending,
    required this.onClear,
  });

  final int total;
  final int selected;
  final int pending;
  final ValueChanged<bool> onSelectPending;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final allPendingSelected = pending > 0 && selected == pending;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: allPendingSelected,
              onChanged: pending == 0
                  ? null
                  : (value) => onSelectPending(value ?? false),
            ),
            const Text('Seleccionar pendientes'),
          ],
        ),
        TextButton(
          onPressed: selected == 0 ? null : onClear,
          child: const Text('Limpiar selección'),
        ),
      ],
    );
  }
}

class _AssignmentItemCard extends StatelessWidget {
  const _AssignmentItemCard({
    required this.item,
    required this.selected,
    required this.enabled,
    required this.onToggle,
    required this.onRevert,
  });

  final OrderItemDraft item;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool?> onToggle;
  final VoidCallback onRevert;

  @override
  Widget build(BuildContext context) {
    final supplier = (item.supplier ?? '').trim();
    final internalOrder = (item.internalOrder ?? '').trim();
    final budget = item.budget ?? 0;
    final details = <String>[
      if (item.partNumber.trim().isNotEmpty) 'No. parte: ${item.partNumber}',
      'Cantidad: ${item.pieces} ${item.unit}',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(value: selected, onChanged: enabled ? onToggle : null),
                Expanded(child: Text('Item ${item.line}: ${item.description}')),
                if (!enabled)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Completo',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
            if (details.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(left: 40, bottom: 8),
                child: Text(
                  details.join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            if (supplier.isNotEmpty || budget > 0) ...[
              Text(
                supplier.isEmpty
                    ? 'Proveedor: pendiente'
                    : 'Proveedor: $supplier',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                internalOrder.isEmpty
                    ? 'OC interna: opcional'
                    : 'OC interna: $internalOrder',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                budget <= 0
                    ? 'Presupuesto: pendiente'
                    : 'Presupuesto: ${_formatBudget(budget)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (!enabled) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onRevert,
                  child: const Text('Revertir'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CotizacionDraftPreviewScreen extends StatelessWidget {
  const _CotizacionDraftPreviewScreen({
    required this.pdfData,
    required this.submitLabel,
  });

  final OrderPdfData pdfData;
  final String submitLabel;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      descendantsAreFocusable: false,
      descendantsAreTraversable: false,
      child: FocusScope(
        canRequestFocus: false,
        child: Scaffold(
          appBar: AppBar(title: const Text('Ver PDF')),
          body: Column(
            children: [
              Expanded(
                child: OrderPdfInlineView(
                  data: pdfData,
                  skipCache: true,
                  pdfBuilder: buildCotizacionPdf,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 360;
                    final cancelButton = OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar'),
                    );
                    final sendButton = FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(submitLabel),
                    );

                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          cancelButton,
                          const SizedBox(height: 8),
                          sendButton,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: cancelButton),
                        const SizedBox(width: 12),
                        Expanded(child: sendButton),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabWithBadge extends StatelessWidget {
  const _TabWithBadge({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final showBadge = count > 0;
    final display = count > 99 ? '99+' : count.toString();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        if (showBadge) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              display,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CotizacionSaveResult {
  const _CotizacionSaveResult({required this.pdfData, required this.ready});

  final OrderPdfData pdfData;
  final bool ready;
}

class _CotizacionSaveData {
  const _CotizacionSaveData({
    required this.supplierBudgets,
    required this.budget,
    required this.reviewerName,
    required this.reviewerArea,
    required this.items,
  });

  final Map<String, num> supplierBudgets;
  final num? budget;
  final String reviewerName;
  final String reviewerArea;
  final List<OrderItemDraft> items;
}
