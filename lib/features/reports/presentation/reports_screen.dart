import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTimeRange? _dateRange;

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(allOrdersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Panel Dirección General')),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('No hay órdenes registradas.'));
          }

          final filtered = _applyDateRange(orders, _dateRange);
          if (filtered.isEmpty) {
            return _EmptyReport(onClear: _clearRange);
          }

          final numberFormat = NumberFormat('#,##0');
          final moneyFormat = NumberFormat('#,##0.##');

          final totalOrders = filtered.length;
          final ordersWithBudget = _countWithBudget(filtered);
          final ordersWithoutBudget = totalOrders - ordersWithBudget;
          final totalBudget = _sumBudget(filtered);
          final avgTicket =
              ordersWithBudget == 0 ? 0 : totalBudget / ordersWithBudget;

          final comparison = _budgetComparison(orders, _dateRange);
          final trendItems = _monthlyBudgetTrend(
            _dateRange == null ? orders : filtered,
            range: _dateRange,
          );

          final supplierItems = _budgetBySupplier(filtered);
          final areaItems = _budgetByArea(filtered);
          final urgencyItems = _budgetByUrgency(filtered);

          final diffByOrder = _discrepancyByOrder(filtered);
          final diffBySupplier = _discrepancyBySupplier(filtered);
          final diffByItem = _discrepancyByItem(filtered);

          final now = DateTime.now();
          final orderTimings = filtered
              .map((order) => _orderTimingForOrder(order, now))
              .toList()
            ..sort((a, b) => b.total.compareTo(a.total));

          final statusAverageItems = _statusAverageItems(orderTimings);

          final deltaValue = comparison.current - comparison.previous;
          final deltaPercent =
              _deltaPercent(comparison.current, comparison.previous);

          final scheme = Theme.of(context).colorScheme;
          final deltaColor = deltaValue == 0
              ? scheme.outline
              : deltaValue > 0
                  ? Colors.green
                  : scheme.error;
          final deltaIcon = deltaValue == 0
              ? Icons.trending_flat
              : deltaValue > 0
                  ? Icons.trending_up
                  : Icons.trending_down;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _FiltersRow(
                dateRange: _dateRange,
                onPickRange: _pickRange,
                onClear: _clearRange,
              ),
              const SizedBox(height: 16),
              _SectionTitle(title: 'Indicadores clave'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _StatCard(
                    title: 'Gasto total',
                    value: '\$${moneyFormat.format(totalBudget)}',
                    icon: Icons.payments_outlined,
                    color: scheme.primary,
                  ),
                  _StatCard(
                    title: comparison.label,
                    value: '\$${moneyFormat.format(comparison.current)}',
                    icon: Icons.calendar_today_outlined,
                    color: scheme.secondary,
                  ),
                  _StatCard(
                    title: 'Variación vs período anterior',
                    value: deltaPercent,
                    icon: deltaIcon,
                    color: deltaColor,
                  ),
                  _StatCard(
                    title: 'Ticket promedio',
                    value: '\$${moneyFormat.format(avgTicket)}',
                    icon: Icons.bar_chart_outlined,
                    color: scheme.tertiary,
                  ),
                  _StatCard(
                    title: 'Órdenes con presupuesto',
                    value: numberFormat.format(ordersWithBudget),
                    icon: Icons.receipt_long_outlined,
                    color: scheme.primary,
                  ),
                  _StatCard(
                    title: 'Órdenes sin presupuesto',
                    value: numberFormat.format(ordersWithoutBudget),
                    icon: Icons.report_outlined,
                    color: scheme.error,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionTitle(title: 'Tendencia de gasto'),
              const SizedBox(height: 8),
              _BreakdownCard(
                title: 'Gasto por mes',
                items: trendItems,
                emptyText: 'Sin datos de presupuesto.',
              ),
              const SizedBox(height: 16),
              _SectionTitle(title: 'Concentración de gasto'),
              const SizedBox(height: 8),
              _BreakdownCard(
                title: 'Top proveedores',
                items: supplierItems,
                emptyText: 'Sin proveedores con presupuesto.',
              ),
              const SizedBox(height: 16),
              _SectionTitle(title: 'Gasto por área'),
              const SizedBox(height: 8),
              _BreakdownCard(
                title: 'Distribución por área',
                items: areaItems,
                emptyText: 'Sin áreas con presupuesto.',
              ),
              const SizedBox(height: 16),
              _SectionTitle(title: 'Gasto por urgencia'),
              const SizedBox(height: 8),
              _BreakdownCard(
                title: 'Presupuesto por urgencia',
                items: urgencyItems,
                emptyText: 'Sin datos de urgencia.',
              ),
              const SizedBox(height: 16),
              _SectionTitle(title: 'Diferencias en almacén'),
              const SizedBox(height: 8),
              _BreakdownCard(
                title: 'Diferencias por orden',
                items: diffByOrder,
                emptyText: 'Sin diferencias registradas.',
              ),
              const SizedBox(height: 12),
              _BreakdownCard(
                title: 'Diferencias por proveedor',
                items: diffBySupplier,
                emptyText: 'Sin diferencias registradas.',
              ),
              const SizedBox(height: 12),
              _BreakdownCard(
                title: 'Diferencias por ítem',
                items: diffByItem,
                emptyText: 'Sin diferencias registradas.',
              ),
              const SizedBox(height: 16),
              _SectionTitle(title: 'Tiempos por estatus'),
              const SizedBox(height: 8),
              _BreakdownCard(
                title: 'Promedio por estatus',
                items: statusAverageItems,
                emptyText: 'Sin datos de tiempo disponibles.',
              ),
              const SizedBox(height: 16),
              _SectionTitle(title: 'Tiempos por orden'),
              const SizedBox(height: 8),
              if (orderTimings.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Sin datos de tiempo disponibles.'),
                  ),
                )
              else
                for (final timing in orderTimings) ...[
                  _OrderTimingCard(timing: timing),
                  if (timing != orderTimings.last) const SizedBox(height: 12),
                ],
            ],
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            'Error: ${reportError(error, stack, context: 'ReportsScreen')}',
          ),
        ),
      ),
    );
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365 * 5)),
      lastDate: now.add(const Duration(days: 365)),
      currentDate: now,
      initialDateRange: _dateRange,
    );
    if (picked == null) return;
    setState(() => _dateRange = picked);
  }

  void _clearRange() => setState(() => _dateRange = null);

  List<PurchaseOrder> _applyDateRange(
    List<PurchaseOrder> orders,
    DateTimeRange? range,
  ) {
    if (range == null) return orders;
    return orders.where((order) {
      final createdAt = order.createdAt;
      if (createdAt == null) return false;
      return _isWithinRange(createdAt, range);
    }).toList();
  }

  num _sumBudget(List<PurchaseOrder> orders) {
    num total = 0;
    for (final order in orders) {
      final b = order.budget;
      if (b != null) total += b;
    }
    return total;
  }

  int _countWithBudget(List<PurchaseOrder> orders) {
    return orders.where((order) => order.budget != null).length;
  }

  List<_BreakdownItem> _budgetBySupplier(List<PurchaseOrder> orders) {
    final totals = <String, num>{};
    for (final order in orders) {
      final supplier = order.supplier?.trim();
      final budget = order.budget;
      if (supplier == null || supplier.isEmpty || budget == null) continue;
      totals[supplier] = (totals[supplier] ?? 0) + budget;
    }

    final moneyFormat = NumberFormat('#,##0.##');
    final items = totals.entries
        .map(
          (entry) => _BreakdownItem(
            entry.key,
            '\$${moneyFormat.format(entry.value)}',
            entry.value,
          ),
        )
        .toList()
      ..sort((a, b) => b.order.compareTo(a.order));

    return items.take(8).toList();
  }

  List<_BreakdownItem> _budgetByArea(List<PurchaseOrder> orders) {
    final totals = <String, num>{};
    for (final order in orders) {
      final budget = order.budget;
      if (budget == null) continue;

      final rawArea = order.areaName;
      final area = rawArea.trim().isEmpty ? 'Sin área' : rawArea.trim();
      totals[area] = (totals[area] ?? 0) + budget;
    }

    final moneyFormat = NumberFormat('#,##0.##');
    final items = totals.entries
        .map(
          (entry) => _BreakdownItem(
            entry.key,
            '\$${moneyFormat.format(entry.value)}',
            entry.value,
          ),
        )
        .toList()
      ..sort((a, b) => b.order.compareTo(a.order));

    return items.take(8).toList();
  }

  List<_BreakdownItem> _budgetByUrgency(List<PurchaseOrder> orders) {
    final totals = <PurchaseOrderUrgency, num>{};
    for (final order in orders) {
      final budget = order.budget;
      if (budget == null) continue;
      totals[order.urgency] = (totals[order.urgency] ?? 0) + budget;
    }

    final moneyFormat = NumberFormat('#,##0.##');
    final items = totals.entries
        .map(
          (entry) => _BreakdownItem(
            entry.key.label,
            '\$${moneyFormat.format(entry.value)}',
            entry.value,
          ),
        )
        .toList()
      ..sort((a, b) => b.order.compareTo(a.order));

    return items;
  }

  List<_BreakdownItem> _discrepancyByOrder(List<PurchaseOrder> orders) {
    final items = <_BreakdownItem>[];

    for (final order in orders) {
      num totalDiff = 0;
      var diffCount = 0;

      for (final item in order.items) {
        final diff = _itemDifference(item);
        if (diff == null || diff == 0) continue;
        totalDiff += diff;
        diffCount += 1;
      }

      if (diffCount == 0) continue;

      items.add(
        _BreakdownItem(
          '${order.id} ($diffCount ítems)',
          'Δ ${_formatDiff(totalDiff)}',
          totalDiff.abs(),
        ),
      );
    }

    items.sort((a, b) => b.order.compareTo(a.order));
    return items.take(8).toList();
  }

  List<_BreakdownItem> _discrepancyBySupplier(List<PurchaseOrder> orders) {
    final totals = <String, _DiffBucket>{};

    for (final order in orders) {
      final supplier = (order.supplier?.trim().isNotEmpty == true)
          ? order.supplier!.trim()
          : 'Sin proveedor';

      for (final item in order.items) {
        final diff = _itemDifference(item);
        if (diff == null || diff == 0) continue;

        final bucket = totals.putIfAbsent(supplier, _DiffBucket.new);
        bucket.total += diff;
        bucket.count += 1;
      }
    }

    final items = totals.entries
        .map((entry) {
          final bucket = entry.value;
          return _BreakdownItem(
            '${entry.key} (${bucket.count} ítems)',
            'Δ ${_formatDiff(bucket.total)}',
            bucket.total.abs(),
          );
        })
        .toList()
      ..sort((a, b) => b.order.compareTo(a.order));

    return items.take(8).toList();
  }

  List<_BreakdownItem> _discrepancyByItem(List<PurchaseOrder> orders) {
    final totals = <String, _DiffBucket>{};

    for (final order in orders) {
      for (final item in order.items) {
        final diff = _itemDifference(item);
        if (diff == null || diff == 0) continue;

        final key = item.partNumber.trim().isNotEmpty
            ? item.partNumber.trim()
            : item.description.trim().isNotEmpty
                ? item.description.trim()
                : 'Ítem ${item.line}';

        final bucket = totals.putIfAbsent(key, _DiffBucket.new);
        bucket.total += diff;
        bucket.count += 1;
      }
    }

    final items = totals.entries
        .map((entry) {
          final bucket = entry.value;
          return _BreakdownItem(
            '${entry.key} (${bucket.count} ítems)',
            'Δ ${_formatDiff(bucket.total)}',
            bucket.total.abs(),
          );
        })
        .toList()
      ..sort((a, b) => b.order.compareTo(a.order));

    return items.take(8).toList();
  }

  num? _itemDifference(PurchaseOrderItem item) {
    final received = item.receivedQuantity;
    if (received == null) return null;
    return received - item.quantity;
  }

  String _formatDiff(num value) {
    final formatter = NumberFormat('#,##0.##');
    final sign = value > 0 ? '+' : '';
    return '$sign${formatter.format(value)}';
  }

  List<_BreakdownItem> _monthlyBudgetTrend(
    List<PurchaseOrder> orders, {
    DateTimeRange? range,
  }) {
    final moneyFormat = NumberFormat('#,##0.##');
    final now = DateTime.now();
    final keys =
        range == null ? _lastMonthsKeys(now, 6) : _rangeMonthKeys(range);

    final buckets = <DateTime, num>{
      for (final key in keys) key: 0,
    };

    final oldest = keys.isEmpty ? now : keys.first;

    for (final order in orders) {
      final createdAt = order.createdAt;
      final budget = order.budget;
      if (createdAt == null || budget == null) continue;

      if (range == null) {
        if (createdAt.isBefore(oldest)) continue;
      } else {
        if (!_isWithinRange(createdAt, range)) continue;
      }

      final key = DateTime(createdAt.year, createdAt.month, 1);
      buckets[key] = (buckets[key] ?? 0) + budget;
    }

    final formatter = DateFormat('MMM yyyy');
    final entries = buckets.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return entries
        .map(
          (entry) => _BreakdownItem(
            formatter.format(entry.key),
            '\$${moneyFormat.format(entry.value)}',
            entry.value,
          ),
        )
        .toList();
  }

  List<DateTime> _lastMonthsKeys(DateTime now, int count) {
    final keys = <DateTime>[];
    var cursor = DateTime(now.year, now.month, 1);

    for (var i = 0; i < count; i++) {
      keys.add(DateTime(cursor.year, cursor.month, 1));
      cursor = DateTime(cursor.year, cursor.month - 1, 1);
    }

    return keys.reversed.toList();
  }

  List<DateTime> _rangeMonthKeys(DateTimeRange range) {
    final keys = <DateTime>[];
    var cursor = DateTime(range.start.year, range.start.month, 1);
    final end = DateTime(range.end.year, range.end.month, 1);

    while (!cursor.isAfter(end)) {
      keys.add(DateTime(cursor.year, cursor.month, 1));
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }

    return keys;
  }

  _PeriodComparison _budgetComparison(
    List<PurchaseOrder> orders,
    DateTimeRange? range,
  ) {
    final now = DateTime.now();
    final currentRange = range ??
        DateTimeRange(
          start: now.subtract(const Duration(days: 30)),
          end: now,
        );

    final duration = currentRange.end.difference(currentRange.start);

    final previousRange = DateTimeRange(
      start: currentRange.start.subtract(duration),
      end: currentRange.start,
    );

    final current = _sumBudgetInRange(orders, currentRange);
    final previous = _sumBudgetInRange(orders, previousRange);

    final label = range == null
        ? 'Últimos 30 días'
        : '${currentRange.start.toShortDate()} - ${currentRange.end.toShortDate()}';

    return _PeriodComparison(
      current: current,
      previous: previous,
      label: label,
    );
  }

  num _sumBudgetInRange(List<PurchaseOrder> orders, DateTimeRange range) {
    num total = 0;

    for (final order in orders) {
      final createdAt = order.createdAt;
      final budget = order.budget;
      if (createdAt == null || budget == null) continue;

      if (_isWithinRange(createdAt, range)) {
        total += budget;
      }
    }

    return total;
  }

  String _deltaPercent(num current, num previous) {
    if (previous == 0) {
      if (current == 0) return '0%';
      return 'Nuevo';
    }
    final delta = ((current - previous) / previous) * 100;
    final sign = delta > 0 ? '+' : '';
    return '$sign${delta.toStringAsFixed(1)}%';
  }

  bool _isWithinRange(DateTime date, DateTimeRange range) {
    final start = DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day)
        .add(const Duration(days: 1));

    // inclusivo por día
    return date.isAfter(start.subtract(const Duration(milliseconds: 1))) &&
        date.isBefore(end);
  }
}

_OrderTiming _orderTimingForOrder(PurchaseOrder order, DateTime now) {
  final durations = <PurchaseOrderStatus, Duration>{};

  for (final entry in order.statusDurations.entries) {
    final status = _statusFromKey(entry.key);
    if (status == null) continue;
    if (entry.value <= 0) continue;
    durations[status] = Duration(milliseconds: entry.value);
  }

  // Sumar tiempo transcurrido en el estatus actual (si aplica)
  if (order.statusEnteredAt != null && order.status != PurchaseOrderStatus.eta) {
    final elapsed = now.difference(order.statusEnteredAt!).inMilliseconds;
    if (elapsed > 0) {
      final current = durations[order.status] ?? Duration.zero;
      durations[order.status] = current + Duration(milliseconds: elapsed);
    }
  }

  var total = durations.values.fold(Duration.zero, (sum, value) => sum + value);

  if (total == Duration.zero) {
    final start = order.createdAt;
    if (start != null) {
      final end = order.status == PurchaseOrderStatus.eta
          ? (order.updatedAt ?? now)
          : now;
      total = end.difference(start);
    }
  }

  PurchaseOrderStatus? longestStatus;
  var longestDuration = Duration.zero;

  for (final entry in durations.entries) {
    if (entry.value > longestDuration) {
      longestDuration = entry.value;
      longestStatus = entry.key;
    }
  }

  return _OrderTiming(
    order: order,
    durations: durations,
    total: total,
    longestStatus: longestStatus,
    longestDuration: longestDuration,
  );
}

PurchaseOrderStatus? _statusFromKey(String raw) {
  for (final status in PurchaseOrderStatus.values) {
    if (status.name == raw) return status;
  }
  return null;
}

List<_BreakdownItem> _statusAverageItems(List<_OrderTiming> timings) {
  final totals = <PurchaseOrderStatus, Duration>{};
  final counts = <PurchaseOrderStatus, int>{};

  for (final timing in timings) {
    for (final entry in timing.durations.entries) {
      if (entry.value <= Duration.zero) continue;
      totals[entry.key] = (totals[entry.key] ?? Duration.zero) + entry.value;
      counts[entry.key] = (counts[entry.key] ?? 0) + 1;
    }
  }

  final items = <_BreakdownItem>[];

  for (final entry in totals.entries) {
    final count = counts[entry.key] ?? 0;
    if (count <= 0) continue;

    final avgMs = entry.value.inMilliseconds ~/ count;
    final avg = Duration(milliseconds: avgMs);

    items.add(
      _BreakdownItem(
        entry.key.label,
        _formatDuration(avg),
        avg.inMilliseconds,
      ),
    );
  }

  items.sort((a, b) => b.order.compareTo(a.order));
  return items;
}

String _formatDuration(Duration duration) {
  final totalMinutes = duration.inMinutes;
  if (totalMinutes <= 0) return 'menos de 1 min';

  final days = duration.inDays;
  final hours = duration.inHours % 24;
  final minutes = duration.inMinutes % 60;

  if (days > 0) {
    final dayLabel = days == 1 ? 'día' : 'días';
    final hourPart = hours > 0 ? ' $hours h' : '';
    final minutePart = minutes > 0 ? ' $minutes min' : '';
    return '$days $dayLabel$hourPart$minutePart';
  }

  if (hours > 0) {
    final minutePart = minutes > 0 ? ' $minutes min' : '';
    return '$hours h$minutePart';
  }

  return '$minutes min';
}

class _FiltersRow extends StatelessWidget {
  const _FiltersRow({
    required this.dateRange,
    required this.onPickRange,
    required this.onClear,
  });

  final DateTimeRange? dateRange;
  final VoidCallback onPickRange;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final label = dateRange == null
        ? 'Todas las fechas'
        : '${dateRange!.start.toShortDate()} - ${dateRange!.end.toShortDate()}';

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: onPickRange,
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text(label),
        ),
        TextButton(
          onPressed: dateRange == null ? null : onClear,
          child: const Text('Limpiar'),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color, width: 1.2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BreakdownItem {
  const _BreakdownItem(this.label, this.value, this.order);

  final String label;
  final String value;
  final num order;
}

class _DiffBucket {
  num total = 0;
  int count = 0;
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.title,
    required this.items,
    required this.emptyText,
  });

  final String title;
  final List<_BreakdownItem> items;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(emptyText),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            for (final item in items) ...[
              Row(
                children: [
                  Expanded(child: Text(item.label)),
                  Text(
                    item.value,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              if (item != items.last) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _OrderTiming {
  const _OrderTiming({
    required this.order,
    required this.durations,
    required this.total,
    required this.longestStatus,
    required this.longestDuration,
  });

  final PurchaseOrder order;
  final Map<PurchaseOrderStatus, Duration> durations;
  final Duration total;
  final PurchaseOrderStatus? longestStatus;
  final Duration longestDuration;
}

class _OrderTimingCard extends StatelessWidget {
  const _OrderTimingCard({required this.timing});
  final _OrderTiming timing;

  @override
  Widget build(BuildContext context) {
    final entries = timing.durations.entries.toList()
      ..sort((a, b) => PurchaseOrderStatus.values
          .indexOf(a.key)
          .compareTo(PurchaseOrderStatus.values.indexOf(b.key)));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Orden ${timing.order.id}',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('Total: ${_formatDuration(timing.total)}'),
            if (timing.longestStatus != null)
              Text(
                'Mayor tiempo: ${timing.longestStatus!.label} (${_formatDuration(timing.longestDuration)})',
              ),
            if (entries.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in entries)
                    if (entry.value > Duration.zero)
                      Chip(
                        label: Text(
                          '${entry.key.label}: ${_formatDuration(entry.value)}',
                        ),
                      ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyReport extends StatelessWidget {
  const _EmptyReport({required this.onClear});
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 48),
            const SizedBox(height: 12),
            const Text('No hay órdenes en ese período.'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onClear,
              child: const Text('Limpiar rango'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodComparison {
  const _PeriodComparison({
    required this.current,
    required this.previous,
    required this.label,
  });

  final num current;
  final num previous;
  final String label;
}
