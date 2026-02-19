import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/core/widgets/searchable_select.dart';

import 'package:sistema_compras/features/orders/application/create_order_controller.dart'; // <- OrderItemDraft
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/domain/shared_quote.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_inline_view.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_rejection_history.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_status_duration.dart';
import 'package:sistema_compras/features/partners/data/partner_repository.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

class CotizacionesOrdersScreen extends ConsumerStatefulWidget {
  const CotizacionesOrdersScreen({super.key});

  @override
  ConsumerState<CotizacionesOrdersScreen> createState() => _CotizacionesOrdersScreenState();
}

class _CotizacionesOrdersScreenState extends ConsumerState<CotizacionesOrdersScreen> {
  late final TextEditingController _searchController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(cotizacionesOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cotizaciones'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
      ),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('No hay órdenes en cotizaciones.'));
          }

          final filtered =
              orders.where((order) => orderMatchesSearch(order, _searchQuery)).toList();

          final branding = ref.read(currentBrandingProvider);
          prefetchOrderPdfsForOrders(filtered, branding: branding);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Buscar por folio (000001), solicitante, cliente, fecha...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No hay órdenes con ese filtro.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final order = filtered[index];
                          return _CotizacionOrderCard(
                            order: order,
                            onReview: () => context.push('/orders/cotizaciones/${order.id}'),
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
      ),
    );
  }
}

class _CotizacionOrderCard extends StatelessWidget {
  const _CotizacionOrderCard({
    required this.order,
    required this.onReview,
  });

  final PurchaseOrder order;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final createdLabel = order.createdAt?.toFullDateTime() ?? 'Pendiente';

    final hasLink = order.cotizacionPdfUrls.isNotEmpty ||
        ((order.cotizacionPdfUrl ?? '').trim().isNotEmpty);

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
              ],
            ),
            const SizedBox(height: 8),
            Text('Solicitante: ${order.requesterName}'),
            Text('Urgencia: ${order.urgency.label}'),
            Text('Creada: $createdLabel'),
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: DefaultTextStyle(
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: Colors.blue.shade900,
                    ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Área: ${order.areaName}'),
                    const SizedBox(height: 4),
                    OrahJ91ZuNL8Y2px8iYciYeHN8sfSh5eXH8(order: order),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onReview,
              child: const Text('Completar datos'),
            ),
          ],
        ),
      ),
    );
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

  final List<OrderItemDraft> _itemDrafts = [];
  final List<TextEditingController> _itemSupplierControllers = [];

  final Map<String, TextEditingController> _supplierBudgetControllers = {};
  final List<String> _supplierBudgetKeys = [];

  final Map<String, TextEditingController> _supplierLinkControllers = {};
  final List<String> _supplierLinkKeys = [];

  final Set<int> _selectedItems = <int>{};

  bool _prefilled = false;
  bool _itemsPrefilled = false;
  bool _budgetsPrefilled = false;
  bool _linksPrefilled = false;

  @override
  void dispose() {
    _internalController.dispose();
    _commentController.dispose();

    for (final controller in _itemSupplierControllers) {
      controller.dispose();
    }
    for (final controller in _supplierBudgetControllers.values) {
      controller.dispose();
    }
    for (final controller in _supplierLinkControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdStreamProvider(widget.orderId));

    return Scaffold(
      appBar: AppBar(title: const Text('Subir cotización')),
      body: orderAsync.when(
        data: (order) {
          if (order == null) return const AppSplash();

          final sharedQuotes = ref.watch(sharedQuotesProvider).value ?? const <SharedQuote>[];
          final sharedQuoteMap = {for (final quote in sharedQuotes) quote.id: quote};

          final cotizacionesOrders =
              ref.watch(cotizacionesOrdersProvider).value ?? const <PurchaseOrder>[];

          final supplierOptions = (ref.watch(userSuppliersProvider).value ?? const [])
              .map((e) => e.name)
              .toList();

          if (!_prefilled) {
            _prefilled = true;
            _internalController.text = (order.internalOrder ?? '').trim();
            _commentController.text = (order.comprasComment ?? '').trim();
          }

          _syncItems(order);
          _syncSupplierBudgets(order);
          _syncSupplierLinks(order);

          final sharedRefs = _sharedQuoteRefsBySupplier(order);
          final supplierBudgets = _currentSupplierBudgets();
          final totalBudget = _sumBudgets(supplierBudgets);

          final branding = ref.read(currentBrandingProvider);

          // Precalcula (por si tu builder usa caché interna)
          buildPdfDataFromOrder(
            order,
            branding: branding,
            supplier: order.supplier,
            internalOrder: _internalController.text,
            budget: totalBudget,
            supplierBudgets: supplierBudgets,
            comprasComment: _commentController.text,
            items: _itemDrafts,
          );

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  children: [
                    TextFormField(
                      controller: _internalController,
                      decoration: const InputDecoration(
                        labelText: 'Orden de compra interna',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),

                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Proveedores por artículo'),
                      children: [
                        const SizedBox(height: 8),
                        _BulkSupplierActions(
                          total: _itemDrafts.length,
                          selected: _selectedItems.length,
                          onSelectAll: _toggleSelectAll,
                          onClear: _clearSelection,
                        ),
                        const SizedBox(height: 8),
                        for (var i = 0; i < _itemDrafts.length; i++) ...[
                          _ItemSupplierField(
                            item: _itemDrafts[i],
                            controller: _itemSupplierControllers[i],
                            options: supplierOptions,
                            selected: _selectedItems.contains(i),
                            onSelected: (value) => _toggleSelection(i, value ?? false),
                            onAdd: _addSupplierFromSearch,
                            onChanged: (updated) => _updateItem(i, updated),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),

                    const SizedBox(height: 12),

                    _SupplierBudgetSection(
                      suppliers: _supplierBudgetKeys,
                      controllers: _supplierBudgetControllers,
                      total: totalBudget,
                      onChanged: () => setState(() {}),
                    ),

                    const SizedBox(height: 12),

                    _SharedQuotesSection(
                      suppliers: _supplierBudgetKeys,
                      sharedRefs: sharedRefs,
                      sharedQuoteMap: sharedQuoteMap,
                      onCreate: (supplier) =>
                          _createSharedQuote(order, supplier, cotizacionesOrders),
                      onLink: (supplier) => _linkSharedQuote(order, supplier, sharedQuotes),
                      onUpdate: (quote) => _updateSharedQuote(quote),
                      onUnlink: (quote) => _unlinkSharedQuote(order, quote),
                    ),

                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _commentController,
                      decoration: const InputDecoration(labelText: 'Comentarios extras'),
                      minLines: 2,
                      maxLines: 4,
                      onChanged: (_) => setState(() {}),
                    ),

                    const SizedBox(height: 12),

                    _SupplierLinksSection(
                      suppliers: _supplierLinkKeys,
                      controllers: _supplierLinkControllers,
                      onOpen: _openLink,
                      onChanged: () => setState(() {}),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => _showPreview(order, sharedQuoteMap),
                    child: const Text('Previsualizar PDF'),
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

  Future<void> _handleSend(
    PurchaseOrder order,
    Map<String, SharedQuote> sharedQuoteMap,
  ) async {
    if (!_allSuppliersAssigned()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa los proveedores de todos los artículos.')),
      );
      return;
    }
    if (!_allBudgetsAssigned()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa el presupuesto de cada proveedor.')),
      );
      return;
    }
    if (!_allLinksAssigned()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega el link de cotización por proveedor.')),
      );
      return;
    }

    final sharedIssue = _sharedQuoteIssue(order, sharedQuoteMap);
    if (sharedIssue != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sharedIssue)));
      return;
    }

    try {
      final actor = ref.read(currentUserProfileProvider).value;
      if (actor == null) throw StateError('Perfil no disponible.');

      final repo = ref.read(purchaseOrderRepositoryProvider);

      await _persistApprovalData(order, actor.name);

      final links = _buildCotizacionLinks(order, sharedQuoteMap);

      await repo.sendToDireccionWithCotizacion(
        order: order,
        cotizacionLinks: links,
        actor: actor,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Orden enviada a Dirección General.')),
      );
      context.go('/orders/cotizaciones');
    } catch (error, stack) {
      if (!mounted) return;
      final message = reportError(error, stack, context: 'CotizacionOrderReview.send');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _persistApprovalData(PurchaseOrder order, String reviewerName) async {
    final repo = ref.read(purchaseOrderRepositoryProvider);
    final reviewerArea = ref.read(currentUserProfileProvider).value?.areaDisplay ?? '';

    final supplierBudgets = _currentSupplierBudgets();
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
  // Links por proveedor (excluyendo compartidos)
  // ---------------------------------------------------------------------------

  void _syncSupplierLinks(PurchaseOrder order) {
    final suppliers = _supplierBudgetKeys;
    final sharedSuppliers = _sharedSuppliers(order);
    final seededLinks = _seedLinksFromOrder(order);
    final unassigned = _seedUnassignedLinks(order);

    final nextKeys = <String>[];
    final existingKeys = _supplierLinkControllers.keys.toSet();

    for (final supplier in suppliers) {
      final supplierKey = _normalizeSupplierKey(supplier);

      // Si es proveedor compartido -> no pide link individual
      if (sharedSuppliers.contains(supplierKey)) {
        if (_supplierLinkControllers.containsKey(supplier)) {
          _supplierLinkControllers[supplier]?.dispose();
          _supplierLinkControllers.remove(supplier);
        }
        continue;
      }

      nextKeys.add(supplier);

      final existing = _supplierLinkControllers[supplier];
      final seed = seededLinks[supplierKey] ??
          (unassigned.isNotEmpty ? unassigned.removeAt(0) : '');

      if (existing == null) {
        _supplierLinkControllers[supplier] = TextEditingController(text: seed);
      } else if (!_linksPrefilled && existing.text.trim().isEmpty && seed.isNotEmpty) {
        existing.text = seed;
      }
    }

    for (final key in existingKeys) {
      if (!nextKeys.contains(key)) {
        _supplierLinkControllers[key]?.dispose();
        _supplierLinkControllers.remove(key);
      }
    }

    _supplierLinkKeys
      ..clear()
      ..addAll(nextKeys);

    _linksPrefilled = true;
  }

  Map<String, String> _seedLinksFromOrder(PurchaseOrder order) {
    final seeded = <String, String>{};

    if (order.cotizacionLinks.isNotEmpty) {
      for (final link in order.cotizacionLinks) {
        final supplier = link.supplier.trim();
        final url = link.url.trim();
        if (supplier.isEmpty || url.isEmpty) continue;
        seeded[_normalizeSupplierKey(supplier)] = url;
      }
    }
    return seeded;
  }

  List<String> _seedUnassignedLinks(PurchaseOrder order) {
    final unassigned = <String>[];

    if (order.cotizacionLinks.isNotEmpty) {
      for (final link in order.cotizacionLinks) {
        if (link.supplier.trim().isEmpty && link.url.trim().isNotEmpty) {
          unassigned.add(link.url.trim());
        }
      }
      return unassigned;
    }

    for (final url in order.cotizacionPdfUrls) {
      final trimmed = url.trim();
      if (trimmed.isNotEmpty) unassigned.add(trimmed);
    }
    final single = order.cotizacionPdfUrl?.trim();
    if (single != null && single.isNotEmpty && !unassigned.contains(single)) {
      unassigned.insert(0, single);
    }
    return unassigned;
  }

  Map<String, String> _currentSupplierLinks() {
    final links = <String, String>{};
    for (final supplier in _supplierLinkKeys) {
      final controller = _supplierLinkControllers[supplier];
      final raw = controller?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      links[supplier] = _normalizeLink(raw);
    }
    return links;
  }

  bool _allLinksAssigned() {
    if (_supplierLinkKeys.isEmpty) return true;
    for (final supplier in _supplierLinkKeys) {
      final controller = _supplierLinkControllers[supplier];
      final raw = controller?.text.trim() ?? '';
      if (raw.isEmpty) return false;
      if (!_isValidUrl(raw)) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Cotizaciones compartidas
  // ---------------------------------------------------------------------------

  String? _sharedQuoteIssue(PurchaseOrder order, Map<String, SharedQuote> sharedQuoteMap) {
    if (order.sharedQuoteRefs.isEmpty) return null;

    for (final ref in order.sharedQuoteRefs) {
      if (ref.quoteId.trim().isEmpty) continue;

      final quote = sharedQuoteMap[ref.quoteId];
      if (quote == null) return 'Falta la cotización compartida de ${ref.supplier}.';
      if (quote.pdfUrl.trim().isEmpty) {
        return 'Agrega el link de la cotización compartida de ${quote.supplier}.';
      }
      if (quote.needsUpdate) {
        return 'La cotización compartida de ${quote.supplier} requiere actualización.';
      }
    }
    return null;
  }

  List<CotizacionLink> _buildCotizacionLinks(
    PurchaseOrder order,
    Map<String, SharedQuote> sharedQuoteMap,
  ) {
    final links = <CotizacionLink>[];

    final directLinks = _currentSupplierLinks();
    for (final entry in directLinks.entries) {
      final supplier = entry.key.trim();
      final url = entry.value.trim();
      if (supplier.isEmpty || url.isEmpty) continue;
      _addUniqueCotizacionLink(links, CotizacionLink(supplier: supplier, url: url));
    }

    for (final ref in order.sharedQuoteRefs) {
      if (ref.quoteId.trim().isEmpty) continue;
      final quote = sharedQuoteMap[ref.quoteId];
      if (quote == null) continue;

      final url = quote.pdfUrl.trim();
      if (url.isEmpty) continue;

      final supplier =
          ref.supplier.trim().isNotEmpty ? ref.supplier.trim() : quote.supplier.trim();
      if (supplier.isEmpty) continue;

      _addUniqueCotizacionLink(links, CotizacionLink(supplier: supplier, url: url));
    }

    return links;
  }

  void _addUniqueCotizacionLink(List<CotizacionLink> links, CotizacionLink next) {
    final normalizedSupplier = next.supplier.trim().toLowerCase();
    final normalizedUrl = next.url.trim().toLowerCase();

    final exists = links.any(
      (link) =>
          link.supplier.trim().toLowerCase() == normalizedSupplier &&
          link.url.trim().toLowerCase() == normalizedUrl,
    );
    if (!exists) links.add(next);
  }

  Map<String, SharedQuoteRef> _sharedQuoteRefsBySupplier(PurchaseOrder order) {
    final refs = <String, SharedQuoteRef>{};
    for (final ref in order.sharedQuoteRefs) {
      final key = _normalizeSupplierKey(ref.supplier);
      if (key.isEmpty) continue;
      refs[key] = ref;
    }
    return refs;
  }

  Set<String> _sharedSuppliers(PurchaseOrder order) {
    final suppliers = <String>{};
    for (final ref in order.sharedQuoteRefs) {
      final key = _normalizeSupplierKey(ref.supplier);
      if (key.isNotEmpty) suppliers.add(key);
    }
    return suppliers;
  }

  String _normalizeSupplierKey(String value) => value.trim().toLowerCase();

  bool _isValidUrl(String raw) {
    final link = _normalizeLink(raw);
    final uri = Uri.tryParse(link);
    return uri != null &&
        uri.isAbsolute &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  Future<void> _createSharedQuote(
    PurchaseOrder order,
    String supplier,
    List<PurchaseOrder> availableOrders,
  ) async {
    final supplierKey = _normalizeSupplierKey(supplier);

    final candidates = availableOrders
        .where((entry) => _orderHasSupplier(entry, supplierKey))
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    if (!candidates.any((entry) => entry.id == order.id)) {
      candidates.insert(0, order);
    }

    final selected = <String>{order.id};
    final linkController = TextEditingController();

    final result = await showDialog<_SharedQuoteDraftResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cotización compartida: $supplier'),
        content: StatefulBuilder(
          builder: (context, setState) => SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Selecciona las órdenes que compartirán esta cotización.'),
                  const SizedBox(height: 8),
                  if (candidates.isEmpty)
                    const Text('No hay otras órdenes con este proveedor.'),
                  for (final entry in candidates)
                    CheckboxListTile(
                      value: selected.contains(entry.id),
                      onChanged: entry.id == order.id
                          ? null
                          : (value) {
                              setState(() {
                                if (value == true) {
                                  selected.add(entry.id);
                                } else {
                                  selected.remove(entry.id);
                                }
                              });
                            },
                      title: Text(entry.requesterName),
                      subtitle: Text(entry.areaName),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: linkController,
                    decoration: const InputDecoration(
                      labelText: 'Link del PDF (Drive)',
                      prefixIcon: Icon(Icons.link),
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Si no tienes el link, déjalo vacío. Quedará pendiente de actualizar.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(
                context,
                _SharedQuoteDraftResult(
                  orderIds: selected.toList(),
                  link: linkController.text.trim(),
                ),
              );
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    linkController.dispose();
    if (result == null) return;

    if (result.orderIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos una orden.')),
      );
      return;
    }
    if (result.link.isNotEmpty && !_isValidUrl(result.link)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El link no es válido.')),
      );
      return;
    }

    try {
      final repo = ref.read(purchaseOrderRepositoryProvider);
      final quote = await repo.createSharedQuote(
        supplier: supplier,
        orderIds: result.orderIds,
        pdfUrl: result.link.isEmpty ? null : _normalizeLink(result.link),
      );
      await repo.linkOrdersToSharedQuote(quote: quote, orderIds: result.orderIds);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cotización compartida creada.')),
      );
    } catch (error, stack) {
      if (!mounted) return;
      final message = reportError(
        error,
        stack,
        context: 'CotizacionOrderReview.createSharedQuote',
      );
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _linkSharedQuote(
    PurchaseOrder order,
    String supplier,
    List<SharedQuote> sharedQuotes,
  ) async {
    final supplierKey = _normalizeSupplierKey(supplier);

    final candidates = sharedQuotes
        .where((quote) => _normalizeSupplierKey(quote.supplier) == supplierKey)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay cotizaciones compartidas para este proveedor.')),
      );
      return;
    }

    final selectedId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Vincular cotización: $supplier'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: candidates.length,
            itemBuilder: (context, index) {
              final quote = candidates[index];
              return ListTile(
                title: Text('ID ${quote.id}'),
                subtitle: Text(
                  quote.pdfUrl.trim().isEmpty
                      ? 'Sin link'
                      : 'Link cargado (${quote.orderIds.length} órdenes)',
                ),
                onTap: () => Navigator.pop(context, quote.id),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (selectedId == null) return;

    final selectedQuote = candidates.firstWhere((quote) => quote.id == selectedId);

    try {
      final repo = ref.read(purchaseOrderRepositoryProvider);
      await repo.linkOrdersToSharedQuote(quote: selectedQuote, orderIds: [order.id]);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Orden vinculada a cotización compartida.')),
      );
    } catch (error, stack) {
      if (!mounted) return;
      final message = reportError(error, stack, context: 'CotizacionOrderReview.linkSharedQuote');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _updateSharedQuote(SharedQuote quote) async {
    final controller = TextEditingController(text: quote.pdfUrl);

    final updated = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Actualizar cotización compartida'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Link del PDF (Drive)',
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
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (updated == null) return;

    if (updated.isEmpty || !_isValidUrl(updated)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El link no es válido.')),
      );
      return;
    }

    try {
      final repo = ref.read(purchaseOrderRepositoryProvider);
      await repo.updateSharedQuoteLink(quote: quote, pdfUrl: _normalizeLink(updated));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cotización compartida actualizada.')),
      );
    } catch (error, stack) {
      if (!mounted) return;
      final message =
          reportError(error, stack, context: 'CotizacionOrderReview.updateSharedQuote');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _unlinkSharedQuote(PurchaseOrder order, SharedQuote quote) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desvincular cotización compartida'),
        content: Text(
          'Se quitará la cotización compartida de ${quote.supplier} para la orden ${order.id}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desvincular'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final repo = ref.read(purchaseOrderRepositoryProvider);
      await repo.unlinkOrderFromSharedQuote(order: order, quote: quote);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cotización compartida desvinculada.')),
      );
    } catch (error, stack) {
      if (!mounted) return;
      final message =
          reportError(error, stack, context: 'CotizacionOrderReview.unlinkSharedQuote');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  bool _orderHasSupplier(PurchaseOrder order, String supplierKey) {
    if (supplierKey.isEmpty) return false;
    for (final item in order.items) {
      final key = _normalizeSupplierKey((item.supplier ?? '').trim());
      if (key == supplierKey) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Preview
  // ---------------------------------------------------------------------------

  Future<void> _showPreview(
    PurchaseOrder order,
    Map<String, SharedQuote> sharedQuoteMap,
  ) async {
    final branding = ref.read(currentBrandingProvider);

    final supplierBudgets = _currentSupplierBudgets();
    final totalBudget = _sumBudgets(supplierBudgets);

    final data = buildPdfDataFromOrder(
      order,
      branding: branding,
      supplier: order.supplier,
      internalOrder: _internalController.text,
      budget: totalBudget,
      supplierBudgets: supplierBudgets,
      comprasComment: _commentController.text,
      items: _itemDrafts,
    );

    final canSubmit = _allSuppliersAssigned() &&
        _allBudgetsAssigned() &&
        _allLinksAssigned() &&
        _sharedQuoteIssue(order, sharedQuoteMap) == null;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _CotizacionPdfPreviewScreen(
          order: order,
          data: data,
          canSubmit: canSubmit,
          hint: canSubmit ? null : _submissionHint(order, sharedQuoteMap),
          onSubmit: () => _handleSend(order, sharedQuoteMap),
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El link no es válido.')),
      );
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el link.')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Validaciones
  // ---------------------------------------------------------------------------

  bool _allSuppliersAssigned() {
    return _itemDrafts.every((item) {
      final supplier = (item.supplier ?? '').trim();
      return supplier.isNotEmpty;
    });
  }

  String _submissionHint(PurchaseOrder order, Map<String, SharedQuote> sharedQuoteMap) {
    if (!_allSuppliersAssigned()) return 'Completa los proveedores de todos los artículos.';
    if (!_allBudgetsAssigned()) return 'Completa el presupuesto de cada proveedor.';
    if (!_allLinksAssigned()) return 'Agrega el link de cotización por proveedor.';
    return _sharedQuoteIssue(order, sharedQuoteMap) ?? '';
  }

  // ---------------------------------------------------------------------------
  // Selección masiva / UI
  // ---------------------------------------------------------------------------

  void _toggleSelection(int index, bool selected) {
    setState(() {
      if (selected) {
        _selectedItems.add(index);
      } else {
        _selectedItems.remove(index);
      }
    });
  }

  void _toggleSelectAll(bool value) {
    setState(() {
      if (value) {
        _selectedItems
          ..clear()
          ..addAll(List<int>.generate(_itemDrafts.length, (i) => i));
      } else {
        _selectedItems.clear();
      }
    });
  }

  void _clearSelection() {
    setState(() => _selectedItems.clear());
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

    for (final controller in _itemSupplierControllers) {
      controller.dispose();
    }

    _itemSupplierControllers
      ..clear()
      ..addAll(_itemDrafts.map((item) => TextEditingController(text: item.supplier ?? '')));

    _itemsPrefilled = true;
  }

  void _updateItem(int index, OrderItemDraft updated) {
    setState(() => _itemDrafts[index] = updated);
  }

  void _syncSupplierBudgets(PurchaseOrder order) {
    final suppliers = _extractSuppliers();
    final seedBudgets = order.supplierBudgets;

    final nextKeys = suppliers.toList()..sort();
    final existingKeys = _supplierBudgetControllers.keys.toSet();

    for (final key in nextKeys) {
      final existing = _supplierBudgetControllers[key];
      if (existing == null) {
        final seed = seedBudgets[key];
        _supplierBudgetControllers[key] = TextEditingController(
          text: seed == null ? '' : seed.toString(),
        );
      } else if (!_budgetsPrefilled && existing.text.trim().isEmpty) {
        final seed = seedBudgets[key];
        if (seed != null) existing.text = seed.toString();
      }
    }

    for (final key in existingKeys) {
      if (!nextKeys.contains(key)) {
        _supplierBudgetControllers[key]?.dispose();
        _supplierBudgetControllers.remove(key);
      }
    }

    _supplierBudgetKeys
      ..clear()
      ..addAll(nextKeys);

    _budgetsPrefilled = true;
  }

  Set<String> _extractSuppliers() {
    final suppliers = <String>{};
    for (final item in _itemDrafts) {
      final supplier = (item.supplier ?? '').trim();
      if (supplier.isNotEmpty) suppliers.add(supplier);
    }
    return suppliers;
  }

  Map<String, num> _currentSupplierBudgets() {
    final budgets = <String, num>{};

    for (final supplier in _supplierBudgetKeys) {
      final controller = _supplierBudgetControllers[supplier];
      final raw = controller?.text.trim() ?? '';
      if (raw.isEmpty) continue;

      final parsed = num.tryParse(raw);
      if (parsed != null) budgets[supplier] = parsed;
    }

    return budgets;
  }

  bool _allBudgetsAssigned() {
    if (_supplierBudgetKeys.isEmpty) return false;

    for (final supplier in _supplierBudgetKeys) {
      final controller = _supplierBudgetControllers[supplier];
      final raw = controller?.text.trim() ?? '';
      final parsed = num.tryParse(raw);
      if (parsed == null || parsed <= 0) return false;
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

String _normalizeLink(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme) return trimmed;
  return 'https://$trimmed';
}

// -----------------------------------------------------------------------------
// Preview screen
// -----------------------------------------------------------------------------

class _CotizacionPdfPreviewScreen extends ConsumerStatefulWidget {
  const _CotizacionPdfPreviewScreen({
    required this.order,
    required this.data,
    required this.canSubmit,
    required this.onSubmit,
    this.hint,
  });

  final PurchaseOrder order;
  final OrderPdfData data;
  final bool canSubmit;
  final String? hint;
  final Future<void> Function() onSubmit;

  @override
  ConsumerState<_CotizacionPdfPreviewScreen> createState() => _CotizacionPdfPreviewScreenState();
}

class _CotizacionPdfPreviewScreenState extends ConsumerState<_CotizacionPdfPreviewScreen> {
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(orderEventsProvider(widget.order.id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Previsualizar PDF'),
        actions: [
          eventsAsync.when(
            data: (events) => IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Historial de cambios',
              onPressed: events.isEmpty ? null : () => _showHistory(context, widget.order, events),
            ),
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
        ],
      ),
      body: Column(
        children: [
          Expanded(child: OrderPdfInlineView(data: widget.data)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: _isSubmitting || !widget.canSubmit
                        ? null
                        : () async {
                            setState(() => _isSubmitting = true);
                            await widget.onSubmit();
                            if (mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Enviar a Dirección General'),
                  ),
                  if (!widget.canSubmit && widget.hint != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.hint!,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
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
}

// -----------------------------------------------------------------------------
// UI components
// -----------------------------------------------------------------------------

class _SharedQuoteDraftResult {
  const _SharedQuoteDraftResult({
    required this.orderIds,
    required this.link,
  });

  final List<String> orderIds;
  final String link;
}

class _SharedQuotesSection extends StatelessWidget {
  const _SharedQuotesSection({
    required this.suppliers,
    required this.sharedRefs,
    required this.sharedQuoteMap,
    required this.onCreate,
    required this.onLink,
    required this.onUpdate,
    required this.onUnlink,
  });

  final List<String> suppliers;
  final Map<String, SharedQuoteRef> sharedRefs;
  final Map<String, SharedQuote> sharedQuoteMap;
  final Future<void> Function(String supplier) onCreate;
  final Future<void> Function(String supplier) onLink;
  final Future<void> Function(SharedQuote quote) onUpdate;
  final Future<void> Function(SharedQuote quote) onUnlink;

  @override
  Widget build(BuildContext context) {
    if (suppliers.isEmpty) {
      return const Text('Asigna proveedores para gestionar cotizaciones compartidas.');
    }
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Cotizaciones compartidas'),
      children: [
        const SizedBox(height: 8),
        for (final supplier in suppliers) ...[
          _SharedQuoteSupplierCard(
            supplier: supplier,
            sharedRef: _findSharedRef(sharedRefs, supplier),
            sharedQuoteMap: sharedQuoteMap,
            onCreate: onCreate,
            onLink: onLink,
            onUpdate: onUpdate,
            onUnlink: onUnlink,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  SharedQuoteRef? _findSharedRef(Map<String, SharedQuoteRef> refs, String supplier) {
    final key = supplier.trim().toLowerCase();
    if (key.isEmpty) return null;
    return refs[key];
  }
}

class _SharedQuoteSupplierCard extends StatelessWidget {
  const _SharedQuoteSupplierCard({
    required this.supplier,
    required this.sharedRef,
    required this.sharedQuoteMap,
    required this.onCreate,
    required this.onLink,
    required this.onUpdate,
    required this.onUnlink,
  });

  final String supplier;
  final SharedQuoteRef? sharedRef;
  final Map<String, SharedQuote> sharedQuoteMap;
  final Future<void> Function(String supplier) onCreate;
  final Future<void> Function(String supplier) onLink;
  final Future<void> Function(SharedQuote quote) onUpdate;
  final Future<void> Function(SharedQuote quote) onUnlink;

  @override
  Widget build(BuildContext context) {
    final quote = sharedRef == null ? null : sharedQuoteMap[sharedRef!.quoteId];
    final fallbackQuote = sharedRef == null
        ? null
        : SharedQuote(
            id: sharedRef!.quoteId,
            supplier: sharedRef!.supplier,
            orderIds: const [],
            pdfUrl: '',
          );

    final hasShared = sharedRef != null;
    final hasLink = (quote?.pdfUrl ?? '').trim().isNotEmpty;
    final needsUpdate = quote?.needsUpdate ?? false;

    final statusText = hasShared
        ? (quote == null
            ? 'Cotización compartida no encontrada'
            : needsUpdate
                ? 'Requiere actualización'
                : hasLink
                    ? 'Link cargado'
                    : 'Sin link')
        : 'No compartida';

    final statusColor = needsUpdate
        ? Colors.red.shade200
        : hasShared
            ? Colors.blue.shade100
            : Colors.grey.shade200;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(supplier, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(statusText, style: Theme.of(context).textTheme.bodySmall),
            ),
            if ((quote?.pdfUrl ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                quote!.pdfUrl,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (!hasShared)
                  OutlinedButton.icon(
                    onPressed: () => onCreate(supplier),
                    icon: const Icon(Icons.add),
                    label: const Text('Crear'),
                  ),
                if (!hasShared)
                  TextButton(
                    onPressed: () => onLink(supplier),
                    child: const Text('Vincular existente'),
                  ),
                if (hasShared)
                  OutlinedButton.icon(
                    onPressed: quote == null ? null : () => onUpdate(quote),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar link'),
                  ),
                if (hasShared)
                  TextButton(
                    onPressed: () {
                      final target = quote ?? fallbackQuote;
                      if (target != null) onUnlink(target);
                    },
                    child: const Text('Desvincular'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SupplierLinksSection extends StatelessWidget {
  const _SupplierLinksSection({
    required this.suppliers,
    required this.controllers,
    required this.onOpen,
    required this.onChanged,
  });

  final List<String> suppliers;
  final Map<String, TextEditingController> controllers;
  final Future<void> Function(String link) onOpen;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    if (suppliers.isEmpty) {
      return const Text('Los proveedores compartidos no requieren link individual.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Links de cotización por proveedor'),
        const SizedBox(height: 8),
        for (final supplier in suppliers) ...[
          TextFormField(
            controller: controllers[supplier],
            decoration: InputDecoration(
              labelText: supplier,
              prefixIcon: const Icon(Icons.link),
              suffixIcon: IconButton(
                tooltip: 'Abrir link',
                icon: const Icon(Icons.open_in_new),
                onPressed: () {
                  final raw = controllers[supplier]?.text.trim() ?? '';
                  if (raw.isNotEmpty) onOpen(raw);
                },
              ),
            ),
            keyboardType: TextInputType.url,
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          'Si el proveedor usa cotización compartida, el link se gestiona arriba.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ItemSupplierField extends StatelessWidget {
  const _ItemSupplierField({
    required this.item,
    required this.controller,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.onChanged,
    this.onAdd,
  });

  final OrderItemDraft item;
  final TextEditingController controller;
  final List<String> options;
  final bool selected;
  final ValueChanged<bool?> onSelected;
  final ValueChanged<OrderItemDraft> onChanged;
  final Future<String?> Function(String query)? onAdd;

  @override
  Widget build(BuildContext context) {
    final hasOptions = options.isNotEmpty;
    final canSearch = hasOptions || onAdd != null;

    Future<void> pickSupplier() async {
      final selectedSupplier = await showSearchableSelect(
        context: context,
        title: 'Selecciona proveedor',
        options: options,
        addLabel: 'Agregar proveedor',
        onAdd: onAdd,
      );
      if (selectedSupplier == null) return;

      controller.text = selectedSupplier;
      onChanged(item.copyWith(supplier: selectedSupplier));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(value: selected, onChanged: onSelected),
                Expanded(child: Text('Item ${item.line}: ${item.description}')),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: controller,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Proveedor',
                suffixIcon: canSearch
                    ? IconButton(
                        tooltip: 'Buscar',
                        icon: const Icon(Icons.search),
                        onPressed: pickSupplier,
                      )
                    : null,
              ),
              onTap: canSearch ? pickSupplier : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _BulkSupplierActions extends StatelessWidget {
  const _BulkSupplierActions({
    required this.total,
    required this.selected,
    required this.onSelectAll,
    required this.onClear,
  });

  final int total;
  final int selected;
  final ValueChanged<bool> onSelectAll;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final allSelected = total > 0 && selected == total;

    return Row(
      children: [
        Checkbox(
          value: allSelected,
          onChanged: total == 0 ? null : (value) => onSelectAll(value ?? false),
        ),
        const Text('Seleccionar todo'),
        const Spacer(),
        TextButton(
          onPressed: selected == 0 ? null : onClear,
          child: const Text('Limpiar'),
        ),
      ],
    );
  }
}

class _SupplierBudgetSection extends StatelessWidget {
  const _SupplierBudgetSection({
    required this.suppliers,
    required this.controllers,
    required this.total,
    required this.onChanged,
  });

  final List<String> suppliers;
  final Map<String, TextEditingController> controllers;
  final num? total;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    if (suppliers.isEmpty) {
      return const Text('Asigna proveedores para capturar presupuestos.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Presupuesto por proveedor'),
        const SizedBox(height: 8),
        for (final supplier in suppliers) ...[
          TextFormField(
            controller: controllers[supplier],
            decoration: InputDecoration(labelText: supplier),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 8),
        ],
        if (total != null)
          Text('Total: $total', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
