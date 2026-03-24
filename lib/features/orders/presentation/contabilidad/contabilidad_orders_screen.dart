import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/session_drafts.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/create_order_controller.dart';
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

class ContabilidadOrdersScreen extends ConsumerStatefulWidget {
  const ContabilidadOrdersScreen({super.key});

  @override
  ConsumerState<ContabilidadOrdersScreen> createState() =>
      _ContabilidadOrdersScreenState();
}

class _ContabilidadOrdersScreenState
    extends ConsumerState<ContabilidadOrdersScreen> {
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
    final ordersAsync = ref.watch(contabilidadOrdersProvider);
    final compactAppBar = useCompactOrderModuleAppBar(context);

    return Scaffold(
      appBar: AppBar(
        title: ordersAsync.when(
          data: (orders) => compactAppBar
              ? const Text('Contabilidad')
              : OrderModuleAppBarTitle(
                  title: 'Contabilidad',
                  counts: OrderUrgencyCounts.fromOrders(orders),
                  filter: _urgencyFilter,
                  onSelected: _setUrgencyFilter,
                ),
          loading: () => const Text('Contabilidad'),
          error: (_, __) => const Text('Contabilidad'),
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              guardedGo(context, '/home');
            }
          },
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
                                label: const Text('Ver mÃƒÆ’Ã‚Â¡s'),
                              ),
                            );
                          }
                          final order = visibleOrders[index];
                          return _ContabilidadOrderCard(
                            order: order,
                            onReview: () => context.push(
                              '/orders/contabilidad/${order.id}',
                            ),
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
            'Error: ${reportError(error, stack, context: 'ContabilidadOrdersScreen')}',
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

class _ContabilidadOrderCard extends StatelessWidget {
  const _ContabilidadOrderCard({required this.order, required this.onReview});

  final PurchaseOrder order;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final createdLabel = order.createdAt?.toFullDateTime() ?? 'Pendiente';
    final urgentJustification = (order.urgentJustification ?? '').trim();

    final hasFactura =
        order.facturaPdfUrls.isNotEmpty ||
        ((order.facturaPdfUrl != null) &&
            order.facturaPdfUrl!.trim().isNotEmpty);

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
                if (hasFactura)
                  OrderTagPill(
                    label: 'Factura cargada',
                    backgroundColor: Colors.green.shade100,
                    borderColor: Colors.green.shade400,
                    textColor: Colors.green.shade800,
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
                  fromStatus: PurchaseOrderStatus.paymentDone,
                  toStatus: PurchaseOrderStatus.contabilidad,
                  label: 'Tiempo en transito de llegada',
                ),
              ],
            ),
            const SizedBox(height: 8),
            _OrderCardSummary(order: order),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onReview,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Ver PDF'),
            ),
          ],
        ),
      ),
    );
  }
}

class ContabilidadOrderReviewScreen extends ConsumerStatefulWidget {
  const ContabilidadOrderReviewScreen({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<ContabilidadOrderReviewScreen> createState() =>
      _ContabilidadOrderReviewScreenState();
}

class _ContabilidadOrderReviewScreenState
    extends ConsumerState<ContabilidadOrderReviewScreen> {
  final _linkController = TextEditingController();
  final List<_FacturaLinkDraft> _facturaLinks = [];
  final List<OrderItemDraft> _itemDrafts = [];
  bool _prefilled = false;
  bool _itemsPrefilled = false;
  bool _linksConfirmed = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdStreamProvider(widget.orderId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ver PDF'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              guardedGo(context, '/orders/contabilidad');
            }
          },
        ),
      ),
      body: orderAsync.when(
        data: (order) {
          if (order == null) {
            return const AppSplash();
          }
          if (!_prefilled) {
            _prefilled = true;
            final cachedDraft = SessionDraftStore.contabilidad(order.id);
            if (cachedDraft != null) {
              _facturaLinks
                ..clear()
                ..addAll(
                  cachedDraft.facturaLinks.map(
                    (url) => _FacturaLinkDraft(url: url),
                  ),
                );
              _linkController.text = cachedDraft.pendingLink;
              _linksConfirmed = cachedDraft.linksConfirmed;
              _syncItems(order, draftItems: cachedDraft.items);
            } else {
              _seedFacturaLinks(order);
              _linksConfirmed = _facturaLinks.isNotEmpty;
              _syncItems(order);
            }
          }

          final branding = ref.watch(currentBrandingProvider);
          final pdfData = buildPdfDataFromOrder(
            order,
            branding: branding,
            items: _itemDrafts,
          );
          final internalOrderCount = _itemDrafts
              .where((item) => (item.internalOrder ?? '').trim().isNotEmpty)
              .length;
          final hasAllInternalOrders = _hasAllInternalOrders();

          return Column(
            children: [
              Expanded(child: OrderPdfInlineView(data: pdfData)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: _ContabilidadActionsPanel(
                  internalOrderCount: internalOrderCount,
                  totalItems: _itemDrafts.length,
                  linkCount: _facturaLinks.length,
                  hasAllInternalOrders: hasAllInternalOrders,
                  linksConfirmed: _linksConfirmed,
                  isSubmitting: _isSubmitting,
                  onManageInternalOrders: () => _manageInternalOrders(order),
                  onManageLinks: () => _manageFacturaLinks(order),
                  onSend: _isSubmitting ||
                          !hasAllInternalOrders ||
                          _facturaLinks.isEmpty ||
                          !_linksConfirmed
                      ? null
                      : () => _handleSend(order),
                ),
              ),
            ],
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            'Error: ${reportError(error, stack, context: 'ContabilidadOrderReview')}',
          ),
        ),
      ),
    );
  }

  void _seedFacturaLinks(PurchaseOrder order) {
    _facturaLinks.clear();
    final urls = <String>[
      ...order.facturaPdfUrls,
      if (order.facturaPdfUrl != null) order.facturaPdfUrl!.trim(),
    ].where((link) => link.trim().isNotEmpty).toList();

    for (final url in urls) {
      _facturaLinks.add(_FacturaLinkDraft(url: _normalizeLink(url)));
    }
  }

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

  bool _hasAllInternalOrders() {
    if (_itemDrafts.isEmpty) return false;
    for (final item in _itemDrafts) {
      if ((item.internalOrder ?? '').trim().isEmpty) {
        return false;
      }
    }
    return true;
  }

  Future<void> _manageInternalOrders(PurchaseOrder order) async {
    final result = await showDialog<_ContabilidadInternalOrderResult>(
      context: context,
      builder: (context) => _ContabilidadInternalOrderDialog(
        initialItems: _itemDrafts,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _itemDrafts
        ..clear()
        ..addAll(result.items);
    });
    _saveDraft(order.id);
  }

  Future<void> _manageFacturaLinks(PurchaseOrder order) async {
    final result = await showDialog<_ContabilidadLinkEditorResult>(
      context: context,
      builder: (context) => _ContabilidadLinkEditorDialog(
        initialLinks: _facturaLinks,
        initialPendingLink: _linkController.text,
        onOpenLink: _openLink,
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      _facturaLinks
        ..clear()
        ..addAll(result.links);
      _linkController.text = result.pendingLink;
      _linksConfirmed = result.links.isNotEmpty;
    });
    _saveDraft(order.id);
  }

  Future<void> _handleSend(PurchaseOrder order) async {
    if (!_hasAllInternalOrders()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Captura una orden de compra interna para cada articulo antes de registrar la llegada del material.',
          ),
        ),
      );
      return;
    }
    if (_facturaLinks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos un link de factura.')),
      );
      return;
    }
    if (!_linksConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Confirma los links de factura antes de enviar.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final actor = ref.read(currentUserProfileProvider).value;
      if (actor == null) {
        throw StateError('Perfil no disponible.');
      }

      final repo = ref.read(purchaseOrderRepositoryProvider);
      await repo.completeFromContabilidad(
        order: order,
        facturaUrls: _facturaLinks.map((entry) => entry.url).toList(),
        actor: actor,
        items: _itemDrafts.map((item) => item.toModel()).toList(),
      );

      if (!mounted) return;

      SessionDraftStore.clearContabilidad(order.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Llegada registrada. El usuario ya fue notificado para confirmar cuando reciba el material.',
          ),
        ),
      );
      guardedGo(context, '/orders/contabilidad');
    } catch (error, stack) {
      if (!mounted) return;
      final message = reportError(
        error,
        stack,
        context: 'ContabilidadOrderReview.send',
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _saveDraft(String orderId) {
    SessionDraftStore.saveContabilidad(
      orderId,
      ContabilidadDraft(
        facturaLinks: _facturaLinks.map((entry) => entry.url).toList(),
        pendingLink: _linkController.text,
        linksConfirmed: _linksConfirmed,
        items: List<OrderItemDraft>.from(_itemDrafts),
      ),
    );
  }

  Future<void> _openLink(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;

    final link = _normalizeLink(trimmed);
    final uri = Uri.tryParse(link);

    if (uri == null ||
        !uri.isAbsolute ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('El link no es vÃ¡lido.')));
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el link.')),
      );
    }
  }
}

class _ContabilidadActionsPanel extends StatelessWidget {
  const _ContabilidadActionsPanel({
    required this.internalOrderCount,
    required this.totalItems,
    required this.linkCount,
    required this.hasAllInternalOrders,
    required this.linksConfirmed,
    required this.isSubmitting,
    required this.onManageInternalOrders,
    required this.onManageLinks,
    required this.onSend,
  });

  final int internalOrderCount;
  final int totalItems;
  final int linkCount;
  final bool hasAllInternalOrders;
  final bool linksConfirmed;
  final bool isSubmitting;
  final VoidCallback onManageInternalOrders;
  final VoidCallback onManageLinks;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final internalOrderSummary = totalItems == 0
        ? 'No hay artículos para capturar.'
        : hasAllInternalOrders
            ? '$internalOrderCount/$totalItems OC internas capturadas.'
            : '$internalOrderCount/$totalItems OC internas capturadas. Falta al menos una.';
    final summary = linkCount == 0
        ? 'Aún no has agregado links de factura.'
        : linksConfirmed
            ? '$linkCount link(s) de factura confirmados.'
            : '$linkCount link(s) capturados. Falta confirmarlos.';

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(internalOrderSummary),
          const SizedBox(height: 8),
          Text(summary),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onManageInternalOrders,
            icon: const Icon(Icons.confirmation_number_outlined),
            label: const Text('Agregar orden de compra interna'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onManageLinks,
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Agregar factura'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onSend,
            child: isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: AppSplash(compact: true, size: 20),
                  )
                : const Text('Registrar llegada y notificar'),
          ),
        ],
      ),
    );
  }
}

class _ContabilidadInternalOrderResult {
  const _ContabilidadInternalOrderResult({required this.items});

  final List<OrderItemDraft> items;
}

class _ContabilidadInternalOrderDialog extends StatefulWidget {
  const _ContabilidadInternalOrderDialog({required this.initialItems});

  final List<OrderItemDraft> initialItems;

  @override
  State<_ContabilidadInternalOrderDialog> createState() =>
      _ContabilidadInternalOrderDialogState();
}

class _ContabilidadInternalOrderDialogState
    extends State<_ContabilidadInternalOrderDialog> {
  late final List<OrderItemDraft> _items;
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _items = widget.initialItems
        .map((item) => item.copyWith(internalOrder: item.internalOrder))
        .toList(growable: true);
    _controllers = _items
        .map(
          (item) => TextEditingController(
            text: (item.internalOrder ?? '').trim(),
          ),
        )
        .toList(growable: false);
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final completed = _controllers
        .where((controller) => controller.text.trim().isNotEmpty)
        .length;
    return AlertDialog(
      title: const Text('Agregar orden de compra interna'),
      content: SizedBox(
        width: 720,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Captura una OC interna por cada articulo. En Contabilidad este dato es obligatorio antes de registrar la llegada del material.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '$completed/${_items.length} artículos capturados',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Item ${item.line}: ${item.description}',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Cantidad: ${item.pieces} ${item.unit}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _controllers[index],
                              decoration: const InputDecoration(
                                labelText: 'OC interna',
                                prefixIcon: Icon(Icons.confirmation_number_outlined),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: completed == _items.length && _items.isNotEmpty
              ? () => Navigator.pop(
                    context,
                    _ContabilidadInternalOrderResult(
                      items: [
                        for (var i = 0; i < _items.length; i++)
                          _items[i].copyWith(
                            internalOrder: _controllers[i].text.trim(),
                          ),
                      ],
                    ),
                  )
              : null,
          child: const Text('Guardar OCs internas'),
        ),
      ],
    );
  }
}

class _ContabilidadLinkEditorResult {
  const _ContabilidadLinkEditorResult({
    required this.links,
    required this.pendingLink,
  });

  final List<_FacturaLinkDraft> links;
  final String pendingLink;
}

class _ContabilidadLinkEditorDialog extends StatefulWidget {
  const _ContabilidadLinkEditorDialog({
    required this.initialLinks,
    required this.initialPendingLink,
    required this.onOpenLink,
  });

  final List<_FacturaLinkDraft> initialLinks;
  final String initialPendingLink;
  final Future<void> Function(String raw) onOpenLink;

  @override
  State<_ContabilidadLinkEditorDialog> createState() =>
      _ContabilidadLinkEditorDialogState();
}

class _ContabilidadLinkEditorDialogState
    extends State<_ContabilidadLinkEditorDialog> {
  late final TextEditingController _linkController;
  late final List<_FacturaLinkDraft> _links;

  @override
  void initState() {
    super.initState();
    _linkController = TextEditingController(text: widget.initialPendingLink);
    _links = widget.initialLinks
        .map((entry) => _FacturaLinkDraft(url: entry.url))
        .toList(growable: true);
  }

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar factura'),
      content: SizedBox(
        width: 640,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Agrega uno o varios links del PDF de la factura.'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _linkController,
                      decoration: const InputDecoration(
                        labelText: 'Link del PDF de la factura',
                        prefixIcon: Icon(Icons.link),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      onSubmitted: (_) => _addFacturaLink(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _addFacturaLink,
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 260,
                child: _links.isEmpty
                    ? const Center(child: Text('AÃºn no hay links agregados.'))
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final link in _links)
                            Card(
                              child: ListTile(
                                title: Text(
                                  link.url,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                leading: const Icon(Icons.link),
                                trailing: Wrap(
                                  spacing: 4,
                                  children: [
                                    IconButton(
                                      tooltip: 'Editar',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () => _editFacturaLink(link),
                                    ),
                                    IconButton(
                                      tooltip: 'Abrir link',
                                      icon: const Icon(Icons.open_in_new),
                                      onPressed: () => widget.onOpenLink(link.url),
                                    ),
                                    IconButton(
                                      tooltip: 'Quitar',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _removeFacturaLink(link),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _links.isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    _ContabilidadLinkEditorResult(
                      links: _links
                          .map((entry) => _FacturaLinkDraft(url: entry.url))
                          .toList(growable: false),
                      pendingLink: _linkController.text,
                    ),
                  ),
          child: const Text('Confirmar facturas'),
        ),
      ],
    );
  }

  void _addFacturaLink() {
    final normalized = _validateLink(_linkController.text);
    if (normalized == null) return;

    setState(() {
      _links.add(_FacturaLinkDraft(url: normalized));
      _linkController.clear();
    });
  }

  void _removeFacturaLink(_FacturaLinkDraft link) {
    setState(() => _links.removeWhere((entry) => entry.url == link.url));
  }

  Future<void> _editFacturaLink(_FacturaLinkDraft link) async {
    final urlController = TextEditingController(text: link.url);
    final updated = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar link de factura'),
        content: TextFormField(
          controller: urlController,
          decoration: const InputDecoration(
            labelText: 'Link del PDF de la factura',
            prefixIcon: Icon(Icons.link),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final normalized = _validateLink(
                urlController.text,
                excludeUrl: link.url,
              );
              if (normalized == null) return;
              Navigator.pop(context, normalized);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    urlController.dispose();
    if (updated == null) return;

    setState(() {
      final index = _links.indexWhere((entry) => entry.url == link.url);
      if (index != -1) {
        _links[index] = _FacturaLinkDraft(url: updated);
      }
    });
  }

  String? _validateLink(String raw, {String? excludeUrl}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      _showMessage('Completa el link de la factura.');
      return null;
    }

    final normalized = _normalizeLink(trimmed);
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !uri.isAbsolute ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      _showMessage('El link no es vÃ¡lido.');
      return null;
    }

    final exists = _links.any(
      (entry) => entry.url == normalized && entry.url != excludeUrl,
    );
    if (exists) {
      _showMessage('El link ya fue agregado.');
      return null;
    }

    return normalized;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FacturaLinkDraft {
  const _FacturaLinkDraft({required this.url});
  final String url;
}

String _normalizeLink(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme) return trimmed;
  return 'https://$trimmed';
}

/// Resumen pequeÃƒÆ’Ã‚Â±o para tarjetas (reemplaza el widget corrupto).
class _OrderCardSummary extends StatelessWidget {
  const _OrderCardSummary({required this.order});
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

