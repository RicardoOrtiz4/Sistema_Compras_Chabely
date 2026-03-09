import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/core/navigation_guard.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/domain/shared_quote.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';

enum CotizacionesDashboardMode { compras, direccion }

class CotizacionesDashboardScreen extends ConsumerStatefulWidget {
  const CotizacionesDashboardScreen({
    required this.mode,
    this.embedded = false,
    this.onOpenOrder,
    super.key,
  });

  final CotizacionesDashboardMode mode;
  final bool embedded;
  final ValueChanged<String>? onOpenOrder;

  @override
  ConsumerState<CotizacionesDashboardScreen> createState() =>
      _CotizacionesDashboardScreenState();
}

class _CotizacionesDashboardScreenState
    extends ConsumerState<CotizacionesDashboardScreen> {
  final Set<String> _selectedOrderIds = <String>{};
  late final TextEditingController _bundleLabelController;
  late final TextEditingController _bundleLinkController;
  late final TextEditingController _searchController;
  final OrderSearchCache _searchCache = OrderSearchCache();
  bool _migrationInProgress = false;
  bool _migrationDone = false;
  bool _sendingToDireccion = false;
  bool _prefetchingDireccion = false;
  final Set<String> _bundleBusyIds = <String>{};
  String? _lastDireccionPrefetchKey;
  bool _prefetchScheduled = false;
  Timer? _searchDebounce;
  String _searchQuery = '';
  int _orderLimit = defaultOrderPageSize;
  int _bundleLimit = defaultOrderPageSize;

  bool get _isReadOnly => widget.mode == CotizacionesDashboardMode.direccion;

  void _warmPdfCacheForDireccion(List<PurchaseOrder> orders) {
    if (!_isReadOnly || orders.isEmpty) return;
    final branding = ref.read(currentBrandingProvider);
    final key = orders
        .map((order) => '${order.id}:${order.updatedAt?.millisecondsSinceEpoch ?? 0}')
        .join('|');
    if (_lastDireccionPrefetchKey == key) return;
    _lastDireccionPrefetchKey = key;
    if (_prefetchScheduled) return;
    _prefetchScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefetchScheduled = false;
      if (!mounted) return;
      setState(() => _prefetchingDireccion = true);
      Future(() async {
        try {
          // Deja que el loader pinte y anime antes de iniciar el trabajo pesado.
          await Future<void>.delayed(const Duration(milliseconds: 16));
          if (!mounted) return;

          final dataList = orders
              .take(3)
              .map((order) => buildPdfDataFromOrder(order, branding: branding))
              .toList(growable: false);
          if (dataList.isEmpty) {
            if (mounted) {
              setState(() => _prefetchingDireccion = false);
            }
            return;
          }

          for (final data in dataList) {
            try {
              // Cede el hilo entre PDFs para mantener la animación fluida.
              await Future<void>.delayed(const Duration(milliseconds: 8));
              await buildOrderPdf(data, useIsolate: true);
            } catch (error, stack) {
              logError(error, stack, context: 'DireccionDashboard.prefetch');
            }
          }
        } finally {
          if (mounted) {
            setState(() => _prefetchingDireccion = false);
          }
        }
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _bundleLabelController = TextEditingController();
    _bundleLinkController = TextEditingController();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _bundleLabelController.dispose();
    _bundleLinkController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _updateSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _searchQuery = value;
        _orderLimit = defaultOrderPageSize;
        _bundleLimit = defaultOrderPageSize;
      });
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _orderLimit = defaultOrderPageSize;
      _bundleLimit = defaultOrderPageSize;
    });
  }

  void _loadMoreOrders() {
    setState(() => _orderLimit += orderPageSizeStep);
  }

  void _loadMoreBundles() {
    setState(() => _bundleLimit += orderPageSizeStep);
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = widget.mode == CotizacionesDashboardMode.compras
        ? ref.watch(cotizacionesOrdersProvider)
        : ref.watch(pendingDireccionOrdersProvider);
    final bundlesAsync = ref.watch(sharedQuotesProvider);

    final body = ordersAsync.when(
      data: (orders) => bundlesAsync.when(
        data: (bundles) {
          if (!_isReadOnly) {
            _maybeMigrateLegacyLinks(orders, bundles);
          }

          final visibleOrders = _isReadOnly
              ? orders
              : orders.where(_orderReady).toList();
          _warmPdfCacheForDireccion(orders);
          _searchCache.retainFor(visibleOrders);
          final ordersById = {for (final order in orders) order.id: order};
          final visibleBundlesBase = _filterBundlesForOrders(bundles, ordersById);
          final visibleBundles = _isReadOnly
              ? visibleBundlesBase
                  .where(
                    (bundle) => bundle.orderIds.any(
                      (id) =>
                          ordersById.containsKey(id) &&
                          !bundle.approvedOrderIds.contains(id),
                    ),
                  )
                  .toList()
              : visibleBundlesBase;
          final quotesById = {
            for (final bundle in bundles) bundle.id: bundle,
          };
          final trimmedQuery = _searchQuery.trim();
          final filteredOrders = trimmedQuery.isEmpty
              ? visibleOrders
              : visibleOrders
                  .where(
                    (order) => orderMatchesSearch(
                      order,
                      trimmedQuery,
                      cache: _searchCache,
                    ),
                  )
                  .toList();
          final limitedOrders = _isReadOnly
              ? filteredOrders
              : filteredOrders.take(_orderLimit).toList();
          final filteredBundles = trimmedQuery.isEmpty
              ? visibleBundles
              : visibleBundles
                  .where(
                    (bundle) => _bundleMatchesSearch(
                      bundle,
                      ordersById,
                      trimmedQuery,
                    ),
                  )
                  .toList();
          final limitedBundles = filteredBundles.take(_bundleLimit).toList();
          final canLoadMoreOrders =
              !_isReadOnly && filteredOrders.length > limitedOrders.length;
          final canLoadMoreBundles =
              filteredBundles.length > limitedBundles.length;
          final bundleCountByOrder = _bundleCountByOrder(visibleBundles);
          final visibleOrderIds = visibleOrders.map((order) => order.id).toSet();
          final selectedVisibleIds =
              _selectedOrderIds.intersection(visibleOrderIds);
          final limitedOrderIds = limitedOrders.map((order) => order.id).toSet();
          final selectedLimitedIds =
              selectedVisibleIds.intersection(limitedOrderIds);

          final ordersReadyToSend =
              _isReadOnly ? const <PurchaseOrder>[] : _ordersReadyToSend(visibleOrders);
          final ordersReadyIds = ordersReadyToSend.map((order) => order.id).toSet();
          final bundlesReadyToSend = _isReadOnly
              ? const <SharedQuote>[]
              : visibleBundles
                  .where((bundle) => bundle.orderIds.any(ordersReadyIds.contains))
                  .toList();

          final showEmptySearch = trimmedQuery.isNotEmpty &&
              filteredOrders.isEmpty &&
              filteredBundles.isEmpty;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText:
                        'Buscar por folio, solicitante, área, proveedor, link...',
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
                child: showEmptySearch
                    ? const Center(
                        child: Text('No hay resultados con ese filtro.'),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (!_isReadOnly) ...[
                            _OrdersSection(
                              orders: limitedOrders,
                              readOnly: _isReadOnly,
                              selectedOrderIds: selectedLimitedIds,
                              bundleCountByOrder: bundleCountByOrder,
                              onToggleSelection: _toggleSelection,
                              onSelectAllPending: _selectAllPending,
                              onClearSelection: _clearSelection,
                              onOpenOrder: (order) => _showOrderDetails(order),
                            ),
                            if (canLoadMoreOrders) ...[
                              const SizedBox(height: 8),
                              Center(
                                child: OutlinedButton.icon(
                                  onPressed: _loadMoreOrders,
                                  icon: const Icon(Icons.expand_more),
                                  label: const Text('Ver más'),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            const SizedBox(height: 16),
                          ],
                          _BundlesSection(
                            bundles: limitedBundles,
                            ordersById: ordersById,
                            readOnly: _isReadOnly,
                            showOpenQuote: _isReadOnly,
                            onOpenQuoteLink: _openLink,
                            busyBundleIds: _bundleBusyIds,
                            selectedCount: selectedVisibleIds.length,
                            emptyMessage: _isReadOnly
                                ? 'Aún no hay cotizaciones enviadas.'
                                : 'Aún no hay cotizaciones registradas.',
                            labelController: _bundleLabelController,
                            linkController: _bundleLinkController,
                            onCreateBundle: _isReadOnly
                                ? null
                                : () => _createBundle(visibleOrders),
                            onRejectBundle: _isReadOnly
                                ? (bundle) => _handleRejectBundle(
                                      bundle,
                                      ordersById,
                                    )
                                : null,
                            onSendToEta: _isReadOnly
                                ? (bundle) => _handleSendToEtaBundle(
                                      bundle,
                                      ordersById,
                                      quotesById,
                                    )
                                : null,
                            onEditBundle: _isReadOnly ? null : _editBundleLink,
                            onManageBundle: _isReadOnly
                                ? null
                                : (bundle) => _manageBundle(bundle, visibleOrders),
                            onDeleteBundle: _isReadOnly
                                ? null
                                : (bundle) => _deleteBundle(bundle, ordersById),
                            onOpenLink: _openLink,
                            onOpenOrder: widget.onOpenOrder,
                          ),
                          if (canLoadMoreBundles) ...[
                            const SizedBox(height: 8),
                            Center(
                              child: OutlinedButton.icon(
                                onPressed: _loadMoreBundles,
                                icon: const Icon(Icons.expand_more),
                                label: const Text('Ver más'),
                              ),
                            ),
                          ],
                          if (!_isReadOnly) ...[
                            const SizedBox(height: 16),
                            _SendToDireccionSection(
                              ordersCount: ordersReadyToSend.length,
                              bundlesCount: bundlesReadyToSend.length,
                              isBusy: _sendingToDireccion,
                              onSend: ordersReadyToSend.isEmpty || _sendingToDireccion
                                  ? null
                                  : () => _confirmSendToDireccion(ordersReadyToSend),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => _ErrorPanel(
          message: reportError(error, stack, context: 'CotizacionesDashboard.bundles'),
        ),
      ),
      loading: () => const AppSplash(),
      error: (error, stack) => _ErrorPanel(
        message: reportError(error, stack, context: 'CotizacionesDashboard.orders'),
      ),
    );

    final showLoadingOverlay = _isReadOnly && _prefetchingDireccion;
    final composedBody = _isReadOnly
        ? Stack(
            children: [
              body,
              if (showLoadingOverlay)
                const Positioned.fill(
                  child: AppSplash(),
                ),
            ],
          )
        : body;

    if (widget.embedded) {
      return composedBody;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isReadOnly
              ? 'Dashboard de cotizaciones (DG)'
              : 'Dashboard de cotizaciones',
        ),
        actions: const [],
      ),
      body: composedBody,
    );
  }

  void _toggleSelection(String orderId, bool selected) {
    setState(() {
      if (selected) {
        _selectedOrderIds.add(orderId);
      } else {
        _selectedOrderIds.remove(orderId);
      }
    });
  }

  void _selectAllPending(List<PurchaseOrder> orders, bool value) {
    setState(() {
      _selectedOrderIds.clear();
      if (value) {
        for (final order in orders) {
          _selectedOrderIds.add(order.id);
        }
      }
    });
  }

  void _clearSelection() {
    setState(() => _selectedOrderIds.clear());
  }

  void _showOrderDetails(PurchaseOrder order) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _OrderDetailsSheet(order: order),
    );
  }

  Future<void> _createBundle(List<PurchaseOrder> orders) async {
    if (_selectedOrderIds.isEmpty) return;

    final link = _bundleLinkController.text.trim();
    final label = _bundleLabelController.text.trim();
    final selectedOrders = orders
        .where((order) => _selectedOrderIds.contains(order.id))
        .toList();

    if (link.isEmpty) {
      _showMessage('Ingresa un link de cotizacion.');
      return;
    }
    if (!_isValidUrl(link)) {
      _showMessage('Ingresa un link valido.');
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar agrupacion'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Se agruparan ${selectedOrders.length} orden(es) con este link. '
                'Quedaran en espera para enviar a Direccion General. '
                'Puedes crear mas agrupaciones despues.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (label.isNotEmpty) Text('Etiqueta: $label'),
              Text('Link: $link'),
              const SizedBox(height: 12),
              for (final order in selectedOrders)
                Text('- ${order.requesterName} (${order.areaName})'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      final repo = ref.read(purchaseOrderRepositoryProvider);
      final quote = await repo.createSharedQuote(
        supplier: label,
        orderIds: selectedOrders.map((order) => order.id).toList(),
        pdfUrl: _normalizeLink(link),
      );
      await repo.linkOrdersToSharedQuote(
        quote: quote,
        orderIds: selectedOrders.map((order) => order.id).toList(),
      );

      if (!mounted) return;
      _showMessage('Cotizacion creada.');
      _bundleLabelController.clear();
      _bundleLinkController.clear();
      _clearSelection();
    } catch (error, stack) {
      if (!mounted) return;
      _showMessage(reportError(error, stack, context: 'CotizacionesDashboard.create'));
    }
  }

  Future<void> _editBundleLink(SharedQuote bundle) async {
    final controller = TextEditingController(text: bundle.pdfUrl);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Actualizar link'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Link de cotizacion',
            prefixIcon: Icon(Icons.link),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    final link = controller.text.trim();
    controller.dispose();

    if (result != true) return;
    if (!_isValidUrl(link)) {
      _showMessage('Ingresa un link valido.');
      return;
    }

    try {
      final repo = ref.read(purchaseOrderRepositoryProvider);
      await repo.updateSharedQuoteLink(quote: bundle, pdfUrl: _normalizeLink(link));
      if (!mounted) return;
      _showMessage('Link actualizado.');
    } catch (error, stack) {
      if (!mounted) return;
      _showMessage(reportError(error, stack, context: 'CotizacionesDashboard.updateLink'));
    }
  }

  Future<void> _manageBundle(SharedQuote bundle, List<PurchaseOrder> orders) async {
    final selected = bundle.orderIds.toSet();
    final availableOrders = orders.toList();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text('Ordenes en ${_bundleLabel(bundle)}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final order in availableOrders)
                  CheckboxListTile(
                    value: selected.contains(order.id),
                    onChanged: (value) {
                      setStateDialog(() {
                        if (value == true) {
                          selected.add(order.id);
                        } else {
                          selected.remove(order.id);
                        }
                      });
                    },
                    title: Text(order.requesterName),
                    subtitle: Text(order.areaName),
                  ),
                if (bundle.orderIds.any((id) => !availableOrders.any((o) => o.id == id)))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Hay ordenes fuera de cotizaciones que no se muestran aqui.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    final availableIds = orders.map((o) => o.id).toSet();
    final toAdd = selected.difference(bundle.orderIds.toSet()).toList();
    final toRemove = bundle.orderIds
        .where((id) => availableIds.contains(id) && !selected.contains(id))
        .toList();

    try {
      final repo = ref.read(purchaseOrderRepositoryProvider);
      if (toAdd.isNotEmpty) {
        await repo.linkOrdersToSharedQuote(quote: bundle, orderIds: toAdd);
      }
      for (final orderId in toRemove) {
        final order = orders.firstWhere((o) => o.id == orderId);
        await repo.unlinkOrderFromSharedQuote(order: order, quote: bundle);
      }
      if (!mounted) return;
      _showMessage('Cotizacion actualizada.');
    } catch (error, stack) {
      if (!mounted) return;
      _showMessage(reportError(error, stack, context: 'CotizacionesDashboard.manage'));
    }
  }

  Future<void> _deleteBundle(SharedQuote bundle, Map<String, PurchaseOrder> ordersById) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminar ${_bundleLabel(bundle)}'),
        content: const Text('Se desvincularan todas las ordenes de esta cotizacion.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final repo = ref.read(purchaseOrderRepositoryProvider);
      for (final orderId in bundle.orderIds) {
        final order = ordersById[orderId];
        if (order != null) {
          await repo.unlinkOrderFromSharedQuote(order: order, quote: bundle);
        }
      }
      if (!mounted) return;
      _showMessage('Cotizacion eliminada.');
    } catch (error, stack) {
      if (!mounted) return;
      _showMessage(reportError(error, stack, context: 'CotizacionesDashboard.delete'));
    }
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
      _showMessage('El link no es valido.');
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      _showMessage('No se pudo abrir el link.');
    }
  }

  Future<void> _confirmSendToDireccion(List<PurchaseOrder> orders) async {
    if (orders.isEmpty) return;
    if (_sendingToDireccion) return;

    final count = orders.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enviar a Direccion General'),
        content: Text(
          'Se enviaran $count orden(es) con sus links de cotizacion. '
          'Despues de enviar, ya no podras agrupar estas ordenes.',
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

    if (confirmed != true) return;

    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) {
      _showMessage('Perfil no disponible.');
      return;
    }

    setState(() => _sendingToDireccion = true);
    try {
      final repo = ref.read(purchaseOrderRepositoryProvider);
      for (final order in orders) {
        final links = order.cotizacionLinks
            .where((link) => link.url.trim().isNotEmpty)
            .toList();
        if (links.isEmpty) continue;
        await repo.sendToDireccionWithCotizacion(
          order: order,
          cotizacionLinks: links,
          actor: actor,
        );
      }
      if (!mounted) return;
      _showMessage('Ordenes enviadas a Direccion General.');
      _clearSelection();
    } catch (error, stack) {
      if (!mounted) return;
      _showMessage(reportError(error, stack, context: 'CotizacionesDashboard.send'));
    } finally {
      if (mounted) {
        setState(() => _sendingToDireccion = false);
      }
    }
  }

  Future<void> _handleSendToEtaBundle(
    SharedQuote bundle,
    Map<String, PurchaseOrder> ordersById,
    Map<String, SharedQuote> quotesById,
  ) async {
    if (_bundleBusyIds.contains(bundle.id)) return;
    final orders = bundle.orderIds
        .map((id) => ordersById[id])
        .whereType<PurchaseOrder>()
        .toList();
    if (orders.isEmpty) {
      _showMessage('No hay órdenes disponibles en esta cotización.');
      return;
    }

    final selectedOrderIds = await _confirmBundleApprovalSelection(
      bundle: bundle,
      orders: orders,
    );
    if (selectedOrderIds == null || selectedOrderIds.isEmpty) return;

    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) {
      _showMessage('Perfil no disponible.');
      return;
    }

    setState(() => _bundleBusyIds.add(bundle.id));
    try {
      final repo = ref.read(purchaseOrderRepositoryProvider);
      await repo.approveSharedQuoteFromDireccion(
        quote: bundle,
        actor: actor,
        approvedOrderIds: selectedOrderIds.toList(),
      );

      final approvedByQuote = <String, Set<String>>{};
      for (final quote in quotesById.values) {
        approvedByQuote[quote.id] = {
          ...quote.approvedOrderIds.map((id) => id.trim()).where((id) => id.isNotEmpty),
        };
      }
      approvedByQuote.putIfAbsent(bundle.id, () => <String>{});
      approvedByQuote[bundle.id]!.addAll(selectedOrderIds);

      var moved = 0;
      var blocked = 0;
      for (final order in orders) {
        if (!selectedOrderIds.contains(order.id)) continue;
        final quoteIds = order.sharedQuoteRefs
            .map((ref) => ref.quoteId.trim())
            .where((id) => id.isNotEmpty)
            .toList();
        final canAdvance = quoteIds.isNotEmpty &&
            quoteIds.every(
              (id) => approvedByQuote[id]?.contains(order.id) ?? false,
            );
        if (!canAdvance) {
          blocked += 1;
          continue;
        }
        await repo.markPaymentDone(order: order, actor: actor);
        moved += 1;
      }
      if (!mounted) return;
      if (blocked > 0) {
        _showMessage(
          'Se aprobaron $moved orden(es). '
          '$blocked orden(es) seguirán en Dirección General hasta aprobar sus otras cotizaciones.',
        );
      } else {
        _showMessage('Ordenes enviadas a pendientes de fecha estimada.');
      }
    } catch (error, stack) {
      if (!mounted) return;
      _showMessage(reportError(error, stack, context: 'DireccionBundle.sendEta'));
    } finally {
      if (mounted) {
        setState(() => _bundleBusyIds.remove(bundle.id));
      }
    }
  }

  Future<Set<String>?> _confirmBundleApprovalSelection({
    required SharedQuote bundle,
    required List<PurchaseOrder> orders,
  }) async {
    final approvedSet = bundle.approvedOrderIds.toSet();
    final selected = orders
        .where((order) => !approvedSet.contains(order.id))
        .map((order) => order.id)
        .toSet();

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final canSubmit = selected.isNotEmpty;
          return AlertDialog(
            title: const Text('Enviar a pendientes de fecha estimada'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Selecciona las órdenes que aprobarás de esta cotización.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          setStateDialog(() {
                            selected
                              ..clear()
                              ..addAll(
                                orders
                                    .where((o) => !approvedSet.contains(o.id))
                                    .map((o) => o.id),
                              );
                          });
                        },
                        child: const Text('Seleccionar todo'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          setStateDialog(() => selected.clear());
                        },
                        child: const Text('Limpiar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final order in orders)
                          CheckboxListTile(
                            value: approvedSet.contains(order.id)
                                ? true
                                : selected.contains(order.id),
                            onChanged: approvedSet.contains(order.id)
                                ? null
                                : (value) {
                                    setStateDialog(() {
                                      if (value == true) {
                                        selected.add(order.id);
                                      } else {
                                        selected.remove(order.id);
                                      }
                                    });
                            },
                            title: Text('Orden ${order.id}'),
                            subtitle: Text(
                              '${order.requesterName} - ${order.areaName}'
                              '${_primaryQuoteId(order) == bundle.id ? ' · Principal' : ''}'
                              '${approvedSet.contains(order.id) ? ' · Ya aprobada' : ''}',
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: canSubmit ? () => Navigator.pop(context, selected) : null,
                child: const Text('Enviar'),
              ),
            ],
          );
        },
      ),
    );

    return result;
  }

  Future<void> _handleRejectBundle(
    SharedQuote bundle,
    Map<String, PurchaseOrder> ordersById,
  ) async {
    if (_bundleBusyIds.contains(bundle.id)) return;
    final orders = bundle.orderIds
        .map((id) => ordersById[id])
        .whereType<PurchaseOrder>()
        .toList();
    if (orders.isEmpty) {
      _showMessage('No hay órdenes disponibles en esta cotización.');
      return;
    }

    final rejection = await _confirmBundleRejection(orders);
    if (rejection == null) return;

    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) {
      _showMessage('Perfil no disponible.');
      return;
    }

    setState(() => _bundleBusyIds.add(bundle.id));
    try {
      final repo = ref.read(purchaseOrderRepositoryProvider);
      for (final order in orders) {
        if (!rejection.orderIds.contains(order.id)) continue;
        await repo.returnToCotizaciones(
          order: order,
          comment: rejection.comment,
          items: order.items,
          actor: actor,
        );
      }
      if (!mounted) return;
      _showMessage('Órdenes regresadas a cotizaciones.');
    } catch (error, stack) {
      if (!mounted) return;
      _showMessage(reportError(error, stack, context: 'DireccionBundle.reject'));
    } finally {
      if (mounted) {
        setState(() => _bundleBusyIds.remove(bundle.id));
      }
    }
  }

  Future<_BundleRejectionResult?> _confirmBundleRejection(
    List<PurchaseOrder> orders,
  ) async {
    final controller = TextEditingController();
    final orderLabels = orders.map((order) => order.id).join(', ');
    final selected = <String>{};

    final result = await showDialog<_BundleRejectionResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final allSelected = selected.length == orders.length && orders.isNotEmpty;
          final comment = controller.text.trim();
          final hasSelection = selected.isNotEmpty;
          final canSubmit = hasSelection && comment.isNotEmpty;

          return AlertDialog(
            title: const Text('Rechazar cotización'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Selecciona las órdenes a rechazar y escribe el motivo.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Órdenes: $orderLabels',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: allSelected,
                      onChanged: (value) {
                        setStateDialog(() {
                          if (value == true) {
                            selected
                              ..clear()
                              ..addAll(orders.map((order) => order.id));
                          } else {
                            selected.clear();
                          }
                        });
                      },
                      title: const Text('Seleccionar todo'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final order in orders)
                          CheckboxListTile(
                            value: selected.contains(order.id),
                            onChanged: (value) {
                              setStateDialog(() {
                                if (value == true) {
                                  selected.add(order.id);
                                } else {
                                  selected.remove(order.id);
                                }
                              });
                            },
                            title: Text('Orden ${order.id}'),
                            subtitle: Text(
                              '${order.requesterName} - ${order.areaName}',
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    enabled: hasSelection,
                    decoration: InputDecoration(
                      labelText: 'Comentario general',
                      helperText: hasSelection
                          ? null
                          : 'Selecciona al menos una orden para habilitar el comentario.',
                    ),
                    onChanged: hasSelection ? (_) => setStateDialog(() {}) : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: canSubmit
                    ? () => Navigator.pop(
                          context,
                          _BundleRejectionResult(
                            orderIds: selected,
                            comment: comment,
                          ),
                        )
                    : null,
                child: const Text('Rechazar'),
              ),
            ],
          );
        },
      ),
    );

    controller.dispose();
    return result;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _maybeMigrateLegacyLinks(
    List<PurchaseOrder> orders,
    List<SharedQuote> bundles,
  ) {
    if (_migrationInProgress || _migrationDone) return;

    final legacyLinks = orders
        .expand((order) => order.cotizacionLinks)
        .where((link) => (link.quoteId ?? '').trim().isEmpty && link.url.trim().isNotEmpty)
        .toList();
    if (legacyLinks.isEmpty) {
      _migrationDone = true;
      return;
    }

    _migrationInProgress = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final repo = ref.read(purchaseOrderRepositoryProvider);
        final byUrl = <String, SharedQuote>{};
        for (final bundle in bundles) {
          final url = bundle.pdfUrl.trim();
          if (url.isNotEmpty) {
            byUrl[_normalizeLink(url)] = bundle;
          }
        }

        for (final order in orders) {
          for (final link in order.cotizacionLinks) {
            if ((link.quoteId ?? '').trim().isNotEmpty) continue;
            final url = link.url.trim();
            if (url.isEmpty) continue;

            final normalized = _normalizeLink(url);
            var bundle = byUrl[normalized];
            if (bundle == null) {
              bundle = await repo.createSharedQuote(
                supplier: link.supplier.trim(),
                orderIds: [order.id],
                pdfUrl: normalized,
              );
              byUrl[normalized] = bundle;
            }

            if (!bundle.orderIds.contains(order.id)) {
              await repo.linkOrdersToSharedQuote(quote: bundle, orderIds: [order.id]);
            }
          }
        }

        _migrationDone = true;
        _migrationInProgress = false;
        if (mounted) setState(() {});
      } catch (_) {
        _migrationInProgress = false;
        _migrationDone = true;
      }
    });
  }
}

class _BundleRejectionResult {
  const _BundleRejectionResult({
    required this.orderIds,
    required this.comment,
  });

  final Set<String> orderIds;
  final String comment;
}

class _OrdersSection extends StatelessWidget {
  const _OrdersSection({
    required this.orders,
    required this.readOnly,
    required this.selectedOrderIds,
    required this.bundleCountByOrder,
    required this.onToggleSelection,
    required this.onSelectAllPending,
    required this.onClearSelection,
    required this.onOpenOrder,
  });

  final List<PurchaseOrder> orders;
  final bool readOnly;
  final Set<String> selectedOrderIds;
  final Map<String, int> bundleCountByOrder;
  final void Function(String orderId, bool selected) onToggleSelection;
  final void Function(List<PurchaseOrder> orders, bool value) onSelectAllPending;
  final VoidCallback onClearSelection;
  final void Function(PurchaseOrder order) onOpenOrder;

  @override
  Widget build(BuildContext context) {
    final allSelected = selectedOrderIds.length == orders.length && orders.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.receipt_long_outlined),
            const SizedBox(width: 8),
            Text('Órdenes', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (!readOnly)
              Text(
                '${selectedOrderIds.length} seleccionadas',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (!readOnly)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: allSelected,
                    onChanged: (value) => onSelectAllPending(orders, value ?? false),
                  ),
                  const Text('Seleccionar todo'),
                ],
              ),
              TextButton(
                onPressed: selectedOrderIds.isEmpty ? null : onClearSelection,
                child: const Text('Limpiar selección'),
              ),
            ],
          ),
        if (!readOnly) const SizedBox(height: 8),
        if (orders.isEmpty)
          const Text('No hay órdenes para mostrar.')
        else
          for (final order in orders) ...[
            _OrderSelectionCard(
              order: order,
              selected: selectedOrderIds.contains(order.id),
              readOnly: readOnly,
              bundleCount: bundleCountByOrder[order.id] ?? 0,
              onToggle: (value) => onToggleSelection(order.id, value ?? false),
              onOpen: () => onOpenOrder(order),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _OrderSelectionCard extends StatelessWidget {
  const _OrderSelectionCard({
    required this.order,
    required this.selected,
    required this.readOnly,
    required this.bundleCount,
    required this.onToggle,
    required this.onOpen,
  });

  final PurchaseOrder order;
  final bool selected;
  final bool readOnly;
  final int bundleCount;
  final ValueChanged<bool?> onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final itemsTotal = order.items.length;
    final itemsReady = order.items.where(_itemReady).length;
    final linkCount = order.cotizacionLinks.where((link) => link.url.trim().isNotEmpty).length;

    return Card(
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!readOnly)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, top: 2),
                      child: Checkbox(
                        value: selected,
                        onChanged: onToggle,
                      ),
                    ),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _FolioPill(folio: order.id),
                        _UrgencyPill(urgency: order.urgency),
                        if (bundleCount > 0)
                          _InfoPill(
                            label: 'Cotizaciones $bundleCount',
                            color: Colors.blueGrey.shade100,
                            textColor: Colors.blueGrey.shade800,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Solicitante: ${order.requesterName}'),
              Text('Área: ${order.areaName}'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text('Artículos completos: $itemsReady/$itemsTotal'),
                  Text('Links asignados: $linkCount'),
                ],
              ),
            ],
          ),
        ),
      ),
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

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _OrderDetailsSheet extends StatelessWidget {
  const _OrderDetailsSheet({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemsTotal = order.items.length;
    final itemsReady = order.items.where(_itemReady).length;
    final linkCount = order.cotizacionLinks.where((link) => link.url.trim().isNotEmpty).length;
    final comprasComment = (order.comprasComment ?? '').trim();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Material(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Orden ${order.id}',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${order.requesterName} - ${order.areaName}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Text('Resumen', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: 'Articulos',
                    value: '$itemsReady/$itemsTotal completos',
                  ),
                  _InfoRow(label: 'Links', value: '$linkCount cotizacion(es)'),
                  if (comprasComment.isNotEmpty)
                    _InfoRow(label: 'Comentario', value: comprasComment),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () =>
                        guardedPush(context, '/orders/${order.id}/pdf'),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Ver PDF'),
                  ),
                  const SizedBox(height: 16),
                  Text('Articulos', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final item in order.items) ...[
                    _OrderItemCard(item: item),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _OrderItemCard extends StatelessWidget {
  const _OrderItemCard({required this.item});

  final PurchaseOrderItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supplier = (item.supplier ?? '').trim();
    final part = item.partNumber.trim();
    final quantity = _formatNum(item.quantity);
    final budget = item.budget;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Item ${item.line}',
                style: theme.textTheme.titleSmall,
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 6),
          Text(item.description, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text('Cantidad: $quantity ${item.unit}'),
          if (item.pieces > 0) Text('Piezas: ${item.pieces}'),
          if (part.isNotEmpty) Text('No. parte: $part'),
          if (supplier.isNotEmpty) Text('Proveedor: $supplier'),
          if (budget != null) Text('Presupuesto: ${_formatNum(budget)}'),
        ],
      ),
    );
  }
}

class _BundlesSection extends StatelessWidget {
  const _BundlesSection({
    required this.bundles,
    required this.ordersById,
    required this.readOnly,
    required this.showOpenQuote,
    required this.onOpenQuoteLink,
    required this.busyBundleIds,
    required this.selectedCount,
    required this.emptyMessage,
    required this.labelController,
    required this.linkController,
    required this.onCreateBundle,
    required this.onRejectBundle,
    required this.onSendToEta,
    required this.onEditBundle,
    required this.onManageBundle,
    required this.onDeleteBundle,
    required this.onOpenLink,
    required this.onOpenOrder,
  });

  final List<SharedQuote> bundles;
  final Map<String, PurchaseOrder> ordersById;
  final bool readOnly;
  final bool showOpenQuote;
  final Future<void> Function(String link) onOpenQuoteLink;
  final Set<String> busyBundleIds;
  final int selectedCount;
  final String emptyMessage;
  final TextEditingController labelController;
  final TextEditingController linkController;
  final VoidCallback? onCreateBundle;
  final Future<void> Function(SharedQuote bundle)? onRejectBundle;
  final Future<void> Function(SharedQuote bundle)? onSendToEta;
  final Future<void> Function(SharedQuote bundle)? onEditBundle;
  final Future<void> Function(SharedQuote bundle)? onManageBundle;
  final Future<void> Function(SharedQuote bundle)? onDeleteBundle;
  final Future<void> Function(String link) onOpenLink;
  final ValueChanged<String>? onOpenOrder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.link),
            const SizedBox(width: 8),
            Text('Cotizaciones', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 12),
        if (!readOnly) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedCount == 0
                        ? 'Selecciona órdenes para agruparlas con un link de cotización.'
                        : 'Se agruparán $selectedCount orden(es) con el link que ingreses.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: labelController,
                    decoration: const InputDecoration(
                      labelText: 'Etiqueta (opcional)',
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: linkController,
                    decoration: const InputDecoration(
                      labelText: 'Link de cotización (Drive)',
                      prefixIcon: Icon(Icons.link),
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: selectedCount == 0 ? null : onCreateBundle,
                      child: const Text('Aceptar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (bundles.isEmpty)
          Text(emptyMessage)
        else
          for (final bundle in bundles) ...[
            _BundleCard(
              bundle: bundle,
              ordersById: ordersById,
              readOnly: readOnly,
              showOpenQuote: showOpenQuote,
              onOpenQuoteLink: onOpenQuoteLink,
              busy: busyBundleIds.contains(bundle.id),
              onReject: onRejectBundle == null ? null : () => onRejectBundle!(bundle),
              onSendToEta: onSendToEta == null ? null : () => onSendToEta!(bundle),
              onEdit: onEditBundle,
              onManage: onManageBundle,
              onDelete: onDeleteBundle,
              onOpen: onOpenLink,
              onOpenOrder: onOpenOrder,
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _SendToDireccionSection extends StatelessWidget {
  const _SendToDireccionSection({
    required this.ordersCount,
    required this.bundlesCount,
    required this.isBusy,
    required this.onSend,
  });

  final int ordersCount;
  final int bundlesCount;
  final bool isBusy;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.send_outlined),
                const SizedBox(width: 8),
                Text(
                  'Enviar a Direccion General',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              ordersCount == 0
                  ? 'No hay ordenes con link de cotizacion listas para enviar.'
                  : 'Listas para enviar: $ordersCount orden(es) en $bundlesCount cotizacion(es).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onSend,
                child: isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: AppSplash(compact: true, size: 18),
                      )
                    : const Text('Enviar agrupaciones'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BundleCard extends StatelessWidget {
  const _BundleCard({
    required this.bundle,
    required this.ordersById,
    required this.readOnly,
    required this.showOpenQuote,
    required this.onOpenQuoteLink,
    required this.busy,
    required this.onReject,
    required this.onSendToEta,
    required this.onEdit,
    required this.onManage,
    required this.onDelete,
    required this.onOpen,
    required this.onOpenOrder,
  });

  final SharedQuote bundle;
  final Map<String, PurchaseOrder> ordersById;
  final bool readOnly;
  final bool showOpenQuote;
  final Future<void> Function(String link) onOpenQuoteLink;
  final bool busy;
  final VoidCallback? onReject;
  final VoidCallback? onSendToEta;
  final Future<void> Function(SharedQuote bundle)? onEdit;
  final Future<void> Function(SharedQuote bundle)? onManage;
  final Future<void> Function(SharedQuote bundle)? onDelete;
  final Future<void> Function(String link) onOpen;
  final ValueChanged<String>? onOpenOrder;

  @override
  Widget build(BuildContext context) {
    final label = _bundleLabel(bundle);
    final visibleOrderIds = readOnly
        ? bundle.orderIds.where(ordersById.containsKey).toList()
        : bundle.orderIds;
    final orderCount = visibleOrderIds.length;
    final link = bundle.pdfUrl.trim();

    final approvedCount = bundle.approvedOrderIds.length;
    final totalCount = bundle.orderIds.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label, style: Theme.of(context).textTheme.titleSmall),
                ),
                if (readOnly)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Aprobadas $approvedCount/$totalCount',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
                if (link.isNotEmpty)
                  IconButton(
                    tooltip: 'Abrir link',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => onOpen(link),
                  ),
              ],
            ),
            if (link.isNotEmpty)
              Text(
                link,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (showOpenQuote && link.isNotEmpty) ...[
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => onOpenQuoteLink(link),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Abrir cotización'),
              ),
            ],
            const SizedBox(height: 6),
            Text('Órdenes vinculadas: $orderCount'),
            if (orderCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: readOnly && onOpenOrder != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Órdenes en esta cotización:',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          for (final orderId in visibleOrderIds) ...[
                            _BundleOrderRow(
                              orderId: orderId,
                              order: ordersById[orderId],
                              onOpen: onOpenOrder!,
                              isPrimary: () {
                                final order = ordersById[orderId];
                                if (order == null) return false;
                                final rawPrimary = order.primaryQuoteId?.trim() ?? '';
                                final primaryId = rawPrimary.isNotEmpty
                                    ? rawPrimary
                                    : (order.sharedQuoteRefs.isNotEmpty
                                        ? order.sharedQuoteRefs.first.quoteId
                                        : '');
                                return primaryId == bundle.id;
                              }(),
                              isApproved: bundle.approvedOrderIds.contains(orderId),
                            ),
                            const SizedBox(height: 6),
                          ],
                        ],
                      )
                    : Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                        for (final orderId in visibleOrderIds.take(6))
                          Chip(
                            label: Text(
                              ordersById[orderId]?.requesterName ?? 'Orden $orderId',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (orderCount > 6)
                          Chip(label: Text('+${orderCount - 6} más')),
                      ],
                    ),
              ),
            if (readOnly) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy ? null : onReject,
                    icon: const Icon(Icons.reply_outlined),
                    label: const Text('Rechazar'),
                  ),
                  FilledButton.icon(
                    onPressed: busy ? null : onSendToEta,
                    icon: const Icon(Icons.schedule_send),
                    label: const Text('Aprobar órdenes del grupo'),
                  ),
                ],
              ),
            ],
            if (!readOnly) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onEdit == null ? null : () => onEdit!(bundle),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar link'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onManage == null ? null : () => onManage!(bundle),
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('Administrar Órdenes'),
                  ),
                  TextButton(
                    onPressed: onDelete == null ? null : () => onDelete!(bundle),
                    child: const Text('Eliminar'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BundleOrderRow extends StatelessWidget {
  const _BundleOrderRow({
    required this.orderId,
    required this.order,
    required this.onOpen,
    required this.isPrimary,
    required this.isApproved,
  });

  final String orderId;
  final PurchaseOrder? order;
  final ValueChanged<String> onOpen;
  final bool isPrimary;
  final bool isApproved;

  @override
  Widget build(BuildContext context) {
    final requester = (order?.requesterName ?? '').trim();
    final area = (order?.areaName ?? '').trim();
    final title = requester.isNotEmpty ? requester : 'Orden $orderId';
    final subtitleParts = <String>[];
    if (area.isNotEmpty) subtitleParts.add(area);
    if (requester.isNotEmpty) subtitleParts.add('Orden $orderId');
    final subtitle = subtitleParts.join(' - ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 360;
          final primaryTag = isPrimary
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Principal',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                )
              : const SizedBox.shrink();
          final approvedTag = isApproved
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Aprobada',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: Colors.green.shade800),
                    ),
                  ),
                )
              : const SizedBox.shrink();

          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (isPrimary || isApproved)
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (isPrimary) primaryTag,
                    if (isApproved) approvedTag,
                  ],
                ),
            ],
          );
          final button = OutlinedButton(
            onPressed: () => onOpen(orderId),
            child: const Text('Visualizar PDF'),
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                content,
                const SizedBox(height: 6),
                button,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: content),
              const SizedBox(width: 8),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(message));
  }
}

bool _bundleMatchesSearch(
  SharedQuote bundle,
  Map<String, PurchaseOrder> ordersById,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return true;

  final buffer = StringBuffer();
  void addValue(Object? value) {
    if (value == null) return;
    final text = value.toString().trim().toLowerCase();
    if (text.isEmpty) return;
    buffer.write(text);
    buffer.write(' ');
  }

  addValue(bundle.id);
  addValue(bundle.supplier);
  addValue(_bundleLabel(bundle));
  addValue(bundle.pdfUrl);
  for (final orderId in bundle.orderIds) {
    addValue(orderId);
    final order = ordersById[orderId];
    if (order == null) continue;
    addValue(order.requesterName);
    addValue(order.areaName);
  }

  final haystack = buffer.toString();
  final tokens = normalized.split(RegExp(r'\s+')).where((token) => token.isNotEmpty);
  for (final token in tokens) {
    if (!haystack.contains(token)) return false;
  }
  return true;
}

String _primaryQuoteId(PurchaseOrder order) {
  final rawPrimary = order.primaryQuoteId?.trim() ?? '';
  if (rawPrimary.isNotEmpty) return rawPrimary;
  if (order.sharedQuoteRefs.isNotEmpty) {
    return order.sharedQuoteRefs.first.quoteId;
  }
  return '';
}

Map<String, int> _bundleCountByOrder(List<SharedQuote> bundles) {
  final counts = <String, int>{};
  for (final bundle in bundles) {
    for (final id in bundle.orderIds) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
  }
  return counts;
}

List<SharedQuote> _filterBundlesForOrders(
  List<SharedQuote> bundles,
  Map<String, PurchaseOrder> ordersById,
) {
  if (ordersById.isEmpty) return const [];
  return bundles
      .where((bundle) => bundle.orderIds.any(ordersById.containsKey))
      .toList();
}

List<PurchaseOrder> _ordersReadyToSend(List<PurchaseOrder> orders) {
  return orders
      .where(_orderReady)
      .where(_hasQuoteLinks)
      .toList();
}

String _formatNum(num value) {
  if (value % 1 == 0) return value.toInt().toString();
  return value.toStringAsFixed(2);
}

bool _itemReady(PurchaseOrderItem item) {
  final supplier = (item.supplier ?? '').trim();
  final budget = item.budget ?? 0;
  return supplier.isNotEmpty && budget > 0;
}

bool _orderReady(PurchaseOrder order) {
  if (order.items.isEmpty) return false;
  if (order.cotizacionReady != true) return false;
  return order.items.every(_itemReady);
}

bool _hasQuoteLinks(PurchaseOrder order) {
  return order.cotizacionLinks.any((link) => link.url.trim().isNotEmpty);
}

String _bundleLabel(SharedQuote bundle) {
  final label = bundle.supplier.trim();
  if (label.isNotEmpty) return label;
  final id = bundle.id.trim();
  if (id.length <= 6) return 'Cotización $id';
  return 'Cotización ${id.substring(0, 6)}';
}

String _normalizeLink(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme) return trimmed;
  return 'https://$trimmed';
}

bool _isValidUrl(String raw) {
  final link = _normalizeLink(raw);
  final uri = Uri.tryParse(link);
  return uri != null &&
      uri.isAbsolute &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}
