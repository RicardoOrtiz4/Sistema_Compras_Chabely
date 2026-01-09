import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';

class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen> {
  PurchaseOrderStatus? statusFilter;
  PurchaseOrderUrgency? urgencyFilter;
  DateTimeRange? dateRange;

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(userOrdersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de �rdenes')),
      body: ordersAsync.when(
        data: (orders) {
          final filtered = orders.where(_filterOrder).toList();
          if (filtered.isEmpty) {
            return _EmptyHistory(onCreate: () => context.push('/orders/create'));
          }
          return Column(
            children: [
              _FiltersBar(
                statusFilter: statusFilter,
                urgencyFilter: urgencyFilter,
                dateRange: dateRange,
                onStatusChanged: (value) => setState(() => statusFilter = value),
                onUrgencyChanged: (value) => setState(() => urgencyFilter = value),
                onDateRangeChanged: (range) => setState(() => dateRange = range),
                onClear: () => setState(() {
                  statusFilter = null;
                  urgencyFilter = null;
                  dateRange = null;
                }),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final order = filtered[index];
                    return _OrderHistoryCard(order: order);
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
    );
  }

  bool _filterOrder(PurchaseOrder order) {
    final statusOk = statusFilter == null || order.status == statusFilter;
    final urgencyOk = urgencyFilter == null || order.urgency == urgencyFilter;
    final dateOk = dateRange == null ||
        (order.createdAt != null &&
            order.createdAt!.isAfter(dateRange!.start.subtract(const Duration(days: 1))) &&
            order.createdAt!.isBefore(dateRange!.end.add(const Duration(days: 1))));
    return statusOk && urgencyOk && dateOk;
  }
}

class _FiltersBar extends StatelessWidget {
  const _FiltersBar({
    required this.statusFilter,
    required this.urgencyFilter,
    required this.dateRange,
    required this.onStatusChanged,
    required this.onUrgencyChanged,
    required this.onDateRangeChanged,
    required this.onClear,
  });

  final PurchaseOrderStatus? statusFilter;
  final PurchaseOrderUrgency? urgencyFilter;
  final DateTimeRange? dateRange;
  final ValueChanged<PurchaseOrderStatus?> onStatusChanged;
  final ValueChanged<PurchaseOrderUrgency?> onUrgencyChanged;
  final ValueChanged<DateTimeRange?> onDateRangeChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<PurchaseOrderStatus?>(
              value: statusFilter,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos')),
                ...PurchaseOrderStatus.values
                    .where((status) => status != PurchaseOrderStatus.draft)
                    .map((status) => DropdownMenuItem(
                          value: status,
                          child: Text(status.label),
                        )),
              ],
              onChanged: onStatusChanged,
            ),
          ),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<PurchaseOrderUrgency?>(
              value: urgencyFilter,
              decoration: const InputDecoration(labelText: 'Urgencia'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todas')),
                ...PurchaseOrderUrgency.values.map((urgency) => DropdownMenuItem(
                      value: urgency,
                      child: Text(urgency.label),
                    )),
              ],
              onChanged: onUrgencyChanged,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                currentDate: DateTime.now(),
                initialDateRange: dateRange,
              );
              onDateRangeChanged(picked);
            },
            icon: const Icon(Icons.calendar_today),
            label: Text(
              dateRange == null
                  ? 'Rango de fechas'
                  : '${dateRange!.start.toShortDate()} - ${dateRange!.end.toShortDate()}',
            ),
          ),
          TextButton(onPressed: onClear, child: const Text('Limpiar filtros')),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox, size: 48),
            const SizedBox(height: 12),
            const Text('A�n no hay �rdenes registradas'),
            const SizedBox(height: 12),
            FilledButton(onPressed: onCreate, child: const Text('Crear primera orden')),
          ],
        ),
      ),
    );
  }
}

class _OrderHistoryCard extends ConsumerWidget {
  const _OrderHistoryCard({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: InkWell(
        onTap: () => context.push('/orders/${order.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(order.folio ?? 'Sin folio',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  Chip(label: Text(order.urgency.label)),
                ],
              ),
              const SizedBox(height: 8),
              Text('Estado: ${order.status.label}'),
              if (order.lastReturnReason != null) ...[
                const SizedBox(height: 4),
                Text('�ltimo comentario: ${order.lastReturnReason}'),
              ],
              const SizedBox(height: 8),
              Text('Creada: ${order.createdAt?.toFullDateTime() ?? 'Pendiente'}'),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _statusProgress(order.status),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _statusProgress(PurchaseOrderStatus status) {
    final index = defaultStatusFlow.indexOf(status);
    if (index == -1) return 0;
    return (index + 1) / defaultStatusFlow.length;
  }
}
