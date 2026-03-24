import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/domain/supplier_quote.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_pdf_thumbnail.dart';

import 'order_timeline.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({required this.orderId, super.key});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderByIdStreamProvider(orderId));
    final order = orderAsync.valueOrNull;

    if (orderAsync.isLoading && order == null) {
      return const Scaffold(body: AppSplash());
    }
    if (orderAsync.hasError && order == null) {
      return Scaffold(
        body: Center(
          child: Text(
            'Error: ${reportError(orderAsync.error!, orderAsync.stackTrace, context: 'OrderDetailScreen')}',
          ),
        ),
      );
    }
    if (order == null) {
      return const Scaffold(body: AppSplash());
    }
    final detailData = _buildOrderDetailData(order);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de orden'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _OrderSummaryHeader(order: order, compact: false),
          const SizedBox(height: 16),
          _OrderItemProgressSection(order: order),
          const SizedBox(height: 16),
          _OrderTimelineSection(order: order, orderId: orderId),
          const SizedBox(height: 16),
          _OrderPdfSection(order: order),
          const SizedBox(height: 16),
          _CotizacionSection(orderId: order.id),
          const SizedBox(height: 16),
          _FacturaSection(links: detailData.facturaLinks),
        ],
      ),
    );
  }
}

class _OrderSummaryHeader extends StatelessWidget {
  const _OrderSummaryHeader({
    required this.order,
    required this.compact,
  });

  final PurchaseOrder order;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final createdLabel = order.createdAt?.toFullDateTime() ?? 'Pendiente';
    final updatedLabel = order.updatedAt?.toFullDateTime();
    final folio = order.id; // Si existe otro folio, ajustalo aqui.
    final urgentJustification = (order.urgentJustification ?? '').trim();
    final requestedDeliveryDate = resolveRequestedDeliveryDate(order);

    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(label: Text(order.urgency.label)),
                if (order.urgency == PurchaseOrderUrgency.urgente &&
                    urgentJustification.isNotEmpty)
                  Chip(label: Text(urgentJustification)),
                Chip(label: Text(requesterReceiptStatusLabel(order))),
              ],
            ),
            const SizedBox(height: 12),

            Text(
              'Folio: $folio',
              style: theme.textTheme.titleMedium,
            ),

            const SizedBox(height: 8),
            Text(
              'Solicitante / Area: ${order.requesterName}${(order.areaName).trim().isNotEmpty ? ' | ${order.areaName}' : ''}',
              style: theme.textTheme.bodyMedium,
            ),
            if ((order.supplier ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Proveedor: ${order.supplier!.trim()}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (requestedDeliveryDate != null) ...[
              const SizedBox(height: 4),
              Text(
                'Fecha requerida: ${requestedDeliveryDate.toShortDate()}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Creada: $createdLabel',
              style: theme.textTheme.bodySmall,
            ),
            if (updatedLabel != null) ...[
              const SizedBox(height: 2),
              Text(
                'Actualizada: $updatedLabel',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OrderPdfSection extends StatelessWidget {
  const _OrderPdfSection({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    final pdfRoute = '/orders/${order.id}/pdf';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PDF de la orden', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            OrderPdfThumbnail(
              order: order,
              onTap: () => guardedPdfPush(context, pdfRoute),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => guardedPdfPush(context, pdfRoute),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Ver PDF'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CotizacionSection extends ConsumerWidget {
  const _CotizacionSection({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotesAsync = ref.watch(supplierQuotesByOrderIdProvider(orderId));
    final quotes = quotesAsync.valueOrNull ?? const <SupplierQuote>[];
    final hasLink = quotes.any((quote) => quote.links.isNotEmpty);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Compra', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (quotesAsync.isLoading && quotes.isEmpty)
              const AppSplash(compact: true)
            else if (hasLink)
              for (final quote in quotes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Proveedor: ${quote.supplier.trim().isEmpty ? 'Sin proveedor' : quote.supplier.trim()}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        'Estado: ${quote.status.label}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      for (final link in quote.links)
                        Text(
                          link,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                )
            else
              const Text('Sin link de compra.'),
            if (hasLink) ...[
              for (final quote in quotes)
                for (final link in quote.links) ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: () => _openExternalLink(context, link),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Abrir link'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
            ],
          ],
        ),
      ),
    );
  }
}

class _OrderItemProgressSection extends StatelessWidget {
  const _OrderItemProgressSection({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    final committedCount = countItemsWithCommittedDeliveryDate(order);
    final committedDate = resolveCommittedDeliveryDate(order);
    final arrivedCount = countArrivedItems(order);
    final pendingArrivalCount = countPendingArrivalItems(order);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Avance parcial por articulos',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Items con fecha estimada de entrega: $committedCount/${order.items.length}',
            ),
            const SizedBox(height: 4),
            Text(
              'Items llegados: $arrivedCount | Pendientes de llegada: $pendingArrivalCount',
            ),
            if (committedDate != null) ...[
              const SizedBox(height: 4),
              Text(
                'Ultima fecha estimada de entrega: ${committedDate.toShortDate()}',
              ),
            ],
            const SizedBox(height: 12),
            for (final item in order.items) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Item ${item.line}: ${item.description}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text('Proceso: ${_itemProgressLabel(order, item)}'),
                    if ((item.supplier ?? '').trim().isNotEmpty)
                      Text('Proveedor: ${item.supplier!.trim()}'),
                    if (item.estimatedDate != null)
                      Text(
                        'Fecha requerida: ${item.estimatedDate!.toShortDate()}',
                      ),
                    if (item.deliveryEtaDate != null)
                      Text(
                        'Fecha estimada de entrega: ${item.deliveryEtaDate!.toShortDate()}',
                      ),
                    if (item.arrivedAt != null)
                      Text(
                        'Llegada registrada: ${item.arrivedAt!.toFullDateTime()}',
                      ),
                    if (item.deliveryEtaDate != null || item.arrivedAt != null)
                      Text(itemArrivalComplianceLabel(item)),
                  ],
                ),
                trailing: Chip(
                  label: Text(_itemProgressLabel(order, item)),
                ),
              ),
              const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }
}

class _FacturaSection extends StatelessWidget {
  const _FacturaSection({required this.links});

  final List<String> links;

  @override
  Widget build(BuildContext context) {
    final hasLink = links.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Factura', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (hasLink)
              for (final link in links)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    link,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
            else
              const Text('Sin link de factura.'),
            if (hasLink) ...[
              for (final link in links) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () => _openExternalLink(context, link),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Abrir link'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _openExternalLink(BuildContext context, String raw) async {
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.isAbsolute) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('El link no es valido.')),
    );
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched && messenger.mounted) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No se pudo abrir el link.')),
    );
  }
}

class _OrderTimelineSection extends ConsumerWidget {
  const _OrderTimelineSection({
    required this.order,
    required this.orderId,
  });

  final PurchaseOrder order;
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(orderEventsProvider(orderId));
    return eventsAsync.when(
      data: (events) => OrderTimeline(order: order, events: events),
      loading: () => const SizedBox(height: 200, child: AppSplash()),
      error: (error, stack) => Text(
        'Error en timeline: ${reportError(error, stack, context: 'OrderDetailScreen')}',
      ),
    );
  }
}

String _itemProgressLabel(PurchaseOrder order, PurchaseOrderItem item) {
  if (item.isArrivalRegistered) {
    return 'Llego';
  }
  if (item.deliveryEtaDate != null) {
    return 'Pendiente de llegada';
  }
  if (order.status == PurchaseOrderStatus.eta) {
    return 'Finalizada';
  }
  if (order.status == PurchaseOrderStatus.contabilidad) {
    return 'En Contabilidad';
  }

  switch (item.quoteStatus) {
    case PurchaseOrderItemQuoteStatus.pending:
      if (order.status == PurchaseOrderStatus.pendingCompras) {
        return pendingRequirementAuthorizationLabel;
      }
      return 'Pendiente de compra';
    case PurchaseOrderItemQuoteStatus.draft:
      return 'En dashboard de compras';
    case PurchaseOrderItemQuoteStatus.pendingDireccion:
      return paymentAuthorizationLabel;
    case PurchaseOrderItemQuoteStatus.approved:
      return 'Aprobado, pendiente fecha estimada';
    case PurchaseOrderItemQuoteStatus.rejected:
      return 'Rechazado';
  }
}

List<String> _facturaLinks(PurchaseOrder order) {
  final links = <String>[];

  for (final url in order.facturaPdfUrls) {
    final trimmed = url.trim();
    if (trimmed.isNotEmpty) {
      links.add(trimmed);
    }
  }

  final single = order.facturaPdfUrl?.trim();
  if (single != null && single.isNotEmpty && !links.contains(single)) {
    links.insert(0, single);
  }

  return links;
}

_OrderDetailData _buildOrderDetailData(PurchaseOrder order) {
  return _OrderDetailData(
    facturaLinks: _facturaLinks(order),
  );
}

class _OrderDetailData {
  const _OrderDetailData({
    required this.facturaLinks,
  });

  final List<String> facturaLinks;
}
