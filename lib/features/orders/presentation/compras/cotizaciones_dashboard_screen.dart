import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/domain/shared_quote.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

enum CotizacionesDashboardMode { compras, direccion }

class CotizacionesDashboardScreen extends ConsumerStatefulWidget {
  const CotizacionesDashboardScreen({
    required this.mode,
    this.embedded = false,
    super.key,
  });

  final CotizacionesDashboardMode mode;
  final bool embedded;

  @override
  ConsumerState<CotizacionesDashboardScreen> createState() =>
      _CotizacionesDashboardScreenState();
}

class _CotizacionesDashboardScreenState
    extends ConsumerState<CotizacionesDashboardScreen> {
  final Set<String> _selectedOrderIds = <String>{};
  late final TextEditingController _bundleLabelController;
  late final TextEditingController _bundleLinkController;
  bool _migrationInProgress = false;
  bool _migrationDone = false;
  bool _sendingToDireccion = false;

  bool get _isReadOnly => widget.mode == CotizacionesDashboardMode.direccion;

  @override
  void initState() {
    super.initState();
    _bundleLabelController = TextEditingController();
    _bundleLinkController = TextEditingController();
  }

  @override
  void dispose() {
    _bundleLabelController.dispose();
    _bundleLinkController.dispose();
    super.dispose();
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
          final ordersById = {for (final order in orders) order.id: order};
          final visibleBundles = _filterBundlesForOrders(bundles, ordersById);
          final bundleCountByOrder = _bundleCountByOrder(visibleBundles);
          final visibleOrderIds = visibleOrders.map((order) => order.id).toSet();
          final selectedVisibleIds =
              _selectedOrderIds.intersection(visibleOrderIds);

          final ordersReadyToSend =
              _isReadOnly ? const <PurchaseOrder>[] : _ordersReadyToSend(visibleOrders);
          final ordersReadyIds = ordersReadyToSend.map((order) => order.id).toSet();
          final bundlesReadyToSend = _isReadOnly
              ? const <SharedQuote>[]
              : visibleBundles
                  .where((bundle) => bundle.orderIds.any(ordersReadyIds.contains))
                  .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!_isReadOnly) ...[
                _OrdersSection(
                  orders: visibleOrders,
                  readOnly: _isReadOnly,
                  selectedOrderIds: selectedVisibleIds,
                  bundleCountByOrder: bundleCountByOrder,
                  onToggleSelection: _toggleSelection,
                  onSelectAllPending: _selectAllPending,
                  onClearSelection: _clearSelection,
                  onOpenOrder: (order) => _showOrderDetails(order),
                ),
                const SizedBox(height: 16),
              ],
              _BundlesSection(
                bundles: visibleBundles,
                ordersById: ordersById,
                readOnly: _isReadOnly,
                selectedCount: selectedVisibleIds.length,
                emptyMessage: _isReadOnly
                    ? 'Aun no hay cotizaciones enviadas.'
                    : 'Aun no hay cotizaciones registradas.',
                labelController: _bundleLabelController,
                linkController: _bundleLinkController,
                onCreateBundle: _isReadOnly
                    ? null
                    : () => _createBundle(visibleOrders),
                onEditBundle: _isReadOnly ? null : _editBundleLink,
                onManageBundle: _isReadOnly
                    ? null
                    : (bundle) => _manageBundle(bundle, visibleOrders),
                onDeleteBundle:
                    _isReadOnly ? null : (bundle) => _deleteBundle(bundle, ordersById),
                onOpenLink: _openLink,
              ),
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

    if (widget.embedded) {
      return body;
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
      body: body,
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
    if (orders.isEmpty) {
      return const Text('No hay ordenes para mostrar.');
    }

    final allSelected = selectedOrderIds.length == orders.length && orders.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined),
                const SizedBox(width: 8),
                Text('Ordenes', style: Theme.of(context).textTheme.titleMedium),
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
                    child: const Text('Limpiar seleccion'),
                  ),
                ],
              ),
            if (!readOnly) const SizedBox(height: 8),
            for (final order in orders) ...[
              _OrderSelectionCard(
                order: order,
                selected: selectedOrderIds.contains(order.id),
                readOnly: readOnly,
                bundleCount: bundleCountByOrder[order.id] ?? 0,
                onToggle: (value) => onToggleSelection(order.id, value ?? false),
                onOpen: () => onOpenOrder(order),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
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
    final statusLabel = itemsReady == itemsTotal ? 'Listo' : 'Pendiente';

    return InkWell(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (!readOnly)
                  Checkbox(
                    value: selected,
                    onChanged: onToggle,
                  ),
                Expanded(
                  child: Text(
                    'Orden ${order.id}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: itemsReady == itemsTotal ? Colors.green.shade100 : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(statusLabel, style: Theme.of(context).textTheme.bodySmall),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('${order.requesterName} - ${order.areaName}'),
            const SizedBox(height: 4),
            Text('Articulos completos: $itemsReady/$itemsTotal'),
            Text('Links asignados: $linkCount | Cotizaciones: $bundleCount'),
          ],
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
    final internalOrder = (order.internalOrder ?? '').trim();
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
                  _InfoRow(label: 'Urgencia', value: order.urgency.label),
                  _InfoRow(label: 'Estado', value: order.status.label),
                  _InfoRow(
                    label: 'Articulos',
                    value: '$itemsReady/$itemsTotal completos',
                  ),
                  _InfoRow(label: 'Links', value: '$linkCount cotizacion(es)'),
                  if (internalOrder.isNotEmpty)
                    _InfoRow(label: 'OC interna', value: internalOrder),
                  if (comprasComment.isNotEmpty)
                    _InfoRow(label: 'Comentario', value: comprasComment),
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
    final isReady = _itemReady(item);

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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isReady ? Colors.green.shade100 : Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isReady ? 'Listo' : 'Pendiente',
                  style: theme.textTheme.bodySmall,
                ),
              ),
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
    required this.selectedCount,
    required this.emptyMessage,
    required this.labelController,
    required this.linkController,
    required this.onCreateBundle,
    required this.onEditBundle,
    required this.onManageBundle,
    required this.onDeleteBundle,
    required this.onOpenLink,
  });

  final List<SharedQuote> bundles;
  final Map<String, PurchaseOrder> ordersById;
  final bool readOnly;
  final int selectedCount;
  final String emptyMessage;
  final TextEditingController labelController;
  final TextEditingController linkController;
  final VoidCallback? onCreateBundle;
  final Future<void> Function(SharedQuote bundle)? onEditBundle;
  final Future<void> Function(SharedQuote bundle)? onManageBundle;
  final Future<void> Function(SharedQuote bundle)? onDeleteBundle;
  final Future<void> Function(String link) onOpenLink;

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
                const Icon(Icons.link),
                const SizedBox(width: 8),
                Text('Cotizaciones', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            if (!readOnly) ...[
              Text(
                selectedCount == 0
                    ? 'Selecciona ordenes para agruparlas con un link de cotizacion.'
                    : 'Se agruparan $selectedCount orden(es) con el link que ingreses.',
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
                  labelText: 'Link de cotizacion (Drive)',
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
              const SizedBox(height: 16),
            ],
            if (bundles.isEmpty)
              Text(emptyMessage),
            for (final bundle in bundles) ...[
              _BundleCard(
                bundle: bundle,
                ordersById: ordersById,
                readOnly: readOnly,
                onEdit: onEditBundle,
                onManage: onManageBundle,
                onDelete: onDeleteBundle,
                onOpen: onOpenLink,
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
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
    required this.onEdit,
    required this.onManage,
    required this.onDelete,
    required this.onOpen,
  });

  final SharedQuote bundle;
  final Map<String, PurchaseOrder> ordersById;
  final bool readOnly;
  final Future<void> Function(SharedQuote bundle)? onEdit;
  final Future<void> Function(SharedQuote bundle)? onManage;
  final Future<void> Function(SharedQuote bundle)? onDelete;
  final Future<void> Function(String link) onOpen;

  @override
  Widget build(BuildContext context) {
    final label = _bundleLabel(bundle);
    final orderCount = bundle.orderIds.length;
    final link = bundle.pdfUrl.trim();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: Theme.of(context).textTheme.titleSmall),
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
          const SizedBox(height: 6),
          Text('Ordenes vinculadas: $orderCount'),
          if (orderCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final orderId in bundle.orderIds.take(6))
                    Chip(
                      label: Text(
                        ordersById[orderId]?.requesterName ?? 'Orden $orderId',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (orderCount > 6)
                    Chip(label: Text('+${orderCount - 6} mas')),
                ],
              ),
            ),
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
                  label: const Text('Administrar ordenes'),
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
  return order.items.every(_itemReady);
}

bool _hasQuoteLinks(PurchaseOrder order) {
  return order.cotizacionLinks.any((link) => link.url.trim().isNotEmpty);
}

String _bundleLabel(SharedQuote bundle) {
  final label = bundle.supplier.trim();
  if (label.isNotEmpty) return label;
  final id = bundle.id.trim();
  if (id.length <= 6) return 'Cotizacion $id';
  return 'Cotizacion ${id.substring(0, 6)}';
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

