import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/widgets/info_action.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_pdf_thumbnail.dart';

import 'order_timeline.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({required this.orderId, super.key});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderByIdProvider(orderId));
    final eventsAsync = ref.watch(orderEventsProvider(orderId));

    if (order == null) {
      return const Scaffold(body: AppSplash());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de orden'),
        actions: [
          infoAction(
            context,
            title: 'Detalle de orden',
            message:
                'Consulta el resumen y el timeline de eventos.\n'
                'Revisa PDFs, cotizaciones, facturas y almacen.\n'
                'Usa las secciones para abrir documentos.',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ✅ Reemplazo del widget corrupto:
          _OrderSummaryHeader(order: order, compact: false),

          eventsAsync.when(
            data: (events) => OrderTimeline(order: order, events: events),
            loading: () => const SizedBox(height: 200, child: AppSplash()),
            error: (error, stack) => Text(
              'Error en timeline: ${reportError(error, stack, context: 'OrderDetailScreen')}',
            ),
          ),
          const SizedBox(height: 16),
          _OrderPdfSection(order: order),
          const SizedBox(height: 16),
          _CotizacionSection(order: order),
          const SizedBox(height: 16),
          _FacturaSection(order: order),
          const SizedBox(height: 16),
          _AlmacenDiffSection(order: order),
        ],
      ),
    );
  }
}

/// Encabezado/resumen de la orden (reemplaza al widget cuyo nombre se corrompió).
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
    final folio = order.id; // si tienes un folio distinto, cámbialo aquí.

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
                Chip(label: Text(order.status.label)),
              ],
            ),
            const SizedBox(height: 12),

            Text(
              'Folio: $folio',
              style: theme.textTheme.titleMedium,
            ),

            const SizedBox(height: 8),
            Text(
              'Solicitante: ${order.requesterName}',
              style: theme.textTheme.bodyMedium,
            ),
            if ((order.areaName).trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Área: ${order.areaName}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if ((order.supplier ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Proveedor: ${order.supplier!.trim()}',
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
              onTap: () => guardedPush(context, pdfRoute),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => guardedPush(context, pdfRoute),
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

class _CotizacionSection extends StatelessWidget {
  const _CotizacionSection({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    final links = _cotizacionLinks(order);
    final hasLink = links.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cotización', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (hasLink)
              for (final link in links)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (link.supplier.trim().isNotEmpty)
                        Text(
                          'Proveedor: ${link.supplier.trim()}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      Text(link.url, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                )
            else
              const Text('Sin link de cotización.'),
            if (hasLink) ...[
              for (final link in links) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () => _openLink(context, link.url),
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

  Future<void> _openLink(BuildContext context, String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.isAbsolute) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El link no es válido.')),
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
}

class _FacturaSection extends StatelessWidget {
  const _FacturaSection({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    final links = _facturaLinks(order);
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
                    onPressed: () => _openLink(context, link),
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

  Future<void> _openLink(BuildContext context, String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.isAbsolute) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El link no es válido.')),
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
}

List<CotizacionLink> _cotizacionLinks(PurchaseOrder order) {
  if (order.cotizacionLinks.isNotEmpty) {
    return order.cotizacionLinks;
  }

  final links = <CotizacionLink>[];

  for (final url in order.cotizacionPdfUrls) {
    final trimmed = url.trim();
    if (trimmed.isNotEmpty) {
      links.add(CotizacionLink(supplier: '', url: trimmed));
    }
  }

  final single = order.cotizacionPdfUrl?.trim();
  if (single != null &&
      single.isNotEmpty &&
      !links.any((link) => link.url == single)) {
    links.insert(0, CotizacionLink(supplier: '', url: single));
  }

  return links;
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

class _AlmacenDiffSection extends StatelessWidget {
  const _AlmacenDiffSection({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    final diffs = _itemDiffs(order.items);
    final hasReceived = order.items.any((item) => item.receivedQuantity != null);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recepción en almacén',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (!hasReceived)
              const Text('Sin recepción registrada.')
            else if (diffs.isEmpty)
              const Text('Sin diferencias registradas.')
            else
              Column(
                children: [
                  for (final diff in diffs) ...[
                    _DiffRow(diff: diff),
                    if (diff != diffs.last) const SizedBox(height: 8),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({required this.diff});

  final _ItemDiff diff;

  @override
  Widget build(BuildContext context) {
    final diffLabel = diff.delta > 0 ? '+${diff.delta}' : diff.delta.toString();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(diff.title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text('Solicitado: ${diff.requested} ${diff.unit}'),
            Text('Recibido: ${diff.received} ${diff.unit}'),
            Text('Diferencia: $diffLabel'),
            if (diff.comment.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Comentario: ${diff.comment}'),
            ],
          ],
        ),
      ),
    );
  }
}

List<_ItemDiff> _itemDiffs(List<PurchaseOrderItem> items) {
  final diffs = <_ItemDiff>[];

  for (final item in items) {
    final received = item.receivedQuantity;
    if (received == null) continue;

    final delta = received - item.quantity;
    if (delta == 0) continue;

    diffs.add(
      _ItemDiff(
        title: 'Item ${item.line}: ${item.description}',
        unit: item.unit,
        requested: item.quantity,
        received: received,
        delta: delta,
        comment: (item.receivedComment ?? '').trim(),
      ),
    );
  }

  return diffs;
}

class _ItemDiff {
  _ItemDiff({
    required this.title,
    required this.unit,
    required this.requested,
    required this.received,
    required this.delta,
    required this.comment,
  });

  final String title;
  final String unit;
  final num requested;
  final num received;
  final num delta;
  final String comment;
}
