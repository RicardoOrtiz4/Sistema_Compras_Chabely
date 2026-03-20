import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/domain/supplier_quote.dart';
import 'package:sistema_compras/features/orders/presentation/monitoring/order_monitoring_support.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTimeRange? _dateRange;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProfileProvider).value;
    final canView = user != null &&
        (isAdminRole(user.role) ||
            isComprasLabel(user.areaDisplay) ||
            isDireccionGeneralLabel(user.areaDisplay));
    final ordersAsync = ref.watch(operationalOrdersProvider);
    final quotesAsync = ref.watch(supplierQuotesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes'),
      ),
      body: !canView
          ? const Center(
              child: Text('No tienes permisos para ver reportes.'),
            )
          : ordersAsync.when(
              data: (orders) => quotesAsync.when(
                data: (quotes) {
                  final data = _buildReportsData(
                    orders: orders,
                    quotes: quotes,
                    range: _dateRange,
                    now: DateTime.now(),
                  );
                  if (data.filteredOrders.isEmpty && data.filteredQuotes.isEmpty) {
                    return _EmptyReports(onClear: _clearRange);
                  }

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _ReportsFiltersBar(
                        dateRange: _dateRange,
                        onPickRange: _pickRange,
                        onClearRange: _clearRange,
                      ),
                      const SizedBox(height: 16),
                      _ReportsOverview(
                        data: data,
                        rangeLabel: _rangeLabel(_dateRange),
                      ),
                      const SizedBox(height: 16),
                      _SectionTitle(title: 'Operacion actual'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _SimpleBreakdownCard(
                            title: 'Ordenes por estatus',
                            subtitle: 'Foto actual del flujo',
                            items: data.statusItems,
                            emptyText: 'Sin ordenes en el periodo.',
                          ),
                          _SimpleBreakdownCard(
                            title: 'Cuellos de botella',
                            subtitle: 'Promedio de espera por cola activa',
                            items: data.bottleneckItems,
                            emptyText: 'No hay colas activas.',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _SectionTitle(title: 'Tiempos y cumplimiento'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _SimpleBreakdownCard(
                            title: 'Promedio acumulado por estatus',
                            subtitle: 'Tomado de statusDurations',
                            items: data.statusDurationItems,
                            emptyText: 'Sin tiempos disponibles.',
                          ),
                          _SimpleBreakdownCard(
                            title: 'Top ordenes activas mas atrasadas',
                            subtitle: 'Mayor tiempo en el estatus actual',
                            items: data.delayedOrderItems,
                            emptyText: 'No hay ordenes activas.',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _SectionTitle(title: 'Presupuesto y proveedores'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _SimpleBreakdownCard(
                            title: 'Top areas por volumen',
                            subtitle: 'Cantidad de ordenes',
                            items: data.areaItems,
                            emptyText: 'Sin datos de areas.',
                          ),
                          _SimpleBreakdownCard(
                            title: 'Top proveedores por presupuesto',
                            subtitle: 'Basado en budget de la orden',
                            items: data.supplierBudgetItems,
                            emptyText: 'Sin presupuesto capturado.',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _SectionTitle(title: 'Cotizaciones'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _SimpleBreakdownCard(
                            title: 'Estado de cotizaciones',
                            subtitle: 'Pendientes, aprobadas y rechazadas',
                            items: data.quoteStatusItems,
                            emptyText: 'Sin cotizaciones en el periodo.',
                          ),
                          _SimpleBreakdownCard(
                            title: 'Top proveedores por monto cotizado',
                            subtitle: 'Basado en totalAmount de la cotizacion',
                            items: data.quoteSupplierItems,
                            emptyText: 'Sin montos cotizados.',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _SectionTitle(title: 'Tendencia'),
                      const SizedBox(height: 8),
                      _SimpleBreakdownCard(
                        title: 'Ultimos 6 meses',
                        subtitle: 'Volumen y presupuesto creado',
                        items: data.monthlyTrendItems,
                        fullWidth: true,
                        emptyText: 'Sin datos historicos suficientes.',
                      ),
                    ],
                  );
                },
                loading: () => const AppSplash(),
                error: (error, stack) => Center(
                  child: Text(
                    'Error: ${reportError(error, stack, context: 'ReportsScreen.quotes')}',
                  ),
                ),
              ),
              loading: () => const AppSplash(),
              error: (error, stack) => Center(
                child: Text(
                  'Error: ${reportError(error, stack, context: 'ReportsScreen.orders')}',
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
}

_ReportsData _buildReportsData({
  required List<PurchaseOrder> orders,
  required List<SupplierQuote> quotes,
  required DateTimeRange? range,
  required DateTime now,
}) {
  final filteredOrders = orders
      .where((order) => _matchesRange(order.createdAt, range))
      .toList(growable: false);
  final filteredQuotes = quotes
      .where((quote) => _matchesRange(quote.createdAt ?? quote.updatedAt, range))
      .toList(growable: false);

  final rejectedOrders = filteredOrders.where(_isRejectedOrder).toList(growable: false);
  final completedOrders = filteredOrders
      .where((order) => order.status == PurchaseOrderStatus.eta)
      .toList(growable: false);
  final activeOrders = filteredOrders
      .where((order) => order.status != PurchaseOrderStatus.eta && !_isRejectedOrder(order))
      .toList(growable: false);
  final urgentOrders = filteredOrders
      .where((order) => order.urgency == PurchaseOrderUrgency.urgente)
      .toList(growable: false);

  final ordersWithBudget = filteredOrders.where((order) => (order.budget ?? 0) > 0).toList();
  final totalBudget = ordersWithBudget.fold<num>(0, (sum, order) => sum + (order.budget ?? 0));
  final avgBudget = ordersWithBudget.isEmpty ? 0 : totalBudget / ordersWithBudget.length;

  final completedCycles = completedOrders
      .map((order) => _completionCycle(order, now))
      .whereType<Duration>()
      .toList(growable: false);
  final avgCompletionCycle = completedCycles.isEmpty
      ? Duration.zero
      : Duration(
          milliseconds: completedCycles
                  .fold<int>(0, (sum, value) => sum + value.inMilliseconds) ~/
              completedCycles.length,
        );

  final currentWaits = activeOrders
      .map((order) => currentStatusElapsed(order, now))
      .toList(growable: false);
  final avgCurrentWait = currentWaits.isEmpty
      ? Duration.zero
      : Duration(
          milliseconds:
              currentWaits.fold<int>(0, (sum, value) => sum + value.inMilliseconds) ~/
                  currentWaits.length,
        );

  return _ReportsData(
    filteredOrders: filteredOrders,
    filteredQuotes: filteredQuotes,
    totalBudget: totalBudget,
    avgBudget: avgBudget,
    totalOrders: filteredOrders.length,
    activeOrders: activeOrders.length,
    completedOrders: completedOrders.length,
    rejectedOrders: rejectedOrders.length,
    urgentOrders: urgentOrders.length,
    avgCompletionCycle: avgCompletionCycle,
    avgCurrentWait: avgCurrentWait,
    statusItems: _buildStatusItems(filteredOrders),
    bottleneckItems: _buildBottleneckItems(activeOrders, now),
    statusDurationItems: _buildStatusDurationItems(filteredOrders, now),
    areaItems: _buildAreaItems(filteredOrders),
    supplierBudgetItems: _buildSupplierBudgetItems(filteredOrders),
    quoteStatusItems: _buildQuoteStatusItems(filteredQuotes),
    quoteSupplierItems: _buildQuoteSupplierItems(filteredQuotes),
    delayedOrderItems: _buildDelayedOrderItems(activeOrders, now),
    monthlyTrendItems: _buildMonthlyTrendItems(filteredOrders, now),
  );
}

bool _matchesRange(DateTime? date, DateTimeRange? range) {
  if (range == null) return true;
  if (date == null) return false;
  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day)
      .add(const Duration(days: 1));
  return !date.isBefore(start) && date.isBefore(end);
}

bool _isRejectedOrder(PurchaseOrder order) {
  final reason = order.lastReturnReason?.trim() ?? '';
  return order.status == PurchaseOrderStatus.draft &&
      (reason.isNotEmpty || order.returnCount > 0);
}

Duration? _completionCycle(PurchaseOrder order, DateTime now) {
  final start = order.createdAt;
  if (start == null) return null;
  final end = order.completedAt ?? order.updatedAt ?? now;
  final diff = end.difference(start);
  return diff.isNegative ? Duration.zero : diff;
}

List<_ReportItem> _buildStatusItems(List<PurchaseOrder> orders) {
  final counts = <String, int>{};
  for (final order in orders) {
    final label =
        _isRejectedOrder(order) ? 'Rechazadas / correccion' : order.status.label;
    counts[label] = (counts[label] ?? 0) + 1;
  }
  return _mapToSortedItems(counts, formatter: (value) => '$value');
}

List<_ReportItem> _buildBottleneckItems(List<PurchaseOrder> orders, DateTime now) {
  final totals = <String, int>{};
  final counts = <String, int>{};
  for (final order in orders) {
    final label = order.status.label;
    totals[label] = (totals[label] ?? 0) + currentStatusElapsed(order, now).inMilliseconds;
    counts[label] = (counts[label] ?? 0) + 1;
  }
  final items = <_ReportItem>[];
  for (final entry in totals.entries) {
    final count = counts[entry.key] ?? 1;
    final avg = Duration(milliseconds: entry.value ~/ count);
    items.add(
      _ReportItem(
        label: entry.key,
        value: formatMonitoringDuration(avg),
        order: avg.inMilliseconds,
      ),
    );
  }
  items.sort((a, b) => b.order.compareTo(a.order));
  return items;
}

List<_ReportItem> _buildStatusDurationItems(List<PurchaseOrder> orders, DateTime now) {
  final totals = <PurchaseOrderStatus, int>{};
  final counts = <PurchaseOrderStatus, int>{};
  for (final order in orders) {
    for (final status in PurchaseOrderStatus.values) {
      final elapsed = accumulatedStatusElapsed(order, status, now);
      if (elapsed <= Duration.zero) continue;
      totals[status] = (totals[status] ?? 0) + elapsed.inMilliseconds;
      counts[status] = (counts[status] ?? 0) + 1;
    }
  }
  final items = <_ReportItem>[];
  for (final entry in totals.entries) {
    final count = counts[entry.key] ?? 1;
    final avg = Duration(milliseconds: entry.value ~/ count);
    items.add(
      _ReportItem(
        label: entry.key.label,
        value: formatMonitoringDuration(avg),
        order: avg.inMilliseconds,
      ),
    );
  }
  items.sort((a, b) => b.order.compareTo(a.order));
  return items;
}

List<_ReportItem> _buildAreaItems(List<PurchaseOrder> orders) {
  final counts = <String, int>{};
  for (final order in orders) {
    final key = order.areaName.trim().isEmpty ? 'Sin area' : order.areaName.trim();
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return _mapToSortedItems(counts, formatter: (value) => '$value');
}

List<_ReportItem> _buildSupplierBudgetItems(List<PurchaseOrder> orders) {
  final totals = <String, num>{};
  for (final order in orders) {
    final supplier = order.supplier?.trim() ?? '';
    final budget = order.budget ?? 0;
    if (supplier.isEmpty || budget <= 0) continue;
    totals[supplier] = (totals[supplier] ?? 0) + budget;
  }
  return _mapToSortedItems(totals, formatter: (value) => _money(value));
}

List<_ReportItem> _buildQuoteStatusItems(List<SupplierQuote> quotes) {
  final counts = <String, int>{};
  for (final quote in quotes) {
    counts[quote.status.label] = (counts[quote.status.label] ?? 0) + 1;
  }
  return _mapToSortedItems(counts, formatter: (value) => '$value');
}

List<_ReportItem> _buildQuoteSupplierItems(List<SupplierQuote> quotes) {
  final totals = <String, num>{};
  for (final quote in quotes) {
    final supplier = quote.supplier.trim();
    final total = quote.totalAmount;
    if (supplier.isEmpty || total <= 0) continue;
    totals[supplier] = (totals[supplier] ?? 0) + total;
  }
  return _mapToSortedItems(totals, formatter: (value) => _money(value));
}

List<_ReportItem> _buildDelayedOrderItems(List<PurchaseOrder> orders, DateTime now) {
  final sorted = [...orders]
    ..sort((a, b) => currentStatusElapsed(b, now).compareTo(currentStatusElapsed(a, now)));
  return sorted
      .take(6)
      .map(
        (order) => _ReportItem(
          label: '${order.id} | ${order.status.label}',
          value:
              '${formatMonitoringDuration(currentStatusElapsed(order, now))} | ${order.requesterName}',
          order: currentStatusElapsed(order, now).inMilliseconds,
        ),
      )
      .toList(growable: false);
}

List<_ReportItem> _buildMonthlyTrendItems(List<PurchaseOrder> orders, DateTime now) {
  final buckets = <String, _MonthBucket>{};
  for (var offset = 5; offset >= 0; offset--) {
    final date = DateTime(now.year, now.month - offset, 1);
    final key = _monthKey(date);
    buckets[key] = _MonthBucket(
      label: DateFormat('MMM yyyy').format(date),
      count: 0,
      budget: 0,
    );
  }
  for (final order in orders) {
    final createdAt = order.createdAt;
    if (createdAt == null) continue;
    final key = _monthKey(DateTime(createdAt.year, createdAt.month, 1));
    final bucket = buckets[key];
    if (bucket == null) continue;
    bucket.count += 1;
    bucket.budget += order.budget ?? 0;
  }
  return buckets.values
      .map(
        (bucket) => _ReportItem(
          label: bucket.label,
          value: '${bucket.count} ord | ${_money(bucket.budget)}',
          order: bucket.count * 1000000 + bucket.budget.toInt(),
        ),
      )
      .toList(growable: false);
}

String _monthKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';

List<_ReportItem> _mapToSortedItems<T extends num>(
  Map<String, T> values, {
  required String Function(T value) formatter,
}) {
  final items = values.entries
      .map(
        (entry) => _ReportItem(
          label: entry.key,
          value: formatter(entry.value),
          order: entry.value.toDouble(),
        ),
      )
      .toList(growable: false);
  items.sort((a, b) => b.order.compareTo(a.order));
  return items;
}

String _money(num value) => '\$${NumberFormat('#,##0.##').format(value)}';

String _rangeLabel(DateTimeRange? range) {
  if (range == null) return 'Todo el historial';
  return '${range.start.toShortDate()} - ${range.end.toShortDate()}';
}

class _ReportsData {
  const _ReportsData({
    required this.filteredOrders,
    required this.filteredQuotes,
    required this.totalBudget,
    required this.avgBudget,
    required this.totalOrders,
    required this.activeOrders,
    required this.completedOrders,
    required this.rejectedOrders,
    required this.urgentOrders,
    required this.avgCompletionCycle,
    required this.avgCurrentWait,
    required this.statusItems,
    required this.bottleneckItems,
    required this.statusDurationItems,
    required this.areaItems,
    required this.supplierBudgetItems,
    required this.quoteStatusItems,
    required this.quoteSupplierItems,
    required this.delayedOrderItems,
    required this.monthlyTrendItems,
  });

  final List<PurchaseOrder> filteredOrders;
  final List<SupplierQuote> filteredQuotes;
  final num totalBudget;
  final num avgBudget;
  final int totalOrders;
  final int activeOrders;
  final int completedOrders;
  final int rejectedOrders;
  final int urgentOrders;
  final Duration avgCompletionCycle;
  final Duration avgCurrentWait;
  final List<_ReportItem> statusItems;
  final List<_ReportItem> bottleneckItems;
  final List<_ReportItem> statusDurationItems;
  final List<_ReportItem> areaItems;
  final List<_ReportItem> supplierBudgetItems;
  final List<_ReportItem> quoteStatusItems;
  final List<_ReportItem> quoteSupplierItems;
  final List<_ReportItem> delayedOrderItems;
  final List<_ReportItem> monthlyTrendItems;
}

class _ReportItem {
  const _ReportItem({
    required this.label,
    required this.value,
    required this.order,
  });

  final String label;
  final String value;
  final num order;
}

class _MonthBucket {
  _MonthBucket({
    required this.label,
    required this.count,
    required this.budget,
  });

  final String label;
  int count;
  num budget;
}

class _ReportsFiltersBar extends StatelessWidget {
  const _ReportsFiltersBar({
    required this.dateRange,
    required this.onPickRange,
    required this.onClearRange,
  });

  final DateTimeRange? dateRange;
  final VoidCallback onPickRange;
  final VoidCallback onClearRange;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: onPickRange,
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text(_rangeLabel(dateRange)),
        ),
        TextButton(
          onPressed: dateRange == null ? null : onClearRange,
          child: const Text('Limpiar'),
        ),
        Text(
          'Los reportes usan fecha de creacion.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ReportsOverview extends StatelessWidget {
  const _ReportsOverview({
    required this.data,
    required this.rangeLabel,
  });

  final _ReportsData data;
  final String rangeLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen ejecutivo',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(rangeLabel, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricCard(
                title: 'Ordenes',
                value: '${data.totalOrders}',
                caption: 'Creadas en el rango',
                icon: Icons.inventory_2_outlined,
              ),
              _MetricCard(
                title: 'Activas',
                value: '${data.activeOrders}',
                caption: 'Aun en flujo',
                icon: Icons.radar_outlined,
              ),
              _MetricCard(
                title: 'Finalizadas',
                value: '${data.completedOrders}',
                caption: 'Cerradas',
                icon: Icons.task_alt_outlined,
              ),
              _MetricCard(
                title: 'Rechazadas',
                value: '${data.rejectedOrders}',
                caption: 'Devueltas a correccion',
                icon: Icons.report_problem_outlined,
              ),
              _MetricCard(
                title: 'Urgentes',
                value: '${data.urgentOrders}',
                caption: 'Prioridad alta',
                icon: Icons.priority_high,
              ),
              _MetricCard(
                title: 'Presupuesto',
                value: _money(data.totalBudget),
                caption: 'Suma de budget',
                icon: Icons.payments_outlined,
              ),
              _MetricCard(
                title: 'Promedio por orden',
                value: _money(data.avgBudget),
                caption: 'Solo con budget',
                icon: Icons.bar_chart_outlined,
              ),
              _MetricCard(
                title: 'Ciclo promedio',
                value: formatMonitoringDuration(data.avgCompletionCycle),
                caption: 'Ordenes finalizadas',
                icon: Icons.timelapse_outlined,
              ),
              _MetricCard(
                title: 'Espera promedio',
                value: formatMonitoringDuration(data.avgCurrentWait),
                caption: 'Ordenes activas',
                icon: Icons.hourglass_top_outlined,
              ),
              _MetricCard(
                title: 'Cotizaciones',
                value: '${data.filteredQuotes.length}',
                caption: 'Total en el rango',
                icon: Icons.request_quote_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.caption,
    required this.icon,
  });

  final String title;
  final String value;
  final String caption;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(caption, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
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

class _SimpleBreakdownCard extends StatelessWidget {
  const _SimpleBreakdownCard({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.emptyText,
    this.fullWidth = false,
  });

  final String title;
  final String subtitle;
  final List<_ReportItem> items;
  final String emptyText;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: fullWidth ? double.infinity : 420,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              if (items.isEmpty)
                Text(emptyText)
              else
                for (final item in items) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.label,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        item.value,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  if (item != items.last) const SizedBox(height: 8),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyReports extends StatelessWidget {
  const _EmptyReports({required this.onClear});

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
            const Text('No hay datos para ese rango.'),
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
