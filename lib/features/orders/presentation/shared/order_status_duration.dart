import 'package:flutter/material.dart';
import 'package:sistema_compras/core/constants.dart';

import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';

/// Muestra cuánto tiempo lleva la orden en su estado actual.
/// Heurística: usa updatedAt como "desde", si no, createdAt.
class OrderStatusDuration extends StatelessWidget {
  const OrderStatusDuration({
    super.key,
    required this.order,
    this.compact = true,
    this.prefix,
  });

  final PurchaseOrder order;
  final bool compact;
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    final since = order.updatedAt ?? order.createdAt;
    if (since == null) {
      return Text(
        '${prefix ?? ''}Estado: ${order.status.label} (sin fecha)',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final now = DateTime.now();
    var diff = now.difference(since);
    if (diff.isNegative) diff = Duration.zero;

    final durationLabel = _formatDuration(diff);

    if (compact) {
      return Text(
        '${prefix ?? ''}Estado: ${order.status.label} • $durationLabel',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${prefix ?? ''}Estado: ${order.status.label}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 2),
        Text(
          'Desde: ${since.toFullDateTime()} • $durationLabel',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final totalMinutes = d.inMinutes;
    if (totalMinutes <= 0) return 'hace < 1 min';

    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;

    if (days > 0) {
      final dayLabel = days == 1 ? 'día' : 'días';
      final hourPart = hours > 0 ? ' $hours h' : '';
      return 'hace $days $dayLabel$hourPart';
    }
    if (hours > 0) {
      final minPart = minutes > 0 ? ' $minutes min' : '';
      return 'hace $hours h$minPart';
    }
    return 'hace $minutes min';
  }
}

/// ---------------------------------------------------------------------------
/// Compatibilidad: en varios de tus archivos tienes estos “nombres raros”.
/// Para que NO tengas que reemplazar todo ahorita, los dejamos como alias.
/// ---------------------------------------------------------------------------

class OrahJ91ZuNL8Y2px8iYciYeHN8sfSh5eXH8 extends OrderStatusDuration {
  const OrahJ91ZuNL8Y2px8iYciYeHN8sfSh5eXH8({
    super.key,
    required super.order,
    super.compact = true,
    super.prefix,
  });
}

class PrMq6aNvWB9RmWRCbyBDeDQD9oy469anXH8 extends OrderStatusDuration {
  const PrMq6aNvWB9RmWRCbyBDeDQD9oy469anXH8({
    super.key,
    required super.order,
    super.compact = true,
    super.prefix,
  });
}
