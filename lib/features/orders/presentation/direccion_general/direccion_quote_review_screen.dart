import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistema_compras/core/area_labels.dart';
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
import 'package:sistema_compras/features/orders/domain/supplier_quote_history_entry.dart';
import 'package:sistema_compras/features/orders/presentation/preview/supplier_quote_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/supplier_quote_pdf_view_screen.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:url_launcher/url_launcher.dart';

class DireccionQuoteReviewScreen extends ConsumerStatefulWidget {
  const DireccionQuoteReviewScreen({required this.quoteId, super.key});

  final String quoteId;

  @override
  ConsumerState<DireccionQuoteReviewScreen> createState() =>
      _DireccionQuoteReviewScreenState();
}

class _DireccionQuoteReviewScreenState
    extends ConsumerState<DireccionQuoteReviewScreen> {
  bool _isBusy = false;
  String? _scheduledPdfCacheKey;

  @override
  Widget build(BuildContext context) {
    final quoteAsync = ref.watch(supplierQuoteByIdProvider(widget.quoteId));
    final historyAsync = ref.watch(supplierQuoteHistoryProvider(widget.quoteId));
    final ordersAsync = ref.watch(operationalOrdersProvider);
    final actor = ref.watch(currentUserProfileProvider).value;
    final branding = ref.watch(currentBrandingProvider);
    final canAuthorize = actor != null && _canAuthorizeQuote(actor);

    return Scaffold(
      appBar: AppBar(title: const Text('Revisar ordenes')),
      body: quoteAsync.when(
        data: (quote) {
          if (quote == null) {
            return const Center(child: Text('Cotizacion no disponible.'));
          }

          return ordersAsync.when(
            data: (orders) {
              final viewData = _buildViewData(quote, orders);
              final pdfData = SupplierQuotePdfData(
                branding: branding,
                quoteId: quote.displayId,
                supplier: quote.supplier,
                links: quote.links,
                orders: [for (final order in viewData.orders) order.toPdfData()],
                comprasComment: quote.comprasComment,
                createdAt: quote.createdAt,
                processedByName: quote.processedByName,
                processedByArea: quote.processedByArea,
                authorizedByName: quote.approvedByName ?? actor?.name,
                authorizedByArea: quote.approvedByArea ?? actor?.areaDisplay,
              );
              _schedulePdfCache(pdfData);

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    quote.supplier,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text('Folio ${quote.displayId}')),
                      Chip(label: Text(quote.status.label)),
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
                      'Monto total a pagar de esta cotizacion: ${_money(viewData.totalAmount)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Links de cotizacion',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (quote.links.isEmpty)
                    const Text('Sin links registrados.')
                  else
                    for (final link in quote.links) ...[
                      Text(link),
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
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => SupplierQuotePdfViewScreen(data: pdfData),
                        ),
                      ),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Ver PDF'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Historial de cotizacion',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  historyAsync.when(
                    data: (entries) => _QuoteHistoryCard(entries: entries),
                    loading: () => const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Cargando historial...'),
                      ),
                    ),
                    error: (error, stack) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          reportError(
                            error,
                            stack,
                            context: 'DireccionQuoteReview.history',
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Ordenes de esta cotizacion',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final order in viewData.orders) ...[
                    _QuoteOrderCard(order: order),
                    const SizedBox(height: 12),
                  ],
                  if (canAuthorize)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isBusy ? null : () => _rejectQuote(quote),
                            child: const Text('Rechazar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _isBusy ? null : () => _approveQuote(quote),
                            child: const Text('Autorizar'),
                          ),
                        ),
                      ],
                    ),
                ],
              );
            },
            loading: () => const AppSplash(),
            error: (error, stack) => Center(
              child: Text(
                reportError(error, stack, context: 'DireccionQuoteReview.orders'),
              ),
            ),
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            reportError(error, stack, context: 'DireccionQuoteReviewScreen'),
          ),
        ),
      ),
    );
  }

  Future<void> _approveQuote(SupplierQuote quote) async {
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) {
      _showMessage('Perfil no disponible.');
      return;
    }
    if (!_canAuthorizeQuote(actor)) {
      _showMessage('Solo Direccion General puede autorizar esta cotizacion.');
      return;
    }
    setState(() => _isBusy = true);
    try {
      await ref.read(purchaseOrderRepositoryProvider).approveSupplierQuote(
            quote: quote,
            actor: actor,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      _showMessage('Cotizacion autorizada.');
    } catch (error, stack) {
      _showMessage(reportError(error, stack, context: 'DireccionQuoteReview.approve'));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _rejectQuote(SupplierQuote quote) async {
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) {
      _showMessage('Perfil no disponible.');
      return;
    }
    if (!_canAuthorizeQuote(actor)) {
      _showMessage('Solo Direccion General puede rechazar esta cotizacion.');
      return;
    }
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rechazar cotizacion'),
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
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    setState(() => _isBusy = true);
    try {
      await ref.read(purchaseOrderRepositoryProvider).rejectSupplierQuote(
            quote: quote,
            comment: controller.text,
            actor: actor,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      _showMessage('Cotizacion rechazada.');
    } catch (error, stack) {
      _showMessage(reportError(error, stack, context: 'DireccionQuoteReview.reject'));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _openLink(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.isAbsolute) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _schedulePdfCache(SupplierQuotePdfData data) {
    final cacheKey = supplierQuotePdfCacheKey(data);
    if (_scheduledPdfCacheKey == cacheKey) return;
    _scheduledPdfCacheKey = cacheKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _scheduledPdfCacheKey != cacheKey) return;
      cacheSupplierQuotePdfs([data], limit: 1);
    });
  }
}

class _QuoteReviewViewData {
  const _QuoteReviewViewData({required this.orders});

  final List<_QuoteReviewOrderData> orders;

  num get totalAmount {
    var total = 0.0;
    for (final order in orders) {
      total += order.selectedTotal.toDouble();
    }
    return total;
  }
}

class _QuoteReviewOrderData {
  const _QuoteReviewOrderData({
    required this.orderId,
    required this.requesterName,
    required this.areaName,
    required this.items,
  });

  final String orderId;
  final String requesterName;
  final String areaName;
  final List<_QuoteReviewItemData> items;

  num get orderTotal {
    var total = 0.0;
    for (final item in items) {
      final amount = item.amount;
      if (amount != null) total += amount.toDouble();
    }
    return total;
  }

  num get selectedTotal {
    var total = 0.0;
    for (final item in items) {
      if (!item.selected) continue;
      final amount = item.amount;
      if (amount != null) total += amount.toDouble();
    }
    return total;
  }

  SupplierQuotePdfOrderData toPdfData() {
    return SupplierQuotePdfOrderData(
      orderId: orderId,
      requesterName: requesterName,
      areaName: areaName,
      items: [for (final item in items) item.toPdfData()],
    );
  }
}

class _QuoteReviewItemData {
  const _QuoteReviewItemData({
    required this.line,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.selected,
    this.partNumber,
    this.customer,
    this.amount,
  });

  final int line;
  final String description;
  final num quantity;
  final String unit;
  final bool selected;
  final String? partNumber;
  final String? customer;
  final num? amount;

  SupplierQuotePdfItemData toPdfData() {
    return SupplierQuotePdfItemData(
      line: line,
      description: description,
      quantity: quantity,
      unit: unit,
      selected: selected,
      partNumber: partNumber,
      customer: customer,
      amount: amount,
    );
  }
}

class _QuoteHistoryCard extends StatelessWidget {
  const _QuoteHistoryCard({required this.entries});

  final List<SupplierQuoteHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Aun no hay snapshots guardados para esta cotizacion.'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Versiones guardadas',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            for (var index = 0; index < entries.length; index++) ...[
              _QuoteHistoryEntryTile(entry: entries[index]),
              if (index != entries.length - 1) const Divider(height: 24),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuoteHistoryEntryTile extends StatelessWidget {
  const _QuoteHistoryEntryTile({required this.entry});

  final SupplierQuoteHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actorParts = <String>[
      if ((entry.actorName ?? '').trim().isNotEmpty) entry.actorName!.trim(),
      if ((entry.actorArea ?? '').trim().isNotEmpty) entry.actorArea!.trim(),
    ];
    final orderLabels = <String>{
      for (final order in entry.orders)
        if (order.orderId.trim().isNotEmpty) order.orderId.trim(),
      for (final orderId in entry.orderIds)
        if (orderId.trim().isNotEmpty) orderId.trim(),
    }.toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text(entry.eventLabel)),
            Chip(label: Text('Version ${entry.version}')),
            Chip(label: Text(entry.status.label)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _formatHistoryTimestamp(entry.timestamp),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text('Monto snapshot: ${_money(entry.totalAmount)}'),
        Text('${entry.itemCount} item(s) · ${entry.orderCount} orden(es)'),
        if (actorParts.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Movimiento por: ${actorParts.join(' · ')}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if ((entry.comment ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            entry.comment!.trim(),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (orderLabels.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Ordenes asociadas',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final orderId in orderLabels) Chip(label: Text(orderId)),
            ],
          ),
        ],
      ],
    );
  }
}

String _money(num value) {
  return '\$${value.toDouble().toStringAsFixed(2)}';
}

String _formatHistoryTimestamp(DateTime? value) {
  if (value == null) return 'Sin fecha';
  return value.toFullDateTime();
}

_QuoteReviewViewData _buildViewData(
  SupplierQuote quote,
  List<PurchaseOrder> allOrders,
) {
  final refsByOrder = <String, Map<int, SupplierQuoteItemRef>>{};
  for (final ref in quote.items) {
    refsByOrder.putIfAbsent(ref.orderId, () => <int, SupplierQuoteItemRef>{})[ref.line] = ref;
  }

  final orders = <_QuoteReviewOrderData>[];
  for (final order in allOrders) {
    final refs = refsByOrder[order.id];
    if (refs == null || refs.isEmpty) continue;

    final items = <_QuoteReviewItemData>[];
    for (final item in order.items) {
      final selectedRef = refs[item.line];
      items.add(
        _QuoteReviewItemData(
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
      _QuoteReviewOrderData(
        orderId: order.id,
        requesterName: order.requesterName,
        areaName: order.areaName,
        items: items,
      ),
    );
  }

  orders.sort((a, b) => a.orderId.compareTo(b.orderId));
  return _QuoteReviewViewData(orders: orders);
}

class _QuoteOrderCard extends StatelessWidget {
  const _QuoteOrderCard({required this.order});

  final _QuoteReviewOrderData order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Orden ${order.orderId}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('${order.requesterName} | ${order.areaName}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    'Total orden: ${order.orderTotal.toDouble().toStringAsFixed(2)}',
                  ),
                ),
                Chip(
                  label: Text(
                    'Total en esta cotizacion: ${order.selectedTotal.toDouble().toStringAsFixed(2)}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final item in order.items) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: item.selected
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: item.selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Item ${item.line}: ${item.description}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: item.selected
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.quantity} ${item.unit}  ${item.partNumber ?? ''}'.trim(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: item.selected
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.selected
                          ? 'Monto en esta cotizacion: ${item.amount?.toDouble().toStringAsFixed(2) ?? '0.00'}'
                          : 'Fuera de esta cotizacion',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: item.selected ? FontWeight.w600 : FontWeight.w400,
                        color: item.selected
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

bool _canAuthorizeQuote(AppUser actor) {
  return isAdminRole(actor.role) || isDireccionGeneralLabel(actor.areaDisplay);
}
