import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'order_timeline.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({required this.orderId, super.key});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderByIdProvider(orderId));
    final eventsAsync = ref.watch(orderEventsProvider(orderId));

    if (order == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: Text(order.folio ?? 'Detalle')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _OrderSummary(order: order),
          const SizedBox(height: 16),
          eventsAsync.when(
            data: (events) => OrderTimeline(order: order, events: events),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Text('Error en timeline: $error'),
          ),
          const SizedBox(height: 16),
          if (order.lastReturnReason != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Devuelta con comentario: ${order.lastReturnReason}'),
              ),
            ),
          const SizedBox(height: 16),
          Text('Items', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...order.items.map(
            (item) => Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${item.line}. ${item.description}',
                        style: Theme.of(context).textTheme.titleMedium),
                    Text('No. parte: ${item.partNumber}'),
                    Text('Cantidad: ${item.quantity} ${item.unit}'),
                    Text('Piezas requeridas: ${item.pieces}'),
                    if (item.customer?.isNotEmpty ?? false)
                      Text('Cliente: ${item.customer}'),
                    if (item.estimatedDate != null)
                      Text('Entrega estimada: ${item.estimatedDate!.toShortDate()}'),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (order.pdfUrl != null)
            FilledButton.icon(
              onPressed: () async {
                final uri = Uri.parse(order.pdfUrl!);
                final messenger = ScaffoldMessenger.of(context);
                final opened = await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
                if (!opened) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('No se pudo abrir el PDF')),
                  );
                }
              },
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Ver PDF generado'),
            ),
        ],
      ),
    );
  }
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(order.requesterName, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Área: ${order.areaName}'),
            Text('Urgencia: ${order.urgency.label}'),
            Text('Estado actual: ${order.status.label}'),
            if (order.createdAt != null)
              Text('Creada: ${order.createdAt!.toFullDateTime()}'),
          ],
        ),
      ),
    );
  }
}
