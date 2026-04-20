import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:sistema_compras/core/access_control.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class ReportsPage extends ReportsScreen {
  const ReportsPage({super.key});
}

enum _ReportsQuickRange {
  all,
  today,
  sevenDays,
  thirtyDays,
  thisMonth,
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTimeRange? _dateRange;
  _ReportsQuickRange _quickRange = _ReportsQuickRange.all;

  @override
  Widget build(BuildContext context) {
        final user = ref.watch(currentUserProfileProvider).value;
    final canView = canViewReports(user);
    final ordersAsync = ref.watch(allOrdersProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F7FB),
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: Navigator.of(context).canPop(),
        titleSpacing: 16,
        title: ReportsHeader(
          title: 'Reportes',
          rangeLabel: _rangeLabel(_dateRange, _quickRange),
          onPickRange: _pickRange,
          onClear: _clearRange,
        ),
      ),
      body: !canView
          ? const Center(child: Text('No tienes permisos para ver reportes.'))
          : ordersAsync.when(
              data: (orders) {
                final data = _buildReportsData(
                  orders: orders,
                  now: DateTime.now(),
                  dateRange: _effectiveRange(DateTime.now()),
                );
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    FilterChipGroup(
                      activeRange: _quickRange,
                      onSelected: _selectQuickRange,
                    ),
                    const SizedBox(height: 18),
                    _ExecutiveSummarySection(data: data),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 980;
                        final left = TopSuppliersCard(data: data);
                        final right = OrdersTrendCard(data: data);
                        if (!isWide) {
                          return Column(
                            children: [
                              left,
                              const SizedBox(height: 16),
                              right,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 9, child: left),
                            const SizedBox(width: 16),
                            Expanded(flex: 11, child: right),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    const InfoBanner(
                      text:
                          'Los reportes se generan con base en la fecha de creación de las órdenes.',
                    ),
                  ],
                );
              },
              loading: () => const AppSplash(),
              error: (error, stack) => Center(
                child: Text(
                  reportError(error, stack, context: 'ReportsScreen'),
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
    if (picked == null || !mounted) return;
    setState(() {
      _quickRange = _ReportsQuickRange.all;
      _dateRange = DateTimeRange(
        start: DateTime(picked.start.year, picked.start.month, picked.start.day),
        end: DateTime(picked.end.year, picked.end.month, picked.end.day),
      );
    });
  }

  void _clearRange() {
    setState(() {
      _quickRange = _ReportsQuickRange.all;
      _dateRange = null;
    });
  }

  void _selectQuickRange(_ReportsQuickRange range) {
    setState(() {
      _quickRange = range;
      _dateRange = null;
    });
  }

  DateTimeRange? _effectiveRange(DateTime now) {
    if (_dateRange != null) return _dateRange;
    switch (_quickRange) {
      case _ReportsQuickRange.all:
        return null;
      case _ReportsQuickRange.today:
        return DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: DateTime(now.year, now.month, now.day),
        );
      case _ReportsQuickRange.sevenDays:
        final start = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 6));
        final end = DateTime(now.year, now.month, now.day);
        return DateTimeRange(start: start, end: end);
      case _ReportsQuickRange.thirtyDays:
        final start = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 29));
        final end = DateTime(now.year, now.month, now.day);
        return DateTimeRange(start: start, end: end);
      case _ReportsQuickRange.thisMonth:
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month + 1, 0),
        );
    }
  }
}

class ReportsHeader extends StatelessWidget {
  const ReportsHeader({
    super.key,
    required this.title,
    required this.rangeLabel,
    required this.onPickRange,
    required this.onClear,
  });

  final String title;
  final String rangeLabel;
  final VoidCallback onPickRange;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: _softShadow,
          ),
          child: const Icon(Icons.menu_rounded),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: onPickRange,
          icon: const Icon(Icons.date_range_outlined),
          label: Text(rangeLabel),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: onClear,
          icon: const Icon(Icons.restart_alt_outlined),
          label: const Text('Limpiar'),
        ),
      ],
    );
  }
}

class FilterChipGroup extends StatelessWidget {
  const FilterChipGroup({
    super.key,
    required this.activeRange,
    required this.onSelected,
  });

  final _ReportsQuickRange activeRange;
  final ValueChanged<_ReportsQuickRange> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _QuickRangeChip(
          label: 'Todo el historial',
          selected: activeRange == _ReportsQuickRange.all,
          onTap: () => onSelected(_ReportsQuickRange.all),
        ),
        _QuickRangeChip(
          label: 'Hoy',
          selected: activeRange == _ReportsQuickRange.today,
          onTap: () => onSelected(_ReportsQuickRange.today),
        ),
        _QuickRangeChip(
          label: '7 días',
          selected: activeRange == _ReportsQuickRange.sevenDays,
          onTap: () => onSelected(_ReportsQuickRange.sevenDays),
        ),
        _QuickRangeChip(
          label: '30 días',
          selected: activeRange == _ReportsQuickRange.thirtyDays,
          onTap: () => onSelected(_ReportsQuickRange.thirtyDays),
        ),
        _QuickRangeChip(
          label: 'Este mes',
          selected: activeRange == _ReportsQuickRange.thisMonth,
          onTap: () => onSelected(_ReportsQuickRange.thisMonth),
        ),
      ],
    );
  }
}

class _QuickRangeChip extends StatelessWidget {
  const _QuickRangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
          boxShadow: selected ? _softShadow : null,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? scheme.onPrimary : scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

class _ExecutiveSummarySection extends StatelessWidget {
  const _ExecutiveSummarySection({required this.data});

  final _ReportsData data;

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen ejecutivo',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SummaryKpiCard(
                title: 'Órdenes',
                value: '${data.totalOrders}',
                subtitle: 'registradas en el rango',
                icon: Icons.inventory_2_outlined,
                tone: const Color(0xFF3B82F6),
              ),
              SummaryKpiCard(
                title: 'Activas',
                value: '${data.activeOrders}',
                subtitle: 'siguen en flujo',
                icon: Icons.play_circle_outline,
                tone: const Color(0xFF16A34A),
              ),
              SummaryKpiCard(
                title: 'Finalizadas',
                value: '${data.completedOrders}',
                subtitle: 'cerradas correctamente',
                icon: Icons.task_alt_outlined,
                tone: const Color(0xFF10B981),
              ),
              SummaryKpiCard(
                title: 'Rechazadas',
                value: '${data.rejectedOrders}',
                subtitle: 'devueltas o canceladas',
                icon: Icons.close_rounded,
                tone: const Color(0xFFEF4444),
              ),
              SummaryKpiCard(
                title: 'Urgentes',
                value: '${data.urgentOrders}',
                subtitle: 'prioridad alta',
                icon: Icons.priority_high_outlined,
                tone: const Color(0xFFF59E0B),
              ),
              SummaryKpiCard(
                title: 'Con proveedor',
                value: '${data.ordersWithSupplier}',
                subtitle: 'ya asignadas',
                icon: Icons.local_shipping_outlined,
                tone: const Color(0xFF60A5FA),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SummaryKpiCard extends StatelessWidget {
  const SummaryKpiCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.tone,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 180),
      child: _DashboardCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: tone.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: tone),
            ),
            const SizedBox(height: 18),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class TopSuppliersCard extends StatelessWidget {
  const TopSuppliersCard({super.key, required this.data});

  final _ReportsData data;

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top proveedores por orden',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Órdenes acumuladas por proveedor en el rango',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6B7280),
                ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'Total con proveedor: ${data.ordersWithSupplier}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1D4ED8),
                  ),
            ),
          ),
          const SizedBox(height: 16),
          if (data.supplierItems.isEmpty)
            Text(
              'Sin proveedores en el rango.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            Column(
              children: [
                for (final entry in data.supplierItems.take(8).indexed)
                  Padding(
                    padding: EdgeInsets.only(bottom: entry.$1 == math.min(7, data.supplierItems.length - 1) ? 0 : 14),
                    child: SupplierRow(
                      rank: entry.$1 + 1,
                      item: entry.$2,
                      maxValue: data.supplierItems.first.order,
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: () {},
            child: const Text('Ver todos los proveedores'),
          ),
        ],
      ),
    );
  }
}

class SupplierRow extends StatelessWidget {
  const SupplierRow({
    super.key,
    required this.rank,
    required this.item,
    required this.maxValue,
  });

  final int rank;
  final _ReportItem item;
  final num maxValue;

  @override
  Widget build(BuildContext context) {
    final ratio = maxValue <= 0 ? 0.0 : item.order / maxValue;
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$rank',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1D4ED8),
                    ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              item.value,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF6B7280),
                  ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: ratio.clamp(0.0, 1.0),
            backgroundColor: const Color(0xFFE5E7EB),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
          ),
        ),
      ],
    );
  }
}

class OrdersTrendCard extends StatelessWidget {
  const OrdersTrendCard({super.key, required this.data});

  final _ReportsData data;

  @override
  Widget build(BuildContext context) {
    final totalOrders = data.monthlyTrendBuckets.fold<int>(
      0,
      (sum, bucket) => sum + bucket.ordersCount,
    );
    return _DashboardCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tendencia de órdenes',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Últimos 6 meses de órdenes registradas',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF6B7280),
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _SoftInfoChip(label: 'Por mes'),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SoftInfoChip(label: 'Total órdenes: $totalOrders'),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 260,
            child: _OrdersTrendChart(buckets: data.monthlyTrendBuckets),
          ),
        ],
      ),
    );
  }
}

class _OrdersTrendChart extends StatelessWidget {
  const _OrdersTrendChart({required this.buckets});

  final List<_MonthBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final maxValue = buckets.fold<int>(0, (max, bucket) => math.max(max, bucket.ordersCount));
    final chartMax = math.max(1, maxValue);
    final guideValues = <int>[chartMax, (chartMax / 2).ceil(), 0];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 28,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final value in guideValues)
                Text(
                  '$value',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF94A3B8),
                      ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var index = 0; index < 3; index++)
                          Container(height: 1, color: const Color(0xFFE5E7EB)),
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final bucket in buckets)
                          Expanded(
                            child: _TrendBarColumn(
                              bucket: bucket,
                              maxValue: chartMax,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final bucket in buckets)
                    Expanded(
                      child: Center(
                        child: Text(
                          bucket.shortLabel,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF64748B),
                              ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrendBarColumn extends StatelessWidget {
  const _TrendBarColumn({
    required this.bucket,
    required this.maxValue,
  });

  final _MonthBucket bucket;
  final int maxValue;

  @override
  Widget build(BuildContext context) {
    final heightFactor = maxValue <= 0 ? 0.0 : bucket.ordersCount / maxValue;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (bucket.ordersCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${bucket.ordersCount}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            )
          else
            const SizedBox(height: 28),
          Flexible(
            child: FractionallySizedBox(
              heightFactor: heightFactor.clamp(0.0, 1.0),
              alignment: Alignment.bottomCenter,
              child: Container(
                width: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.info_outline, color: Color(0xFF0284C7)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF475569),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: _softShadow,
      ),
      child: child,
    );
  }
}

class _SoftInfoChip extends StatelessWidget {
  const _SoftInfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

_ReportsData _buildReportsData({
  required List<PurchaseOrder> orders,
  required DateTime now,
  required DateTimeRange? dateRange,
}) {
  final filteredOrders = orders
      .where((order) => _matchesRange(order.createdAt, dateRange))
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
  final ordersWithSupplier = filteredOrders.where((order) {
    if ((order.supplier ?? '').trim().isNotEmpty) return true;
    return order.items.any((item) => (item.supplier ?? '').trim().isNotEmpty);
  }).length;

  return _ReportsData(
    totalOrders: filteredOrders.length,
    activeOrders: activeOrders.length,
    completedOrders: completedOrders.length,
    rejectedOrders: rejectedOrders.length,
    urgentOrders: urgentOrders.length,
    ordersWithSupplier: ordersWithSupplier,
    supplierItems: _buildSupplierItems(filteredOrders),
    monthlyTrendBuckets: _buildMonthlyTrendBuckets(now: now, orders: filteredOrders),
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
  return order.isRejectedDraft || order.isRejectedPendingAcknowledgment;
}

List<_ReportItem> _buildSupplierItems(List<PurchaseOrder> orders) {
  final totals = <String, int>{};
  for (final order in orders) {
    final seen = <String>{};
    final directSupplier = (order.supplier ?? '').trim();
    if (directSupplier.isNotEmpty) {
      seen.add(directSupplier);
    }
    for (final item in order.items) {
      final supplier = (item.supplier ?? '').trim();
      if (supplier.isNotEmpty) {
        seen.add(supplier);
      }
    }
    for (final supplier in seen) {
      totals[supplier] = (totals[supplier] ?? 0) + 1;
    }
  }
  final items = totals.entries
      .map(
        (entry) => _ReportItem(
          label: entry.key,
          value: '${entry.value} ord',
          order: entry.value,
        ),
      )
      .toList(growable: false)
    ..sort((a, b) => b.order.compareTo(a.order));
  return items;
}

List<_MonthBucket> _buildMonthlyTrendBuckets({
  required DateTime now,
  required List<PurchaseOrder> orders,
}) {
  final buckets = <String, _MonthBucket>{};
  for (var offset = 5; offset >= 0; offset--) {
    final date = DateTime(now.year, now.month - offset, 1);
    final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
    buckets[key] = _MonthBucket(date: date, ordersCount: 0);
  }
  for (final order in orders) {
    final createdAt = order.createdAt;
    if (createdAt == null) continue;
    final key = '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}';
    final bucket = buckets[key];
    if (bucket == null) continue;
    bucket.ordersCount += 1;
  }
  return buckets.values.toList(growable: false);
}

String _rangeLabel(DateTimeRange? explicitRange, _ReportsQuickRange quickRange) {
  if (explicitRange != null) {
    return '${explicitRange.start.toShortDate()} - ${explicitRange.end.toShortDate()}';
  }
  switch (quickRange) {
    case _ReportsQuickRange.all:
      return 'Rango de fechas';
    case _ReportsQuickRange.today:
      return 'Hoy';
    case _ReportsQuickRange.sevenDays:
      return '7 días';
    case _ReportsQuickRange.thirtyDays:
      return '30 días';
    case _ReportsQuickRange.thisMonth:
      return 'Este mes';
  }
}

class _ReportsData {
  const _ReportsData({
    required this.totalOrders,
    required this.activeOrders,
    required this.completedOrders,
    required this.rejectedOrders,
    required this.urgentOrders,
    required this.ordersWithSupplier,
    required this.supplierItems,
    required this.monthlyTrendBuckets,
  });

  final int totalOrders;
  final int activeOrders;
  final int completedOrders;
  final int rejectedOrders;
  final int urgentOrders;
  final int ordersWithSupplier;
  final List<_ReportItem> supplierItems;
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
    required this.date,
    required this.ordersCount,
  });

  final DateTime date;
  int ordersCount;

  String get shortLabel => DateFormat('MMM').format(date);
}

const List<BoxShadow> _softShadow = [
  BoxShadow(
    color: Color(0x120F172A),
    blurRadius: 24,
    offset: Offset(0, 10),
  ),
];
