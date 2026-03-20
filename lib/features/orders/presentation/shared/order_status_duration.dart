import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistema_compras/core/constants.dart';

import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
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
    final since = order.statusEnteredAt ?? order.updatedAt ?? order.createdAt;
    if (since == null) {
      return Text(
        '${prefix ?? ''}Estado: ${order.status.label} (sin fecha)',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final now = DateTime.now();
    var diff = now.difference(since);
    if (diff.isNegative) diff = Duration.zero;

    final durationLabel = formatDurationLabel(diff);

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
}

class OrderStatusDurationPill extends StatelessWidget {
  const OrderStatusDurationPill({
    super.key,
    required this.order,
    this.alignRight = true,
    this.prefix,
    this.label,
    this.durationOverride,
  });

  final PurchaseOrder order;
  final bool alignRight;
  final String? prefix;
  final String? label;
  final Duration? durationOverride;

  @override
  Widget build(BuildContext context) {
    Duration? diff = durationOverride;
    if (diff == null) {
      final since = order.statusEnteredAt ?? order.updatedAt ?? order.createdAt;
      if (since == null) return const SizedBox.shrink();

      final now = DateTime.now();
      diff = now.difference(since);
      if (diff.isNegative) diff = Duration.zero;
    }

    final durationLabel = formatDurationLabel(diff);
    final statusLabel = order.status.label;
    final baseLabel = label ?? prefix ?? 'Tiempo en $statusLabel';
    final text = '$baseLabel: $durationLabel';

    return StatusDurationPill(
      text: text,
      alignRight: alignRight,
    );
  }
}

class StatusDurationPill extends StatelessWidget {
  const StatusDurationPill({
    super.key,
    required this.text,
    this.alignRight = true,
  });

  final String text;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blueGrey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blueGrey.shade200),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.blueGrey.shade800,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class PreviousStatusDurationPill extends ConsumerWidget {
  const PreviousStatusDurationPill({
    super.key,
    required this.orderIds,
    required this.fromStatus,
    required this.toStatus,
    required this.label,
    this.alignRight = true,
  });

  final List<String> orderIds;
  final PurchaseOrderStatus fromStatus;
  final PurchaseOrderStatus toStatus;
  final String label;
  final bool alignRight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final durations = <Duration>[];
    for (final orderId in orderIds.toSet()) {
      final events = ref.watch(orderEventsProvider(orderId)).valueOrNull;
      if (events == null) continue;
      final duration = timeBetweenStatuses(
        events,
        fromStatus: fromStatus,
        toStatus: toStatus,
      );
      if (duration != null) {
        durations.add(duration);
      }
    }

    if (durations.isEmpty) {
      return const SizedBox.shrink();
    }

    final effectiveDuration = durations.length == 1
        ? durations.first
        : averageDuration(durations);
    final effectiveLabel = durations.length == 1 ? label : '$label promedio';

    return StatusDurationPill(
      text: '$effectiveLabel: ${formatDurationLabel(effectiveDuration)}',
      alignRight: alignRight,
    );
  }
}

String formatDurationLabel(Duration d) {
  final totalSeconds = d.inSeconds;
  if (totalSeconds <= 0) return '0 s';
  final days = d.inDays;
  final hours = d.inHours % 24;
  final minutes = d.inMinutes % 60;
  final seconds = d.inSeconds % 60;

  if (days > 0) {
    final dayLabel = days == 1 ? 'día' : 'días';
    return '$days $dayLabel $hours h $minutes min $seconds s';
  }
  if (hours > 0) {
    return '${d.inHours} h $minutes min $seconds s';
  }
  if (minutes > 0) {
    return '$minutes min $seconds s';
  }
  return '$seconds s';
}

Duration? timeBetweenStatuses(
  List<PurchaseOrderEvent> events, {
  required PurchaseOrderStatus fromStatus,
  required PurchaseOrderStatus toStatus,
}) {
  if (events.isEmpty) return null;

  PurchaseOrderEvent? enterToStatus;
  for (final event in events.reversed) {
    if (event.toStatus == toStatus && event.timestamp != null) {
      enterToStatus = event;
      break;
    }
  }
  if (enterToStatus == null) return null;

  final targetTimestamp = enterToStatus.timestamp!;
  PurchaseOrderEvent? enterFromStatus;
  for (final event in events.reversed) {
    if (event.toStatus == fromStatus &&
        event.timestamp != null &&
        !event.timestamp!.isAfter(targetTimestamp)) {
      enterFromStatus = event;
      break;
    }
  }
  if (enterFromStatus == null) return null;

  final duration = targetTimestamp.difference(enterFromStatus.timestamp!);
  if (duration.isNegative) return null;
  return duration;
}

Duration averageDuration(List<Duration> durations) {
  if (durations.isEmpty) return Duration.zero;
  final totalMs = durations.fold<int>(
    0,
    (sum, duration) => sum + duration.inMilliseconds,
  );
  return Duration(milliseconds: totalMs ~/ durations.length);
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
