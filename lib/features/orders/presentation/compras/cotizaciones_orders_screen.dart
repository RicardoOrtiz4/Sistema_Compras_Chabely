import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/core/widgets/searchable_select.dart';
import 'package:sistema_compras/core/widgets/info_action.dart';

import 'package:sistema_compras/features/orders/application/create_order_controller.dart'; // <- OrderItemDraft
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_inline_view.dart';
import 'package:sistema_compras/features/orders/presentation/compras/cotizaciones_dashboard_screen.dart';
import 'package:sistema_compras/features/orders/presentation/shared/item_review_dialog.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_rejection_history.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_status_duration.dart';
import 'package:sistema_compras/features/partners/data/partner_repository.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

class CotizacionesOrdersScreen extends ConsumerStatefulWidget {
  const CotizacionesOrdersScreen({this.initialTab = 0, super.key});

  final int initialTab;

  @override
  ConsumerState<CotizacionesOrdersScreen> createState() => _CotizacionesOrdersScreenState();
}

class _CotizacionesOrdersScreenState extends ConsumerState<CotizacionesOrdersScreen> {
  late final TextEditingController _searchController;
  final OrderSearchCache _searchCache = OrderSearchCache();
  Timer? _searchDebounce;
  String _searchQuery = '';
  int _limit = defaultOrderPageSize;
  String? _lastPrefetchKey;

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
      setState(() => _searchQuery = value);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  void _loadMore() {
    setState(() => _limit += orderPageSizeStep);
  }

  void _openOrderPreview(String orderId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _CotizacionOrderPreviewScreen(orderId: orderId),
      ),
    );
  }

  void _schedulePrefetch(
    List<PurchaseOrder> orders,
    CompanyBranding branding,
  ) {
    if (orders.isEmpty) return;
    final entries = orders.take(defaultPdfPrefetchLimit).toList(growable: false);
    if (entries.isEmpty) return;

    final key = entries
        .map((order) =>
            '${order.id}:${order.updatedAt?.millisecondsSinceEpoch ?? 0}')
        .join('|');
    if (key == _lastPrefetchKey) return;
    _lastPrefetchKey = key;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        prefetchOrderPdfsForOrders(entries, branding: branding, limit: 3);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(cotizacionesOrdersPagedProvider(_limit));
    final initialTab = widget.initialTab < 0
        ? 0
        : (widget.initialTab > 1 ? 1 : widget.initialTab);

    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cotizaciones'),
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
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Pendientes'),
              Tab(text: 'Dashboard'),
            ],
          ),
          actions: [
            infoAction(
              context,
              title: 'Cotizaciones',
              message:
                  'Completa OC interna y comentarios, y asigna proveedor y presupuesto.\n'
                  'En Dashboard agrupas ordenes con el link de cotizacion y envias a Direccion.',
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _buildPendientesTab(ordersAsync),
            const CotizacionesDashboardScreen(
              mode: CotizacionesDashboardMode.compras,
              embedded: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendientesTab(AsyncValue<List<PurchaseOrder>> ordersAsync) {
    return ordersAsync.when(
      data: (orders) {
        if (orders.isEmpty) {
          return const Center(child: Text('No hay ordenes en cotizaciones.'));
        }

        _searchCache.retainFor(orders);
        final trimmedQuery = _searchQuery.trim();
        final filtered = trimmedQuery.isEmpty
            ? orders
            : orders
                .where(
                  (order) => orderMatchesSearch(order, trimmedQuery, cache: _searchCache),
                )
                .toList();
        final pendingOnly = filtered.where((order) => !_orderReady(order)).toList();
        final canLoadMore = orders.length >= _limit;

        final branding = ref.read(currentBrandingProvider);
        _schedulePrefetch(pendingOnly, branding);

        return Column(
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
            const SizedBox(height: 12),
            Expanded(
              child: pendingOnly.isEmpty
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('No hay ordenes con ese filtro.'),
                        if (canLoadMore) ...[
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
                      itemCount: pendingOnly.length + (canLoadMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        if (index >= pendingOnly.length) {
                          return Center(
                            child: OutlinedButton.icon(
                              onPressed: _loadMore,
                              icon: const Icon(Icons.expand_more),
                              label: const Text('Ver mas'),
                            ),
                          );
                        }
                        final order = pendingOnly[index];
                        return _CotizacionOrderCard(
                          order: order,
                          onPreview: () => _openOrderPreview(order.id),
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
          'Error: ${reportError(error, stack, context: 'CotizacionesOrdersScreen')}',
        ),
      ),
    );
  }
}

class _CotizacionOrderCard extends StatelessWidget {
  const _CotizacionOrderCard({
    required this.order,
    required this.onPreview,
  });

  final PurchaseOrder order;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final createdLabel = order.createdAt?.toFullDateTime() ?? 'Pendiente';

    final hasLink = order.cotizacionPdfUrls.isNotEmpty ||
        ((order.cotizacionPdfUrl ?? '').trim().isNotEmpty);

    final totalItems = order.items.length;
    final completedItems = order.items.where(_itemReady).length;

    final returnCount = order.returnCount;
    final wasReturned = returnCount > 0 ||
        ((order.lastReturnReason ?? '').trim().isNotEmpty);

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
                _UrgencyPill(urgency: order.urgency),
                if (wasReturned)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade400),
                    ),
                    child: Text(
                      returnCount > 1 ? 'Reenviada x$returnCount' : 'Reenviada',
                      style: TextStyle(
                        color: Colors.red.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (hasLink)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade400),
                    ),
                    child: Text(
                      'Link cargado',
                      style: TextStyle(
                        color: Colors.green.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (completedItems > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: completedItems == totalItems
                          ? Colors.green.shade100
                          : Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: completedItems == totalItems
                            ? Colors.green.shade400
                            : Colors.orange.shade400,
                      ),
                    ),
                    child: Text(
                      completedItems == totalItems
                          ? 'Datos completos'
                          : 'En progreso $completedItems/$totalItems',
                      style: TextStyle(
                        color: completedItems == totalItems
                            ? Colors.green.shade800
                            : Colors.orange.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Solicitante: ${order.requesterName}'),
            Text('Área: ${order.areaName}'),
            Text('Creada: $createdLabel'),
            const SizedBox(height: 8),
            _OrderCardSummary(order: order),
            const SizedBox(height: 6),
            OrderStatusDurationPill(order: order),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onPreview,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Previsualizar PDF'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderCardSummary extends StatelessWidget {
  const _OrderCardSummary({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    final supplier = (order.supplier ?? '').trim();
    final internalOrder = (order.internalOrder ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (supplier.isNotEmpty) Text('Proveedor: $supplier'),
        if (internalOrder.isNotEmpty) Text('OC interna: $internalOrder'),
        if (order.budget != null) Text('Presupuesto: ${order.budget}'),
      ],
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
    final isDark = ThemeData.estimateBrightnessForColor(color) == Brightness.dark;
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

bool _itemReady(PurchaseOrderItem item) {
  final supplier = (item.supplier ?? '').trim();
  final budget = item.budget ?? 0;
  return supplier.isNotEmpty && budget > 0;
}

bool _orderReady(PurchaseOrder order) {
  if (order.items.isEmpty) return false;
  return order.items.every(_itemReady);
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
  bool _isBusy = false;
  int _pdfRefreshTick = 0;

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdStreamProvider(widget.orderId));

    final actions = orderAsync.maybeWhen(
      data: (order) {
        if (order == null) return const <Widget>[];
        final eventsAsync = ref.watch(orderEventsProvider(order.id));
        final hasReturns = order.returnCount > 0;
        return [
          eventsAsync.when(
            data: (events) {
              final canShow =
                  hasReturns && events.any((event) => event.type == 'return');
              return IconButton(
                icon: const Icon(Icons.history),
                tooltip: 'Historial de cambios',
                onPressed: canShow ? () => _showHistory(context, order, events) : null,
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
          ),
        ];
      },
      orElse: () => const <Widget>[],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Previsualizar PDF'),
        actions: [
          ...actions,
          infoAction(
            context,
            title: 'Previsualizar PDF',
            message:
                'Revisa el PDF de la orden.\n'
                'Completar datos abre el formulario de cotizacion.\n'
                'Rechazar solicita motivos por articulo.',
          ),
        ],
      ),
      body: orderAsync.when(
        data: (order) {
          if (order == null) return const AppSplash();

          final branding = ref.watch(currentBrandingProvider);
          final actor = ref.watch(currentUserProfileProvider).value;
          final reviewerName = (order.comprasReviewerName ?? '').trim().isNotEmpty
              ? order.comprasReviewerName
              : actor?.name;
          final reviewerArea = (order.comprasReviewerArea ?? '').trim().isNotEmpty
              ? order.comprasReviewerArea
              : actor?.areaDisplay;
          final pdfData = buildPdfDataFromOrder(
            order,
            branding: branding,
            comprasReviewerName: reviewerName,
            comprasReviewerArea: reviewerArea,
          );

          final maxCorrectionsReached = order.returnCount >= _maxCorrections;

          return Column(
            children: [
              Expanded(
                child: OrderPdfInlineView(
                  key: ValueKey(
                    '${order.id}-${order.updatedAt?.millisecondsSinceEpoch ?? 0}-$_pdfRefreshTick',
                  ),
                  data: pdfData,
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
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 360;

                    final rejectButton = OutlinedButton(
                      onPressed: _isBusy || maxCorrectionsReached
                          ? null
                          : () => _handleReject(order),
                      child: _isBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: AppSplash(compact: true, size: 18),
                            )
                          : const Text('Rechazar orden'),
                    );

                    final completeButton = FilledButton(
                      onPressed: () async {
                        await guardedPush(
                          context,
                          '/orders/cotizaciones/${order.id}',
                        );
                        if (!mounted) return;
                        setState(() => _pdfRefreshTick += 1);
                      },
                      child: const Text('Completar datos'),
                    );

                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          completeButton,
                          const SizedBox(height: 8),
                          rejectButton,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: completeButton),
                        const SizedBox(width: 12),
                        Expanded(child: rejectButton),
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

  void _showHistory(BuildContext context, PurchaseOrder order, List<PurchaseOrderEvent> events) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: OrderRejectionHistory(
            order: order,
            events: events,
            showOriginalWithReturns: true,
          ),
        ),
      ),
    );
  }

  Future<void> _handleReject(PurchaseOrder order) async {
    if (order.returnCount >= _maxCorrections) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximo de correcciones alcanzado. Crea otra requisicion.'),
        ),
      );
      return;
    }

    final review = await showItemReviewDialog(
      context: context,
      order: order,
      title: 'Rechazar orden ${order.id}',
      confirmLabel: 'Rechazar',
    );
    if (review == null) return;

    setState(() => _isBusy = true);
    try {
      final actor = ref.read(currentUserProfileProvider).value;
      if (actor == null) {
        throw StateError('Perfil no disponible.');
      }

      final repo = ref.read(purchaseOrderRepositoryProvider);
      await repo.requestEdit(
        order: order,
        comment: review.summary,
        items: review.items,
        actor: actor,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Orden devuelta al solicitante.')),
      );
      Navigator.of(context).pop();
    } catch (error, stack) {
      if (!mounted) return;
      final message = reportError(error, stack, context: 'CotizacionOrderPreview.reject');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }
}

class CotizacionOrderReviewScreen extends ConsumerStatefulWidget {
  const CotizacionOrderReviewScreen({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<CotizacionOrderReviewScreen> createState() =>
      _CotizacionOrderReviewScreenState();
}

class _CotizacionOrderReviewScreenState extends ConsumerState<CotizacionOrderReviewScreen> {
  final _internalController = TextEditingController();
  final _commentController = TextEditingController();
  final TextEditingController _supplierController = TextEditingController();
  final TextEditingController _budgetController = TextEditingController();
  final Set<int> _selected = <int>{};

  final List<OrderItemDraft> _itemDrafts = [];

  bool _prefilled = false;
  bool _itemsPrefilled = false;

  @override
  void dispose() {
    _internalController.dispose();
    _commentController.dispose();
    _supplierController.dispose();
    _budgetController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdStreamProvider(widget.orderId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Completar datos de cotizacion'),
        actions: [
          infoAction(
            context,
            title: 'Completar datos de cotizacion',
            message:
                'Completa la OC interna y comentarios (opcional).\n'
                'Asigna proveedor y presupuesto por articulo.\n'
                'Guarda para continuar en el dashboard.',
          ),
        ],
      ),
      body: orderAsync.when(
        data: (order) {
          if (order == null) return const AppSplash();

          final supplierOptions = (ref.watch(userSuppliersProvider).value ?? const [])
              .map((e) => e.name)
              .toList()
            ..sort();

          if (!_prefilled) {
            _prefilled = true;
            _internalController.text = (order.internalOrder ?? '').trim();
            _commentController.text = (order.comprasComment ?? '').trim();
          }

          _syncItems(order);

          final pending = _itemDrafts.where((item) => !_isCompleted(item)).length;
          final canContinue = _allSuppliersAssigned() && _allItemBudgetsAssigned();
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
                    TextFormField(
                      controller: _internalController,
                      decoration: const InputDecoration(
                        labelText: 'Orden de compra interna',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _commentController,
                      decoration: const InputDecoration(
                        labelText: 'Comentarios extras',
                      ),
                      minLines: 2,
                      maxLines: 4,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Selecciona los artículos pendientes y asigna proveedor y presupuesto.',
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
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton(
                                    onPressed: _selected.isEmpty ? null : _applySelection,
                                    child: const Text('Aplicar a seleccionados'),
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
                        onToggle: (value) => _toggleSelection(i, value ?? false),
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
                        onPressed: canContinue ? () => _saveAndClose(order) : null,
                        child: const Text('Guardar cambios'),
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

  Future<void> _saveAndClose(PurchaseOrder order) async {
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) {
      _showMessage('Perfil no disponible.');
      return;
    }
    try {
      await _persistApprovalData(order, actor.name);
      if (!mounted) return;
      _showMessage('Datos guardados.');
      Navigator.of(context).pop();
    } catch (error, stack) {
      if (!mounted) return;
      final message =
          reportError(error, stack, context: 'CotizacionOrderReview.save');
      _showMessage(message);
    }
  }


  Future<void> _persistApprovalData(PurchaseOrder order, String reviewerName) async {
    final repo = ref.read(purchaseOrderRepositoryProvider);
    final reviewerArea = ref.read(currentUserProfileProvider).value?.areaDisplay ?? '';

    final supplierBudgets = _supplierBudgetsFromItems();
    final budget = _sumBudgets(supplierBudgets);

    await repo.updateApprovalData(
      orderId: order.id,
      supplier: order.supplier,
      internalOrder: _internalController.text.trim(),
      budget: budget,
      supplierBudgets: supplierBudgets,
      comprasComment: _commentController.text.trim(),
      comprasReviewerName: reviewerName,
      comprasReviewerArea: reviewerArea,
      items: _itemDrafts.map((item) => item.toModel()).toList(),
    );
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

    setState(() {
      for (final index in _selected) {
        if (index < 0 || index >= _itemDrafts.length) continue;
        _itemDrafts[index] =
            _itemDrafts[index].copyWith(supplier: supplier, budget: budget);
      }
      _selected.clear();
      _supplierController.clear();
      _budgetController.clear();
    });
  }

  void _revertItem(int index) {
    setState(() {
      _itemDrafts[index] =
          _itemDrafts[index].copyWith(clearBudget: true, clearSupplier: true);
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------------------
  // Alta de proveedores
  // ---------------------------------------------------------------------------

  Future<String?> _addSupplierFromSearch(String query) async {
    final name = await _askNewSupplierName(query);
    if (name == null) return null;

    final confirmed = await _confirmPartnerCreation(type: PartnerType.supplier, name: name);
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

  void _syncItems(PurchaseOrder order) {
    if (_itemsPrefilled && _itemDrafts.length == order.items.length) return;

    _itemDrafts
      ..clear()
      ..addAll(order.items.map(OrderItemDraft.fromModel));

    _itemsPrefilled = true;
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
              onChanged: pending == 0 ? null : (value) => onSelectPending(value ?? false),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                supplier.isEmpty ? 'Proveedor: pendiente' : 'Proveedor: $supplier',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                budget <= 0 ? 'Presupuesto: pendiente' : 'Presupuesto: ${_formatBudget(budget)}',
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


