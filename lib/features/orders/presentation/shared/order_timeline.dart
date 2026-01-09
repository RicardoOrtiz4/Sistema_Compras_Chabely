import 'package:flutter/material.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';

class OrderTimeline extends StatelessWidget {
  const OrderTimeline({required this.order, required this.events, super.key});

  final PurchaseOrder order;
  final List<PurchaseOrderEvent> events;

  @override
  Widget build(BuildContext context) {
    final statuses = List<PurchaseOrderStatus>.from(defaultStatusFlow);
    var currentIndex = -1;
    for (final event in events) {
      final index = statuses.indexWhere((status) => status == event.toStatus);
      if (index > currentIndex) {
        currentIndex = index;
      }
    }
    final fallbackIndex = statuses.indexWhere((status) => status == order.status);
    if (fallbackIndex > currentIndex) {
      currentIndex = fallbackIndex;
    }
    return Column(
      children: [
        for (var i = 0; i < statuses.length; i++)
          _TimelineTile(
            status: statuses[i],
            isCompleted: currentIndex >= 0 && i <= currentIndex,
            isLast: i == statuses.length - 1,
            event: _eventForStatus(statuses[i]),
          ),
      ],
    );
  }

  PurchaseOrderEvent? _eventForStatus(PurchaseOrderStatus status) {
    for (final event in events) {
      if (event.toStatus == status) {
        return event;
      }
    }
    return null;
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.status,
    required this.isCompleted,
    required this.isLast,
    this.event,
  });

  final PurchaseOrderStatus status;
  final bool isCompleted;
  final bool isLast;
  final PurchaseOrderEvent? event;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isCompleted ? status.statusColor(scheme) : scheme.outlineVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(status.icon, color: color),
            if (!isLast)
              Container(
                width: 2,
                height: 48,
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: color,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card(
            color:
                isCompleted ? color.withValues(alpha: color.a * 0.1) : Theme.of(context).cardColor,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(status.label, style: Theme.of(context).textTheme.titleMedium),
                  if (event?.timestamp != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(event!.timestamp!.toFullDateTime(),
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  if (event?.byRole != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Rol: ${event!.byRole}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  if (event?.comment != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Comentario: ${event!.comment}'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}



