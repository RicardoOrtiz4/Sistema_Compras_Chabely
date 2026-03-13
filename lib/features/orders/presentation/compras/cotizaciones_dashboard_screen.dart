import 'dart:async';

import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/core/navigation_guard.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/domain/shared_quote.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_pdf_preload_gate.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';

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
  ProviderSubscription<AsyncValue<List<PurchaseOrder>>>? _legacyOrdersSubscription;
  ProviderSubscription<AsyncValue<List<SharedQuote>>>? _legacyBundlesSubscription;
  bool _migrationInProgress = false;
  bool _migrationDone = false;
  final Set<String> _bundleBusyIds = <String>{};
  final Set<String> _dismissedDireccionBundleIds = <String>{};
  final Set<String> _editedDashboardOrderIds = <String>{};
  final Set<String> _editedBundleIds = <String>{};
  final Set<String> _restoredOrderIds = <String>{};
  int _orderLimit = defaultOrderPageSize;
  int _bundleLimit = defaultOrderPageSize;
  List<PurchaseOrder>? _derivedOrdersRef;
  List<PurchaseOrder>? _derivedAllOrdersRef;
  List<SharedQuote>? _derivedBundlesRef;
  List<PurchaseOrder>? _latestOrdersForMigration;
  List<SharedQuote>? _latestBundlesForMigration;
  bool? _derivedReadOnly;
  String? _derivedRestoredOrdersKey;
  _DashboardDerivedData? _derivedCache;

  bool get _isReadOnly => widget.mode == CotizacionesDashboardMode.direccion;

  @override
  void initState() {
    super.initState();
    _bundleLabelController = TextEditingController();
    _bundleLinkController = TextEditingController();
    _bindLegacyMigrationListeners();
  }

  @override
  void didUpdateWidget(covariant CotizacionesDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _unbindLegacyMigrationListeners();
      _bindLegacyMigrationListeners();
    }
  }

  @override
  void dispose() {
    _unbindLegacyMigrationListeners();
    _bundleLabelController.dispose();
    _bundleLinkController.dispose();
    super.dispose();
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
    final allOrdersAsync = _isReadOnly
        ? const AsyncValue<List<PurchaseOrder>>.data(<PurchaseOrder>[])
        : ref.watch(comprasDashboardAllOrdersProvider);
    final bundlesAsync = ref.watch(sharedQuotesProvider);

    final body = ordersAsync.when(
      data: (orders) => allOrdersAsync.when(
        data: (allOrders) => bundlesAsync.when(
          data: (bundles) {
          final derived = _resolveDerivedData(
            orders,
            bundles,
            allOrders: allOrders,
          );
          final visibleOrders = derived.visibleOrders;
          final ordersById = derived.ordersById;
          final visibleBundles = _isReadOnly
              ? derived.visibleBundles
                    .where(
                      (bundle) =>
                          !_dismissedDireccionBundleIds.contains(bundle.id),
                    )
                    .toList(growable: false)
              : derived.visibleBundles;
          final quotesById = derived.quotesById;
          final filteredOrders = visibleOrders;
          final limitedOrders = _isReadOnly
              ? filteredOrders
              : filteredOrders.take(_orderLimit).toList();
          final filteredBundles = visibleBundles;
          final limitedBundles = filteredBundles.take(_bundleLimit).toList();
          final canLoadMoreOrders =
              !_isReadOnly && filteredOrders.length > limitedOrders.length;
          final canLoadMoreBundles =
              filteredBundles.length > limitedBundles.length;
          final bundleCountByOrder = derived.bundleCountByOrder;
          final visibleOrderIds = visibleOrders.map((order) => order.id).toSet();
          final selectedVisibleIds =
              _selectedOrderIds.intersection(visibleOrderIds);
          final limitedOrderIds = limitedOrders.map((order) => order.id).toSet();
          final selectedLimitedIds =
              selectedVisibleIds.intersection(limitedOrderIds);

          final content = Column(
            children: [
              Expanded(
                child: ListView(
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
                        onOpenOrder: (order) => guardedPdfPush(
                          context,
                          '/orders/${order.id}/pdf',
                        ),
                      ),
                      if (canLoadMoreOrders) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: OutlinedButton.icon(
                            onPressed: _loadMoreOrders,
                            icon: const Icon(Icons.expand_more),
                            label: const Text('Ver mÃ¡s'),
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
                      onSendToDireccion: _isReadOnly
                          ? null
                          : (bundle) => _sendBundleToDireccion(
                                bundle,
                                ordersById,
                              ),
                      onSendToEta: _isReadOnly
                          ? (bundle) => _handleSendToEtaBundle(
                                bundle,
                                ordersById,
                                quotesById,
                              )
                          : null,
                      onEditBundle: _isReadOnly
                          ? null
                          : (bundle) => _editBundle(
                                bundle,
                                visibleOrders,
                                ordersById: ordersById,
                              ),
                      onDeleteBundle: _isReadOnly
                          ? null
                          : (bundle) => _deleteBundle(bundle, ordersById),
                      onOpenLink: _openLink,
                      onOpenOrder:
                          widget.onOpenOrder ??
                          (orderId) => guardedPdfPush(
                                context,
                                '/orders/$orderId/pdf',
                              ),
                      onEditOrder: _isReadOnly ? null : _editOrderDataFromDashboard,
                      editedOrderIds: _editedDashboardOrderIds,
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
                  ],
                ),
              ),
            ],
          );
          return OrderPdfPreloadGate(
            orders: visibleOrders,
            child: content,
          );
          },
          loading: () => const AppSplash(),
          error: (error, stack) => _ErrorPanel(
            message: reportError(error, stack, context: 'CotizacionesDashboard.bundles'),
          ),
        ),
        loading: () => const AppSplash(),
        error: (error, stack) => _ErrorPanel(
          message: reportError(error, stack, context: 'CotizacionesDashboard.allOrders'),
        ),
      ),
      loading: () => const AppSplash(),
      error: (error, stack) => _ErrorPanel(
        message: reportError(error, stack, context: 'CotizacionesDashboard.orders'),
      ),
    );

    final composedBody = body;

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

  void _bindLegacyMigrationListeners() {
    if (_isReadOnly) return;

    final ordersProvider = widget.mode == CotizacionesDashboardMode.compras
        ? cotizacionesOrdersProvider
        : pendingDireccionOrdersProvider;
    _latestOrdersForMigration = ref.read(ordersProvider).valueOrNull;
    _latestBundlesForMigration = ref.read(sharedQuotesProvider).valueOrNull;

    _legacyOrdersSubscription =
        ref.listenManual<AsyncValue<List<PurchaseOrder>>>(ordersProvider, (
      _,
      next,
    ) {
      _latestOrdersForMigration = next.valueOrNull;
      _triggerLegacyMigrationIfReady();
    });
    _legacyBundlesSubscription =
        ref.listenManual<AsyncValue<List<SharedQuote>>>(sharedQuotesProvider, (
      _,
      next,
    ) {
      _latestBundlesForMigration = next.valueOrNull;
      _triggerLegacyMigrationIfReady();
    });
    _triggerLegacyMigrationIfReady();
  }

  void _unbindLegacyMigrationListeners() {
    _legacyOrdersSubscription?.close();
    _legacyOrdersSubscription = null;
    _legacyBundlesSubscription?.close();
    _legacyBundlesSubscription = null;
    _latestOrdersForMigration = null;
    _latestBundlesForMigration = null;
  }

  void _triggerLegacyMigrationIfReady() {
    if (_isReadOnly) return;
    final orders = _latestOrdersForMigration;
    final bundles = _latestBundlesForMigration;
    if (orders == null || bundles == null) return;
    _maybeMigrateLegacyLinks(orders, bundles);
  }

  _DashboardDerivedData _resolveDerivedData(
    List<PurchaseOrder> orders,
    List<SharedQuote> bundles,
    {
    List<PurchaseOrder>? allOrders,
  }
  ) {
    final cached = _derivedCache;
    if (cached != null &&
        identical(_derivedOrdersRef, orders) &&
        identical(_derivedAllOrdersRef, allOrders) &&
        identical(_derivedBundlesRef, bundles) &&
        _derivedReadOnly == _isReadOnly &&
        _derivedRestoredOrdersKey == _restoredOrdersKey()) {
      return cached;
    }

    final ordersForLookup = _isReadOnly ? orders : (allOrders ?? orders);
    final ordersById = {for (final order in ordersForLookup) order.id: order};
    final readyOrderIds = orders.where(_orderReady).map((order) => order.id).toSet();
    final restoredOrderIds = ordersForLookup
        .where(
          (order) =>
              order.restoredToCotizacionesOrders ||
              _restoredOrderIds.contains(order.id),
        )
        .map((order) => order.id)
        .toSet();
    final visibleOrders = _isReadOnly
        ? List<PurchaseOrder>.unmodifiable(orders)
        : List<PurchaseOrder>.unmodifiable(
            ordersForLookup.where(
              (order) =>
                  readyOrderIds.contains(order.id) ||
                  restoredOrderIds.contains(order.id),
            ),
          );
    final visibleOrderIds = visibleOrders.map((order) => order.id).toSet();
    final visibleBundlesBase = _isReadOnly
        ? List<SharedQuote>.unmodifiable(
            _filterBundlesForOrders(bundles, ordersById),
          )
        : List<SharedQuote>.unmodifiable(
            _visibleComprasBundles(
              bundles: bundles,
              visibleOrderIds: visibleOrderIds,
              ordersById: ordersById,
            ),
          );
    final visibleBundles = _isReadOnly
        ? List<SharedQuote>.unmodifiable(
            visibleBundlesBase.where(
              (bundle) => bundle.orderIds.any(
                (id) =>
                    ordersById.containsKey(id) &&
                    !bundle.approvedOrderIds.contains(id),
              ),
            ).where((bundle) => !bundle.needsUpdate),
          )
        : visibleBundlesBase;
    final quotesById = {for (final bundle in bundles) bundle.id: bundle};
    final derived = _DashboardDerivedData(
      visibleOrders: visibleOrders,
      ordersById: ordersById,
      visibleBundles: visibleBundles,
      quotesById: quotesById,
      bundleCountByOrder: _bundleCountByOrder(visibleBundles),
    );
    _derivedOrdersRef = orders;
    _derivedAllOrdersRef = allOrders;
    _derivedBundlesRef = bundles;
    _derivedReadOnly = _isReadOnly;
    _derivedRestoredOrdersKey = _restoredOrdersKey();
    _derivedCache = derived;
    return derived;
  }

  String _restoredOrdersKey() {
    if (_restoredOrderIds.isEmpty) return '';
    final ids = _restoredOrderIds.toList()..sort();
    return ids.join('|');
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

  Future<void> _createBundle(List<PurchaseOrder> orders) async {
    if (_selectedOrderIds.isEmpty) return;

    final link = _bundleLinkController.text.trim();
    final label = _bundleLabelController.text.trim();
    final bundles = ref.read(sharedQuotesProvider).maybeWhen(
          data: (items) => items,
          orElse: () => const <SharedQuote>[],
        );
    final selectedOrders = orders
        .where((order) => _selectedOrderIds.contains(order.id))
        .toList();

    if (link.isEmpty) {
      _showMessage('Ingresa un link de cotizacion.');
      return;
    }
    if (label.isEmpty) {
      _showMessage('Ingresa una etiqueta.');
      return;
    }
    if (!_isValidUrl(link)) {
      _showMessage('Ingresa un link valido.');
      return;
    }
    final duplicateMessage = _validateBundleUniqueness(
      bundles: bundles,
      label: label,
      link: link,
    );
    if (duplicateMessage != null) {
      _showMessage(duplicateMessage);
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
              Text('Etiqueta: $label'),
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

  Future<void> _editBundle(
    SharedQuote bundle,
    List<PurchaseOrder> orders,
    {
    required Map<String, PurchaseOrder> ordersById,
  }
  ) async {
    final linkController = TextEditingController(text: bundle.pdfUrl);
    final bundles = ref.read(sharedQuotesProvider).maybeWhen(
          data: (items) => items,
          orElse: () => const <SharedQuote>[],
        );
    final selected = bundle.orderIds.toSet();
    final availableOrders = orders.toList();
    final canRestoreOrders =
        bundle.needsUpdate && bundle.rejectedOrderIds.isNotEmpty;

    final result = await showDialog<_EditBundleAction>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text('Editar agrupacion ${_bundleLabel(bundle)}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                TextField(
                  controller: linkController,
                  decoration: const InputDecoration(
                    labelText: 'Link de cotizacion',
                    prefixIcon: Icon(Icons.link),
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                Text(
                  'Órdenes en la agrupación',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
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
                    title: Text(order.id),
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
                if (canRestoreOrders) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Si restauras las órdenes, también volverán a mostrarse en la sección "Órdenes" para que puedas crear nuevas agrupaciones sin sacarlas de esta agrupación.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (canRestoreOrders)
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(
                  context,
                  _EditBundleAction.restoreOrders,
                ),
                icon: const Icon(Icons.restore_outlined),
                label: const Text('Restaurar órdenes'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context, _EditBundleAction.cancel),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, _EditBundleAction.save),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    final link = linkController.text.trim();
    linkController.dispose();

    if (result == null || result == _EditBundleAction.cancel) return;
    if (result == _EditBundleAction.restoreOrders) {
      await _restoreBundleOrders(
        bundle,
        ordersById: ordersById,
      );
      return;
    }
    if (selected.isEmpty) {
      _showMessage('La agrupacion debe conservar al menos una orden.');
      return;
    }
    if (!_isValidUrl(link)) {
      _showMessage('Ingresa un link valido.');
      return;
    }
    final duplicateMessage = _validateBundleUniqueness(
      bundles: bundles,
      label: bundle.supplier,
      link: link,
      editingBundleId: bundle.id,
    );
    if (duplicateMessage != null) {
      _showMessage(duplicateMessage);
      return;
    }

    final availableIds = orders.map((o) => o.id).toSet();
    final toAdd = selected.difference(bundle.orderIds.toSet()).toList();
    final toRemove = bundle.orderIds
        .where((id) => availableIds.contains(id) && !selected.contains(id))
        .toList();

    try {
      final repo = ref.read(purchaseOrderRepositoryProvider);
      final normalizedLink = _normalizeLink(link);
      var currentQuote = bundle;
      if (normalizedLink != bundle.pdfUrl.trim()) {
        await repo.updateSharedQuoteLink(quote: bundle, pdfUrl: normalizedLink);
        currentQuote = SharedQuote(
          id: bundle.id,
          supplier: bundle.supplier,
          orderIds: bundle.orderIds,
          pdfUrl: normalizedLink,
          approvedOrderIds: bundle.approvedOrderIds,
          approvedAt: bundle.approvedAt,
          rejectedOrderIds: bundle.rejectedOrderIds,
          rejectionComment: bundle.rejectionComment,
          rejectedAt: bundle.rejectedAt,
          rejectedByName: bundle.rejectedByName,
          rejectedByArea: bundle.rejectedByArea,
          needsUpdate: false,
          version: bundle.version + 1,
        );
      }
      if (toAdd.isNotEmpty) {
        await repo.linkOrdersToSharedQuote(quote: currentQuote, orderIds: toAdd);
      }
      for (final orderId in toRemove) {
        final order = orders.firstWhere((o) => o.id == orderId);
        await repo.unlinkOrderFromSharedQuote(order: order, quote: currentQuote);
      }
      if (mounted) {
        setState(() => _editedBundleIds.add(bundle.id));
      }
      if (!mounted) return;
      _showMessage('Agrupacion actualizada.');
    } catch (error, stack) {
      if (!mounted) return;
      _showMessage(reportError(error, stack, context: 'CotizacionesDashboard.editBundle'));
    }
  }

  Future<void> _restoreBundleOrders(
    SharedQuote bundle, {
    required Map<String, PurchaseOrder> ordersById,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Restaurar órdenes de ${_bundleLabel(bundle)}'),
        content: const Text(
          'Las órdenes volverán a mostrarse en la sección "Órdenes" para que puedas crear nuevas agrupaciones, pero seguirán perteneciendo a esta agrupación.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final repo = ref.read(purchaseOrderRepositoryProvider);
      final restored = bundle.orderIds
          .where((orderId) => ordersById.containsKey(orderId))
          .toList(growable: false);
      if (!mounted) return;
      if (restored.isEmpty) {
        _showMessage('No se encontraron órdenes para restaurar.');
        return;
      }
      await repo.restoreOrdersToCotizacionesOrders(orderIds: restored);
      if (!mounted) return;
      setState(() {
        _restoredOrderIds.addAll(restored);
        _derivedCache = null;
      });
      _showMessage(
        'Órdenes restauradas a la sección "Órdenes" sin quitarse de la agrupación.',
      );
    } catch (error, stack) {
      if (!mounted) return;
      _showMessage(
        reportError(error, stack, context: 'CotizacionesDashboard.restoreBundleOrders'),
      );
    }
  }

  Future<void> _editOrderDataFromDashboard(String orderId) async {
    final result = await guardedPush<Object?>(
      context,
      '/orders/cotizaciones/$orderId?fromDashboard=1',
    );
    if (!mounted) return;
    if (result != null) {
      setState(() => _editedDashboardOrderIds.add(orderId));
    }
    ref.invalidate(orderByIdStreamProvider(orderId));
  }

  Future<void> _deleteBundle(SharedQuote bundle, Map<String, PurchaseOrder> ordersById) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminar agrupacion ${_bundleLabel(bundle)}'),
        content: const Text('Se desvincularan todas las ordenes de esta agrupacion.'),
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
      _showMessage('Agrupacion eliminada.');
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

  Future<void> _sendBundleToDireccion(
    SharedQuote bundle,
    Map<String, PurchaseOrder> ordersById,
  ) async {
    if (_bundleBusyIds.contains(bundle.id)) return;

    final orders = bundle.orderIds
        .map((id) => ordersById[id])
        .whereType<PurchaseOrder>()
        .toList();
    final readyOrders = _ordersReadyToSend(orders);
    if (readyOrders.isEmpty) {
      _showMessage('Esta agrupacion no tiene ordenes listas para enviar.');
      return;
    }

    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) {
      _showMessage('Perfil no disponible.');
      return;
    }

    final count = readyOrders.length;
    final processedName = actor.name.trim().isEmpty ? 'Tu nombre' : actor.name.trim();
    final processedArea = actor.areaDisplay.trim().isEmpty
        ? 'Tu area'
        : actor.areaDisplay.trim();

    if (!_bundleHasCorrectionsSinceRejection(bundle)) {
      final resendWithoutCorrections = await _confirmSendWithoutCorrections(bundle);
      if (resendWithoutCorrections != true) return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Enviar agrupacion ${_bundleLabel(bundle)}'),
        content: Text(
          'Se enviaran $count orden(es) con sus links de cotizacion. '
          'Despues de enviar, este grupo pasara a Direccion General.\n\n'
          'En el PDF, la casilla PROCESÓ mostrara "$processedName" y el area "$processedArea".',
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

    setState(() => _bundleBusyIds.add(bundle.id));
    try {
      final repo = ref.read(purchaseOrderRepositoryProvider);
      if (bundle.needsUpdate) {
        final normalizedLink = _normalizeLink(bundle.pdfUrl);
        if (!_isValidUrl(normalizedLink)) {
          _showMessage(
            'Esta agrupacion necesita un link de cotizacion valido antes de enviarse.',
          );
          return;
        }
        await repo.updateSharedQuoteLink(
          quote: bundle,
          pdfUrl: normalizedLink,
        );
      }
      for (final order in readyOrders) {
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
      if (mounted) {
        setState(() {
          _editedDashboardOrderIds.removeAll(bundle.orderIds);
          _editedBundleIds.remove(bundle.id);
        });
      }
      if (!mounted) return;
      _showMessage('Agrupacion enviada a Direccion General.');
    } catch (error, stack) {
      if (!mounted) return;
      _showMessage(reportError(error, stack, context: 'CotizacionesDashboard.sendBundle'));
    } finally {
      if (mounted) {
        setState(() => _bundleBusyIds.remove(bundle.id));
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
      _showMessage('No hay Ã³rdenes disponibles en esta cotizaciÃ³n.');
      return;
    }

    final selectedOrderIds = await _confirmBundleApprovalSelection(
      bundle: bundle,
      orders: orders,
      quotesById: quotesById,
    );
    if (selectedOrderIds == null || selectedOrderIds.isEmpty) return;
    final blockedOrders = orders
        .where(
          (order) =>
              selectedOrderIds.contains(order.id) &&
              _hasRejectedSiblingQuote(
                order: order,
                currentQuoteId: bundle.id,
                quotesById: quotesById,
              ),
        )
        .toList(growable: false);
    if (blockedOrders.isNotEmpty) {
      final confirmed = await _confirmBlockedBundleApproval(
        bundle: bundle,
        blockedOrders: blockedOrders,
        selectedCount: selectedOrderIds.length,
      );
      if (confirmed != true) return;
    }

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
      var blockedByRejectedGroup = 0;
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
          if (_hasRejectedSiblingQuote(
            order: order,
            currentQuoteId: bundle.id,
            quotesById: quotesById,
          )) {
            blockedByRejectedGroup += 1;
          }
          continue;
        }
        await repo.markPaymentDone(order: order, actor: actor);
        moved += 1;
      }
      if (moved > 0) {
        final branding = ref.read(currentBrandingProvider);
        prefetchOrderPdfsForOrders(
          orders.where((order) => selectedOrderIds.contains(order.id)).toList(),
          branding: branding,
          limit: selectedOrderIds.length,
        );
      }
      if (!mounted) return;
      if (blocked > 0) {
        final rejectedMessage = blockedByRejectedGroup > 0
            ? ' $blockedByRejectedGroup orden(es) tienen otro grupo con link de cotizacion rechazado y no pueden avanzar hasta que ese grupo sea corregido y aprobado.'
            : '';
        _showMessage(
          'Se aprobaron $moved orden(es). '
          '$blocked orden(es) seguirán en Dirección General hasta aprobar sus otras cotizaciones.$rejectedMessage',
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
    required Map<String, SharedQuote> quotesById,
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
          final selectedWithRejectedSibling = orders
              .where(
                (order) =>
                    selected.contains(order.id) &&
                    _hasRejectedSiblingQuote(
                      order: order,
                      currentQuoteId: bundle.id,
                      quotesById: quotesById,
                    ),
              )
              .length;
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
                  if (selectedWithRejectedSibling > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '$selectedWithRejectedSibling orden(es) tienen otro grupo con link de cotizacion rechazado. Aunque apruebes este grupo, esas ordenes no avanzaran hasta que el otro grupo sea corregido y aprobado.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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
                              '${approvedSet.contains(order.id) ? ' · Ya aprobada' : ''}'
                              '${_hasRejectedSiblingQuote(order: order, currentQuoteId: bundle.id, quotesById: quotesById) ? ' · Tiene otro grupo rechazado' : ''}',
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

  bool _bundleHasCorrectionsSinceRejection(SharedQuote bundle) {
    final rejectedAt = bundle.rejectedAt;
    if (rejectedAt == null) return true;
    if (_editedBundleIds.contains(bundle.id)) return true;
    if (bundle.orderIds.any(_editedDashboardOrderIds.contains)) return true;

    final updatedAt = bundle.updatedAt;
    if (updatedAt == null) return false;
    return updatedAt.isAfter(rejectedAt);
  }

  Future<bool?> _confirmSendWithoutCorrections(SharedQuote bundle) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirmar reenvio de ${_bundleLabel(bundle)}'),
        content: const Text(
          'Esta agrupacion fue regresada por Direccion General y no se detectaron correcciones desde ese rechazo.\n\n'
          'Si la envias asi, es posible que Direccion General la vuelva a rechazar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enviar de todos modos'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmBlockedBundleApproval({
    required SharedQuote bundle,
    required List<PurchaseOrder> blockedOrders,
    required int selectedCount,
  }) async {
    final blockedIds = blockedOrders.map((order) => order.id).join(', ');
    final blockedCount = blockedOrders.length;
    final unaffectedCount = selectedCount - blockedCount;

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirmar aprobación de ${_bundleLabel(bundle)}'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$blockedCount orden(es) de este grupo tienen otra agrupación rechazada.',
              ),
              const SizedBox(height: 8),
              Text(
                'Si continúas, este grupo quedará aprobado, pero esas ordenes no pasarán a pendientes de fecha estimada hasta que su otra agrupación sea corregida y aprobada.',
              ),
              if (unaffectedCount > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '$unaffectedCount orden(es) sí podrán avanzar normalmente.',
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Órdenes afectadas: $blockedIds',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
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
            child: const Text('Sí, aprobar'),
          ),
        ],
      ),
    );
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
      _showMessage('No hay órdenes disponibles en esta cotizaciÃ³n.');
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
      await repo.rejectSharedQuoteFromDireccion(
        quote: bundle,
        orders: orders,
        rejectedOrderIds: rejection.orderIds,
        comment: rejection.comment,
        actor: actor,
      );
      if (_isReadOnly) {
        setState(() => _dismissedDireccionBundleIds.add(bundle.id));
        unawaited(
          Future<void>.delayed(const Duration(seconds: 3), () {
            if (!mounted) return;
            setState(() => _dismissedDireccionBundleIds.remove(bundle.id));
          }),
        );
      }
      if (!mounted) return;
      _showMessage('Grupo regresado al dashboard de cotizaciones para edición.');
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

    final hasLegacyLinks = orders.any(
      (order) => order.cotizacionLinks.any(
        (link) =>
            (link.quoteId ?? '').trim().isEmpty && link.url.trim().isNotEmpty,
      ),
    );
    if (!hasLegacyLinks) {
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

enum _EditBundleAction { cancel, save, restoreOrders }

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
    final metrics = _OrderQuoteMetrics.fromOrder(order);

    return Card(
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
                Text(
                  'Árticulos completos: '
                  '${metrics.itemsReady}/${metrics.itemsTotal}',
                ),
                Text('Links asignados: ${metrics.linkCount}'),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Ver PDF'),
              ),
            ),
          ],
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

class _OrderQuoteMetrics {
  const _OrderQuoteMetrics({
    required this.signature,
    required this.itemsTotal,
    required this.itemsReady,
    required this.linkCount,
  });

  final String signature;
  final int itemsTotal;
  final int itemsReady;
  final int linkCount;

  static _OrderQuoteMetrics fromOrder(PurchaseOrder order) {
    final signature = _signatureFor(order);
    final cached = _orderQuoteMetricsCache[order.id];
    if (cached != null && cached.signature == signature) {
      _orderQuoteMetricsCache.remove(order.id);
      _orderQuoteMetricsCache[order.id] = cached;
      return cached;
    }

    final computed = _OrderQuoteMetrics(
      signature: signature,
      itemsTotal: order.items.length,
      itemsReady: order.items.where(_itemReady).length,
      linkCount: order.cotizacionLinks
          .where((link) => link.url.trim().isNotEmpty)
          .length,
    );
    _orderQuoteMetricsCache.remove(order.id);
    _orderQuoteMetricsCache[order.id] = computed;
    if (_orderQuoteMetricsCache.length > _maxOrderQuoteMetricsCacheEntries) {
      _orderQuoteMetricsCache.remove(_orderQuoteMetricsCache.keys.first);
    }
    return computed;
  }

  static String _signatureFor(PurchaseOrder order) {
    final buffer = StringBuffer()
      ..write(order.updatedAt?.millisecondsSinceEpoch ?? 0)
      ..write('|')
      ..write(order.items.length)
      ..write('|')
      ..write(order.cotizacionLinks.length)
      ..write('|');
    for (final item in order.items) {
      buffer
        ..write(item.line)
        ..write(':')
        ..write(item.supplier ?? '')
        ..write(':')
        ..write(item.budget?.toString() ?? '')
        ..write(':')
        ..write(item.estimatedDate?.millisecondsSinceEpoch ?? '')
        ..write(';');
    }
    for (final link in order.cotizacionLinks) {
      buffer
        ..write(link.quoteId ?? '')
        ..write(':')
        ..write(link.url)
        ..write(';');
    }
    return buffer.toString();
  }
}

const int _maxOrderQuoteMetricsCacheEntries = 192;
final LinkedHashMap<String, _OrderQuoteMetrics> _orderQuoteMetricsCache =
    LinkedHashMap<String, _OrderQuoteMetrics>();



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
    required this.onSendToDireccion,
    required this.onSendToEta,
    required this.onEditBundle,
    required this.onDeleteBundle,
    required this.onOpenLink,
    required this.onOpenOrder,
    required this.onEditOrder,
    required this.editedOrderIds,
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
  final Future<void> Function(SharedQuote bundle)? onSendToDireccion;
  final Future<void> Function(SharedQuote bundle)? onSendToEta;
  final Future<void> Function(SharedQuote bundle)? onEditBundle;
  final Future<void> Function(SharedQuote bundle)? onDeleteBundle;
  final Future<void> Function(String link) onOpenLink;
  final ValueChanged<String>? onOpenOrder;
  final ValueChanged<String>? onEditOrder;
  final Set<String> editedOrderIds;

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
                      labelText: 'Etiqueta',
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
              onSendToDireccion: onSendToDireccion == null
                  ? null
                  : () => onSendToDireccion!(bundle),
              onSendToEta: onSendToEta == null ? null : () => onSendToEta!(bundle),
              onEdit: onEditBundle,
              onDelete: onDeleteBundle,
              onOpen: onOpenLink,
              onOpenOrder: onOpenOrder,
              onEditOrder: onEditOrder,
              editedOrderIds: editedOrderIds,
            ),
            const SizedBox(height: 12),
          ],
      ],
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
    required this.onSendToDireccion,
    required this.onSendToEta,
    required this.onEdit,
    required this.onDelete,
    required this.onOpen,
    required this.onOpenOrder,
    required this.onEditOrder,
    required this.editedOrderIds,
  });

  final SharedQuote bundle;
  final Map<String, PurchaseOrder> ordersById;
  final bool readOnly;
  final bool showOpenQuote;
  final Future<void> Function(String link) onOpenQuoteLink;
  final bool busy;
  final VoidCallback? onReject;
  final VoidCallback? onSendToDireccion;
  final VoidCallback? onSendToEta;
  final Future<void> Function(SharedQuote bundle)? onEdit;
  final Future<void> Function(SharedQuote bundle)? onDelete;
  final Future<void> Function(String link) onOpen;
  final ValueChanged<String>? onOpenOrder;
  final ValueChanged<String>? onEditOrder;
  final Set<String> editedOrderIds;

  @override
  Widget build(BuildContext context) {
    final label = _bundleLabel(bundle);
    final visibleOrderIds = readOnly
        ? bundle.orderIds.where(ordersById.containsKey).toList()
        : bundle.orderIds;
    final orderCount = visibleOrderIds.length;
    final link = bundle.pdfUrl.trim();
    final rejectedOrderIds = bundle.rejectedOrderIds.toSet();
    final hasRejectedOrders = rejectedOrderIds.isNotEmpty;
    final rejectionComment = (bundle.rejectionComment ?? '').trim();

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: Theme.of(context).textTheme.titleSmall),
                      if (!readOnly && hasRejectedOrders) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _InfoPill(
                              label: 'Rechazada por DG',
                              color: Colors.orange.shade100,
                              textColor: Colors.orange.shade900,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
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
              ],
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
            if (!readOnly && hasRejectedOrders) ...[
              const SizedBox(height: 8),
              Text(
                'Motivo del rechazo: ${rejectionComment.isEmpty ? 'Sin comentario registrado.' : rejectionComment}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.orange.shade900,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Órdenes afectadas: ${visibleOrderIds.where(rejectedOrderIds.contains).join(', ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (orderCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    for (final orderId in visibleOrderIds) ...[
                      _BundleOrderRow(
                        orderId: orderId,
                        order: ordersById[orderId],
                        onOpen: onOpenOrder,
                        onEdit: onEditOrder,
                        isApproved: bundle.approvedOrderIds.contains(orderId),
                        wasEdited: editedOrderIds.contains(orderId),
                      ),
                      const SizedBox(height: 6),
                    ],
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
                    label: const Text('Aprobar Órdenes del grupo'),
                  ),
                ],
              ),
            ],
            if (!readOnly) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: busy ? null : onSendToDireccion,
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Enviar agrupacion'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onEdit == null ? null : () => onEdit!(bundle),
                    icon: const Icon(Icons.edit_note_outlined),
                    label: const Text('Editar agrupacion'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onDelete == null ? null : () => onDelete!(bundle),
                    icon: const Icon(Icons.link_off_outlined),
                    label: const Text('Eliminar agrupacion'),
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
    required this.onEdit,
    required this.isApproved,
    required this.wasEdited,
  });

  final String orderId;
  final PurchaseOrder? order;
  final ValueChanged<String>? onOpen;
  final ValueChanged<String>? onEdit;
  final bool isApproved;
  final bool wasEdited;

  @override
  Widget build(BuildContext context) {
    final area = (order?.areaName ?? '').trim();
    final title = 'Orden $orderId';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 360;
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
          final editedTag = wasEdited
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Editada',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: Colors.amber.shade900),
                    ),
                  ),
                )
              : const SizedBox.shrink();

          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              if (area.isNotEmpty)
                Text(
                  area,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (isApproved || wasEdited)
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (isApproved) approvedTag,
                    if (wasEdited) editedTag,
                  ],
                ),
            ],
          );
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: onOpen == null ? null : () => onOpen!(orderId),
                child: const Text('Visualizar PDF'),
              ),
              if (onEdit != null)
                OutlinedButton(
                  onPressed: () => onEdit!(orderId),
                  child: const Text('Editar datos'),
                ),
            ],
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                content,
                const SizedBox(height: 6),
                actions,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: content),
              const SizedBox(width: 8),
              Flexible(child: actions),
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

class _DashboardDerivedData {
  const _DashboardDerivedData({
    required this.visibleOrders,
    required this.ordersById,
    required this.visibleBundles,
    required this.quotesById,
    required this.bundleCountByOrder,
  });

  final List<PurchaseOrder> visibleOrders;
  final Map<String, PurchaseOrder> ordersById;
  final List<SharedQuote> visibleBundles;
  final Map<String, SharedQuote> quotesById;
  final Map<String, int> bundleCountByOrder;
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

bool _hasRejectedSiblingQuote({
  required PurchaseOrder order,
  required String currentQuoteId,
  required Map<String, SharedQuote> quotesById,
}) {
  for (final ref in order.sharedQuoteRefs) {
    final quoteId = ref.quoteId.trim();
    if (quoteId.isEmpty || quoteId == currentQuoteId) continue;
    final quote = quotesById[quoteId];
    if (quote == null) continue;
    if (quote.needsUpdate && quote.rejectedOrderIds.contains(order.id)) {
      return true;
    }
  }
  return false;
}

List<SharedQuote> _visibleComprasBundles({
  required List<SharedQuote> bundles,
  required Set<String> visibleOrderIds,
  required Map<String, PurchaseOrder> ordersById,
}) {
  return bundles.where((bundle) {
    final hasVisibleOrder = bundle.orderIds.any(visibleOrderIds.contains);
    if (hasVisibleOrder) return true;
    return bundle.needsUpdate &&
        bundle.rejectedOrderIds.isNotEmpty &&
        bundle.orderIds.any(ordersById.containsKey);
  }).toList();
}

String _bundleLabel(SharedQuote bundle) {
  final label = bundle.supplier.trim();
  if (label.isNotEmpty) return label;
  final id = bundle.id.trim();
  if (id.length <= 6) return 'CotizaciÃ³n $id';
  return 'CotizaciÃ³n ${id.substring(0, 6)}';
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

String? _validateBundleUniqueness({
  required List<SharedQuote> bundles,
  required String label,
  required String link,
  String? editingBundleId,
}) {
  final normalizedLabel = _normalizeBundleLabel(label);
  if (normalizedLabel.isNotEmpty) {
    final labelExists = bundles.any(
      (bundle) =>
          bundle.id != editingBundleId &&
          _normalizeBundleLabel(bundle.supplier) == normalizedLabel,
    );
    if (labelExists) {
      return 'Ya existe una etiqueta con ese nombre.';
    }
  }

  final normalizedLink = _normalizeBundleLink(link);
  final linkExists = bundles.any(
    (bundle) =>
        bundle.id != editingBundleId &&
        _normalizeBundleLink(bundle.pdfUrl) == normalizedLink,
  );
  if (linkExists) {
    return 'Ese link de cotizacion ya esta registrado.';
  }

  return null;
}

String _normalizeBundleLabel(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

String _normalizeBundleLink(String value) {
  return _normalizeLink(value).trim().toLowerCase();
}


