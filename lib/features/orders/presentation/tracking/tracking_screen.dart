import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_timeline.dart';

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  String? selectedOrderId;

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(userOrdersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(trackingButtonLabel)),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('No hay �rdenes para mostrar.'));
          }
          selectedOrderId ??= orders.first.id;
          final current = orders.firstWhere((order) => order.id == selectedOrderId);
          final eventsAsync = ref.watch(orderEventsProvider(current.id));

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                value: selectedOrderId,
                decoration: const InputDecoration(labelText: 'Selecciona orden'),
                items: orders
                    .map(
                      (order) => DropdownMenuItem(
                        value: order.id,
                        child: Text(order.folio ?? order.id.substring(0, 6)),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => selectedOrderId = value),
              ),
              const SizedBox(height: 16),
              _TrackingSummary(order: current),
              const SizedBox(height: 16),
              eventsAsync.when(
                data: (events) => OrderTimeline(order: current, events: events),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Text('Error: $error'),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => context.push('/orders/${current.id}'),
                child: const Text('Ver detalle completo'),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
    );
  }
}

class _TrackingSummary extends StatelessWidget {
  const _TrackingSummary({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(order.folio ?? 'Sin folio',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Estado actual: ${order.status.label}'),
            if (order.updatedAt != null)
              Text('�ltima actualizaci�n: ${order.updatedAt!.toFullDateTime()}'),
            Text('Urgencia: ${order.urgency.label}'),
          ],
        ),
      ),
    );
  }
}
