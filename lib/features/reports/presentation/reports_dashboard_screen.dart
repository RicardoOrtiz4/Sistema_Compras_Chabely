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
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 980;
                          if (isWide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 360,
                                  child: _SimpleBreakdownCard(
                                    title: 'Top proveedores por monto',
                                    subtitle: 'Monto cotizado acumulado en el rango',
                                    items: data.quoteSupplierItems
                                        .take(8)
                                        .toList(growable: false),
                                    emptyText: 'Sin montos cotizados.',
                                    totalLabel:
                                        'Total general: ${_money(data.totalQuotedAmount)}',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _TrendCard(
                                    title: 'Tendencia',
                                    subtitle: 'Ultimos 6 meses de ordenes y compras',
                                    buckets: data.monthlyTrendBuckets,
                                    totalQuotes: data.filteredQuotes.length,
                                    fullWidth: true,
                                  ),
                                ),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              _SimpleBreakdownCard(
                                title: 'Top proveedores por monto',
                                subtitle: 'Monto cotizado acumulado en el rango',
                                items: data.quoteSupplierItems.take(8).toList(growable: false),
                                emptyText: 'Sin montos cotizados.',
                                totalLabel:
                                    'Total general: ${_money(data.totalQuotedAmount)}',
                                fullWidth: true,
                              ),
                              const SizedBox(height: 12),
                              _TrendCard(
                                title: 'Tendencia',
                                subtitle: 'Ultimos 6 meses de ordenes y compras',
                                buckets: data.monthlyTrendBuckets,
                                totalQuotes: data.filteredQuotes.length,
                                fullWidth: true,
                              ),
                            ],
                          );
                        },
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

  return _ReportsData(
    filteredOrders: filteredOrders,
    filteredQuotes: filteredQuotes,
    totalOrders: filteredOrders.length,
    activeOrders: activeOrders.length,
    completedOrders: completedOrders.length,
    rejectedOrders: rejectedOrders.length,
    urgentOrders: urgentOrders.length,
    totalQuotedAmount: filteredQuotes.fold<num>(
      0,
      (sum, quote) => sum + (quote.totalAmount > 0 ? quote.totalAmount : 0),
    ),
    quoteSupplierItems: _buildQuoteSupplierItems(filteredQuotes),
    monthlyTrendBuckets: _buildMonthlyTrendBuckets(
      orders: filteredOrders,
      quotes: filteredQuotes,
      now: now,
    ),
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

List<_MonthBucket> _buildMonthlyTrendBuckets({
  required List<PurchaseOrder> orders,
  required List<SupplierQuote> quotes,
  required DateTime now,
}) {
  final buckets = <String, _MonthBucket>{};
  for (var offset = 5; offset >= 0; offset--) {
    final date = DateTime(now.year, now.month - offset, 1);
    final key = _monthKey(date);
    buckets[key] = _MonthBucket(
      label: DateFormat('MMM yyyy').format(date),
      ordersCount: 0,
      quotesCount: 0,
      quotesAmount: 0,
    );
  }
  for (final order in orders) {
    final createdAt = order.createdAt;
    if (createdAt == null) continue;
    final key = _monthKey(DateTime(createdAt.year, createdAt.month, 1));
    final bucket = buckets[key];
    if (bucket == null) continue;
    bucket.ordersCount += 1;
  }
  for (final quote in quotes) {
    final createdAt = quote.createdAt ?? quote.updatedAt;
    if (createdAt == null) continue;
    final key = _monthKey(DateTime(createdAt.year, createdAt.month, 1));
    final bucket = buckets[key];
    if (bucket == null) continue;
    bucket.quotesCount += 1;
    bucket.quotesAmount += quote.totalAmount > 0 ? quote.totalAmount : 0;
  }
  return buckets.values.toList(growable: false);
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
    required this.totalOrders,
    required this.activeOrders,
    required this.completedOrders,
    required this.rejectedOrders,
    required this.urgentOrders,
    required this.totalQuotedAmount,
    required this.quoteSupplierItems,
    required this.monthlyTrendBuckets,
  });

  final List<PurchaseOrder> filteredOrders;
  final List<SupplierQuote> filteredQuotes;
  final int totalOrders;
  final int activeOrders;
  final int completedOrders;
  final int rejectedOrders;
  final int urgentOrders;
  final num totalQuotedAmount;
  final List<_ReportItem> quoteSupplierItems;
  final List<_MonthBucket> monthlyTrendBuckets;
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
    required this.ordersCount,
    required this.quotesCount,
    required this.quotesAmount,
  });

  final String label;
  int ordersCount;
  int quotesCount;
  num quotesAmount;
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 720;
              final metrics = [
                _MetricCard(
                  title: 'Ordenes',
                  value: '${data.totalOrders}',
                  caption: 'en el rango',
                  icon: Icons.inventory_2_outlined,
                  compact: isNarrow,
                ),
                _MetricCard(
                  title: 'Activas',
                  value: '${data.activeOrders}',
                  caption: 'en proceso',
                  icon: Icons.radar_outlined,
                  compact: isNarrow,
                ),
                _MetricCard(
                  title: 'Finalizadas',
                  value: '${data.completedOrders}',
                  caption: 'cerradas',
                  icon: Icons.task_alt_outlined,
                  compact: isNarrow,
                ),
                _MetricCard(
                  title: 'Rechazadas',
                  value: '${data.rejectedOrders}',
                  caption: 'con devolucion',
                  icon: Icons.report_problem_outlined,
                  compact: isNarrow,
                ),
                _MetricCard(
                  title: 'Urgentes',
                  value: '${data.urgentOrders}',
                  caption: 'prioridad alta',
                  icon: Icons.priority_high,
                  compact: isNarrow,
                ),
                _MetricCard(
                  title: 'Compras',
                  value: '${data.filteredQuotes.length}',
                  caption: 'registradas',
                  icon: Icons.request_quote_outlined,
                  compact: isNarrow,
                ),
              ];

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  isNarrow
                      ? SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              Text(
                                'Resumen ejecutivo',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surface,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: scheme.outlineVariant),
                                ),
                                child: Text(
                                  rangeLabel,
                                  style: Theme.of(context).textTheme.labelMedium,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Resumen ejecutivo',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: scheme.outlineVariant),
                              ),
                              child: Text(
                                rangeLabel,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ),
                          ],
                        ),
                  const SizedBox(height: 12),
                  if (isNarrow)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var index = 0; index < metrics.length; index++) ...[
                            metrics[index],
                            if (index != metrics.length - 1) const SizedBox(width: 10),
                          ],
                        ],
                      ),
                    )
                  else
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: metrics,
                    ),
                ],
              );
            },
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
    this.compact = false,
  });

  final String title;
  final String value;
  final String caption;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: compact ? 138 : 156,
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: compact ? 30 : 34,
            height: compact ? 30 : 34,
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: compact ? 16 : 18, color: scheme.primary),
          ),
          SizedBox(height: compact ? 6 : 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: compact ? 17 : null,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: compact ? 11 : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleBreakdownCard extends StatelessWidget {
  const _SimpleBreakdownCard({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.emptyText,
    this.totalLabel,
    this.fullWidth = false,
  });

  final String title;
  final String subtitle;
  final List<_ReportItem> items;
  final String emptyText;
  final String? totalLabel;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: fullWidth ? double.infinity : 360,
      child: Card(
        color: scheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              if (totalLabel != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.summarize_outlined, size: 16, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          totalLabel!,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (items.isEmpty)
                Text(emptyText)
              else
                for (var index = 0; index < items.length; index++) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.primary.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          items[index].label,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        items[index].value,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  if (index != items.length - 1) const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.title,
    required this.subtitle,
    required this.buckets,
    required this.totalQuotes,
    this.fullWidth = false,
  });

  final String title;
  final String subtitle;
  final List<_MonthBucket> buckets;
  final int totalQuotes;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxOrders = buckets.fold<int>(0, (max, item) => item.ordersCount > max ? item.ordersCount : max);
    final maxAmount = buckets.fold<num>(0, (max, item) => item.quotesAmount > max ? item.quotesAmount : max);
    final totalOrders = buckets.fold<int>(0, (sum, item) => sum + item.ordersCount);
    final totalAmount = buckets.fold<num>(0, (sum, item) => sum + item.quotesAmount);

    return SizedBox(
      width: fullWidth ? double.infinity : 520,
      child: Card(
        color: scheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TrendStatChip(
                    icon: Icons.inventory_2_outlined,
                    label: 'Total ordenes: $totalOrders',
                  ),
                  _TrendStatChip(
                    icon: Icons.request_quote_outlined,
                    label: 'Total compras: $totalQuotes',
                  ),
                  _TrendStatChip(
                    icon: Icons.attach_money_outlined,
                    label: 'Total monto: ${_money(totalAmount)}',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (buckets.isEmpty)
                const Text('Sin datos historicos suficientes.')
              else
                for (var index = 0; index < buckets.length; index++) ...[
                  _TrendRow(
                    bucket: buckets[index],
                    maxOrders: maxOrders,
                    maxAmount: maxAmount,
                  ),
                  if (index != buckets.length - 1) const SizedBox(height: 14),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendRow extends StatelessWidget {
  const _TrendRow({
    required this.bucket,
    required this.maxOrders,
    required this.maxAmount,
  });

  final _MonthBucket bucket;
  final int maxOrders;
  final num maxAmount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ordersFactor = maxOrders <= 0 ? 0.0 : bucket.ordersCount / maxOrders;
    final amountFactor = maxAmount <= 0 ? 0.0 : bucket.quotesAmount / maxAmount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 82,
              child: Text(
                bucket.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  _TrendStatChip(
                    icon: Icons.inventory_2_outlined,
                    label: '${bucket.ordersCount} ord',
                  ),
                  _TrendStatChip(
                    icon: Icons.request_quote_outlined,
                    label: '${bucket.quotesCount} compras',
                  ),
                  _TrendStatChip(
                    icon: Icons.attach_money_outlined,
                    label: _money(bucket.quotesAmount),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _TrendBar(
          label: 'Ordenes',
          factor: ordersFactor,
          color: scheme.primary,
          background: scheme.primary.withOpacity(0.12),
        ),
        const SizedBox(height: 6),
        _TrendBar(
          label: 'Monto',
          factor: amountFactor.toDouble(),
          color: scheme.tertiary,
          background: scheme.tertiary.withOpacity(0.12),
        ),
      ],
    );
  }
}

class _TrendStatChip extends StatelessWidget {
  const _TrendStatChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.primary),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _TrendBar extends StatelessWidget {
  const _TrendBar({
    required this.label,
    required this.factor,
    required this.color,
    required this.background,
  });

  final String label;
  final double factor;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: factor.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: background,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
      ],
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
