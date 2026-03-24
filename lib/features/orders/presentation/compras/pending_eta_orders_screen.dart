import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistema_compras/core/company_branding.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_inline_view.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_card_pills.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_pdf_preload_gate.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_status_duration.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_summary_lines.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_urgency_controls.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

class PendingEtaOrdersScreen extends ConsumerStatefulWidget {
  const PendingEtaOrdersScreen({super.key});

  @override
  ConsumerState<PendingEtaOrdersScreen> createState() =>
      _PendingEtaOrdersScreenState();
}

class _PendingEtaOrdersScreenState
    extends ConsumerState<PendingEtaOrdersScreen> {
  List<PurchaseOrder>? _cachedSourceOrders;
  String? _cachedVisibleKey;
  List<PurchaseOrder>? _cachedVisibleOrders;

  late final TextEditingController _searchController;
  final OrderSearchCache _searchCache = OrderSearchCache();
  Timer? _searchDebounce;
  String _searchQuery = '';
  OrderUrgencyFilter _urgencyFilter = OrderUrgencyFilter.all;
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

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(pendingEtaOrdersProvider);
    final compactAppBar = useCompactOrderModuleAppBar(context);

    return Scaffold(
      appBar: AppBar(
        title: ordersAsync.when(
          data: (orders) => compactAppBar
              ? const Text(inTransitArrivalLabel)
              : OrderModuleAppBarTitle(
                  title: inTransitArrivalLabel,
                  counts: OrderUrgencyCounts.fromOrders(orders),
                  filter: _urgencyFilter,
                  onSelected: _setUrgencyFilter,
                ),
          loading: () => const Text(inTransitArrivalLabel),
          error: (_, __) => const Text(inTransitArrivalLabel),
        ),
        bottom: !compactAppBar
            ? null
            : ordersAsync.maybeWhen(
                data: (orders) => OrderModuleAppBarBottom(
                  counts: OrderUrgencyCounts.fromOrders(orders),
                  filter: _urgencyFilter,
                  onSelected: _setUrgencyFilter,
                ),
                orElse: () => null,
              ),
      ),
      body: ordersAsync.when(
        data: (orders) {

          _searchCache.retainFor(orders);
          final filtered = _resolveVisibleOrders(orders);
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
                          const Text('No hay órdenes con ese filtro.'),
                          if (showLoadMore) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _loadMore,
                              icon: const Icon(Icons.expand_more),
                              label: const Text('Ver más'),
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
                                label: const Text('Ver más'),
                              ),
                            );
                          }
                          final order = visibleOrders[index];
                          return _PendingEtaOrderCard(
                            order: order,
                            onViewPdf: () => _openEtaPreview(order.id),
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
            'Error: ${reportError(error, stack, context: 'PendingEtaOrdersScreen')}',
          ),
        ),
      ),
    );
  }

  Future<void> _openEtaPreview(String orderId) async {
    final result = await runGuardedPdfNavigation<bool>(
      'pending-eta-preview:$orderId',
      () => Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => _PendingEtaPreviewScreen(orderId: orderId),
        ),
      ),
    );
    if (!mounted || result != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fecha estimada registrada.')),
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

  String _visibleOrdersKey() =>
      '${_searchQuery.trim().toLowerCase()}|${_urgencyFilter.name}|'
      '${_createdDateRangeFilter?.start.millisecondsSinceEpoch ?? ''}|'
      '${_createdDateRangeFilter?.end.millisecondsSinceEpoch ?? ''}';
}

class _PendingEtaOrderCard extends StatelessWidget {
  const _PendingEtaOrderCard({
    required this.order,
    required this.onViewPdf,
  });

  final PurchaseOrder order;
  final VoidCallback onViewPdf;

  @override
  Widget build(BuildContext context) {
    final createdLabel = order.createdAt?.toFullDateTime() ?? 'Pendiente';
    final requestedDate = _requestedDeliveryDate(order);
    final urgentJustification = (order.urgentJustification ?? '').trim();

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
                OrderFolioPill(folio: order.id),
                OrderUrgencyPill(urgency: order.urgency),
                if (order.urgency == PurchaseOrderUrgency.urgente &&
                    urgentJustification.isNotEmpty)
                  Text(
                    urgentJustification,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.red.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Solicitante / Area: ${order.requesterName} | ${order.areaName}'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text('Creada: $createdLabel')),
                PreviousStatusDurationPill(
                  orderIds: [order.id],
                  fromStatus: PurchaseOrderStatus.authorizedGerencia,
                  toStatus: PurchaseOrderStatus.paymentDone,
                  label: 'Tiempo en autorizacion de pago',
                ),
              ],
            ),
            const SizedBox(height: 8),
            _OrderSummary(order: order),

            if (requestedDate != null)
              Text('Fecha solicitada: ${requestedDate.toShortDate()}'),

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onViewPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Ver PDF'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime? _requestedDeliveryDate(PurchaseOrder order) {
    return resolveRequestedDeliveryDate(order);
  }
}

class _PendingEtaPreviewScreen extends ConsumerStatefulWidget {
  const _PendingEtaPreviewScreen({required this.orderId});

  final String orderId;

  @override
  ConsumerState<_PendingEtaPreviewScreen> createState() =>
      _PendingEtaPreviewScreenState();
}

class _PendingEtaPreviewScreenState
    extends ConsumerState<_PendingEtaPreviewScreen> {
  DateTime? _selectedEtaDate;
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdStreamProvider(widget.orderId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ver PDF'),
      ),
      body: orderAsync.when(
        data: (order) {
          if (order == null) return const AppSplash();

          final branding = ref.watch(currentBrandingProvider);
          final pdfData = buildPdfDataFromOrder(
            order,
            branding: branding,
            etaDate: _selectedEtaDate,
            cacheSalt: _selectedEtaDate == null
                ? null
                : 'eta-preview-${_selectedEtaDate!.millisecondsSinceEpoch}',
          );

          return Column(
            children: [
              Expanded(child: OrderPdfInlineView(data: pdfData)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: _PendingEtaActions(
                  hasSelectedEta: _selectedEtaDate != null,
                  isSubmitting: _isSubmitting,
                  selectedEtaDate: _selectedEtaDate,
                  onPickEta: () => _pickEtaDate(order),
                  onConfirm: _selectedEtaDate == null
                      ? null
                      : () => _confirmAndSubmit(order, _selectedEtaDate!),
                ),
              ),
            ],
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            'Error: ${reportError(error, stack, context: 'PendingEtaPreviewScreen')}',
          ),
        ),
      ),
    );
  }

  Future<void> _pickEtaDate(PurchaseOrder order) async {
    final requested = _requestedDeliveryDate(order);
    final now = DateTime.now();
    final initialDate = (_selectedEtaDate ?? requested ?? now).isAfter(now)
        ? (_selectedEtaDate ?? requested ?? now)
        : now;

    final picked = await showDatePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
      initialDate: initialDate,
    );

    if (picked == null || !mounted) return;
    setState(() => _selectedEtaDate = picked);
  }

  Future<void> _confirmAndSubmit(PurchaseOrder order, DateTime etaDate) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar envío'),
        content: Text(
          'Se enviará la orden ${order.id} a Contabilidad con fecha estimada ${etaDate.toShortDate()}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      final actor = ref.read(currentUserProfileProvider).value;
      if (actor == null) {
        throw StateError('Perfil no disponible.');
      }
      final repo = ref.read(purchaseOrderRepositoryProvider);
      await repo.setEstimatedDeliveryDate(
        order: order,
        etaDate: etaDate,
        actor: actor,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error, stack) {
      if (!mounted) return;
      final message = reportError(
        error,
        stack,
        context: 'PendingEtaPreviewScreen.submit',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      setState(() => _isSubmitting = false);
    }
  }

  DateTime? _requestedDeliveryDate(PurchaseOrder order) {
    return resolveRequestedDeliveryDate(order);
  }
}

class _PendingEtaActions extends StatelessWidget {
  const _PendingEtaActions({
    required this.hasSelectedEta,
    required this.isSubmitting,
    required this.selectedEtaDate,
    required this.onPickEta,
    required this.onConfirm,
  });

  final bool hasSelectedEta;
  final bool isSubmitting;
  final DateTime? selectedEtaDate;
  final VoidCallback onPickEta;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final pickLabel = hasSelectedEta
        ? 'Cambiar fecha estimada'
        : 'Definir fecha estimada';

    final pickButton = OutlinedButton.icon(
      onPressed: isSubmitting ? null : onPickEta,
      icon: const Icon(Icons.event_outlined),
      label: Text(pickLabel),
    );

    final confirmButton = FilledButton.icon(
      onPressed: isSubmitting ? null : onConfirm,
      icon: isSubmitting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: AppSplash(compact: true, size: 18),
            )
          : const Icon(Icons.check_circle_outline),
      label: Text(
        hasSelectedEta
            ? 'Enviar a Contabilidad'
            : 'Selecciona una fecha primero',
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selectedEtaDate != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Fecha estimada a enviar: ${selectedEtaDate!.toShortDate()}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 360;
            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  pickButton,
                  const SizedBox(height: 8),
                  confirmButton,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: pickButton),
                const SizedBox(width: 12),
                Expanded(child: confirmButton),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({required this.order});
  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    return OrderSummaryLines(
      order: order,
      includeUrgentJustification: false,
      emptyLabel: '',
    );
  }
}
