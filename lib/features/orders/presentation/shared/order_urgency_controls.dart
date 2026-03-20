import 'package:flutter/material.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';

enum OrderUrgencyFilter { all, normal, urgente }

const double orderModuleCompactAppBarBreakpoint = 640;

bool useCompactOrderModuleAppBar(BuildContext context) =>
    MediaQuery.sizeOf(context).width < orderModuleCompactAppBarBreakpoint;

bool matchesOrderUrgencyFilter(
  PurchaseOrder order,
  OrderUrgencyFilter filter,
) {
  switch (filter) {
    case OrderUrgencyFilter.all:
      return true;
    case OrderUrgencyFilter.normal:
      return order.urgency == PurchaseOrderUrgency.normal;
    case OrderUrgencyFilter.urgente:
      return order.urgency == PurchaseOrderUrgency.urgente;
  }
}

bool matchesOrderCreatedDateRange(
  PurchaseOrder order,
  DateTimeRange? range,
) {
  if (range == null) return true;
  final createdAt = order.createdAt;
  if (createdAt == null) return false;
  final createdDate = DateTime(createdAt.year, createdAt.month, createdAt.day);
  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day);
  return !createdDate.isBefore(start) && !createdDate.isAfter(end);
}

class OrderUrgencyCounts {
  const OrderUrgencyCounts({
    required this.total,
    required this.normal,
    required this.urgente,
  });

  final int total;
  final int normal;
  final int urgente;

  factory OrderUrgencyCounts.fromOrders(List<PurchaseOrder> orders) {
    var normal = 0;
    var urgente = 0;
    for (final order in orders) {
      switch (order.urgency) {
        case PurchaseOrderUrgency.normal:
          normal += 1;
          break;
        case PurchaseOrderUrgency.urgente:
          urgente += 1;
          break;
      }
    }
    return OrderUrgencyCounts(
      total: orders.length,
      normal: normal,
      urgente: urgente,
    );
  }
}

class OrderUrgencyFilterButton extends StatelessWidget {
  const OrderUrgencyFilterButton({
    required this.filter,
    required this.onSelected,
    super.key,
  });

  final OrderUrgencyFilter filter;
  final ValueChanged<OrderUrgencyFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<OrderUrgencyFilter>(
      initialValue: filter,
      onSelected: onSelected,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: OrderUrgencyFilter.all,
          child: Text('Todas'),
        ),
        PopupMenuItem(
          value: OrderUrgencyFilter.normal,
          child: Text('Normales'),
        ),
        PopupMenuItem(
          value: OrderUrgencyFilter.urgente,
          child: Text('Urgentes'),
        ),
      ],
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.filter_list,
                  size: 18,
                  color: theme.colorScheme.onSurface,
                ),
                const SizedBox(width: 8),
                Text(
                  filter.label,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.arrow_drop_down,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class OrderUrgencySummary extends StatelessWidget {
  const OrderUrgencySummary({
    required this.counts,
    this.selectedFilter = OrderUrgencyFilter.all,
    this.onSelected,
    this.compact = false,
    super.key,
  });

  final OrderUrgencyCounts counts;
  final OrderUrgencyFilter selectedFilter;
  final ValueChanged<OrderUrgencyFilter>? onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: compact ? 6 : 12,
      runSpacing: compact ? 6 : 12,
      children: [
        _OrderUrgencyCountCard(
          label: 'Totales',
          count: counts.total,
          compact: compact,
          selected: selectedFilter == OrderUrgencyFilter.all,
          onTap: onSelected == null
              ? null
              : () => onSelected!(OrderUrgencyFilter.all),
        ),
        _OrderUrgencyCountCard(
          label: 'Normales',
          count: counts.normal,
          compact: compact,
          selected: selectedFilter == OrderUrgencyFilter.normal,
          onTap: onSelected == null
              ? null
              : () => onSelected!(OrderUrgencyFilter.normal),
        ),
        _OrderUrgencyCountCard(
          label: 'Urgentes',
          count: counts.urgente,
          compact: compact,
          selected: selectedFilter == OrderUrgencyFilter.urgente,
          onTap: onSelected == null
              ? null
              : () => onSelected!(OrderUrgencyFilter.urgente),
        ),
      ],
    );
  }
}

class OrderModuleAppBarTitle extends StatelessWidget {
  const OrderModuleAppBarTitle({
    required this.title,
    required this.counts,
    required this.filter,
    required this.onSelected,
    this.trailing,
    super.key,
  });

  final String title;
  final OrderUrgencyCounts counts;
  final OrderUrgencyFilter filter;
  final ValueChanged<OrderUrgencyFilter> onSelected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(width: 10),
          OrderModuleAppBarActions(
            counts: counts,
            filter: filter,
            onSelected: onSelected,
            trailing: trailing,
          ),
        ],
      ),
    );
  }
}

class OrderModuleAppBarActions extends StatelessWidget {
  const OrderModuleAppBarActions({
    required this.counts,
    required this.filter,
    required this.onSelected,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(vertical: 4),
    this.alignment = Alignment.centerRight,
    super.key,
  });

  final OrderUrgencyCounts counts;
  final OrderUrgencyFilter filter;
  final ValueChanged<OrderUrgencyFilter> onSelected;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OrderUrgencySummary(
              counts: counts,
              selectedFilter: filter,
              onSelected: onSelected,
              compact: true,
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

class OrderModuleAppBarBottom extends StatelessWidget
    implements PreferredSizeWidget {
  const OrderModuleAppBarBottom({
    required this.counts,
    required this.filter,
    required this.onSelected,
    this.trailing,
    super.key,
  });

  final OrderUrgencyCounts counts;
  final OrderUrgencyFilter filter;
  final ValueChanged<OrderUrgencyFilter> onSelected;
  final Widget? trailing;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final dividerColor = Theme.of(context).dividerColor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: dividerColor.withOpacity(0.14)),
        ),
      ),
      child: OrderModuleAppBarActions(
        counts: counts,
        filter: filter,
        onSelected: onSelected,
        trailing: trailing,
        padding: const EdgeInsets.symmetric(vertical: 4),
      ),
    );
  }
}

class OrderDateRangeFilterButton extends StatelessWidget {
  const OrderDateRangeFilterButton({
    required this.selectedRange,
    required this.onPickDate,
    required this.onClearDate,
    super.key,
  });

  final DateTimeRange? selectedRange;
  final VoidCallback onPickDate;
  final VoidCallback onClearDate;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: onPickDate,
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text(_rangeLabel()),
        ),
        if (selectedRange != null) ...[
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Limpiar rango',
            onPressed: onClearDate,
            icon: const Icon(Icons.close),
          ),
        ],
      ],
    );
  }

  String _rangeLabel() {
    final range = selectedRange;
    if (range == null) return 'Rango de fechas';
    final start = range.start.toShortDate();
    final end = range.end.toShortDate();
    if (range.start.year == range.end.year &&
        range.start.month == range.end.month &&
        range.start.day == range.end.day) {
      return 'Fecha: $start';
    }
    return '$start - $end';
  }
}

extension on OrderUrgencyFilter {
  String get label {
    switch (this) {
      case OrderUrgencyFilter.all:
        return 'Todas';
      case OrderUrgencyFilter.normal:
        return 'Normales';
      case OrderUrgencyFilter.urgente:
        return 'Urgentes';
    }
  }
}

class _OrderUrgencyCountCard extends StatelessWidget {
  const _OrderUrgencyCountCard({
    required this.label,
    required this.count,
    required this.compact,
    required this.selected,
    this.onTap,
  });

  final String label;
  final int count;
  final bool compact;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final backgroundColor = selected
        ? colorScheme.primaryContainer
        : (compact ? colorScheme.surface : colorScheme.surfaceContainerHighest);
    final foregroundColor = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(compact ? 10 : 14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(compact ? 10 : 14),
        child: Container(
          constraints: BoxConstraints(minWidth: compact ? 62 : 108),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 14,
            vertical: compact ? 5 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 10 : 14),
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: (compact
                        ? theme.textTheme.labelSmall
                        : theme.textTheme.labelMedium)
                    ?.copyWith(
                      fontSize: compact ? 10 : null,
                      color: selected
                          ? foregroundColor
                          : colorScheme.onSurfaceVariant,
                    ),
              ),
              SizedBox(height: compact ? 2 : 4),
              Text(
                count.toString(),
                style: (compact
                        ? theme.textTheme.titleSmall
                        : theme.textTheme.headlineSmall)
                    ?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: foregroundColor,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
