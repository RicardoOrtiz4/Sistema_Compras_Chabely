import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/navigation_guard.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/domain/supplier_quote.dart';
import 'package:sistema_compras/features/orders/presentation/preview/supplier_quote_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/supplier_quote_pdf_view_screen.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_card_pills.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_status_duration.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_urgency_controls.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

class ContabilidadSupplierGroupsScreen extends ConsumerStatefulWidget {
  const ContabilidadSupplierGroupsScreen({super.key});

  @override
  ConsumerState<ContabilidadSupplierGroupsScreen> createState() =>
      _ContabilidadSupplierGroupsScreenState();
}

class _ContabilidadSupplierGroupsScreenState
    extends ConsumerState<ContabilidadSupplierGroupsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  OrderUrgencyFilter _urgencyFilter = OrderUrgencyFilter.all;
  DateTimeRange? _createdDateRangeFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _updateSearch(String value) {
    setState(() => _searchQuery = value);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  void _setUrgencyFilter(OrderUrgencyFilter filter) {
    setState(() => _urgencyFilter = filter);
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
    final quotesAsync = ref.watch(supplierQuotesProvider);
    final ordersAsync = ref.watch(operationalOrdersProvider);
    final compactAppBar = useCompactOrderModuleAppBar(context);

    final titleGroups = _visibleContabilidadGroups(
      quotes: quotesAsync.valueOrNull ?? const <SupplierQuote>[],
      allOrders: ordersAsync.valueOrNull ?? const <PurchaseOrder>[],
      query: _searchQuery,
      filter: _urgencyFilter,
      range: _createdDateRangeFilter,
    );
    final titleCounts = _contabilidadGroupUrgencyCounts(titleGroups);

    return Scaffold(
      appBar: AppBar(
        title: compactAppBar
            ? const Text('Contabilidad')
            : OrderModuleAppBarTitle(
                title: 'Contabilidad',
                counts: titleCounts,
                filter: _urgencyFilter,
                onSelected: _setUrgencyFilter,
              ),
        bottom: !compactAppBar
            ? null
            : OrderModuleAppBarBottom(
                counts: titleCounts,
                filter: _urgencyFilter,
                onSelected: _setUrgencyFilter,
              ),
      ),
      body: quotesAsync.when(
        data: (quotes) => ordersAsync.when(
          data: (orders) {
            final groups = _visibleContabilidadGroups(
              quotes: quotes,
              allOrders: orders,
              query: _searchQuery,
              filter: _urgencyFilter,
              range: _createdDateRangeFilter,
            );
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ContabilidadFiltersBar(
                  searchController: _searchController,
                  searchQuery: _searchQuery,
                  selectedRange: _createdDateRangeFilter,
                  onSearchChanged: _updateSearch,
                  onClearSearch: _clearSearch,
                  onPickDate: _pickCreatedDateFilter,
                  onClearDate: _clearCreatedDateFilter,
                ),
                const SizedBox(height: 16),
                if (groups.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No hay grupos pendientes en Contabilidad.'),
                    ),
                  )
                else
                  for (final group in groups) ...[
                    _ContabilidadGroupCard(group: group),
                    const SizedBox(height: 12),
                  ],
              ],
            );
          },
          loading: () => const AppSplash(),
          error: (error, stack) => _ContabilidadError(
            message: reportError(error, stack, context: 'ContabilidadSupplierGroupsScreen.orders'),
          ),
        ),
        loading: () => const AppSplash(),
        error: (error, stack) => _ContabilidadError(
          message: reportError(error, stack, context: 'ContabilidadSupplierGroupsScreen.quotes'),
        ),
      ),
    );
  }
}

class _ContabilidadFiltersBar extends StatelessWidget {
  const _ContabilidadFiltersBar({
    required this.searchController,
    required this.searchQuery,
    required this.selectedRange,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onPickDate,
    required this.onClearDate,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final DateTimeRange? selectedRange;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onPickDate;
  final VoidCallback onClearDate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 720;
        final searchField = TextField(
          controller: searchController,
          decoration: InputDecoration(
            labelText: 'Buscar por proveedor, folio o solicitante...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: searchQuery.isEmpty
                ? null
                : IconButton(onPressed: onClearSearch, icon: const Icon(Icons.clear)),
          ),
          onChanged: onSearchChanged,
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
              Align(alignment: Alignment.centerRight, child: dateFilter),
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

class _ContabilidadGroupCard extends StatelessWidget {
  const _ContabilidadGroupCard({required this.group});

  final _ContabilidadGroup group;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final urgent = group.orders.any((order) => order.urgency == PurchaseOrderUrgency.urgente);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OrderTagPill(
                  label: group.quote.supplier.trim().isEmpty ? group.quote.displayId : group.quote.supplier.trim(),
                  backgroundColor: scheme.secondaryContainer,
                  borderColor: scheme.secondary,
                  textColor: scheme.onSecondaryContainer,
                ),
                if (urgent) OrderUrgencyPill(urgency: PurchaseOrderUrgency.urgente),
                OrderTagPill(
                  label: '${group.orders.length} orden(es)',
                  backgroundColor: scheme.surfaceContainerHighest,
                  borderColor: scheme.outlineVariant,
                  textColor: scheme.onSurfaceVariant,
                ),
                OrderTagPill(
                  label: '${group.items.length} item(s)',
                  backgroundColor: scheme.surfaceContainerHighest,
                  borderColor: scheme.outlineVariant,
                  textColor: scheme.onSurfaceVariant,
                ),
                if (group.quote.facturaLinks.isNotEmpty)
                  OrderTagPill(
                    label: '${group.quote.facturaLinks.length} factura(s)',
                    backgroundColor: Colors.green.shade100,
                    borderColor: Colors.green.shade400,
                    textColor: Colors.green.shade900,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            PreviousStatusDurationPill(
              orderIds: [for (final order in group.orders) order.id],
              fromStatus: PurchaseOrderStatus.paymentDone,
              toStatus: PurchaseOrderStatus.contabilidad,
              label: 'Tiempo en Contabilidad',
              alignRight: false,
            ),
            const SizedBox(height: 8),
            Text('Ordenes: ${group.orders.map((order) => order.id).join(', ')}'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => guardedPush<void>(
                context,
                '/orders/contabilidad/group/${group.quote.id}',
              ),
              icon: const Icon(Icons.account_tree_outlined),
              label: const Text('Revisar agrupacion'),
            ),
          ],
        ),
      ),
    );
  }
}

class ContabilidadSupplierGroupReviewScreen extends ConsumerStatefulWidget {
  const ContabilidadSupplierGroupReviewScreen({required this.quoteId, super.key});

  final String quoteId;

  @override
  ConsumerState<ContabilidadSupplierGroupReviewScreen> createState() =>
      _ContabilidadSupplierGroupReviewScreenState();
}

class _ContabilidadSupplierGroupReviewScreenState
    extends ConsumerState<ContabilidadSupplierGroupReviewScreen> {
  bool _savingLinks = false;
  bool _returningGroup = false;
  final Set<String> _submittingOrders = <String>{};
  @override
  Widget build(BuildContext context) {
    final quoteAsync = ref.watch(supplierQuoteByIdProvider(widget.quoteId));
    final ordersAsync = ref.watch(operationalOrdersProvider);
    final quotesAsync = ref.watch(supplierQuotesProvider);
    final actor = ref.watch(currentUserProfileProvider).value;
    final branding = ref.watch(currentBrandingProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Regresar',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              guardedGo(context, '/orders/contabilidad');
            }
          },
        ),
        title: const Text('Contabilidad por proveedor'),
      ),
      body: quoteAsync.when(
        data: (quote) => ordersAsync.when(
          data: (orders) => quotesAsync.when(
            data: (allQuotes) {
              if (quote == null) {
                return const Center(child: Text('Agrupacion no encontrada.'));
              }
              final group = _buildContabilidadGroup(quote, orders);
              if (group == null) {
                return const Center(child: Text('Esta agrupacion ya no tiene ordenes pendientes.'));
              }
              final quotePdfData = _buildContabilidadQuotePdfData(
                quote: quote,
                allOrders: orders,
                branding: branding,
                actor: actor,
              );
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    quote.supplier.trim().isEmpty ? quote.displayId : quote.supplier.trim(),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text('Folio ${quote.displayId}')),
                      Chip(label: Text(quote.status.label)),
                      Chip(
                        label: Text(
                          '${group.orders.length} orden(es) · ${group.items.length} item(s)',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Monto total de esta cotizacion: ${_money(quote.totalAmount)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Links de cotizacion',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (quote.links.isEmpty)
                    const Text('Sin links registrados.')
                  else
                    for (final link in quote.links) ...[
                      SelectableText(link),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () => _openLink(link),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Abrir link'),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => SupplierQuotePdfViewScreen(
                            data: quotePdfData,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Ver PDF general'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Links de factura del proveedor', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          if (quote.facturaLinks.isEmpty)
                            const Text('Agrega al menos un link de factura para desbloquear las ordenes individuales.')
                          else
                            for (final link in quote.facturaLinks) ...[
                              SelectableText(link),
                              const SizedBox(height: 6),
                            ],
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _savingLinks ? null : () => _editFacturaLinks(quote),
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: Text(quote.facturaLinks.isEmpty ? 'Agregar factura' : 'Editar facturas'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _returningGroup || actor == null
                              ? null
                              : () => _returnGroupToPreviousStatus(quote),
                          child: _returningGroup
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Regresar agrupacion'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (quote.facturaLinks.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Cuando la agrupacion tenga factura, aqui se abriran las ordenes individuales del mismo proveedor.'),
                      ),
                    )
                  else
                    for (final order in group.orders) ...[
                      _ContabilidadOrderReviewCard(
                        order: order,
                        sentLines: group.sentLinesByOrder[order.id] ?? const <int>{},
                        isSubmitting: _submittingOrders.contains(order.id),
                        onEditInternalOrder: (value) => _saveInternalOrder(
                          order: order,
                          lines: group.sentLinesByOrder[order.id] ?? const <int>{},
                          value: value,
                        ),
                        onFinalize: () => _finalizeOrder(order: order, allQuotes: allQuotes),
                      ),
                      const SizedBox(height: 12),
                    ],
                ],
              );
            },
            loading: () => const AppSplash(),
            error: (error, stack) => _ContabilidadError(
              message: reportError(error, stack, context: 'ContabilidadSupplierGroupReviewScreen.allQuotes'),
            ),
          ),
          loading: () => const AppSplash(),
          error: (error, stack) => _ContabilidadError(
            message: reportError(error, stack, context: 'ContabilidadSupplierGroupReviewScreen.orders'),
          ),
        ),
        loading: () => const AppSplash(),
        error: (error, stack) => _ContabilidadError(
          message: reportError(error, stack, context: 'ContabilidadSupplierGroupReviewScreen.quote'),
        ),
      ),
    );
  }

  Future<void> _editFacturaLinks(SupplierQuote quote) async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => _FacturaLinksDialog(initialLinks: quote.facturaLinks),
    );
    if (result == null || !mounted) return;
    final actor = ref.read(currentUserProfileProvider).value;
    setState(() => _savingLinks = true);
    try {
      await ref.read(purchaseOrderRepositoryProvider).saveSupplierQuoteFacturaLinks(
            quote: quote,
            links: result,
            actor: actor,
          );
    } catch (error, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reportError(error, stack, context: 'ContabilidadSupplierGroupReviewScreen.saveLinks'))),
      );
    } finally {
      if (mounted) setState(() => _savingLinks = false);
    }
  }

  Future<void> _openLink(String raw) async {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.isAbsolute) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _returnGroupToPreviousStatus(SupplierQuote quote) async {
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil no disponible.')),
      );
      return;
    }

    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Regresar agrupacion'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Motivo'),
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
    if (accepted != true) {
      controller.dispose();
      return;
    }

    setState(() => _returningGroup = true);
    try {
      await ref.read(purchaseOrderRepositoryProvider).returnSupplierQuoteItemsFromContabilidad(
            quote: quote,
            actor: actor,
            comment: controller.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agrupacion regresada al estado anterior.'),
        ),
      );
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        guardedGo(context, '/orders/contabilidad');
      }
    } catch (error, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reportError(
              error,
              stack,
              context: 'ContabilidadSupplierGroupReviewScreen.return',
            ),
          ),
        ),
      );
    } finally {
      controller.dispose();
      if (mounted) setState(() => _returningGroup = false);
    }
  }

  Future<void> _saveInternalOrder({
    required PurchaseOrder order,
    required Set<int> lines,
    required String? value,
  }) async {
    await ref.read(purchaseOrderRepositoryProvider).saveInternalOrderForItems(
          order: order,
          lines: lines,
          internalOrder: value,
        );
  }

  Future<void> _finalizeOrder({
    required PurchaseOrder order,
    required List<SupplierQuote> allQuotes,
  }) async {
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Perfil no disponible.')));
      return;
    }
    if (!_canFinalizeOrder(order)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta orden aun no tiene todos sus items en Contabilidad.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finalizar orden'),
        content: Text('Se marcara la orden ${order.id} como finalizada y el solicitante la vera en Ordenes en proceso.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Finalizar')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submittingOrders.add(order.id));
    try {
      final facturaLinks = _collectOrderFacturaLinks(order.id, allQuotes);
      await ref.read(purchaseOrderRepositoryProvider).completeFromContabilidad(
            order: order,
            facturaUrls: facturaLinks,
            actor: actor,
            items: order.items,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Orden ${order.id} finalizada. El solicitante ya puede confirmar recibido cuando le llegue.')),
      );
    } catch (error, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reportError(error, stack, context: 'ContabilidadSupplierGroupReviewScreen.finalize'))),
      );
    } finally {
      if (mounted) setState(() => _submittingOrders.remove(order.id));
    }
  }
}
class _ContabilidadOrderReviewCard extends StatelessWidget {
  const _ContabilidadOrderReviewCard({
    required this.order,
    required this.sentLines,
    required this.isSubmitting,
    required this.onEditInternalOrder,
    required this.onFinalize,
  });

  final PurchaseOrder order;
  final Set<int> sentLines;
  final bool isSubmitting;
  final Future<void> Function(String?) onEditInternalOrder;
  final Future<void> Function() onFinalize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final urgentJustification = (order.urgentJustification ?? '').trim();
    final sentItems = order.items.where((item) => sentLines.contains(item.line)).toList(growable: false);
    final currentInternalOrder = _sharedInternalOrder(sentItems);
    final ready = _canFinalizeOrder(order);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
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
                OrderTagPill(
                  label: '${sentItems.length} item(s) de este proveedor',
                  backgroundColor: scheme.surfaceContainerHighest,
                  borderColor: scheme.outlineVariant,
                  textColor: scheme.onSurfaceVariant,
                ),
                if (ready)
                  OrderTagPill(
                    label: 'Lista para finalizar',
                    backgroundColor: Colors.green.shade100,
                    borderColor: Colors.green.shade400,
                    textColor: Colors.green.shade900,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Solicitante / Area: ${order.requesterName} | ${order.areaName}'),
            const SizedBox(height: 8),
            Text(
              ready
                  ? 'Todos los items de la orden ya llegaron a Contabilidad.'
                  : 'Aun faltan items de otros proveedores para poder finalizar esta orden.',
            ),
            if (currentInternalOrder != null && currentInternalOrder.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('OC interna actual: $currentInternalOrder'),
            ],
            const SizedBox(height: 10),
            Text(
              'Items de esta agrupacion:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            for (final item in sentItems) ...[
              Text('• Item ${item.line}: ${item.description}'),
              const SizedBox(height: 4),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => guardedPdfPush(context, '/orders/${order.id}/pdf'),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Ver PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await showDialog<String?>(
                      context: context,
                      builder: (context) => _InternalOrderDialog(initialValue: currentInternalOrder ?? ''),
                    );
                    if (result == null) return;
                    await onEditInternalOrder(result.trim().isEmpty ? null : result);
                  },
                  icon: const Icon(Icons.confirmation_number_outlined),
                  label: const Text('OC interna opcional'),
                ),
                FilledButton.icon(
                  onPressed: !ready || isSubmitting ? null : onFinalize,
                  icon: isSubmitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_circle_outline),
                  label: const Text('Finalizar orden'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FacturaLinksDialog extends StatefulWidget {
  const _FacturaLinksDialog({required this.initialLinks});

  final List<String> initialLinks;

  @override
  State<_FacturaLinksDialog> createState() => _FacturaLinksDialogState();
}

class _FacturaLinksDialogState extends State<_FacturaLinksDialog> {
  late final TextEditingController _controller;
  late final List<String> _links;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _links = List<String>.from(widget.initialLinks);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Links de factura'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _controller, decoration: const InputDecoration(labelText: 'Pega un link')),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {
                  final value = _controller.text.trim();
                  if (value.isEmpty) return;
                  setState(() {
                    _links.add(value);
                    _controller.clear();
                  });
                },
                child: const Text('Agregar'),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _links.length,
                itemBuilder: (context, index) {
                  final link = _links[index];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(link),
                    trailing: IconButton(
                      onPressed: () => setState(() => _links.removeAt(index)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, _links), child: const Text('Guardar')),
      ],
    );
  }
}

class _InternalOrderDialog extends StatefulWidget {
  const _InternalOrderDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_InternalOrderDialog> createState() => _InternalOrderDialogState();
}

class _InternalOrderDialogState extends State<_InternalOrderDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('OC interna'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(labelText: 'OC interna (opcional)'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Guardar')),
      ],
    );
  }
}

class _ContabilidadError extends StatelessWidget {
  const _ContabilidadError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(message));
  }
}
class _ContabilidadGroup {
  const _ContabilidadGroup({
    required this.quote,
    required this.orders,
    required this.items,
    required this.sentLinesByOrder,
  });

  final SupplierQuote quote;
  final List<PurchaseOrder> orders;
  final List<_ContabilidadGroupItem> items;
  final Map<String, Set<int>> sentLinesByOrder;
}

class _ContabilidadGroupItem {
  const _ContabilidadGroupItem({required this.order, required this.item});

  final PurchaseOrder order;
  final PurchaseOrderItem item;
}

String _money(num value) {
  return '\$${value.toDouble().toStringAsFixed(2)}';
}

SupplierQuotePdfData _buildContabilidadQuotePdfData({
  required SupplierQuote quote,
  required List<PurchaseOrder> allOrders,
  required CompanyBranding branding,
  required AppUser? actor,
}) {
  final refsByOrder = <String, Map<int, SupplierQuoteItemRef>>{};
  for (final ref in quote.items) {
    refsByOrder.putIfAbsent(
      ref.orderId,
      () => <int, SupplierQuoteItemRef>{},
    )[ref.line] = ref;
  }

  final orders = <SupplierQuotePdfOrderData>[];
  for (final order in allOrders) {
    final orderRefs = refsByOrder[order.id];
    if (orderRefs == null || orderRefs.isEmpty) continue;

    final items = <SupplierQuotePdfItemData>[];
    for (final item in order.items) {
      final selectedRef = orderRefs[item.line];
      items.add(
        SupplierQuotePdfItemData(
          line: item.line,
          description: item.description,
          quantity: item.quantity,
          unit: item.unit,
          selected: selectedRef != null,
          partNumber: item.partNumber,
          customer: item.customer,
          amount: selectedRef?.amount ?? item.budget,
        ),
      );
    }

    orders.add(
      SupplierQuotePdfOrderData(
        orderId: order.id,
        requesterName: order.requesterName,
        areaName: order.areaName,
        items: items,
      ),
    );
  }

  orders.sort((a, b) => a.orderId.compareTo(b.orderId));
  return SupplierQuotePdfData(
    branding: branding,
    quoteId: quote.displayId,
    supplier: quote.supplier,
    links: quote.links,
    orders: orders,
    comprasComment: quote.comprasComment,
    createdAt: quote.createdAt,
    processedByName: quote.processedByName ?? actor?.name,
    processedByArea: quote.processedByArea ?? actor?.areaDisplay,
    authorizedByName: quote.approvedByName,
    authorizedByArea: quote.approvedByArea,
  );
}

List<_ContabilidadGroup> _visibleContabilidadGroups({
  required List<SupplierQuote> quotes,
  required List<PurchaseOrder> allOrders,
  required String query,
  required OrderUrgencyFilter filter,
  required DateTimeRange? range,
}) {
  final groups = <_ContabilidadGroup>[];
  for (final quote in quotes) {
    final group = _buildContabilidadGroup(quote, allOrders);
    if (group == null) continue;
    if (!_matchesContabilidadGroupFilters(group: group, query: query, filter: filter, range: range)) {
      continue;
    }
    groups.add(group);
  }
  groups.sort((a, b) {
    final aTime = a.quote.updatedAt?.millisecondsSinceEpoch ?? a.quote.createdAt?.millisecondsSinceEpoch ?? 0;
    final bTime = b.quote.updatedAt?.millisecondsSinceEpoch ?? b.quote.createdAt?.millisecondsSinceEpoch ?? 0;
    return bTime.compareTo(aTime);
  });
  return groups;
}

_ContabilidadGroup? _buildContabilidadGroup(SupplierQuote quote, List<PurchaseOrder> allOrders) {
  if (quote.status != SupplierQuoteStatus.approved) return null;

  final ordersById = {for (final order in allOrders) order.id: order};
  final relatedOrders = <PurchaseOrder>[];
  final relatedItems = <_ContabilidadGroupItem>[];
  final sentLinesByOrder = <String, Set<int>>{};

  for (final orderId in quote.orderIds) {
    final order = ordersById[orderId];
    if (order == null || order.status == PurchaseOrderStatus.eta) continue;
    final sentItems = order.items
        .where(
          (item) =>
              (item.quoteId?.trim() ?? '') == quote.id &&
              item.quoteStatus == PurchaseOrderItemQuoteStatus.approved &&
              _isItemVisibleInContabilidad(item),
        )
        .toList(growable: false);
    if (sentItems.isEmpty) continue;
    relatedOrders.add(order);
    final lines = <int>{};
    for (final item in sentItems) {
      relatedItems.add(_ContabilidadGroupItem(order: order, item: item));
      lines.add(item.line);
    }
    sentLinesByOrder[order.id] = lines;
  }

  if (relatedOrders.isEmpty || relatedItems.isEmpty) return null;
  relatedOrders.sort((a, b) => a.id.compareTo(b.id));
  return _ContabilidadGroup(
    quote: quote,
    orders: relatedOrders,
    items: relatedItems,
    sentLinesByOrder: sentLinesByOrder,
  );
}

bool _isItemVisibleInContabilidad(PurchaseOrderItem item) {
  return item.sentToContabilidadAt != null || item.deliveryEtaDate != null;
}

bool _matchesContabilidadGroupFilters({
  required _ContabilidadGroup group,
  required String query,
  required OrderUrgencyFilter filter,
  required DateTimeRange? range,
}) {
  if (!_contabilidadGroupMatchesSearch(group, query)) return false;
  final urgencyMatches = switch (filter) {
    OrderUrgencyFilter.all => true,
    OrderUrgencyFilter.normal => group.orders.every((order) => order.urgency == PurchaseOrderUrgency.normal),
    OrderUrgencyFilter.urgente => group.orders.any((order) => order.urgency == PurchaseOrderUrgency.urgente),
  };
  if (!urgencyMatches) return false;
  if (range == null) return true;

  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day);
  return group.orders.any((order) {
    final createdAt = order.createdAt;
    if (createdAt == null) return false;
    final createdDate = DateTime(createdAt.year, createdAt.month, createdAt.day);
    return !createdDate.isBefore(start) && !createdDate.isAfter(end);
  });
}

bool _contabilidadGroupMatchesSearch(_ContabilidadGroup group, String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return true;
  final buffer = StringBuffer();

  void addValue(Object? value) {
    if (value == null) return;
    final text = value.toString().trim();
    if (text.isEmpty) return;
    buffer.write(text.toLowerCase());
    buffer.write(' ');
  }

  addValue(group.quote.id);
  addValue(group.quote.displayId);
  addValue(group.quote.supplier);
  for (final order in group.orders) {
    addValue(order.id);
    addValue(order.requesterName);
    addValue(order.areaName);
    addValue(order.clientNote);
  }
  for (final entry in group.items) {
    addValue(entry.item.description);
    addValue(entry.item.partNumber);
  }

  final haystack = buffer.toString();
  return normalized.split(RegExp(r'\s+')).where((token) => token.isNotEmpty).every(haystack.contains);
}

OrderUrgencyCounts _contabilidadGroupUrgencyCounts(List<_ContabilidadGroup> groups) {
  var normal = 0;
  var urgente = 0;
  for (final group in groups) {
    final hasUrgent = group.orders.any((order) => order.urgency == PurchaseOrderUrgency.urgente);
    if (hasUrgent) {
      urgente += 1;
    } else {
      normal += 1;
    }
  }
  return OrderUrgencyCounts(total: groups.length, normal: normal, urgente: urgente);
}

bool _canFinalizeOrder(PurchaseOrder order) {
  if (order.items.isEmpty) return false;
  for (final item in order.items) {
    if (item.sentToContabilidadAt == null) {
      return false;
    }
  }
  return true;
}

List<String> _collectOrderFacturaLinks(String orderId, List<SupplierQuote> quotes) {
  final links = <String>{};
  for (final quote in quotes) {
    if (!quote.orderIds.contains(orderId)) continue;
    for (final link in quote.facturaLinks) {
      final trimmed = link.trim();
      if (trimmed.isNotEmpty) links.add(trimmed);
    }
  }
  return links.toList(growable: false);
}

String? _sharedInternalOrder(List<PurchaseOrderItem> items) {
  if (items.isEmpty) return null;
  final values = items
      .map((item) => (item.internalOrder ?? '').trim())
      .where((value) => value.isNotEmpty)
      .toSet();
  if (values.length == 1) return values.first;
  return values.isEmpty ? null : '';
}
