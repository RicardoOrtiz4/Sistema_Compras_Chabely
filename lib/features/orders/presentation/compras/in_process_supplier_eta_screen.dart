import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/domain/supplier_quote.dart';
import 'package:sistema_compras/features/orders/presentation/compras/supplier_eta_order_preview_screen.dart';
import 'package:sistema_compras/features/orders/presentation/preview/supplier_quote_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/supplier_quote_pdf_view_screen.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_status_duration.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_urgency_controls.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

class InProcessSupplierEtaScreen extends ConsumerStatefulWidget {
  const InProcessSupplierEtaScreen({super.key});

  @override
  ConsumerState<InProcessSupplierEtaScreen> createState() =>
      _InProcessSupplierEtaScreenState();
}

class _InProcessSupplierEtaScreenState
    extends ConsumerState<InProcessSupplierEtaScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isBusy = false;
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
    if (_searchQuery.isEmpty && _searchController.text.isEmpty) return;
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
    final actor = ref.watch(currentUserProfileProvider).value;
    final branding = ref.watch(currentBrandingProvider);
    final compactAppBar = useCompactOrderModuleAppBar(context);

    final titleGroups = _visibleApprovedEtaGroups(
      quotes: quotesAsync.valueOrNull ?? const <SupplierQuote>[],
      allOrders: ordersAsync.valueOrNull ?? const <PurchaseOrder>[],
      query: _searchQuery,
      filter: _urgencyFilter,
      range: _createdDateRangeFilter,
    );
    final titleCounts = _etaGroupUrgencyCounts(titleGroups);

    return Scaffold(
      appBar: AppBar(
        title: compactAppBar
            ? const Text('En proceso')
            : OrderModuleAppBarTitle(
                title: 'En proceso',
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
            final groups = _visibleApprovedEtaGroups(
              quotes: quotes,
              allOrders: orders,
              query: _searchQuery,
              filter: _urgencyFilter,
              range: _createdDateRangeFilter,
            );

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _EtaFiltersBar(
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
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No hay proveedores pendientes de envio a Contabilidad.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  )
                else
                  for (final group in groups) ...[
                    _ApprovedEtaGroupCard(
                      group: group,
                      allOrders: orders,
                      branding: branding,
                      actor: actor,
                      isBusy: _isBusy,
                      onSendToContabilidad: (selectedLinesByOrder, etaDate) =>
                          _sendToContabilidad(
                        quote: group.quote,
                        actor: actor,
                        selectedLinesByOrder: selectedLinesByOrder,
                        etaDate: etaDate,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            );
          },
          loading: () => const AppSplash(),
          error: (error, stack) => _ErrorText(
            message: reportError(
              error,
              stack,
              context: 'InProcessSupplierEtaScreen.orders',
            ),
          ),
        ),
        loading: () => const AppSplash(),
        error: (error, stack) => _ErrorText(
          message: reportError(
            error,
            stack,
            context: 'InProcessSupplierEtaScreen.quotes',
          ),
        ),
      ),
    );
  }

  Future<void> _sendToContabilidad({
    required SupplierQuote quote,
    required AppUser? actor,
    required Map<String, Set<int>> selectedLinesByOrder,
    required DateTime etaDate,
  }) async {
    if (_isBusy) return;
    if (actor == null) {
      _showMessage('Perfil no disponible.');
      return;
    }
    if (selectedLinesByOrder.isEmpty) {
      _showMessage('Selecciona al menos un item.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enviar a Contabilidad'),
        content: Text(
          'Se enviaran a Contabilidad los items seleccionados del proveedor '
          '${quote.supplier.trim().isEmpty ? quote.displayId : quote.supplier.trim()} '
          'con fecha ${etaDate.toShortDate()}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isBusy = true);
    try {
      await ref.read(purchaseOrderRepositoryProvider).sendSupplierQuoteItemsToContabilidad(
            quote: quote,
            etaDate: etaDate,
            actor: actor,
            selectedLinesByOrder: selectedLinesByOrder,
          );
      _showMessage('Items enviados a Contabilidad.');
    } catch (error, stack) {
      _showMessage(
        reportError(
          error,
          stack,
          context: 'InProcessSupplierEtaScreen.sendToContabilidad',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _EtaFiltersBar extends StatelessWidget {
  const _EtaFiltersBar({
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
            labelText: 'Buscar por proveedor, folio, solicitante o item...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: searchQuery.isEmpty
                ? null
                : IconButton(
                    onPressed: onClearSearch,
                    icon: const Icon(Icons.clear),
                  ),
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

class _ApprovedEtaGroupCard extends StatefulWidget {
  const _ApprovedEtaGroupCard({
    required this.group,
    required this.allOrders,
    required this.branding,
    required this.actor,
    required this.isBusy,
    required this.onSendToContabilidad,
  });

  final _ApprovedEtaGroup group;
  final List<PurchaseOrder> allOrders;
  final CompanyBranding branding;
  final AppUser? actor;
  final bool isBusy;
  final Future<void> Function(Map<String, Set<int>>, DateTime)
      onSendToContabilidad;

  @override
  State<_ApprovedEtaGroupCard> createState() => _ApprovedEtaGroupCardState();
}

class _ApprovedEtaGroupCardState extends State<_ApprovedEtaGroupCard> {
  final Set<String> _selectedKeys = <String>{};
  DateTime? _selectedEtaDate;

  String _itemKey(_ApprovedEtaItem entry) => '${entry.order.id}::${entry.item.line}';

  bool _isSelected(_ApprovedEtaItem entry) => _selectedKeys.contains(_itemKey(entry));

  Map<String, Set<int>> _selectedLinesByOrder() {
    final selected = <String, Set<int>>{};
    for (final entry in widget.group.items) {
      if (!_isSelected(entry)) continue;
      selected.putIfAbsent(entry.order.id, () => <int>{}).add(entry.item.line);
    }
    return selected;
  }

  Future<void> _pickEtaDate() async {
    if (_selectedKeys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona uno o mas items primero.')),
      );
      return;
    }
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
      initialDate: _selectedEtaDate ?? now,
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedEtaDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = widget.group;
    final selectedCount = _selectedKeys.length;
    final quotePdfData = _buildSupplierQuotePdfData(
      quote: group.quote,
      allOrders: widget.allOrders,
      branding: widget.branding,
      actor: widget.actor,
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  group.quote.supplier.trim().isEmpty
                      ? 'Proveedor sin nombre'
                      : group.quote.supplier.trim(),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Chip(label: Text(group.quote.status.label)),
            ],
          ),
          const SizedBox(height: 6),
          Text('$selectedCount/${group.items.length} item(s) seleccionados · ${group.orders.length} orden(es)'),
          const SizedBox(height: 8),
          PreviousStatusDurationPill(
            orderIds: [for (final order in group.orders) order.id],
            fromStatus: PurchaseOrderStatus.authorizedGerencia,
            toStatus: PurchaseOrderStatus.paymentDone,
            label: 'Tiempo en Direccion General',
            alignRight: false,
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Seleccion y fecha estimada',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$selectedCount/${group.items.length} item(s) listos',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (_selectedEtaDate != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Fecha a aplicar: ${_selectedEtaDate!.toShortDate()}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ordenes relacionadas',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final order in group.orders)
                FilledButton.tonalIcon(
                  onPressed: _selectedEtaDate == null
                      ? null
                      : () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => SupplierEtaOrderPreviewScreen(
                                order: order,
                                etaDate: _selectedEtaDate!,
                              ),
                            ),
                          ),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(order.id),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Items pendientes',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          for (final entry in group.items) ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _isSelected(entry),
              onChanged: widget.isBusy
                  ? null
                  : (value) {
                      setState(() {
                        final key = _itemKey(entry);
                        if (value == true) {
                          _selectedKeys.add(key);
                        } else {
                          _selectedKeys.remove(key);
                        }
                      });
                    },
              title: Text(entry.item.description),
              subtitle: Text('Orden ${entry.order.id} · ${entry.order.requesterName}'),
              secondary: entry.item.deliveryEtaDate == null
                  ? const Chip(label: Text('Sin fecha'))
                  : Chip(label: Text(entry.item.deliveryEtaDate!.toShortDate())),
            ),
            const Divider(height: 1),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => SupplierQuotePdfViewScreen(data: quotePdfData),
                  ),
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Ver PDF general'),
              ),
              OutlinedButton.icon(
                onPressed: widget.isBusy ? null : _pickEtaDate,
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  _selectedEtaDate == null
                      ? 'Definir fecha estimada'
                      : 'Cambiar fecha estimada',
                ),
              ),
              FilledButton.icon(
                onPressed: widget.isBusy || _selectedEtaDate == null || selectedCount == 0
                    ? null
                    : () => widget.onSendToContabilidad(
                          _selectedLinesByOrder(),
                          _selectedEtaDate!,
                        ),
                icon: const Icon(Icons.forward_to_inbox_outlined),
                label: const Text('Enviar a Contabilidad'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(message));
  }
}

class _ApprovedEtaGroup {
  const _ApprovedEtaGroup({
    required this.quote,
    required this.orders,
    required this.items,
  });

  final SupplierQuote quote;
  final List<PurchaseOrder> orders;
  final List<_ApprovedEtaItem> items;

  int get itemsWithEta =>
      items.where((entry) => entry.item.deliveryEtaDate != null).length;
}

class _ApprovedEtaItem {
  const _ApprovedEtaItem({
    required this.order,
    required this.item,
  });

  final PurchaseOrder order;
  final PurchaseOrderItem item;
}

List<_ApprovedEtaGroup> _visibleApprovedEtaGroups({
  required List<SupplierQuote> quotes,
  required List<PurchaseOrder> allOrders,
  required String query,
  required OrderUrgencyFilter filter,
  required DateTimeRange? range,
}) {
  final groups = <_ApprovedEtaGroup>[];
  for (final quote in quotes) {
    if (quote.status != SupplierQuoteStatus.approved) continue;
    final group = _buildApprovedEtaGroup(quote, allOrders);
    if (group == null) continue;
    if (!_matchesApprovedEtaFilters(
      group: group,
      query: query,
      filter: filter,
      range: range,
    )) {
      continue;
    }
    groups.add(group);
  }

  groups.sort((a, b) {
    final aTime = a.quote.updatedAt?.millisecondsSinceEpoch ??
        a.quote.createdAt?.millisecondsSinceEpoch ??
        0;
    final bTime = b.quote.updatedAt?.millisecondsSinceEpoch ??
        b.quote.createdAt?.millisecondsSinceEpoch ??
        0;
    return bTime.compareTo(aTime);
  });
  return groups;
}

_ApprovedEtaGroup? _buildApprovedEtaGroup(
  SupplierQuote quote,
  List<PurchaseOrder> allOrders,
) {
  final ordersById = {
    for (final order in allOrders) order.id: order,
  };
  final relatedOrders = <PurchaseOrder>[];
  final relatedItems = <_ApprovedEtaItem>[];

  for (final orderId in quote.orderIds) {
    final order = ordersById[orderId];
    if (order == null || order.status == PurchaseOrderStatus.eta) {
      continue;
    }
    final quoteItems = order.items
        .where(
          (item) =>
              (item.quoteId?.trim() ?? '') == quote.id &&
              item.quoteStatus == PurchaseOrderItemQuoteStatus.approved &&
              item.sentToContabilidadAt == null,
        )
        .toList(growable: false);
    if (quoteItems.isEmpty) continue;
    relatedOrders.add(order);
    for (final item in quoteItems) {
      relatedItems.add(_ApprovedEtaItem(order: order, item: item));
    }
  }

  if (relatedOrders.isEmpty || relatedItems.isEmpty) {
    return null;
  }

  relatedOrders.sort((a, b) => a.id.compareTo(b.id));
  return _ApprovedEtaGroup(
    quote: quote,
    orders: relatedOrders,
    items: relatedItems,
  );
}

bool _matchesApprovedEtaFilters({
  required _ApprovedEtaGroup group,
  required String query,
  required OrderUrgencyFilter filter,
  required DateTimeRange? range,
}) {
  if (!_approvedEtaGroupMatchesSearch(group, query)) {
    return false;
  }
  final urgencyMatches = switch (filter) {
    OrderUrgencyFilter.all => true,
    OrderUrgencyFilter.normal => group.orders.every(
        (order) => order.urgency == PurchaseOrderUrgency.normal,
      ),
    OrderUrgencyFilter.urgente => group.orders.any(
        (order) => order.urgency == PurchaseOrderUrgency.urgente,
      ),
  };
  if (!urgencyMatches) return false;
  if (range == null) return true;

  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day);
  return group.orders.any((order) {
    final createdAt = order.createdAt;
    if (createdAt == null) return false;
    final createdDate =
        DateTime(createdAt.year, createdAt.month, createdAt.day);
    return !createdDate.isBefore(start) && !createdDate.isAfter(end);
  });
}

bool _approvedEtaGroupMatchesSearch(_ApprovedEtaGroup group, String query) {
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
    addValue(order.urgency.label);
    addValue(order.clientNote);
  }
  for (final item in group.items) {
    addValue(item.item.description);
    addValue(item.item.partNumber);
    addValue(item.item.customer);
  }

  final haystack = buffer.toString();
  final tokens = normalized
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty);
  for (final token in tokens) {
    if (!haystack.contains(token)) return false;
  }
  return true;
}

OrderUrgencyCounts _etaGroupUrgencyCounts(List<_ApprovedEtaGroup> groups) {
  var normal = 0;
  var urgente = 0;
  for (final group in groups) {
    final hasUrgent = group.orders.any(
      (order) => order.urgency == PurchaseOrderUrgency.urgente,
    );
    if (hasUrgent) {
      urgente += 1;
    } else {
      normal += 1;
    }
  }
  return OrderUrgencyCounts(
    total: groups.length,
    normal: normal,
    urgente: urgente,
  );
}

SupplierQuotePdfData _buildSupplierQuotePdfData({
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
