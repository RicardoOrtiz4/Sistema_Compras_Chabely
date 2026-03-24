import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/navigation_guard.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/domain/supplier_quote.dart';
import 'package:sistema_compras/features/orders/presentation/contabilidad/contabilidad_group_pdf_screen.dart';
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

class _ContabilidadGroupCard extends ConsumerStatefulWidget {
  const _ContabilidadGroupCard({required this.group});

  final _ContabilidadGroup group;

  @override
  ConsumerState<_ContabilidadGroupCard> createState() =>
      _ContabilidadGroupCardState();
}

class _ContabilidadGroupCardState extends ConsumerState<_ContabilidadGroupCard> {
  bool _savingLinks = false;

  _ContabilidadGroup get group => widget.group;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final urgent = group.orders.any(
      (order) => order.urgency == PurchaseOrderUrgency.urgente,
    );
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
                if (group.quote.paymentLinks.isNotEmpty)
                  OrderTagPill(
                    label: '${group.quote.paymentLinks.length} pago(s)',
                    backgroundColor: Colors.blue.shade100,
                    borderColor: Colors.blue.shade400,
                    textColor: Colors.blue.shade900,
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
            const SizedBox(height: 12),
            Text(
              'Ordenes de esta agrupacion',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final order in group.orders)
                  OutlinedButton.icon(
                    onPressed: () =>
                        guardedPdfPush(context, '/orders/${order.id}/pdf'),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(order.id),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              group.quote.facturaLinks.isEmpty && group.quote.paymentLinks.isEmpty
                  ? 'Aun no hay links contables cargados.'
                  : 'Facturas: ${group.quote.facturaLinks.length} · Pagos: '
                      '${group.quote.paymentLinks.length}',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _savingLinks ? null : _editLinks,
                  icon: const Icon(Icons.link),
                  label: const Text('Agregar links'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) =>
                          ContabilidadGroupPdfScreen(quoteId: group.quote.id),
                    ),
                  ),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Ver PDF'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editLinks() async {
    final result = await showDialog<_AccountingLinksResult>(
      context: context,
      builder: (context) => _AccountingLinksDialog(
        initialFacturaLinks: group.quote.facturaLinks,
        initialPaymentLinks: group.quote.paymentLinks,
        onOpenLink: _openLink,
      ),
    );
    if (result == null || !mounted) return;
    final actor = ref.read(currentUserProfileProvider).value;
    setState(() => _savingLinks = true);
    try {
      await ref
          .read(purchaseOrderRepositoryProvider)
          .saveSupplierQuoteAccountingLinks(
            quote: group.quote,
            facturaLinks: result.facturaLinks,
            paymentLinks: result.paymentLinks,
            actor: actor,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Links contables guardados.')),
      );
    } catch (error, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reportError(
              error,
              stack,
              context: 'ContabilidadSupplierGroupsScreen.saveLinks',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingLinks = false);
    }
  }

  Future<void> _openLink(String raw) async {
    final normalized = _normalizeLink(raw);
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !uri.isAbsolute ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('El link no es valido.')));
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

class _AccountingLinksResult {
  const _AccountingLinksResult({
    required this.facturaLinks,
    required this.paymentLinks,
  });

  final List<String> facturaLinks;
  final List<String> paymentLinks;
}

class _AccountingLinksDialog extends StatefulWidget {
  const _AccountingLinksDialog({
    required this.initialFacturaLinks,
    required this.initialPaymentLinks,
    required this.onOpenLink,
  });

  final List<String> initialFacturaLinks;
  final List<String> initialPaymentLinks;
  final Future<void> Function(String raw) onOpenLink;

  @override
  State<_AccountingLinksDialog> createState() => _AccountingLinksDialogState();
}

class _AccountingLinksDialogState extends State<_AccountingLinksDialog> {
  late final TextEditingController _facturaController;
  late final TextEditingController _paymentController;
  late final List<String> _facturaLinks;
  late final List<String> _paymentLinks;

  @override
  void initState() {
    super.initState();
    _facturaController = TextEditingController();
    _paymentController = TextEditingController();
    _facturaLinks = List<String>.from(widget.initialFacturaLinks);
    _paymentLinks = List<String>.from(widget.initialPaymentLinks);
  }

  @override
  void dispose() {
    _facturaController.dispose();
    _paymentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _facturaLinks.isNotEmpty && _paymentLinks.isNotEmpty;
    return AlertDialog(
      title: const Text('Agregar links'),
      content: SizedBox(
        width: 720,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Captura minimo un link de factura y un link de pago. Puedes agregar varios de cada tipo.',
              ),
              const SizedBox(height: 16),
              _LinkBucketEditor(
                title: 'Links de factura',
                controller: _facturaController,
                links: _facturaLinks,
                hintText: 'Link de factura',
                emptyLabel: 'Aun no hay links de factura.',
                onAdd: _addFacturaLink,
                onOpenLink: widget.onOpenLink,
                onRemove: (link) =>
                    setState(() => _facturaLinks.remove(link)),
              ),
              const SizedBox(height: 16),
              _LinkBucketEditor(
                title: 'Links de pago',
                controller: _paymentController,
                links: _paymentLinks,
                hintText: 'Link de pago o recibo',
                emptyLabel: 'Aun no hay links de pago.',
                onAdd: _addPaymentLink,
                onOpenLink: widget.onOpenLink,
                onRemove: (link) =>
                    setState(() => _paymentLinks.remove(link)),
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
          onPressed: !canSave
              ? null
              : () => Navigator.pop(
                    context,
                    _AccountingLinksResult(
                      facturaLinks: List<String>.from(_facturaLinks),
                      paymentLinks: List<String>.from(_paymentLinks),
                    ),
                  ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  void _addFacturaLink() {
    final normalized = _validateLink(
      _facturaController.text,
      existing: _facturaLinks,
    );
    if (normalized == null) return;
    setState(() {
      _facturaLinks.add(normalized);
      _facturaController.clear();
    });
  }

  void _addPaymentLink() {
    final normalized = _validateLink(
      _paymentController.text,
      existing: _paymentLinks,
    );
    if (normalized == null) return;
    setState(() {
      _paymentLinks.add(normalized);
      _paymentController.clear();
    });
  }

  String? _validateLink(String raw, {required List<String> existing}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      _showMessage('Completa el link antes de agregarlo.');
      return null;
    }
    final normalized = _normalizeLink(trimmed);
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !uri.isAbsolute ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      _showMessage('El link no es valido.');
      return null;
    }
    if (existing.contains(normalized)) {
      _showMessage('Ese link ya fue agregado.');
      return null;
    }
    return normalized;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LinkBucketEditor extends StatelessWidget {
  const _LinkBucketEditor({
    required this.title,
    required this.controller,
    required this.links,
    required this.hintText,
    required this.emptyLabel,
    required this.onAdd,
    required this.onOpenLink,
    required this.onRemove,
  });

  final String title;
  final TextEditingController controller;
  final List<String> links;
  final String hintText;
  final String emptyLabel;
  final VoidCallback onAdd;
  final Future<void> Function(String raw) onOpenLink;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: hintText,
                    prefixIcon: const Icon(Icons.link),
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  onSubmitted: (_) => onAdd(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Agregar'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: links.isEmpty
                ? Center(child: Text(emptyLabel))
                : ListView(
                    children: [
                      for (final link in links)
                        Card(
                          child: ListTile(
                            title: Text(
                              link,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            leading: const Icon(Icons.link),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  tooltip: 'Abrir link',
                                  icon: const Icon(Icons.open_in_new),
                                  onPressed: () => onOpenLink(link),
                                ),
                                IconButton(
                                  tooltip: 'Quitar',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => onRemove(link),
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
    );
  }
}

String _normalizeLink(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme) return trimmed;
  return 'https://$trimmed';
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



