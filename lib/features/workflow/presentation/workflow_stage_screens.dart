import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:riverpod/legacy.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sistema_compras/core/access_control.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/navigation_guard.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/application/create_order_controller.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_inline_view.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';
import 'package:sistema_compras/features/orders/presentation/preview/pdf_download_helper.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_view_screen.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_csv_export.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_urgency_controls.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_status_duration.dart';
import 'package:sistema_compras/features/partners/data/partner_repository.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/features/purchase_packets/application/purchase_packet_use_cases.dart';
import 'package:sistema_compras/features/purchase_packets/domain/purchase_packet_domain.dart';

class ComprasDashboardScreen extends ConsumerStatefulWidget {
  const ComprasDashboardScreen({super.key});

  @override
  ConsumerState<ComprasDashboardScreen> createState() =>
      _ComprasDashboardScreenState();
}

class _ComprasDashboardScreenState extends ConsumerState<ComprasDashboardScreen> {
  final TextEditingController _quoteUrlController = TextEditingController();
  final List<String> _quoteUrls = <String>[];
  final Set<String> _expandedOrderIds = <String>{};
  final Map<String, DateTime> _sentAtBySupplier = <String, DateTime>{};
  String? _selectedSupplier;
  bool _sending = false;

  @override
  void dispose() {
    _quoteUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readyOrdersAsync = ref.watch(readyOrdersProvider);
    final bundlesAsync = ref.watch(packetBundlesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Compras / Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: readyOrdersAsync.when(
          data: (readyOrders) => bundlesAsync.when(
            data: (bundles) {
              final actualActiveItemRefIds = _activePacketItemRefIds(bundles);
              final activeItemRefIds = actualActiveItemRefIds;
              final pendingOrders = readyOrders
                  .map((order) => _buildPendingDashboardOrder(order, activeItemRefIds))
                  .where((order) => order.pendingItems.isNotEmpty)
                  .toList(growable: false);
              final suppliers = pendingOrders
                  .expand((order) => order.pendingItems)
                  .map((item) => item.supplier)
                  .toSet()
                  .toList(growable: false)
                ..sort();
              final selectedSupplier = suppliers.contains(_selectedSupplier)
                  ? _selectedSupplier
                  : (suppliers.isEmpty ? null : suppliers.first);
              if (selectedSupplier != _selectedSupplier) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    _selectedSupplier = selectedSupplier;
                    _quoteUrls.clear();
                    _expandedOrderIds.clear();
                  });
                });
              }
              final selectedBatch = selectedSupplier == null
                  ? null
                  : _buildSupplierBatch(
                      supplier: selectedSupplier,
                      pendingOrders: pendingOrders,
                    );
              if (pendingOrders.isEmpty) {
                return const Center(
                  child: Text('No hay items pendientes por agrupar en Dashboard.'),
                );
              }
              return ListView(
                children: [
                  _DashboardPanel(
                    title: 'Agrupar por proveedor',
                    subtitle:
                        'Selecciona un proveedor detectado en los items pendientes y envia su cotizacion a Direccion General.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String>(
                          value: selectedSupplier,
                          decoration: const InputDecoration(
                            labelText: 'Proveedor',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final supplier in suppliers)
                              DropdownMenuItem<String>(
                                value: supplier,
                                child: Text(supplier),
                              ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedSupplier = value;
                              _quoteUrls.clear();
                              _expandedOrderIds.clear();
                            });
                          },
                        ),
                        if (selectedBatch != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Ordenes involucradas',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          ...selectedBatch.orderIds.map((orderId) {
                            final orderItems = selectedBatch.items
                                .where((item) => item.orderId == orderId)
                                .toList(growable: false);
                            final expanded = _expandedOrderIds.contains(orderId);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(orderId),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${orderItems.length} item(s) con este proveedor',
                                                style: Theme.of(context).textTheme.bodySmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) => OrderPdfViewScreen(
                                                  orderId: orderId,
                                                ),
                                              ),
                                            );
                                          },
                                          icon: const Icon(Icons.picture_as_pdf_outlined),
                                          label: const Text('Ver PDF'),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          onPressed: () {
                                            setState(() {
                                              if (expanded) {
                                                _expandedOrderIds.remove(orderId);
                                              } else {
                                                _expandedOrderIds.add(orderId);
                                              }
                                            });
                                          },
                                          icon: Icon(
                                            expanded
                                                ? Icons.expand_less
                                                : Icons.expand_more,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (expanded) ...[
                                      const SizedBox(height: 12),
                                      for (final item in orderItems)
                                        ListTile(
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          title: Text('Item ${item.lineNumber}'),
                                          subtitle: Text(
                                            '${item.description} | ${item.quantity} ${item.unit}',
                                          ),
                                          trailing: Text(item.amountLabel),
                                        ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _addQuoteUrl(context),
                                icon: const Icon(Icons.add_link_outlined),
                                label: const Text('Agregar link de cotizacion'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () => _openSupplierPdf(context, selectedBatch),
                                icon: const Icon(Icons.picture_as_pdf_outlined),
                                label: const Text('Ver PDF de paquete por proveedor'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_quoteUrls.isEmpty)
                            Text(
                              'Aun no hay links de cotizacion agregados.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            )
                          else
                            Column(
                              children: [
                                for (final entry in _quoteUrls.asMap().entries)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.link_outlined),
                                    title: Text(entry.value),
                                    trailing: IconButton(
                                      onPressed: () {
                                        setState(() {
                                          _quoteUrls.removeAt(entry.key);
                                        });
                                      },
                                      icon: const Icon(Icons.close),
                                    ),
                                  ),
                              ],
                            ),
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: _sending
                                  ? null
                                  : () => _sendSupplierBatch(
                                        context,
                                        selectedBatch,
                                        pendingOrders,
                                      ),
                              icon: _sending
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.forward_to_inbox_outlined),
                              label: const Text('Enviar a Direccion General'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _DashboardPanel(
                    title: 'Ordenes en espera',
                    subtitle:
                        'Las ordenes permanecen aqui hasta que todos sus items se hayan mandado a Direccion General.',
                    child: Column(
                      children: [
                        for (final order in pendingOrders) ...[
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(order.orderId),
                            subtitle: Text(
                              '${order.pendingItems.length} item(s) pendientes | ${order.sentItemsCount > 0 ? 'Espera' : 'Pendiente'}',
                            ),
                            trailing: Wrap(
                              spacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  order.pendingItems.length == 1
                                      ? '1 item'
                                      : '${order.pendingItems.length} items',
                                ),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => OrderPdfViewScreen(
                                          orderId: order.orderId,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.picture_as_pdf_outlined),
                                  label: const Text('Ver PDF'),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Text(
                reportError(error, stack, context: 'ComprasDashboardScreen.packets'),
              ),
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Text(
              reportError(error, stack, context: 'ComprasDashboardScreen.orders'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addQuoteUrl(BuildContext context) async {
    _quoteUrlController.clear();
    final added = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Agregar link de cotizacion'),
          content: TextField(
            controller: _quoteUrlController,
            decoration: const InputDecoration(
              labelText: 'Link',
              hintText: 'https://drive.google.com/...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(_quoteUrlController.text.trim());
              },
              child: const Text('Agregar'),
            ),
          ],
        );
      },
    );
    final normalized = (added ?? '').trim();
    if (normalized.isEmpty) return;
    if (!_isValidDashboardQuoteUrl(normalized)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un link valido que empiece con http:// o https://')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      if (!_quoteUrls.contains(normalized)) {
        _quoteUrls.add(normalized);
      }
    });
  }

  Future<void> _openSupplierPdf(
    BuildContext context,
    _SupplierDashboardBatch batch,
  ) async {
    final issuedAt = _effectiveDashboardIssuedAt(batch);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _SupplierDashboardPdfScreen(
          batch: batch,
          data: _buildDashboardPdfSeed(
            context,
            batch,
            issuedAt: issuedAt,
            folio: null,
          ),
          pdfBuilder: (
            _, {
            bool useIsolate = false,
          }) => _buildSupplierDashboardPdf(
            context,
            batch: batch,
            issuedAt: issuedAt,
            folio: null,
          ),
        ),
      ),
    );
  }

  Future<void> _sendSupplierBatch(
    BuildContext context,
    _SupplierDashboardBatch batch,
    List<_PendingDashboardOrder> pendingOrders,
  ) async {
    if (_quoteUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos un link de cotizacion.')),
      );
      return;
    }
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final confirmed = await _confirmSendToDireccion(context, batch);
    if (confirmed != true) return;
    final sentAt = DateTime.now();
    setState(() {
      _sending = true;
      _sentAtBySupplier[batch.supplier] = sentAt;
    });
    final submissionCountNotifier = container.read(
      dashboardPacketSubmissionCountProvider.notifier,
    );
    submissionCountNotifier.state = submissionCountNotifier.state + 1;
    try {
      final submittedPacket =
          await ref.read(createAndSubmitPacketFromReadyOrdersProvider).call(
                actor: actor,
                supplierName: batch.supplier,
                totalAmount: batch.totalAmount,
                evidenceUrls: _quoteUrls,
                itemRefIds: batch.items
                    .map((item) => item.itemRefId)
                    .toList(growable: false),
              );
      final selectedItemRefIds = batch.items.map((item) => item.itemRefId).toSet();
      final affectedOrderIds = batch.items.map((item) => item.orderId).toSet();
      unawaited(
        _syncSentOrdersToDireccion(
          pendingOrders: pendingOrders,
          selectedItemRefIds: selectedItemRefIds,
          actor: actor,
        ),
      );
      container.invalidate(packetBundlesProvider);
      container.invalidate(readyOrdersProvider);
      refreshOrderModuleTransitionDataFromContainer(
        container,
        orderIds: affectedOrderIds,
      );
      if (mounted) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              'Paquete enviado a Direccion General.${submittedPacket.folio?.trim().isNotEmpty == true ? ' Folio ${submittedPacket.folio!.trim()}.' : ''}',
            ),
          ),
        );
        setState(() {
          _quoteUrls.clear();
          _selectedSupplier = null;
          _expandedOrderIds.clear();
        });
      }
    } catch (error, stack) {
      if (mounted) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              reportError(error, stack, context: 'ComprasDashboardScreen.send'),
            ),
          ),
        );
      }
    } finally {
      final current = submissionCountNotifier.state;
      submissionCountNotifier.state = current > 0 ? current - 1 : 0;
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<bool?> _confirmSendToDireccion(
    BuildContext context,
    _SupplierDashboardBatch batch,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirmar envio'),
          content: Text(
            'Se enviara el PDF de paquete por proveedor ${batch.supplier} a Direccion General. '
            'En este momento se asignara el folio oficial del paquete. ¿Deseas continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Enviar'),
            ),
          ],
        );
      },
    );
  }

  OrderPdfData _buildDashboardPdfSeed(
    BuildContext context,
    _SupplierDashboardBatch batch,
    {
    required DateTime issuedAt,
    required String? folio,
  }
  ) {
    return _buildSupplierDashboardPdfData(
      branding: ref.read(currentBrandingProvider),
      batch: batch,
      issuedAt: issuedAt,
      folio: folio,
      cacheSalt:
          'dashboard:${folio ?? 'pending'}:${batch.supplier}:${batch.items.map((item) => item.itemRefId).join('|')}:${_quoteUrls.join('|')}',
    );
  }

  Future<Uint8List> _buildSupplierDashboardPdf(
    BuildContext context, {
    required _SupplierDashboardBatch batch,
    required DateTime issuedAt,
    required String? folio,
  }) async {
    return _buildSupplierDashboardPdfDocument(
      branding: ref.read(currentBrandingProvider),
      batch: batch,
      issuedAt: issuedAt,
      folio: folio,
    );
  }

  Future<void> _syncSentOrdersToDireccion({
    required List<_PendingDashboardOrder> pendingOrders,
    required Set<String> selectedItemRefIds,
    required AppUser actor,
  }) async {
    final repository = ref.read(purchaseOrderRepositoryProvider);
    for (final order in pendingOrders) {
      final remainingAfterSend = order.pendingItems
          .where((item) => !selectedItemRefIds.contains(item.itemRefId))
          .length;
      if (remainingAfterSend > 0) continue;
      final legacyOrder = await repository.fetchOrderById(order.orderId);
      if (legacyOrder == null ||
          legacyOrder.status == PurchaseOrderStatus.approvalQueue) {
        continue;
      }
      await repository.advanceOrderStage(
        order: legacyOrder,
        nextStatus: PurchaseOrderStatus.approvalQueue,
        actor: actor,
        comment: 'Items enviados a Direccion General por proveedor.',
      );
    }
    refreshOrderModuleTransitionData(
      ref,
      orderIds: pendingOrders.map((order) => order.orderId).toSet(),
    );
  }



  DateTime _effectiveDashboardIssuedAt(_SupplierDashboardBatch batch) {
    return _sentAtBySupplier[batch.supplier] ?? DateTime.now();
  }
}




class AuthorizeOrdersScreen extends ConsumerStatefulWidget {
  const AuthorizeOrdersScreen({super.key});

  @override
  ConsumerState<AuthorizeOrdersScreen> createState() =>
      _AuthorizeOrdersScreenState();
}

class _AuthorizeOrdersScreenState
    extends ConsumerState<AuthorizeOrdersScreen> {
  OrderUrgencyFilter _urgencyFilter = OrderUrgencyFilter.all;
  bool _acceptingAll = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';
  DateTimeRange? _createdDateRangeFilter;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _setUrgencyFilter(OrderUrgencyFilter filter) {
    setState(() => _urgencyFilter = filter);
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
    });
  }

  void _clearCreatedDateFilter() {
    if (_createdDateRangeFilter == null) return;
    setState(() => _createdDateRangeFilter = null);
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(intakeReviewOrdersProvider);
    final compactAppBar = useCompactOrderModuleAppBar(context);
    final visibleOrders = ordersAsync.valueOrNull
            ?.where((order) => matchesOrderUrgencyFilter(order, _urgencyFilter))
            .where(
              (order) => _matchesWorkflowOrderFilters(
                order,
                searchQuery: _searchQuery,
                createdDateRangeFilter: _createdDateRangeFilter,
              ),
            )
            .toList(growable: false) ??
        const <PurchaseOrder>[];
    return Scaffold(
      appBar: AppBar(
        title: ordersAsync.when(
          data: (orders) {
            final counts = OrderUrgencyCounts.fromOrders(orders);
            if (compactAppBar) {
              return const Text('Autorizar ordenes');
            }
            return OrderModuleAppBarTitle(
              title: 'Autorizar ordenes',
              counts: counts,
              filter: _urgencyFilter,
              onSelected: _setUrgencyFilter,
            );
          },
          loading: () => const Text('Autorizar ordenes'),
          error: (_, __) => const Text('Autorizar ordenes'),
        ),
        actions: [
          if (visibleOrders.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.green.shade700,
                ),
                onPressed: _acceptingAll
                    ? null
                    : () => _acceptAllVisibleOrders(context, visibleOrders),
                icon: _acceptingAll
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.done_all_outlined),
                label: const Text('Aceptar todas'),
              ),
            ),
        ],
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _OrderSearchDateToolbar(
              controller: _searchController,
              searchQuery: _searchQuery,
              onChanged: _updateSearch,
              onClear: _clearSearch,
              selectedRange: _createdDateRangeFilter,
              onPickDate: _pickCreatedDateFilter,
              onClearDate: _clearCreatedDateFilter,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ordersAsync.when(
                data: (orders) {
                  final visibleOrders = orders
                      .where((order) => matchesOrderUrgencyFilter(order, _urgencyFilter))
                      .where(
                        (order) => _matchesWorkflowOrderFilters(
                          order,
                          searchQuery: _searchQuery,
                          createdDateRangeFilter: _createdDateRangeFilter,
                        ),
                      )
                      .toList(growable: false);
                  if (visibleOrders.isEmpty) {
                    return const Center(
                      child: Text('No hay ordenes pendientes por autorizar.'),
                    );
                  }
                  return ListView.separated(
                    itemCount: visibleOrders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final order = visibleOrders[index];
                      return _AuthorizeOrderCard(order: order);
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: Text(
                    reportError(error, stack, context: 'AuthorizeOrdersScreen'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _acceptAllVisibleOrders(
    BuildContext context,
    List<PurchaseOrder> orders,
  ) async {
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null || orders.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Aceptar todas las ordenes visibles'),
        content: Text(
          'Esta accion autorizara y enviara a Compras ${orders.length} orden(es) del filtro actual sin revisar una por una sus PDFs. '
          'Usala solo si ya verificaste el lote completo y aceptas el riesgo operativo de autorizar contenido incorrecto.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: _positiveFilledButtonStyle(context),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Aceptar todas'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _acceptingAll = true);
    try {
      final repository = ref.read(purchaseOrderRepositoryProvider);
      for (final order in orders) {
        await repository.authorizeAndAdvanceToCompras(
          order: order,
          actor: actor,
          comment:
              'Autorizacion masiva desde Autorizar ordenes. La orden fue aceptada por lote desde el AppBar.',
        );
      }
      refreshOrderModuleTransitionData(
        ref,
        orderIds: orders.map((order) => order.id),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${orders.length} orden(es) enviadas a Compras.'),
        ),
      );
    } catch (error, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reportError(error, stack, context: 'AuthorizeOrdersScreen.acceptAll'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _acceptingAll = false);
      }
    }
  }
}

class GeneralQuoteHistoryScreen extends ConsumerWidget {
  const GeneralQuoteHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundlesAsync = ref.watch(packetBundlesProvider);
    final branding = ref.watch(currentBrandingProvider);
    final filter = ref.watch(_generalQuoteHistoryFilterProvider);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Expanded(
              child: Text(
                'Historial de PDFs de paquetes por proveedor',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            _GeneralQuoteHistoryFilterButton(
              filter: filter,
              onSelected: (next) =>
                  ref.read(_generalQuoteHistoryFilterProvider.notifier).state = next,
            ),
          ],
        ),
      ),
      body: bundlesAsync.when(
        data: (bundles) {
          final history = bundles
              .where((bundle) => (bundle.packet.folio?.trim().isNotEmpty ?? false))
              .where((bundle) => _matchesGeneralQuoteHistoryFilter(bundle, filter))
              .toList(growable: false)
            ..sort((left, right) {
              final rightTime =
                  right.packet.submittedAt?.millisecondsSinceEpoch ?? 0;
              final leftTime =
                  left.packet.submittedAt?.millisecondsSinceEpoch ?? 0;
              return rightTime.compareTo(leftTime);
            });
          if (history.isEmpty) {
            return const Center(
              child: Text(
                'Aun no hay PDFs de paquetes por proveedor enviados a Direccion General para este filtro.',
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: history.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final bundle = history[index];
              final packet = bundle.packet;
              final isRejected = _isRejectedGeneralQuoteBundle(bundle);
              final batch = _supplierDashboardBatchFromPacket(packet);
              final issuedAt =
                  packet.submittedAt ?? packet.updatedAt ?? packet.createdAt ?? DateTime.now();
              final data = _buildSupplierDashboardPdfData(
                branding: branding,
                batch: batch,
                issuedAt: issuedAt,
                folio: packet.folio,
                cacheSalt: 'history:${packet.id}:${packet.version}:${packet.folio ?? ''}',
              );
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
                                Text(
                                  packet.folio ?? packet.id,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(packet.supplierName),
                                if (isRejected) ...[
                                  const SizedBox(height: 8),
                                  Chip(
                                    label: const Text('Rechazada'),
                                    avatar: const Icon(Icons.close, size: 18),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  fullscreenDialog: true,
                                  builder: (_) => _SupplierDashboardPdfScreen(
                                    batch: batch,
                                    data: data,
                                    pdfBuilder: (
                                      _, {
                                      bool useIsolate = false,
                                    }) => _buildSupplierDashboardPdfDocument(
                                      branding: branding,
                                      batch: batch,
                                      issuedAt: issuedAt,
                                      folio: packet.folio,
                                    ),
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('Ver PDF de paquete'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          Text('Items: ${packet.itemRefs.length}'),
                          Text('Total: ${packet.totalAmount}'),
                          Text('Fecha: ${issuedAt.toLocal().toFullDateTime()}'),
                          Text(
                            'Estado: ${isRejected ? 'rechazada' : packet.status.storageKey}',
                          ),
                        ],
                      ),
                      if (packet.evidenceUrls.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _showPacketEvidenceLinks(context, packet),
                          icon: const Icon(Icons.link_outlined),
                          label: const Text('Links'),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final url in packet.evidenceUrls)
                              ActionChip(
                                avatar: const Icon(Icons.open_in_new, size: 16),
                                label: Text(_compactLinkLabel(url)),
                                onPressed: () => _openExternalLink(context, url),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              reportError(error, stack, context: 'GeneralQuoteHistoryScreen'),
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _GeneralQuoteHistoryFilterButton extends StatelessWidget {
  const _GeneralQuoteHistoryFilterButton({
    required this.filter,
    required this.onSelected,
  });

  final GeneralQuoteHistoryFilter filter;
  final ValueChanged<GeneralQuoteHistoryFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<GeneralQuoteHistoryFilter>(
      initialValue: filter,
      onSelected: onSelected,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: GeneralQuoteHistoryFilter.all,
          child: Text('Todos'),
        ),
        PopupMenuItem(
          value: GeneralQuoteHistoryFilter.rejectedOnly,
          child: Text('Rechazados'),
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
            Text(
              filter == GeneralQuoteHistoryFilter.rejectedOnly
                  ? 'Rechazados'
                  : 'Todos',
            ),
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

class ComprasHubScreen extends ConsumerWidget {
  const ComprasHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProfileProvider).value;
    final canAccess = hasComprasAccess(user);
    return Scaffold(
      appBar: AppBar(title: const Text('Compras')),
      body: !canAccess
          ? const Center(child: Text('Tu perfil no tiene acceso a Compras.'))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _HubCard(
                      title: 'Pendientes',
                      subtitle: 'Agregar datos faltantes antes de agrupar por proveedor.',
                      icon: Icons.playlist_add_check_circle_outlined,
                      countAsync: ref.watch(sourcingCountProvider),
                      onTap: () => guardedPush(context, '/orders/compras/pendientes'),
                    ),
                    const SizedBox(height: 16),
                    _HubCard(
                      title: 'Dashboard',
                      subtitle: 'Agrupar items por proveedor y enviar a Direccion General.',
                      icon: Icons.dashboard_customize_outlined,
                      countAsync: ref.watch(sourcingDashboardTabCountProvider),
                      onTap: () => guardedPush(context, '/orders/compras/dashboard'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class ComprasPendingScreen extends ConsumerStatefulWidget {
  const ComprasPendingScreen({super.key});

  @override
  ConsumerState<ComprasPendingScreen> createState() =>
      _ComprasPendingScreenState();
}

class _ComprasPendingScreenState extends ConsumerState<ComprasPendingScreen> {
  OrderUrgencyFilter _urgencyFilter = OrderUrgencyFilter.all;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';
  DateTimeRange? _createdDateRangeFilter;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _setUrgencyFilter(OrderUrgencyFilter filter) {
    setState(() => _urgencyFilter = filter);
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
    });
  }

  void _clearCreatedDateFilter() {
    if (_createdDateRangeFilter == null) return;
    setState(() => _createdDateRangeFilter = null);
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(sourcingOrdersProvider);
    final users = ref.watch(allUsersProvider).valueOrNull ?? const <AppUser>[];
    final actorNamesById = <String, String>{
      for (final user in users)
        user.id: user.name.trim().isEmpty ? user.id : user.name.trim(),
    };
    final compactAppBar = useCompactOrderModuleAppBar(context);
    return Scaffold(
      appBar: AppBar(
        title: ordersAsync.when(
          data: (orders) {
            final counts = OrderUrgencyCounts.fromOrders(orders);
            if (compactAppBar) {
              return const Text('Compras / Pendientes');
            }
            return OrderModuleAppBarTitle(
              title: 'Compras / Pendientes',
              counts: counts,
              filter: _urgencyFilter,
              onSelected: _setUrgencyFilter,
            );
          },
          loading: () => const Text('Compras / Pendientes'),
          error: (_, __) => const Text('Compras / Pendientes'),
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _OrderSearchDateToolbar(
              controller: _searchController,
              searchQuery: _searchQuery,
              onChanged: _updateSearch,
              onClear: _clearSearch,
              selectedRange: _createdDateRangeFilter,
              onPickDate: _pickCreatedDateFilter,
              onClearDate: _clearCreatedDateFilter,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ordersAsync.when(
                data: (orders) {
                  final visibleOrders = orders
                      .where((order) => matchesOrderUrgencyFilter(order, _urgencyFilter))
                      .where(
                        (order) => _matchesWorkflowOrderFilters(
                          order,
                          searchQuery: _searchQuery,
                          createdDateRangeFilter: _createdDateRangeFilter,
                        ),
                      )
                      .toList(growable: false);
                  if (visibleOrders.isEmpty) {
                    return const Center(
                      child: Text('No hay ordenes pendientes en Compras.'),
                    );
                  }
                  return ListView.separated(
                    itemCount: visibleOrders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return _ComprasPendingOrderCard(
                        order: visibleOrders[index],
                        actorNamesById: actorNamesById,
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: Text(
                    reportError(error, stack, context: 'ComprasPendingScreen'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<pw.MemoryImage> _loadDashboardLogo(CompanyBranding branding) async {
  final bytes = await rootBundle.load(branding.logoAsset);
  return pw.MemoryImage(bytes.buffer.asUint8List());
}

class AddEstimatedDateScreen extends ConsumerWidget {
  const AddEstimatedDateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const _PacketFollowUpScreen(
      stage: _PacketFollowUpStage.eta,
    );
  }
}

class FacturasEvidenciasScreen extends ConsumerWidget {
  const FacturasEvidenciasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const _PacketFollowUpScreen(
      stage: _PacketFollowUpStage.facturas,
    );
  }
}

class _AuthorizeOrderCard extends ConsumerWidget {
  const _AuthorizeOrderCard({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urgentJustification = (order.urgentJustification ?? '').trim();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Folio: ${order.id}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _RequesterAreaLine(
              requesterName: order.requesterName,
              areaName: order.areaName,
            ),
            const SizedBox(height: 4),
            _OrderUrgencyLine(
              urgencyLabel: order.urgency.label,
              justification: urgentJustification,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AuthorizeOrderPdfScreen(orderId: order.id),
                    ),
                  );
                },
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

class _OrderUrgencyLine extends StatelessWidget {
  const _OrderUrgencyLine({
    required this.urgencyLabel,
    required this.justification,
  });

  final String urgencyLabel;
  final String justification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultStyle = theme.textTheme.bodyMedium;
    if (justification.isEmpty) {
      return Text('Urgencia: $urgencyLabel', style: defaultStyle);
    }
    return RichText(
      text: TextSpan(
        style: defaultStyle?.copyWith(color: theme.colorScheme.onSurface),
        children: [
          TextSpan(text: 'Urgencia: $urgencyLabel'),
          const TextSpan(text: ' · '),
          TextSpan(
            text: justification,
            style: defaultStyle?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RequesterAreaLine extends StatelessWidget {
  const _RequesterAreaLine({
    required this.requesterName,
    required this.areaName,
    this.areaLabel = 'Area del solicitante',
  });

  final String requesterName;
  final String areaName;
  final String areaLabel;

  @override
  Widget build(BuildContext context) {
    return Text('Solicitante: $requesterName · $areaLabel: $areaName');
  }
}

enum _PacketFollowUpStage { eta, facturas }

class _PacketFollowUpScreen extends ConsumerStatefulWidget {
  const _PacketFollowUpScreen({required this.stage});

  final _PacketFollowUpStage stage;

  @override
  ConsumerState<_PacketFollowUpScreen> createState() =>
      _PacketFollowUpScreenState();
}

class _PacketFollowUpScreenState extends ConsumerState<_PacketFollowUpScreen> {
  OrderUrgencyFilter _urgencyFilter = OrderUrgencyFilter.all;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';
  DateTimeRange? _createdDateRangeFilter;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _setUrgencyFilter(OrderUrgencyFilter filter) {
    setState(() => _urgencyFilter = filter);
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
    });
  }

  void _clearCreatedDateFilter() {
    if (_createdDateRangeFilter == null) return;
    setState(() => _createdDateRangeFilter = null);
  }

  @override
  Widget build(BuildContext context) {
    final bundlesAsync = ref.watch(packetBundlesProvider);
    final ordersAsync = ref.watch(allOrdersProvider);
    final compactAppBar = useCompactOrderModuleAppBar(context);
    final stage = widget.stage;
    final title = stage == _PacketFollowUpStage.eta
        ? 'Agregar fecha estimada'
        : 'Facturas y evidencias';
    final relatedOrders = _resolveFollowUpOrders(
      bundlesAsync.valueOrNull ?? const <PacketBundle>[],
      ordersAsync.valueOrNull ?? const <PurchaseOrder>[],
    );
    final counts = OrderUrgencyCounts.fromOrders(relatedOrders);
    return Scaffold(
      appBar: AppBar(
        title: compactAppBar
            ? Text(title)
            : OrderModuleAppBarTitle(
                title: title,
                counts: counts,
                filter: _urgencyFilter,
                onSelected: _setUrgencyFilter,
              ),
        bottom: !compactAppBar
            ? null
            : OrderModuleAppBarBottom(
                counts: counts,
                filter: _urgencyFilter,
                onSelected: _setUrgencyFilter,
              ),
      ),
      body: bundlesAsync.when(
        data: (bundles) => ordersAsync.when(
          data: (orders) {
            final ordersById = <String, PurchaseOrder>{
              for (final order in orders) order.id: order,
            };
          final executionBundles = bundles
              .where((bundle) => bundle.packet.status == PurchasePacketStatus.executionReady)
              .toList(growable: false);
          if (executionBundles.isEmpty) {
            return Center(child: Text('No hay paquetes para ${title.toLowerCase()}.'));
          }
          final packetContexts = _buildFollowUpPacketContexts(
                  executionBundles,
                  ordersById,
                  stage,
                )
              .where(
                (packet) => _packetContextMatchesOrderFilters(
                  packet,
                  searchQuery: _searchQuery,
                  createdDateRangeFilter: _createdDateRangeFilter,
                ),
              )
              .where((packet) => _packetContextMatchesUrgencyFilter(packet, _urgencyFilter))
              .toList(growable: false);
          final waitingOrders = _buildFollowUpWaitingOrders(
                  executionBundles,
                  ordersById,
                  stage,
                )
              .where(
                (order) => _matchesWorkflowOrderFilters(
                  order.order,
                  searchQuery: _searchQuery,
                  createdDateRangeFilter: _createdDateRangeFilter,
                ),
              )
              .where((order) => matchesOrderUrgencyFilter(order.order, _urgencyFilter))
              .toList(growable: false);
          if (packetContexts.isEmpty && waitingOrders.isEmpty) {
            return Center(child: Text('No hay registros para ${title.toLowerCase()}.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _OrderSearchDateToolbar(
                controller: _searchController,
                searchQuery: _searchQuery,
                onChanged: _updateSearch,
                onClear: _clearSearch,
                selectedRange: _createdDateRangeFilter,
                onPickDate: _pickCreatedDateFilter,
                onClearDate: _clearCreatedDateFilter,
              ),
              const SizedBox(height: 16),
              if (packetContexts.isNotEmpty) ...[
                Text(
                  stage == _PacketFollowUpStage.eta
                      ? 'Paquetes pendientes por ETA'
                      : 'Paquetes pendientes por llegada',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                for (final packetContext in packetContexts) ...[
                  _FollowUpPacketCard(
                    contextData: packetContext,
                    stage: stage,
                    onOpenPdf: () => _openFollowUpPacketPdf(context, packetContext),
                    onRegisterEta: stage == _PacketFollowUpStage.eta
                        ? () => _configureEtaForPacket(context, ref, packetContext)
                        : null,
                    onSendToFacturas: stage == _PacketFollowUpStage.eta
                        ? () => _sendPacketToFacturas(context, ref, packetContext)
                        : null,
                    onAddEvidence: stage == _PacketFollowUpStage.facturas
                        ? () => _attachAccountingEvidenceToPacket(context, ref, packetContext)
                        : null,
                    onRegisterArrival: stage == _PacketFollowUpStage.facturas
                        ? () => _registerArrivalForPacket(context, ref, packetContext)
                        : null,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
              const SizedBox(height: 12),
              Text(
                'Ordenes en espera',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (waitingOrders.isEmpty)
                const Text('No hay ordenes en espera.')
              else
                for (final waitingOrder in waitingOrders) ...[
                  _FollowUpWaitingOrderCard(
                    waitingOrder: waitingOrder,
                    stage: stage,
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          );
        },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Text(reportError(error, stack, context: '_PacketFollowUpScreen.orders')),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text(reportError(error, stack, context: '_PacketFollowUpScreen.packets')),
        ),
      ),
    );
  }
}

class _ComprasPendingOrderCard extends ConsumerWidget {
  const _ComprasPendingOrderCard({
    required this.order,
    required this.actorNamesById,
  });

  final PurchaseOrder order;
  final Map<String, String> actorNamesById;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(orderEventsProvider(order.id));
    final urgentJustification = (order.urgentJustification ?? '').trim();
    final previousStatus = PurchaseOrderStatus.intakeReview;
    final previousDuration = Duration(
      milliseconds: order.statusDurations[previousStatus.name] ?? 0,
    );
    final senderLabel = eventsAsync.maybeWhen(
      data: (events) {
        final event = _latestEventToStatus(events, PurchaseOrderStatus.sourcing);
        if (event == null) return 'No disponible';
        return _eventActorLabel(event, actorNamesById);
      },
      orElse: () => 'Cargando...',
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Folio: ${order.id}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _RequesterAreaLine(
              requesterName: order.requesterName,
              areaName: order.areaName,
            ),
            const SizedBox(height: 4),
            _OrderUrgencyLine(
              urgencyLabel: order.urgency.label,
              justification: urgentJustification,
            ),
            const SizedBox(height: 12),
            StatusDurationPill(
              text:
                  'Tiempo en ${previousStatus.label}: ${formatDurationLabel(previousDuration)}',
            ),
            const SizedBox(height: 4),
            Text('Enviada por: $senderLabel'),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ComprasPendingPdfScreen(orderId: order.id),
                      ),
                    );
                  },
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Ver PDF'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () => unawaited(
                    exportOrderCsv(
                      context,
                      order,
                      suggestedFileName: 'orden_compra_${order.id}.csv',
                    ),
                  ),
                  icon: const Icon(Icons.table_view_outlined),
                  label: const Text('Descargar CSV'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AuthorizeOrderPdfScreen extends ConsumerStatefulWidget {
  const AuthorizeOrderPdfScreen({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<AuthorizeOrderPdfScreen> createState() =>
      _AuthorizeOrderPdfScreenState();
}

class _AuthorizeOrderPdfScreenState
    extends ConsumerState<AuthorizeOrderPdfScreen> {
  bool _authorizing = false;
  bool _sending = false;
  bool _rejecting = false;
  bool _downloading = false;
  bool _authorizedPreview = false;
  String? _authorizedName;
  String? _authorizedArea;

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdStreamProvider(widget.orderId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Autorizar orden'),
        actions: orderAsync.valueOrNull == null
            ? null
            : [
                IconButton(
                  tooltip: 'Copiar',
                  onPressed: () => guardedPush(
                    context,
                    _copyOrderLocation(orderAsync.valueOrNull!.id),
                  ),
                  icon: const Icon(Icons.content_copy_outlined),
                ),
                IconButton(
                  tooltip: 'Descargar PDF',
                  onPressed: _downloading
                      ? null
                      : () => _downloadAuthorizePdf(orderAsync.valueOrNull!),
                  icon: _downloading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined),
                ),
              ],
      ),
      body: orderAsync.when(
        data: (order) {
          if (order == null) {
            return const Center(child: Text('La orden ya no esta disponible.'));
          }
          final actor = ref.watch(currentUserProfileProvider).value;
          final persistedAuthorizedName = order.authorizedByName?.trim();
          final persistedAuthorizedArea = order.authorizedByArea?.trim();
          final isAuthorized = _authorizedPreview ||
              (persistedAuthorizedName != null && persistedAuthorizedName.isNotEmpty);
          final effectiveAuthorizedName =
              _authorizedPreview ? _authorizedName : persistedAuthorizedName;
          final effectiveAuthorizedArea =
              _authorizedPreview ? _authorizedArea : persistedAuthorizedArea;
          final branding = ref.watch(currentBrandingProvider);
          final pdfData = buildPdfDataFromOrder(
            order,
            branding: branding,
            authorizedByName: effectiveAuthorizedName,
            authorizedByArea: effectiveAuthorizedArea,
            cacheSalt: isAuthorized
                ? 'authorize-preview:${effectiveAuthorizedName ?? ''}:${effectiveAuthorizedArea ?? ''}'
                : null,
          );
          return Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: OrderPdfInlineView(
                    data: pdfData,
                    remotePdfUrl: _authorizedPreview ? null : order.pdfUrl,
                    pdfBuilder: (
                      data, {
                      bool useIsolate = false,
                    }) => buildOrderPdf(
                      data,
                      useIsolate: false,
                    ),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      style: _negativeOutlinedButtonStyle(context),
                      onPressed: _rejecting
                          ? null
                          : () => _rejectOrder(context, order),
                      icon: _rejecting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.close_outlined),
                      label: const Text('Rechazar'),
                    ),
                    FilledButton.icon(
                      style: _positiveFilledButtonStyle(context),
                      onPressed: isAuthorized || _authorizing || actor == null
                          ? null
                          : () => _authorizePreview(actor),
                      icon: _authorizing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified_outlined),
                      label: const Text('Autorizar'),
                    ),
                    FilledButton.icon(
                      style: _positiveFilledButtonStyle(context),
                      onPressed: !isAuthorized || _sending
                          ? null
                          : () => _sendToCompras(context, order),
                      icon: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward_outlined),
                      label: const Text('Mandar a compras'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text(
            reportError(error, stack, context: 'AuthorizeOrderPdfScreen'),
          ),
        ),
      ),
    );
  }

  Future<void> _authorizePreview(AppUser actor) async {
    final authorizedName = actor.name.trim().isEmpty ? actor.id : actor.name.trim();
    final authorizedArea = actor.areaDisplay.trim();
    setState(() {
      _authorizing = false;
      _authorizedPreview = true;
      _authorizedName = authorizedName;
      _authorizedArea = authorizedArea;
    });
  }

  Future<void> _rejectOrder(BuildContext context, PurchaseOrder order) async {
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) return;
    final comment = await _promptRejectReason(context);
    if (!mounted || comment == null) return;
    setState(() {
      _rejecting = true;
    });
    try {
      await ref.read(purchaseOrderRepositoryProvider).requestEdit(
            order: order,
            comment: comment,
            items: order.items,
            actor: actor,
          );
      refreshOrderModuleData(ref, orderIds: <String>[order.id]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Orden enviada a rechazadas.')),
      );
      Navigator.of(context).pop();
    } catch (error, stack) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              reportError(error, stack, context: 'AuthorizeOrderPdfScreen.reject'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _rejecting = false;
        });
      }
    }
  }

  Future<void> _sendToCompras(BuildContext context, PurchaseOrder order) async {
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) return;
    setState(() {
      _sending = true;
    });
    try {
      await ref.read(purchaseOrderRepositoryProvider).authorizeAndAdvanceToCompras(
            order: order,
            actor: actor,
            comment: 'Orden autorizada y enviada a Compras.',
          );
      refreshOrderModuleTransitionData(ref, orderIds: <String>[order.id]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Orden enviada a Compras.')),
      );
      Navigator.of(context).pop();
    } catch (error, stack) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              reportError(error, stack, context: 'AuthorizeOrderPdfScreen.send'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<void> _downloadAuthorizePdf(PurchaseOrder order) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final branding = ref.read(currentBrandingProvider);
      final persistedAuthorizedName = order.authorizedByName?.trim();
      final persistedAuthorizedArea = order.authorizedByArea?.trim();
      final effectiveAuthorizedName =
          _authorizedPreview ? _authorizedName : persistedAuthorizedName;
      final effectiveAuthorizedArea =
          _authorizedPreview ? _authorizedArea : persistedAuthorizedArea;
      final pdfData = buildPdfDataFromOrder(
        order,
        branding: branding,
        authorizedByName: effectiveAuthorizedName,
        authorizedByArea: effectiveAuthorizedArea,
        cacheSalt: (_authorizedPreview ||
                (persistedAuthorizedName != null && persistedAuthorizedName.isNotEmpty))
            ? 'authorize-preview:${effectiveAuthorizedName ?? ''}:${effectiveAuthorizedArea ?? ''}'
            : null,
      );
      final bytes = await buildOrderPdf(pdfData, useIsolate: false);
      if (!mounted) return;
      await savePdfBytes(
        context,
        bytes: bytes,
        suggestedName: '${order.id}_autorizacion.pdf',
      );
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }
}

class ComprasPendingPdfScreen extends ConsumerStatefulWidget {
  const ComprasPendingPdfScreen({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<ComprasPendingPdfScreen> createState() =>
      _ComprasPendingPdfScreenState();
}

class _ComprasPendingPdfScreenState extends ConsumerState<ComprasPendingPdfScreen> {
  List<PurchaseOrderItem>? _workingItems;
  bool _confirmed = false;
  bool _sending = false;
  bool _rejecting = false;
  bool _downloading = false;
  String? _processName;
  String? _processArea;

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdStreamProvider(widget.orderId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compras / Pendientes'),
        actions: orderAsync.valueOrNull == null
            ? null
            : [
                IconButton(
                  tooltip: 'Copiar',
                  onPressed: () => guardedPush(
                    context,
                    _copyOrderLocation(orderAsync.valueOrNull!.id),
                  ),
                  icon: const Icon(Icons.content_copy_outlined),
                ),
                IconButton(
                  tooltip: 'Descargar PDF',
                  onPressed: _downloading
                      ? null
                      : () => _downloadComprasPdf(orderAsync.valueOrNull!),
                  icon: _downloading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined),
                ),
              ],
      ),
      body: orderAsync.when(
        data: (order) {
          if (order == null) {
            return const Center(child: Text('La orden ya no esta disponible.'));
          }
          final actor = ref.watch(currentUserProfileProvider).value;
          final effectiveItems = _workingItems ?? order.items;
          final supplierBudgets = _buildSupplierBudgets(effectiveItems);
          final totalBudget = _sumItemBudgets(effectiveItems);
          final branding = ref.watch(currentBrandingProvider);
          final pdfData = buildPdfDataFromOrder(
            order,
            branding: branding,
            items: effectiveItems.map(OrderItemDraft.fromModel).toList(growable: false),
            supplier: _resolveSingleSupplier(effectiveItems),
            internalOrder: _resolveSingleInternalOrder(effectiveItems),
            budget: totalBudget == 0 ? null : totalBudget,
            supplierBudgets: supplierBudgets,
            processByName: _confirmed ? _processName : order.processByName,
            processByArea: _confirmed ? _processArea : order.processByArea,
            cacheSalt:
                'compras-pending:${_comprasItemsSignature(effectiveItems)}:${_processName ?? ''}:${_processArea ?? ''}',
          );
          return Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: OrderPdfInlineView(
                    data: pdfData,
                    pdfBuilder: (
                      data, {
                      bool useIsolate = false,
                    }) => buildOrderPdf(
                      data,
                      useIsolate: false,
                    ),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _openDataScreen(context, order),
                      icon: const Icon(Icons.edit_note_outlined),
                      label: Text(_workingItems == null ? 'Completar datos' : 'Editar datos'),
                    ),
                    OutlinedButton.icon(
                      style: _negativeOutlinedButtonStyle(context),
                      onPressed: _rejecting ? null : () => _rejectOrder(context, order),
                      icon: _rejecting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.close_outlined),
                      label: const Text('Rechazar'),
                    ),
                    FilledButton.icon(
                      style: _positiveFilledButtonStyle(context),
                      onPressed: !_isComprasDraftComplete(effectiveItems) ||
                              _confirmed ||
                              actor == null
                          ? null
                          : () => _confirm(actor),
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('Confirmar'),
                    ),
                    FilledButton.icon(
                      style: _positiveFilledButtonStyle(context),
                      onPressed: !_confirmed ||
                              _sending ||
                              !_isComprasDraftComplete(effectiveItems)
                          ? null
                          : () => _sendToDashboard(context, order),
                      icon: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.dashboard_customize_outlined),
                      label: const Text('Mandar al dashboard'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text(
            reportError(error, stack, context: 'ComprasPendingPdfScreen'),
          ),
        ),
      ),
    );
  }

  Future<void> _openDataScreen(BuildContext context, PurchaseOrder order) async {
    final result = await Navigator.of(context).push<List<PurchaseOrderItem>>(
      MaterialPageRoute<List<PurchaseOrderItem>>(
        builder: (_) => ComprasPendingDataScreen(
          order: order,
          initialItems: _workingItems ?? order.items,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _workingItems = result;
      _confirmed = false;
      _processName = null;
      _processArea = null;
    });
  }

  void _confirm(AppUser actor) {
    setState(() {
      _confirmed = true;
      _processName = actor.name.trim().isEmpty ? actor.id : actor.name.trim();
      _processArea = actor.areaDisplay.trim();
    });
  }

  Future<void> _rejectOrder(BuildContext context, PurchaseOrder order) async {
    final actor = ref.read(currentUserProfileProvider).value;
    final effectiveItems = _workingItems ?? order.items;
    if (actor == null) return;
    final comment = await _promptRejectReason(context);
    if (!mounted || comment == null) return;
    setState(() {
      _rejecting = true;
    });
    try {
      await ref.read(purchaseOrderRepositoryProvider).requestEdit(
            order: order,
            comment: comment,
            items: effectiveItems,
            actor: actor,
          );
      refreshOrderModuleData(ref, orderIds: <String>[order.id]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Orden enviada a rechazadas.')),
      );
      Navigator.of(context).pop();
    } catch (error, stack) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              reportError(error, stack, context: 'ComprasPendingPdfScreen.reject'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _rejecting = false;
        });
      }
    }
  }

  Future<void> _sendToDashboard(BuildContext context, PurchaseOrder order) async {
    final actor = ref.read(currentUserProfileProvider).value;
    final updatedItems = _workingItems;
    if (actor == null || updatedItems == null) return;
    setState(() {
      _sending = true;
    });
    try {
      await ref.read(purchaseOrderRepositoryProvider).processAndAdvanceToDashboard(
            order: order,
            actor: actor,
            items: updatedItems,
            totalBudget: _sumItemBudgets(updatedItems),
            supplierBudgets: _buildSupplierBudgets(updatedItems),
            primarySupplier: _resolveSingleSupplier(updatedItems),
            primaryInternalOrder: _resolveSingleInternalOrder(updatedItems),
            comment: 'Datos de Compras completados y enviados al dashboard.',
          );
      refreshOrderModuleTransitionData(ref, orderIds: <String>[order.id]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Orden enviada al dashboard de Compras.')),
      );
      Navigator.of(context).pop();
    } catch (error, stack) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              reportError(error, stack, context: 'ComprasPendingPdfScreen.send'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<void> _downloadComprasPdf(PurchaseOrder order) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final effectiveItems = _workingItems ?? order.items;
      final branding = ref.read(currentBrandingProvider);
      final totalBudget = _sumItemBudgets(effectiveItems);
      final pdfData = buildPdfDataFromOrder(
        order,
        branding: branding,
        items: effectiveItems.map(OrderItemDraft.fromModel).toList(growable: false),
        supplier: _resolveSingleSupplier(effectiveItems),
        internalOrder: _resolveSingleInternalOrder(effectiveItems),
        budget: totalBudget == 0 ? null : totalBudget,
        supplierBudgets: _buildSupplierBudgets(effectiveItems),
        processByName: _confirmed ? _processName : order.processByName,
        processByArea: _confirmed ? _processArea : order.processByArea,
        cacheSalt:
            'compras-pending:${_comprasItemsSignature(effectiveItems)}:${_processName ?? ''}:${_processArea ?? ''}',
      );
      final bytes = await buildOrderPdf(pdfData, useIsolate: false);
      if (!mounted) return;
      await savePdfBytes(
        context,
        bytes: bytes,
        suggestedName: '${order.id}_compras.pdf',
      );
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }
}

class ComprasPendingDataScreen extends ConsumerStatefulWidget {
  const ComprasPendingDataScreen({
    required this.order,
    required this.initialItems,
    super.key,
  });

  final PurchaseOrder order;
  final List<PurchaseOrderItem> initialItems;

  @override
  ConsumerState<ComprasPendingDataScreen> createState() =>
      _ComprasPendingDataScreenState();
}

class _ComprasPendingDataScreenState extends ConsumerState<ComprasPendingDataScreen> {
  late final TextEditingController _amountController;
  late final TextEditingController _internalOrderController;
  late List<PurchaseOrderItem> _workingItems;
  late Set<int> _selectedLines;
  String? _selectedSupplierValue;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    _internalOrderController = TextEditingController();
    _workingItems = widget.initialItems.map((item) => item.copyWith()).toList(growable: true);
    _selectedLines = _workingItems
        .where(_itemHasComprasAssignment)
        .map((item) => item.line)
        .toSet();
    _syncFormFromSelection();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _internalOrderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(userSuppliersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Completar datos')),
      body: suppliersAsync.when(
        data: (suppliers) {
          final supplierNames = suppliers
              .map((entry) => entry.name.trim())
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList(growable: false)
            ..sort();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: supplierNames.contains(_selectedSupplierValue)
                          ? _selectedSupplierValue
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Proveedor',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final name in supplierNames)
                          DropdownMenuItem<String>(
                            value: name,
                            child: Text(name),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedSupplierValue = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => _createSupplier(context),
                    icon: const Icon(Icons.add_business_outlined),
                    label: const Text('Nuevo proveedor'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  _decimalTextInputFormatter(),
                ],
                decoration: const InputDecoration(
                  labelText: 'Monto total',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _internalOrderController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'OC interna (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Items a aplicar',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              CheckboxListTile(
                value: _selectedLines.length == _workingItems.length &&
                    _workingItems.isNotEmpty,
                onChanged: (selected) {
                  setState(() {
                    if (selected ?? false) {
                      _selectedLines = _workingItems.map((item) => item.line).toSet();
                    } else {
                      _selectedLines.clear();
                    }
                    _syncFormFromSelection(preserveManualInput: true);
                  });
                },
                title: const Text('Seleccionar todos'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 8),
              for (final item in _workingItems)
                Card(
                  color: _itemHasComprasAssignment(item)
                      ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45)
                      : null,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: _selectedLines.contains(item.line),
                              onChanged: (selected) {
                                setState(() {
                                  if (selected ?? false) {
                                    _selectedLines.add(item.line);
                                  } else {
                                    _selectedLines.remove(item.line);
                                  }
                                  _syncFormFromSelection(preserveManualInput: true);
                                });
                              },
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Item ${item.line} - ${item.description}'),
                                  const SizedBox(height: 4),
                                  Text(
                                    _comprasItemSubtitle(item),
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (_itemHasComprasAssignment(item))
                              Chip(
                                avatar: const Icon(Icons.check_circle, size: 18),
                                label: const Text('Completo'),
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.14),
                              ),
                            if (_itemHasComprasAssignment(item))
                              OutlinedButton.icon(
                                onPressed: () => _promptUndoItem(context, item),
                                icon: const Icon(Icons.undo_outlined),
                                label: const Text('Deshacer'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: () => _applySelection(context),
                    icon: const Icon(Icons.playlist_add_check_circle_outlined),
                    label: const Text('Aplicar'),
                  ),
                  FilledButton.tonal(
                    onPressed: () => _save(context),
                    child: const Text('Guardar para revision'),
                  ),
                ],
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text(
            reportError(error, stack, context: 'ComprasPendingDataScreen'),
          ),
        ),
      ),
    );
  }

  Future<void> _createSupplier(BuildContext context) async {
    final controller = TextEditingController();
    String? errorText;
    var isSaving = false;
    final repo = ref.read(partnerRepositoryProvider);
    final uid = ref.read(currentUserIdProvider);
    final actor = ref.read(currentUserProfileProvider).value;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Nuevo proveedor'),
              content: TextField(
                controller: controller,
                enabled: !isSaving,
                decoration: InputDecoration(
                  labelText: 'Proveedor',
                  errorText: errorText,
                ),
                onChanged: (_) {
                  if (errorText != null) {
                    setState(() {
                      errorText = null;
                    });
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final name = controller.text.trim();
                          if (name.isEmpty) {
                            setState(() {
                              errorText = 'Nombre requerido';
                            });
                            return;
                          }
                          final confirmed = await showDialog<bool>(
                                context: dialogContext,
                                builder: (confirmContext) {
                                  return AlertDialog(
                                    title: const Text('Confirmar nuevo proveedor'),
                                    content: Text(
                                      'Vas a agregar \"$name\" como proveedor global. Todos los usuarios podran verlo y usarlo. Verifica bien el nombre antes de continuar.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(confirmContext).pop(false),
                                        child: const Text('Cancelar'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.of(confirmContext).pop(true),
                                        child: const Text('Confirmar'),
                                      ),
                                    ],
                                  );
                                },
                              ) ??
                              false;
                          if (!confirmed) {
                            return;
                          }
                          if (uid == null) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(content: Text('Usuario no disponible.')),
                            );
                            return;
                          }
                          setState(() {
                            isSaving = true;
                          });
                          try {
                            await repo.createPartner(
                              uid: uid,
                              type: PartnerType.supplier,
                              name: name,
                              actor: actor,
                            );
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            if (!mounted) return;
                            setState(() {
                              _selectedSupplierValue = name;
                            });
                          } catch (error, stack) {
                            if (!dialogContext.mounted) return;
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                  reportError(
                                    error,
                                    stack,
                                    context: 'ComprasPendingDataScreen.createSupplier',
                                  ),
                                ),
                              ),
                            );
                            setState(() {
                              isSaving = false;
                            });
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  void _applySelection(BuildContext context) {
    final supplierName = (_selectedSupplierValue ?? '').trim();
    final totalAmount = num.tryParse(_amountController.text.trim());
    if (supplierName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proveedor requerido.')),
      );
      return;
    }
    if (_selectedLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos un item.')),
      );
      return;
    }
    if (totalAmount == null || totalAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Monto total invalido.')),
      );
      return;
    }
    final budgets = _splitBudgetEvenly(totalAmount, _selectedLines.length);
    final internalOrder = _internalOrderController.text.trim();
    var budgetIndex = 0;
    setState(() {
      _workingItems = _workingItems.map((item) {
        if (!_selectedLines.contains(item.line)) return item;
        final nextBudget = budgets[budgetIndex];
        budgetIndex += 1;
        return item.copyWith(
          supplier: supplierName,
          budget: nextBudget,
          internalOrder: internalOrder.isEmpty ? null : internalOrder,
          clearInternalOrder: internalOrder.isEmpty,
        );
      }).toList(growable: true);
      _syncFormFromSelection();
    });
  }

  Future<void> _promptUndoItem(BuildContext context, PurchaseOrderItem item) async {
    final supplier = (item.supplier ?? '').trim();
    final hasGroup = supplier.isNotEmpty &&
        _workingItems.where((candidate) => (candidate.supplier ?? '').trim() == supplier).length > 1;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Deshacer asignacion'),
          content: Text(
            hasGroup
                ? 'Puedes deshacer solo este item o todos los items con proveedor $supplier.'
                : 'Se deshara la asignacion de este item.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            if (hasGroup)
              OutlinedButton(
                onPressed: () => Navigator.of(dialogContext).pop('supplier'),
                child: const Text('Todo el proveedor'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop('item'),
              child: const Text('Deshacer'),
            ),
          ],
        );
      },
    );
    if (result == null) return;
    setState(() {
      if (result == 'supplier' && supplier.isNotEmpty) {
        _workingItems = _workingItems
            .map((candidate) => (candidate.supplier ?? '').trim() == supplier
                ? _clearComprasItem(candidate)
                : candidate)
            .toList(growable: true);
        _selectedLines.removeWhere(
          (line) => _workingItems
              .any((candidate) => candidate.line == line && !_itemHasComprasAssignment(candidate)),
        );
      } else {
        _workingItems = _workingItems
            .map((candidate) => candidate.line == item.line ? _clearComprasItem(candidate) : candidate)
            .toList(growable: true);
        _selectedLines.remove(item.line);
      }
      _syncFormFromSelection();
    });
  }

  void _syncFormFromSelection({bool preserveManualInput = false}) {
    final selectedItems = _workingItems
        .where((item) => _selectedLines.contains(item.line))
        .toList(growable: false);
    if (selectedItems.isEmpty) {
      if (!preserveManualInput) {
        _selectedSupplierValue = null;
        _amountController.text = '';
        _internalOrderController.text = '';
      }
      return;
    }
    final suppliers = selectedItems
        .map((item) => (item.supplier ?? '').trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (suppliers.length == 1) {
      _selectedSupplierValue = suppliers.first;
    } else if (!preserveManualInput) {
      _selectedSupplierValue = null;
    }

    final totalBudget = selectedItems.fold<double>(
      0,
      (sum, item) => sum + (item.budget?.toDouble() ?? 0),
    );
    final hasAnyBudget = selectedItems.any((item) => item.budget != null);
    if (hasAnyBudget) {
      _amountController.text = _formatBudgetInput(totalBudget);
    } else if (!preserveManualInput) {
      _amountController.text = '';
    }

    final internalOrders = selectedItems
        .map((item) => (item.internalOrder ?? '').trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (internalOrders.length == 1) {
      _internalOrderController.text = internalOrders.first;
    } else if (!preserveManualInput) {
      _internalOrderController.text = '';
    }
  }



  String _formatBudgetInput(num value) {
    final normalized = value.toStringAsFixed(2);
    return normalized.endsWith('.00')
        ? normalized.substring(0, normalized.length - 3)
        : normalized;
  }

  TextInputFormatter _decimalTextInputFormatter() {
    return TextInputFormatter.withFunction((oldValue, newValue) {
      final next = newValue.text;
      if (next.isEmpty) return newValue;
      final valid = RegExp(r'^\d+([.]\d{0,2})?$').hasMatch(next);
      return valid ? newValue : oldValue;
    });
  }

  PurchaseOrderItem _clearComprasItem(PurchaseOrderItem item) {
    return item.copyWith(
      supplier: '',
      budget: null,
      internalOrder: null,
      clearInternalOrder: true,
    );
  }

  Future<void> _save(BuildContext context) async {
    if (!_workingItems.any(_itemHasComprasAssignment)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aplica datos a por lo menos un item.')),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(_workingItems);
  }
}

bool _itemHasComprasAssignment(PurchaseOrderItem item) {
  final supplier = (item.supplier ?? '').trim();
  final budget = item.budget;
  return supplier.isNotEmpty && budget != null && budget > 0;
}

bool _isComprasDraftComplete(List<PurchaseOrderItem> items) {
  if (items.isEmpty) return false;
  return items.every(_itemHasComprasAssignment);
}

String _comprasItemsSignature(List<PurchaseOrderItem> items) {
  return items
      .map(
        (item) => [
          item.line,
          item.supplier ?? '',
          item.internalOrder ?? '',
          item.budget?.toString() ?? '',
        ].join(':'),
      )
      .join('|');
}

String _comprasItemSubtitle(PurchaseOrderItem item) {
  final parts = <String>['${item.pieces} ${item.unit}'];
  final supplier = (item.supplier ?? '').trim();
  if (supplier.isNotEmpty) {
    parts.add('Proveedor: $supplier');
  }
  if (item.budget != null) {
    parts.add('Monto: ${item.budget}');
  }
  final internalOrder = (item.internalOrder ?? '').trim();
  if (internalOrder.isNotEmpty) {
    parts.add('OC interna: $internalOrder');
  }
  return parts.join(' | ');
}

class _DashboardPanel extends StatelessWidget {
  const _DashboardPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _PendingDashboardOrder {
  const _PendingDashboardOrder({
    required this.orderId,
    required this.pendingItems,
    required this.sentItemsCount,
  });

  final String orderId;
  final List<_DashboardPendingItem> pendingItems;
  final int sentItemsCount;
}

class _SupplierDashboardPdfScreen extends StatelessWidget {
  const _SupplierDashboardPdfScreen({
    required this.batch,
    required this.data,
    required this.pdfBuilder,
  });

  final _SupplierDashboardBatch batch;
  final OrderPdfData data;
  final Future<Uint8List> Function(
    OrderPdfData data, {
    bool useIsolate,
  }) pdfBuilder;

  @override
  Widget build(BuildContext context) {
    final hasFolio = data.folio?.trim().isNotEmpty ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text('PDF de paquete por proveedor - ${batch.supplier}'),
        actions: [
          IconButton(
            tooltip: 'Descargar PDF',
            onPressed: () async {
              final bytes = await pdfBuilder(data, useIsolate: false);
              if (!context.mounted) return;
              await savePdfBytes(
                context,
                bytes: bytes,
                suggestedName:
                    'paquete_por_proveedor_${data.folio?.trim().isNotEmpty == true ? data.folio!.trim() : batch.supplier}.pdf',
              );
            },
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!hasFolio)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text('Folio pendiente. Se asignará al enviar.'),
            ),
          Expanded(
            child: OrderPdfInlineView(
              data: data,
              pdfBuilder: pdfBuilder,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardPendingItem {
  const _DashboardPendingItem({
    required this.itemRefId,
    required this.orderId,
    required this.itemId,
    required this.lineNumber,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.supplier,
    required this.amount,
    required this.internalOrder,
  });

  final String itemRefId;
  final String orderId;
  final String itemId;
  final int lineNumber;
  final String description;
  final num quantity;
  final String unit;
  final String supplier;
  final num amount;
  final String? internalOrder;

  String get amountLabel => amount.toString();
}

class _SupplierDashboardBatch {
  const _SupplierDashboardBatch({
    required this.supplier,
    required this.items,
  });

  final String supplier;
  final List<_DashboardPendingItem> items;

  num get totalAmount => items.fold<num>(0, (sum, item) => sum + item.amount);
  List<String> get orderIds => items
      .map((item) => item.orderId)
      .toSet()
      .toList(growable: false)
    ..sort();
}

_SupplierDashboardBatch _supplierDashboardBatchFromPacket(PurchasePacket packet) {
  final items = <_DashboardPendingItem>[];
  for (var index = 0; index < packet.itemRefs.length; index++) {
    final item = packet.itemRefs[index];
    items.add(
      _DashboardPendingItem(
        itemRefId: item.id,
        orderId: item.orderId,
        itemId: item.itemId,
        lineNumber: item.lineNumber > 0 ? item.lineNumber : index + 1,
        description: item.description,
        quantity: item.quantity,
        unit: item.unit,
        supplier: packet.supplierName,
        amount: item.amount ?? 0,
        internalOrder: null,
      ),
    );
  }
  return _SupplierDashboardBatch(
    supplier: packet.supplierName,
    items: items,
  );
}

enum GeneralQuoteHistoryFilter {
  all,
  rejectedOnly,
}

final _generalQuoteHistoryFilterProvider =
    StateProvider<GeneralQuoteHistoryFilter>(
  (ref) => GeneralQuoteHistoryFilter.all,
);

bool _isRejectedGeneralQuoteBundle(PacketBundle bundle) {
  if (bundle.decisions.isEmpty) return false;
  final sorted = [...bundle.decisions]
    ..sort((left, right) => right.timestamp.compareTo(left.timestamp));
  return sorted.first.action == PacketDecisionAction.returnForRework;
}

bool _matchesGeneralQuoteHistoryFilter(
  PacketBundle bundle,
  GeneralQuoteHistoryFilter filter,
) {
  switch (filter) {
    case GeneralQuoteHistoryFilter.all:
      return true;
    case GeneralQuoteHistoryFilter.rejectedOnly:
      return _isRejectedGeneralQuoteBundle(bundle);
  }
}

Future<void> _showPacketEvidenceLinks(
  BuildContext context,
  PurchasePacket packet,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text('Links - ${packet.folio ?? packet.supplierName}'),
        content: SizedBox(
          width: 540,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final link in packet.evidenceUrls)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link_outlined),
                  title: Text(link),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      );
    },
  );
}

_PendingDashboardOrder _buildPendingDashboardOrder(
  RequestOrder order,
  Set<String> activeItemRefIds,
) {
  final pendingItems = <_DashboardPendingItem>[];
  var sentItemsCount = 0;
  for (final item in order.items) {
    final supplier = (item.supplierName ?? '').trim();
    final amount = item.estimatedAmount;
    if (supplier.isEmpty || amount == null || amount <= 0 || item.isClosed) {
      continue;
    }
    final itemRefId = buildPacketItemRefId(order.id, item.id);
    if (activeItemRefIds.contains(itemRefId)) {
      sentItemsCount += 1;
      continue;
    }
    pendingItems.add(
      _DashboardPendingItem(
        itemRefId: itemRefId,
        orderId: order.id,
        itemId: item.id,
        lineNumber: item.lineNumber,
        description: item.description,
        quantity: item.quantity,
        unit: item.unit,
        supplier: supplier,
        amount: amount,
        internalOrder: null,
      ),
    );
  }
  return _PendingDashboardOrder(
    orderId: order.id,
    pendingItems: pendingItems,
    sentItemsCount: sentItemsCount,
  );
}

_SupplierDashboardBatch _buildSupplierBatch({
  required String supplier,
  required List<_PendingDashboardOrder> pendingOrders,
}) {
  final items = pendingOrders
      .expand((order) => order.pendingItems)
      .where((item) => item.supplier == supplier)
      .toList(growable: false);
  return _SupplierDashboardBatch(supplier: supplier, items: items);
}

bool _isValidDashboardQuoteUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) return false;
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}

String _compactLinkLabel(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null) return value.trim();
  final host = uri.host.trim();
  if (host.isEmpty) return value.trim();
  return uri.pathSegments.isEmpty ? host : '$host/...';
}

Future<void> _openExternalLink(BuildContext context, String raw) async {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.isAbsolute) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('El link no es valido.')),
    );
    return;
  }
  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo abrir el link.')),
    );
  }

}

Set<String> _activePacketItemRefIds(List<PacketBundle> bundles) {
  return bundles
      .where(
        _bundleCountsAsActiveForDashboard,
      )
      .expand((bundle) => bundle.packet.itemRefs)
      .map((item) => item.id)
      .toSet();
}

bool _bundleCountsAsActiveForDashboard(PacketBundle bundle) {
  final status = bundle.packet.status;
  if (status == PurchasePacketStatus.approvalQueue ||
      status == PurchasePacketStatus.executionReady ||
      status == PurchasePacketStatus.completed) {
    return true;
  }
  return bundle.packet.status == PurchasePacketStatus.draft &&
      bundle.packet.isSubmitted &&
      !_isReturnedDraftBundle(bundle);
}


bool _isReturnedDraftBundle(PacketBundle bundle) {
  if (bundle.packet.status != PurchasePacketStatus.draft ||
      bundle.decisions.isEmpty) {
    return false;
  }
  final sorted = [...bundle.decisions]
    ..sort((left, right) => right.timestamp.compareTo(left.timestamp));
  return sorted.first.action == PacketDecisionAction.returnForRework;
}



pw.Widget _dashboardPdfSectionTitle(
  String text,
  PdfColor background,
  PdfColor foreground,
) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    color: background,
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 12,
        fontWeight: pw.FontWeight.bold,
        color: foreground,
      ),
    ),
  );
}

pw.Widget _dashboardPdfField(
  String label,
  String value, {
  bool showRightBorder = true,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: showRightBorder
        ? const pw.BoxDecoration(
            border: pw.Border(
              right: pw.BorderSide(width: 0.8, color: PdfColors.grey700),
            ),
          )
        : null,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: const pw.TextStyle(fontSize: 10),
        ),
      ],
    ),
  );
}

pw.Widget _dashboardPdfCell(
  String text, {
  bool isHeader = false,
  PdfColor? color,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 8),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: isHeader ? 10 : 9,
        fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color,
      ),
    ),
  );
}

OrderPdfData _buildSupplierDashboardPdfData({
  required CompanyBranding branding,
  required _SupplierDashboardBatch batch,
  required DateTime issuedAt,
  required String? folio,
  required String cacheSalt,
}) {
  return OrderPdfData(
    branding: branding,
    requesterName: 'Compras',
    requesterArea: 'Compras',
    areaName: 'Compras',
    urgency: PurchaseOrderUrgency.normal,
    items: batch.items
        .map(
          (item) => OrderItemDraft(
            line: item.lineNumber,
            pieces: 1,
            partNumber: '',
            description: item.description,
            quantity: item.quantity,
            unit: item.unit,
            supplier: batch.supplier,
            budget: item.amount,
            internalOrder: item.internalOrder,
          ),
        )
        .toList(growable: false),
    createdAt: issuedAt,
    observations: 'Resumen de paquete por proveedor.',
    folio: folio,
    supplier: batch.supplier,
    budget: batch.totalAmount,
    supplierBudgets: <String, num>{batch.supplier: batch.totalAmount},
    cacheSalt: cacheSalt,
  );
}

Future<Uint8List> _buildSupplierDashboardPdfDocument({
  required CompanyBranding branding,
  required _SupplierDashboardBatch batch,
  required DateTime issuedAt,
  required String? folio,
}) async {
  final logo = await _loadDashboardLogo(branding);
  final doc = pw.Document();
  final rows = batch.items;
  final titleBarColor = PdfColor.fromInt(branding.pdfTitleBarColor.toARGB32());
  final accentColor = PdfColor.fromInt(branding.pdfAccentColor.toARGB32());
  final titleTextColor = branding.pdfTitleBarColor.computeLuminance() < 0.45
      ? PdfColors.white
      : PdfColors.black;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(20),
      build: (context) {
        return [
          pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 0.8, color: PdfColors.grey700),
            ),
            padding: const pw.EdgeInsets.all(8),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 110,
                  height: 50,
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Image(logo, height: 44, fit: pw.BoxFit.contain),
                ),
                pw.Expanded(
                  child: pw.Container(
                    height: 50,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(width: 0.8, color: PdfColors.grey700),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        pw.Container(
                          color: titleBarColor,
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: pw.Text(
                            'COTIZACION GENERAL POR PROVEEDOR',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              color: titleTextColor,
                            ),
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Center(
                            child: pw.Column(
                              mainAxisAlignment: pw.MainAxisAlignment.center,
                              children: [
                                pw.Text(
                                  branding.pdfHeaderLine1,
                                  style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                                pw.Text(
                                  branding.pdfHeaderLine2,
                                  style: const pw.TextStyle(fontSize: 8),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.Container(
                  width: 118,
                  height: 50,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(width: 0.8, color: PdfColors.grey700),
                  ),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text(
                        'FOLIO',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        (folio != null && folio.trim().isNotEmpty)
                            ? folio.trim()
                            : 'SE ASIGNARA\nAL ENVIAR',
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(top: 8),
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 0.8, color: PdfColors.grey700),
              color: PdfColor.fromHex('#F7F9FC'),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'Fecha y hora de emision',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Text(
                  issuedAt.toLocal().toFullDateTime(),
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
          pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(top: 10),
            padding: const pw.EdgeInsets.all(18),
            decoration: pw.BoxDecoration(
              color: accentColor,
              border: pw.Border.all(width: 1.0, color: PdfColors.grey700),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'TOTAL A PAGAR',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  batch.totalAmount.toString(),
                  style: pw.TextStyle(
                    fontSize: 30,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          _dashboardPdfSectionTitle('DATOS GENERALES', titleBarColor, titleTextColor),
          pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 0.8, color: PdfColors.grey700),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _dashboardPdfField(
                    'PROVEEDOR',
                    batch.supplier,
                  ),
                ),
                pw.Expanded(
                  child: _dashboardPdfField(
                    'ORDENES INVOLUCRADAS',
                    batch.orderIds.join(', '),
                  ),
                ),
                pw.SizedBox(
                  width: 110,
                  child: _dashboardPdfField(
                    'ITEMS',
                    '${batch.items.length}',
                    showRightBorder: false,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          _dashboardPdfSectionTitle('DETALLE DE ARTICULOS', titleBarColor, titleTextColor),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.8),
            columnWidths: const <int, pw.TableColumnWidth>{
              0: pw.FixedColumnWidth(88),
              1: pw.FlexColumnWidth(4.4),
              2: pw.FixedColumnWidth(70),
              3: pw.FixedColumnWidth(64),
              4: pw.FixedColumnWidth(82),
              5: pw.FixedColumnWidth(96),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: titleBarColor),
                children: [
                  _dashboardPdfCell('Orden / Item', isHeader: true, color: titleTextColor),
                  _dashboardPdfCell('Descripcion', isHeader: true, color: titleTextColor),
                  _dashboardPdfCell('Cantidad', isHeader: true, color: titleTextColor),
                  _dashboardPdfCell('Unidad', isHeader: true, color: titleTextColor),
                  _dashboardPdfCell('OC interna', isHeader: true, color: titleTextColor),
                  _dashboardPdfCell('Monto', isHeader: true, color: titleTextColor),
                ],
              ),
              for (var index = 0; index < rows.length; index++)
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: index.isEven ? PdfColors.white : PdfColor.fromHex('#F4F7FB'),
                  ),
                  children: [
                    _dashboardPdfCell('${rows[index].orderId}\n#${rows[index].lineNumber}'),
                    _dashboardPdfCell(rows[index].description),
                    _dashboardPdfCell('${rows[index].quantity}'),
                    _dashboardPdfCell(rows[index].unit),
                    _dashboardPdfCell(rows[index].internalOrder ?? '-'),
                    _dashboardPdfCell(rows[index].amountLabel),
                  ],
                ),
            ],
          ),
        ];
      },
    ),
  );
  return doc.save();
}

String _copyOrderLocation(String orderId) {
  return Uri(
    path: '/orders/create',
    queryParameters: {'copyFromId': orderId},
  ).toString();
}

class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.countAsync,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final AsyncValue<int>? countAsync;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(20),
        leading: Icon(icon, size: 32),
        title: Text(title, style: Theme.of(context).textTheme.titleLarge),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(subtitle),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (countAsync != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  countAsync!.valueOrNull?.toString() ?? '...',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            const SizedBox(height: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _FollowUpPacketItemContext {
  const _FollowUpPacketItemContext({
    required this.packetItem,
    required this.order,
    required this.orderItem,
  });

  final PacketItemRef packetItem;
  final PurchaseOrder order;
  final PurchaseOrderItem orderItem;
}

class _FollowUpPacketContext {
  const _FollowUpPacketContext({
    required this.bundle,
    required this.items,
  });

  final PacketBundle bundle;
  final List<_FollowUpPacketItemContext> items;

  List<PurchaseOrder> get orders {
    final map = <String, PurchaseOrder>{};
    for (final item in items) {
      map[item.order.id] = item.order;
    }
    final values = map.values.toList(growable: false)
      ..sort((left, right) => left.id.compareTo(right.id));
    return values;
  }

  int get pendingEtaCount =>
      items.where((item) => item.orderItem.deliveryEtaDate == null).length;

  int get readyForFacturasCount => items
      .where((item) =>
          item.orderItem.deliveryEtaDate != null &&
          item.orderItem.sentToContabilidadAt == null)
      .length;

  int get pendingArrivalCount =>
      items.where((item) => !item.orderItem.isResolved).length;

  bool get hasAccountingEvidence => orders.every(
        (order) =>
            order.facturaPdfUrls.isNotEmpty &&
            order.paymentReceiptUrls.isNotEmpty,
      );

  int get facturaLinkCount => orders
      .expand((order) => order.facturaPdfUrls)
      .map((url) => url.trim())
      .where((url) => url.isNotEmpty)
      .toSet()
      .length;

  int get paymentReceiptLinkCount => orders
      .expand((order) => order.paymentReceiptUrls)
      .map((url) => url.trim())
      .where((url) => url.isNotEmpty)
      .toSet()
      .length;

  Duration previousStageDuration(_PacketFollowUpStage stage) {
    switch (stage) {
      case _PacketFollowUpStage.eta:
        final approvedDecision = bundle.decisions
            .where((decision) => decision.action == PacketDecisionAction.approve)
            .toList(growable: false);
        if (approvedDecision.isNotEmpty) {
          approvedDecision.sort((left, right) => left.timestamp.compareTo(right.timestamp));
          final enteredDireccionAt =
              bundle.packet.submittedAt ??
              bundle.packet.createdAt ??
              approvedDecision.first.timestamp;
          final duration = approvedDecision.first.timestamp.difference(
            enteredDireccionAt,
          );
          return duration.isNegative ? Duration.zero : duration;
        }
        return Duration.zero;
      case _PacketFollowUpStage.facturas:
        final candidateDurations = <Duration>[];
        for (final item in items) {
          final eta = item.orderItem.deliveryEtaDate;
          final sentToFacturas = item.orderItem.sentToContabilidadAt;
          if (eta == null || sentToFacturas == null) continue;
          final duration = sentToFacturas.difference(eta);
          candidateDurations.add(duration.isNegative ? Duration.zero : duration);
        }
        if (candidateDurations.isEmpty) return Duration.zero;
        candidateDurations.sort((left, right) => left.compareTo(right));
        return candidateDurations.first;
    }
  }
}

class _FollowUpWaitingOrder {
  const _FollowUpWaitingOrder({
    required this.order,
    required this.remainingCount,
    required this.totalTrackedCount,
    required this.previousStageDuration,
  });

  final PurchaseOrder order;
  final int remainingCount;
  final int totalTrackedCount;
  final Duration previousStageDuration;
}

class _FollowUpPacketCard extends StatelessWidget {
  const _FollowUpPacketCard({
    required this.contextData,
    required this.stage,
    required this.onOpenPdf,
    this.onRegisterEta,
    this.onSendToFacturas,
    this.onAddEvidence,
    this.onRegisterArrival,
  });

  final _FollowUpPacketContext contextData;
  final _PacketFollowUpStage stage;
  final Future<void> Function() onOpenPdf;
  final Future<void> Function()? onRegisterEta;
  final Future<void> Function()? onSendToFacturas;
  final Future<void> Function()? onAddEvidence;
  final Future<void> Function()? onRegisterArrival;

  @override
  Widget build(BuildContext context) {
    final packet = contextData.bundle.packet;
    final orderIds = contextData.orders.map((order) => order.id).toList(growable: false);
    final previousStatusLabel = _followUpPreviousStatusLabel(stage);
    final previousDuration = contextData.previousStageDuration(stage);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${packet.folio ?? packet.id} · ${packet.supplierName}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              stage == _PacketFollowUpStage.eta
                  ? 'Sin ETA: ${contextData.pendingEtaCount} | Listos para facturas: ${contextData.readyForFacturasCount}'
                  : 'Pendientes por llegada: ${contextData.pendingArrivalCount} | Facturas: ${contextData.facturaLinkCount} | Recibos: ${contextData.paymentReceiptLinkCount}',
            ),
            const SizedBox(height: 12),
            StatusDurationPill(
              text:
                  'Tiempo en $previousStatusLabel: ${formatDurationLabel(previousDuration)}',
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final orderId in orderIds) ...[
                    OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => OrderPdfViewScreen(orderId: orderId),
                          ),
                        );
                      },
                      child: Text(orderId),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => unawaited(onOpenPdf()),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Ver PDF'),
                ),
                if (stage == _PacketFollowUpStage.eta) ...[
                  FilledButton.icon(
                    style: _positiveFilledButtonStyle(context),
                    onPressed: onRegisterEta == null
                        ? null
                        : () => unawaited(onRegisterEta!()),
                    icon: const Icon(Icons.event_available_outlined),
                    label: const Text('Registrar ETA'),
                  ),
                  FilledButton.icon(
                    style: _positiveFilledButtonStyle(context),
                    onPressed: contextData.readyForFacturasCount == 0 || onSendToFacturas == null
                        ? null
                        : () => unawaited(onSendToFacturas!()),
                    icon: const Icon(Icons.forward_to_inbox_outlined),
                    label: const Text('Enviar a facturas y evidencias'),
                  ),
                ] else ...[
                  FilledButton.tonalIcon(
                    onPressed: onAddEvidence == null
                        ? null
                        : () => unawaited(onAddEvidence!()),
                    icon: const Icon(Icons.add_link_outlined),
                    label: const Text('Agregar links'),
                  ),
                  FilledButton.icon(
                    style: _positiveFilledButtonStyle(context),
                    onPressed: !contextData.hasAccountingEvidence || onRegisterArrival == null
                        ? null
                        : () => unawaited(onRegisterArrival!()),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Registrar llegada'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FollowUpWaitingOrderCard extends StatelessWidget {
  const _FollowUpWaitingOrderCard({
    required this.waitingOrder,
    required this.stage,
  });

  final _FollowUpWaitingOrder waitingOrder;
  final _PacketFollowUpStage stage;

  @override
  Widget build(BuildContext context) {
    final remainingLabel = stage == _PacketFollowUpStage.eta
        ? 'items pendientes por mandar a facturas'
        : 'items pendientes por resolver';
    final previousStatusLabel = _followUpPreviousStatusLabel(stage);
    final previousDuration = waitingOrder.previousStageDuration;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              waitingOrder.order.id,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _RequesterAreaLine(
              requesterName: waitingOrder.order.requesterName,
              areaName: waitingOrder.order.areaName,
              areaLabel: 'Area',
            ),
            const SizedBox(height: 12),
            StatusDurationPill(
              text:
                  'Tiempo en $previousStatusLabel: ${formatDurationLabel(previousDuration)}',
            ),
            const SizedBox(height: 8),
            Text(
              waitingOrder.remainingCount == 0
                  ? stage == _PacketFollowUpStage.facturas
                      ? 'Todos los ${waitingOrder.totalTrackedCount} items ya llegaron. Ahora el solicitante debe confirmar de recibido en Ordenes en proceso.'
                      : 'Todos los ${waitingOrder.totalTrackedCount} items ya pasaron esta etapa.'
                  : '${waitingOrder.remainingCount} ${remainingLabel}.',
            ),
          ],
        ),
      ),
    );
  }
}

List<PurchaseOrder> _resolveFollowUpOrders(
  List<PacketBundle> bundles,
  List<PurchaseOrder> orders,
) {
  final orderIds = bundles
      .where((bundle) => bundle.packet.status == PurchasePacketStatus.executionReady)
      .expand((bundle) => bundle.packet.itemRefs)
      .map((item) => item.orderId)
      .toSet();
  final related = orders
      .where((order) => orderIds.contains(order.id))
      .toList(growable: false)
    ..sort((left, right) => left.id.compareTo(right.id));
  return related;
}

bool _packetContextMatchesUrgencyFilter(
  _FollowUpPacketContext context,
  OrderUrgencyFilter filter,
) {
  if (filter == OrderUrgencyFilter.all) return true;
  return context.orders.any((order) => matchesOrderUrgencyFilter(order, filter));
}

String _followUpPreviousStatusLabel(_PacketFollowUpStage stage) {
  switch (stage) {
    case _PacketFollowUpStage.eta:
      return 'Direccion General';
    case _PacketFollowUpStage.facturas:
      return 'Agregar fecha estimada';
  }
}

Duration _elapsedSince(DateTime? value) {
  if (value == null) return Duration.zero;
  final now = DateTime.now();
  if (value.isAfter(now)) return Duration.zero;
  return now.difference(value);
}

DateTime? _earliestDateTime(Iterable<DateTime?> values) {
  final filtered = values.whereType<DateTime>().toList(growable: false);
  if (filtered.isEmpty) return null;
  filtered.sort((left, right) => left.compareTo(right));
  return filtered.first;
}

List<_FollowUpPacketContext> _buildFollowUpPacketContexts(
  List<PacketBundle> bundles,
  Map<String, PurchaseOrder> ordersById,
  _PacketFollowUpStage stage,
) {
  final contexts = <_FollowUpPacketContext>[];
  for (final bundle in bundles) {
    final items = <_FollowUpPacketItemContext>[];
    for (final packetItem in bundle.packet.itemRefs) {
      final order = ordersById[packetItem.orderId];
      if (order == null) continue;
      final orderItem = _resolveOrderItemForPacket(order, packetItem);
      if (orderItem == null) continue;
      final include = switch (stage) {
        _PacketFollowUpStage.eta =>
          orderItem.requiresFulfillment &&
          (orderItem.deliveryEtaDate == null ||
              orderItem.sentToContabilidadAt == null),
        _PacketFollowUpStage.facturas =>
          orderItem.sentToContabilidadAt != null && !orderItem.isResolved,
      };
      if (!include) continue;
      items.add(
        _FollowUpPacketItemContext(
          packetItem: packetItem,
          order: order,
          orderItem: orderItem,
        ),
      );
    }
    if (items.isEmpty) continue;
    contexts.add(_FollowUpPacketContext(bundle: bundle, items: items));
  }
  return contexts;
}

List<_FollowUpWaitingOrder> _buildFollowUpWaitingOrders(
  List<PacketBundle> bundles,
  Map<String, PurchaseOrder> ordersById,
  _PacketFollowUpStage stage,
) {
  final grouped = <String, List<_FollowUpPacketItemContext>>{};
  for (final bundle in bundles) {
    for (final packetItem in bundle.packet.itemRefs) {
      final order = ordersById[packetItem.orderId];
      if (order == null) continue;
      final orderItem = _resolveOrderItemForPacket(order, packetItem);
      if (orderItem == null || !orderItem.requiresFulfillment) continue;
      grouped.putIfAbsent(order.id, () => <_FollowUpPacketItemContext>[]).add(
            _FollowUpPacketItemContext(
              packetItem: packetItem,
              order: order,
              orderItem: orderItem,
            ),
          );
    }
  }

  final waiting = <_FollowUpWaitingOrder>[];
  for (final entry in grouped.entries) {
    final items = entry.value;
    if (items.isEmpty) continue;
    final order = items.first.order;
    final hasEnteredStage = switch (stage) {
      _PacketFollowUpStage.eta => items.any(
          (item) =>
              item.orderItem.deliveryEtaDate != null ||
              item.orderItem.sentToContabilidadAt != null,
        ),
      _PacketFollowUpStage.facturas => items.any(
          (item) => item.orderItem.sentToContabilidadAt != null,
        ),
    };
    if (!hasEnteredStage) continue;
    final remainingCount = switch (stage) {
      _PacketFollowUpStage.eta =>
        items.where((item) => item.orderItem.sentToContabilidadAt == null).length,
      _PacketFollowUpStage.facturas =>
        items.where((item) => !item.orderItem.isResolved).length,
    };
    if (remainingCount <= 0) continue;
    final previousStageDuration = switch (stage) {
      _PacketFollowUpStage.eta => () {
          final durations = <Duration>[];
          for (final bundle in bundles.where((bundle) => bundle.packet.itemRefs.any((packetItem) => packetItem.orderId == order.id))) {
            final approvedDecision = bundle.decisions
                .where((decision) => decision.action == PacketDecisionAction.approve)
                .toList(growable: false);
            if (approvedDecision.isEmpty) continue;
            approvedDecision.sort((left, right) => left.timestamp.compareTo(right.timestamp));
            final enteredDireccionAt =
                bundle.packet.submittedAt ??
                bundle.packet.createdAt ??
                approvedDecision.first.timestamp;
            final duration = approvedDecision.first.timestamp.difference(
              enteredDireccionAt,
            );
            durations.add(duration.isNegative ? Duration.zero : duration);
          }
          if (durations.isEmpty) return Duration.zero;
          durations.sort((left, right) => left.compareTo(right));
          return durations.first;
        }(),
      _PacketFollowUpStage.facturas => () {
          final durations = <Duration>[];
          for (final item in items) {
            final eta = item.orderItem.deliveryEtaDate;
            final sentToFacturas = item.orderItem.sentToContabilidadAt;
            if (eta == null || sentToFacturas == null) continue;
            final duration = sentToFacturas.difference(eta);
            durations.add(duration.isNegative ? Duration.zero : duration);
          }
          if (durations.isEmpty) return Duration.zero;
          durations.sort((left, right) => left.compareTo(right));
          return durations.first;
        }(),
    };
    waiting.add(
      _FollowUpWaitingOrder(
        order: order,
        remainingCount: remainingCount,
        totalTrackedCount: items.length,
        previousStageDuration: previousStageDuration,
      ),
    );
  }
  waiting.sort((left, right) => left.order.id.compareTo(right.order.id));
  return waiting;
}

PurchaseOrderItem? _resolveOrderItemForPacket(
  PurchaseOrder order,
  PacketItemRef packetItem,
) {
  for (final item in order.items) {
    if (item.line == packetItem.lineNumber && packetItem.lineNumber > 0) {
      return item;
    }
  }
  final parsedLine = _packetItemLineFromId(packetItem.itemId);
  if (parsedLine != null) {
    for (final item in order.items) {
      if (item.line == parsedLine) return item;
    }
  }
  return null;
}

int? _packetItemLineFromId(String rawItemId) {
  final trimmed = rawItemId.trim();
  if (trimmed.startsWith('line_')) {
    return int.tryParse(trimmed.substring(5));
  }
  return int.tryParse(trimmed);
}

Future<void> _openFollowUpPacketPdf(
  BuildContext context,
  _FollowUpPacketContext packetContext,
) async {
  final issuedAt = packetContext.bundle.packet.submittedAt ??
      packetContext.bundle.packet.updatedAt ??
      packetContext.bundle.packet.createdAt ??
      DateTime.now();
  final batch = _supplierDashboardBatchFromPacket(packetContext.bundle.packet);
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (routeContext) => Consumer(
        builder: (_, ref, __) {
          final branding = ref.watch(currentBrandingProvider);
          final data = _buildSupplierDashboardPdfData(
            branding: branding,
            batch: batch,
            issuedAt: issuedAt,
            folio: packetContext.bundle.packet.folio,
            cacheSalt:
                'followup:${packetContext.bundle.packet.id}:${packetContext.bundle.packet.version}',
          );
          return _SupplierDashboardPdfScreen(
            batch: batch,
            data: data,
            pdfBuilder: (
              _, {
              bool useIsolate = false,
            }) => _buildSupplierDashboardPdfDocument(
              branding: branding,
              batch: batch,
              issuedAt: issuedAt,
              folio: packetContext.bundle.packet.folio,
            ),
          );
        },
      ),
    ),
  );
}

Future<void> _configureEtaForPacket(
  BuildContext context,
  WidgetRef ref,
  _FollowUpPacketContext packetContext,
) async {
  final actor = ref.read(currentUserProfileProvider).value;
  if (actor == null) return;
  final selection = await _selectPacketItemsForStage(
    context,
    packetContext,
    stage: _PacketFollowUpStage.eta,
    requireDate: true,
  );
  if (selection == null || selection.date == null) return;

  final groupedLines = <String, Set<int>>{};
  for (final item in selection.items) {
    groupedLines.putIfAbsent(item.order.id, () => <int>{}).add(item.orderItem.line);
  }
  try {
    final repository = ref.read(purchaseOrderRepositoryProvider);
    for (final entry in groupedLines.entries) {
      final order = packetContext.items
          .firstWhere((item) => item.order.id == entry.key)
          .order;
      await repository.setEstimatedDeliveryDateForItems(
        order: order,
        itemLines: entry.value,
        etaDate: selection.date!,
        actor: actor,
      );
    }
    refreshOrderModuleTransitionData(ref, orderIds: groupedLines.keys.toSet());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fecha estimada registrada.')),
      );
    }
  } catch (error, stack) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reportError(error, stack, context: '_configureEtaForPacket'))),
      );
    }
  }
}

Future<void> _sendPacketToFacturas(
  BuildContext context,
  WidgetRef ref,
  _FollowUpPacketContext packetContext,
) async {
  final actor = ref.read(currentUserProfileProvider).value;
  if (actor == null) return;
  final eligibleItems = packetContext.items
      .where((item) =>
          item.orderItem.deliveryEtaDate != null &&
          item.orderItem.sentToContabilidadAt == null)
      .toList(growable: false);
  if (eligibleItems.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero registra la fecha estimada para los items.')),
      );
    }
    return;
  }

  final selection = await _selectSpecificPacketItems(
    context,
    eligibleItems,
    title: 'Enviar a facturas y evidencias',
  );
  if (selection == null || selection.isEmpty) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Confirmar envio'),
        content: const Text(
          'Los items seleccionados se enviaran a Facturas y evidencias. ¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Enviar'),
          ),
        ],
      );
    },
  );
  if (confirmed != true) return;

  final groupedLines = <String, Set<int>>{};
  for (final item in selection) {
    groupedLines.putIfAbsent(item.order.id, () => <int>{}).add(item.orderItem.line);
  }
  try {
    final repository = ref.read(purchaseOrderRepositoryProvider);
    for (final entry in groupedLines.entries) {
      final order = packetContext.items
          .firstWhere((item) => item.order.id == entry.key)
          .order;
      await repository.sendItemsToFacturas(
        order: order,
        itemLines: entry.value,
        actor: actor,
      );
    }
    refreshOrderModuleTransitionData(ref, orderIds: groupedLines.keys.toSet());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Items enviados a Facturas y evidencias.')),
      );
    }
  } catch (error, stack) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reportError(error, stack, context: '_sendPacketToFacturas'))),
      );
    }
  }
}

Future<void> _attachAccountingEvidenceToPacket(
  BuildContext context,
  WidgetRef ref,
  _FollowUpPacketContext packetContext,
) async {
  final actor = ref.read(currentUserProfileProvider).value;
  if (actor == null) return;
  final selectedItems = packetContext.items
      .map((context) => context.orderItem)
      .toList(growable: false);
  final result = await _promptAccountingEvidence(
    context,
    items: selectedItems,
  );
  if (result == null) return;
  try {
    final repository = ref.read(purchaseOrderRepositoryProvider);
    for (final order in packetContext.orders) {
      final updatedItemsByLine = <int, PurchaseOrderItem>{
        for (final item in result.items) item.line: item,
      };
      final mergedItems = order.items
          .map((item) => updatedItemsByLine[item.line] ?? item)
          .toList(growable: false);
      await repository.saveOrder(
        order.copyWith(items: mergedItems),
        actor: actor,
      );
      await repository.attachAccountingEvidence(
        order: order.copyWith(items: mergedItems),
        facturaUrls: result.facturaUrls,
        paymentReceiptUrls: result.paymentReceiptUrls,
        actor: actor,
      );
    }
    refreshOrderModuleData(
      ref,
      orderIds: packetContext.orders.map((order) => order.id).toSet(),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Links de facturas y recibos guardados.')),
      );
    }
  } catch (error, stack) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reportError(error, stack, context: '_attachAccountingEvidenceToPacket'),
          ),
        ),
      );
    }
  }
}

Future<void> _registerArrivalForPacket(
  BuildContext context,
  WidgetRef ref,
  _FollowUpPacketContext packetContext,
) async {
  final actor = ref.read(currentUserProfileProvider).value;
  if (actor == null) return;
  final selection = await _selectPacketItemsForStage(
    context,
    packetContext,
    stage: _PacketFollowUpStage.facturas,
    requireDate: false,
  );
  if (selection == null) return;

  final groupedLines = <String, Set<int>>{};
  for (final item in selection.items) {
    groupedLines.putIfAbsent(item.order.id, () => <int>{}).add(item.orderItem.line);
  }
  try {
    final repository = ref.read(purchaseOrderRepositoryProvider);
    for (final entry in groupedLines.entries) {
      final order = packetContext.items
          .firstWhere((item) => item.order.id == entry.key)
          .order;
      await repository.registerArrivedItems(
        order: order,
        itemLines: entry.value,
        actor: actor,
      );
    }
    refreshOrderModuleData(ref, orderIds: groupedLines.keys.toSet());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Llegada registrada. Si la orden ya quedo completa, el solicitante la confirmara en Ordenes en proceso.',
          ),
        ),
      );
    }
  } catch (error, stack) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reportError(error, stack, context: '_registerArrivalForPacket'))),
      );
    }
  }
}


class _PacketItemSelectionResult {
  const _PacketItemSelectionResult({
    required this.items,
    this.date,
  });

  final List<_FollowUpPacketItemContext> items;
  final DateTime? date;
}

class _AccountingEvidenceResult {
  const _AccountingEvidenceResult({
    required this.facturaUrls,
    required this.paymentReceiptUrls,
    required this.items,
  });

  final List<String> facturaUrls;
  final List<String> paymentReceiptUrls;
  final List<PurchaseOrderItem> items;
}

Future<_PacketItemSelectionResult?> _selectPacketItemsForStage(
  BuildContext context,
  _FollowUpPacketContext packetContext, {
  required _PacketFollowUpStage stage,
  required bool requireDate,
}) async {
  final allIds = packetContext.items
      .map((item) => item.packetItem.id)
      .toSet();
  final selectedIds = <String>{...allIds};
  var applyToWholePacket = true;
  DateTime? selectedDate =
      requireDate ? DateTime.now().add(const Duration(days: 1)) : null;

  return showDialog<_PacketItemSelectionResult>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          Future<void> pickDate() async {
            final today = DateTime.now();
            final firstAllowedDate = DateTime(today.year, today.month, today.day);
            final picked = await showDatePicker(
              context: dialogContext,
              firstDate: firstAllowedDate,
              lastDate: DateTime.now().add(const Duration(days: 365)),
              initialDate: selectedDate == null || selectedDate!.isBefore(firstAllowedDate)
                  ? firstAllowedDate
                  : selectedDate!,
            );
            if (picked == null) return;
            setState(() => selectedDate = picked);
          }

          return AlertDialog(
            title: Text(
              stage == _PacketFollowUpStage.eta
                  ? 'Registrar ETA'
                  : 'Registrar llegada',
            ),
            content: SizedBox(
              width: 640,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RadioListTile<bool>(
                      value: true,
                      groupValue: applyToWholePacket,
                      onChanged: (_) {
                        setState(() {
                          applyToWholePacket = true;
                          selectedIds
                            ..clear()
                            ..addAll(allIds);
                        });
                      },
                      title: const Text('Aplicar al paquete completo'),
                    ),
                    RadioListTile<bool>(
                      value: false,
                      groupValue: applyToWholePacket,
                      onChanged: (_) {
                        setState(() {
                          applyToWholePacket = false;
                        });
                      },
                      title: const Text('Seleccionar items'),
                    ),
                    if (requireDate) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: pickDate,
                        icon: const Icon(Icons.event_outlined),
                        label: Text(
                          selectedDate == null
                              ? 'Seleccionar fecha'
                              : 'Fecha: ${selectedDate!.toShortDate()}',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    for (final item in packetContext.items)
                      CheckboxListTile(
                        value: selectedIds.contains(item.packetItem.id),
                        onChanged: applyToWholePacket
                            ? null
                            : (selected) {
                                setState(() {
                                  if (selected ?? false) {
                                    selectedIds.add(item.packetItem.id);
                                  } else {
                                    selectedIds.remove(item.packetItem.id);
                                  }
                                });
                              },
                        title: Text('${item.order.id} · Item ${item.orderItem.line}'),
                        subtitle: Text(item.orderItem.description),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  if (selectedIds.isEmpty) return;
                  if (requireDate && selectedDate == null) return;
                  final items = packetContext.items
                      .where((item) => selectedIds.contains(item.packetItem.id))
                      .toList(growable: false);
                  Navigator.of(dialogContext).pop(
                    _PacketItemSelectionResult(items: items, date: selectedDate),
                  );
                },
                child: const Text('Aceptar'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<List<_FollowUpPacketItemContext>?> _selectSpecificPacketItems(
  BuildContext context,
  List<_FollowUpPacketItemContext> availableItems, {
  required String title,
}) async {
  final allIds = availableItems.map((item) => item.packetItem.id).toSet();
  final selectedIds = <String>{...allIds};
  var applyToWholePacket = true;
  return showDialog<List<_FollowUpPacketItemContext>>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 640,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RadioListTile<bool>(
                      value: true,
                      groupValue: applyToWholePacket,
                      onChanged: (_) {
                        setState(() {
                          applyToWholePacket = true;
                          selectedIds
                            ..clear()
                            ..addAll(allIds);
                        });
                      },
                      title: const Text('Aplicar al paquete completo'),
                    ),
                    RadioListTile<bool>(
                      value: false,
                      groupValue: applyToWholePacket,
                      onChanged: (_) {
                        setState(() => applyToWholePacket = false);
                      },
                      title: const Text('Seleccionar items'),
                    ),
                    const SizedBox(height: 12),
                    for (final item in availableItems)
                      CheckboxListTile(
                        value: selectedIds.contains(item.packetItem.id),
                        onChanged: applyToWholePacket
                            ? null
                            : (selected) {
                                setState(() {
                                  if (selected ?? false) {
                                    selectedIds.add(item.packetItem.id);
                                  } else {
                                    selectedIds.remove(item.packetItem.id);
                                  }
                                });
                              },
                        title: Text('${item.order.id} | Item ${item.orderItem.line}'),
                        subtitle: Text(item.orderItem.description),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  if (selectedIds.isEmpty) return;
                  Navigator.of(dialogContext).pop(
                    availableItems
                        .where((item) => selectedIds.contains(item.packetItem.id))
                        .toList(growable: false),
                  );
                },
                child: const Text('Aceptar'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<_AccountingEvidenceResult?> _promptAccountingEvidence(
  BuildContext context, {
  required List<PurchaseOrderItem> items,
}) async {
  final facturaController = TextEditingController();
  final receiptController = TextEditingController();
  final facturaUrls = <String>[];
  final receiptUrls = <String>[];
  final internalOrderControllers = <int, TextEditingController>{
    for (final item in items)
      item.line: TextEditingController(text: (item.internalOrder ?? '').trim()),
  };
  try {
    return await showDialog<_AccountingEvidenceResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            void addFactura() {
              final value = facturaController.text.trim();
              if (!_isValidDashboardQuoteUrl(value)) return;
              setState(() {
                if (!facturaUrls.contains(value)) {
                  facturaUrls.add(value);
                }
                facturaController.clear();
              });
            }

            void addReceipt() {
              final value = receiptController.text.trim();
              if (!_isValidDashboardQuoteUrl(value)) return;
              setState(() {
                if (!receiptUrls.contains(value)) {
                  receiptUrls.add(value);
                }
                receiptController.clear();
              });
            }

            return AlertDialog(
              title: const Text('Agregar links'),
              content: SizedBox(
                width: 720,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Links de facturas',
                        style: Theme.of(dialogContext).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: facturaController,
                              decoration: const InputDecoration(
                                labelText: 'https://...',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: addFactura,
                            child: const Text('Agregar'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final entry in facturaUrls.asMap().entries)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(entry.value),
                          trailing: IconButton(
                            onPressed: () => setState(() => facturaUrls.removeAt(entry.key)),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        'Links de recibos de pago',
                        style: Theme.of(dialogContext).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: receiptController,
                              decoration: const InputDecoration(
                                labelText: 'https://...',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: addReceipt,
                            child: const Text('Agregar'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final entry in receiptUrls.asMap().entries)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(entry.value),
                          trailing: IconButton(
                            onPressed: () => setState(() => receiptUrls.removeAt(entry.key)),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        'OC interna por item',
                        style: Theme.of(dialogContext).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      for (final item in items) ...[
                        Text(
                          'Item ${item.line} - ${item.description}',
                          style: Theme.of(dialogContext).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: internalOrderControllers[item.line],
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'OC interna',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: facturaUrls.isEmpty ||
                          receiptUrls.isEmpty ||
                          items.any(
                            (item) => (internalOrderControllers[item.line]?.text.trim().isEmpty ?? true),
                          )
                      ? null
                      : () {
                          final updatedItems = items
                              .map(
                                (item) => item.copyWith(
                                  internalOrder:
                                      internalOrderControllers[item.line]!.text.trim(),
                                  clearInternalOrder: false,
                                ),
                              )
                              .toList(growable: false);
                          Navigator.of(dialogContext).pop(
                            _AccountingEvidenceResult(
                              facturaUrls: List<String>.from(facturaUrls),
                              paymentReceiptUrls: List<String>.from(receiptUrls),
                              items: updatedItems,
                            ),
                          );
                        },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    facturaController.dispose();
    receiptController.dispose();
    for (final controller in internalOrderControllers.values) {
      controller.dispose();
    }
  }
}

PurchaseOrderEvent? _latestEventToStatus(
  List<PurchaseOrderEvent> events,
  PurchaseOrderStatus status,
) {
  for (final event in events.reversed) {
    if (event.toStatus == status) return event;
  }
  return null;
}

String _eventActorLabel(
  PurchaseOrderEvent event,
  Map<String, String> actorNamesById,
) {
  final userName = actorNamesById[event.byUser]?.trim() ?? '';
  final role = event.byRole.trim();
  if (userName.isEmpty && role.isEmpty) return 'Sistema';
  if (userName.isEmpty) return role;
  if (role.isEmpty) return userName;
  return '$userName | $role';
}

bool _matchesWorkflowOrderFilters(
  PurchaseOrder order, {
  required String searchQuery,
  required DateTimeRange? createdDateRangeFilter,
}) {
  return matchesOrderCreatedDateRange(order, createdDateRangeFilter) &&
      orderMatchesSearch(
        order,
        searchQuery,
        includeDates: false,
      );
}

bool _packetContextMatchesOrderFilters(
  _FollowUpPacketContext context, {
  required String searchQuery,
  required DateTimeRange? createdDateRangeFilter,
}) {
  return context.orders.any(
    (order) => _matchesWorkflowOrderFilters(
      order,
      searchQuery: searchQuery,
      createdDateRangeFilter: createdDateRangeFilter,
    ),
  );
}

class _OrderSearchDateToolbar extends StatelessWidget {
  const _OrderSearchDateToolbar({
    required this.controller,
    required this.searchQuery,
    required this.onChanged,
    required this.onClear,
    required this.selectedRange,
    required this.onPickDate,
    required this.onClearDate,
  });

  final TextEditingController controller;
  final String searchQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final DateTimeRange? selectedRange;
  final Future<void> Function() onPickDate;
  final VoidCallback onClearDate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 720;
        final searchField = TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Buscar por folio, solicitante o area',
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
        final dateFilter = OrderDateRangeFilterButton(
          selectedRange: selectedRange,
          onPickDate: onPickDate,
          onClearDate: onClearDate,
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
    );
  }
}

ButtonStyle _positiveFilledButtonStyle(BuildContext context) {
  return FilledButton.styleFrom(
    backgroundColor: Colors.green.shade700,
    foregroundColor: Colors.white,
    disabledBackgroundColor: Theme.of(context).disabledColor.withOpacity(0.12),
    disabledForegroundColor: Theme.of(context).disabledColor,
  );
}

ButtonStyle _negativeFilledButtonStyle(BuildContext context) {
  return FilledButton.styleFrom(
    backgroundColor: Colors.red.shade700,
    foregroundColor: Colors.white,
    disabledBackgroundColor: Theme.of(context).disabledColor.withOpacity(0.12),
    disabledForegroundColor: Theme.of(context).disabledColor,
  );
}

ButtonStyle _negativeOutlinedButtonStyle(BuildContext context) {
  return OutlinedButton.styleFrom(
    foregroundColor: Colors.red.shade700,
    side: BorderSide(color: Colors.red.shade700),
  );
}

List<num> _splitBudgetEvenly(num totalAmount, int itemCount) {
  if (itemCount <= 0) return const <num>[];
  final totalCents = (totalAmount.toDouble() * 100).round();
  final baseCents = totalCents ~/ itemCount;
  var remainder = totalCents % itemCount;
  final values = <num>[];
  for (var index = 0; index < itemCount; index++) {
    final current = baseCents + (remainder > 0 ? 1 : 0);
    if (remainder > 0) remainder -= 1;
    values.add(current / 100);
  }
  return values;
}

num _sumItemBudgets(List<PurchaseOrderItem> items) {
  var total = 0.0;
  for (final item in items) {
    total += (item.budget ?? 0).toDouble();
  }
  return total;
}

Map<String, num> _buildSupplierBudgets(List<PurchaseOrderItem> items) {
  final budgets = <String, num>{};
  for (final item in items) {
    final supplier = (item.supplier ?? '').trim();
    final budget = item.budget;
    if (supplier.isEmpty || budget == null) continue;
    budgets[supplier] = (budgets[supplier] ?? 0) + budget;
  }
  return budgets;
}

String? _resolveSingleSupplier(List<PurchaseOrderItem> items) {
  final values = items
      .map((item) => (item.supplier ?? '').trim())
      .where((value) => value.isNotEmpty)
      .toSet();
  if (values.length != 1) return null;
  return values.first;
}

String? _resolveSingleInternalOrder(List<PurchaseOrderItem> items) {
  final values = items
      .map((item) => (item.internalOrder ?? '').trim())
      .where((value) => value.isNotEmpty)
      .toSet();
  if (values.length != 1) return null;
  return values.first;
}

Future<String?> _promptRejectReason(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Rechazar orden'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Motivo del rechazo',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: _negativeFilledButtonStyle(context),
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.isEmpty) return;
              Navigator.of(context).pop(reason);
            },
            child: const Text('Rechazar'),
          ),
        ],
      );
    },
  );
  controller.dispose();
  return result;
}

