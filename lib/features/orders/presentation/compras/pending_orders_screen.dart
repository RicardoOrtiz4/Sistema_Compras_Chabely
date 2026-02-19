import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';

class PendingOrdersScreen extends ConsumerStatefulWidget {
  const PendingOrdersScreen({super.key});

  @override
  ConsumerState<PendingOrdersScreen> createState() => _PendingOrdersScreenState();
}

class _PendingOrdersScreenState extends ConsumerState<PendingOrdersScreen> {
  late final TextEditingController _searchController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(pendingComprasOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Órdenes por confirmar'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
      ),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('No hay órdenes por confirmar.'));
          }

          final filtered = orders
              .where((order) => orderMatchesSearch(order, _searchQuery))
              .toList();

          final branding = ref.read(currentBrandingProvider);
          prefetchOrderPdfsForOrders(filtered, branding: branding);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText:
                        'Buscar por folio (000001), solicitante, cliente, fecha...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No hay órdenes con ese filtro.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final order = filtered[index];
                          return _PendingOrderCard(
                            order: order,
                            onReview: () => context.push('/orders/review/${order.id}'),
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            'Error: ${reportError(error, stack, context: 'PendingOrdersScreen')}',
          ),
        ),
      ),
    );
  }
}

class _PendingOrderCard extends ConsumerWidget {
  const _PendingOrderCard({
    required this.order,
    required this.onReview,
  });

  final PurchaseOrder order;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final createdLabel = order.createdAt?.toFullDateTime() ?? 'Pendiente';

    final returnCount = order.returnCount;
    final wasReturned = returnCount > 0 ||
        (order.lastReturnReason != null &&
            order.lastReturnReason!.trim().isNotEmpty);

    final eventsAsync = wasReturned ? ref.watch(orderEventsProvider(order.id)) : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (wasReturned)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade400),
                    ),
                    child: Text(
                      returnCount > 1 ? 'Reenviada x$returnCount' : 'Reenviada',
                      style: TextStyle(
                        color: Colors.red.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Solicitante: ${order.requesterName}'),
            Text('Área: ${order.areaName}'),
            Text('Urgencia: ${order.urgency.label}'),
            Text('Creada: $createdLabel'),
            const SizedBox(height: 8),

            // ✅ Reemplazo del widget corrupto:
            _OrderCardSummary(order: order),

            if (wasReturned)
              eventsAsync!.when(
                data: (events) {
                  final duration = _timeInRejected(order, events);
                  if (duration == null) return const SizedBox.shrink();
                  return Text('Tiempo en rechazadas: ${_formatDuration(duration)}');
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

            if (wasReturned && order.updatedAt != null)
              Text('Modificada: ${order.updatedAt!.toFullDateTime()}'),

            if (order.direccionComment != null &&
                order.direccionComment!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.comment_outlined,
                        color: Colors.blue.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Comentario Dirección General: ${order.direccionComment}',
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onReview,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Revisar PDF'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderCardSummary extends StatelessWidget {
  const _OrderCardSummary({required this.order});
  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    final supplier = (order.supplier ?? '').trim();
    final internalOrder = (order.internalOrder ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Estado: ${order.status.label}'),
        if (supplier.isNotEmpty) Text('Proveedor: $supplier'),
        if (internalOrder.isNotEmpty) Text('OC interna: $internalOrder'),
        if (order.budget != null) Text('Presupuesto: ${order.budget}'),
      ],
    );
  }
}

Duration? _timeInRejected(
  PurchaseOrder order,
  List<PurchaseOrderEvent> events,
) {
  if (order.returnCount <= 0) return null;

  PurchaseOrderEvent? lastSubmission;
  for (final event in events) {
    if (event.fromStatus == PurchaseOrderStatus.draft &&
        event.toStatus == PurchaseOrderStatus.pendingCompras &&
        event.timestamp != null) {
      if (lastSubmission == null ||
          event.timestamp!.isAfter(lastSubmission.timestamp!)) {
        lastSubmission = event;
      }
    }
  }
  if (lastSubmission == null) return null;

  PurchaseOrderEvent? lastReturn;
  for (final event in events) {
    if (event.type == 'return' &&
        event.toStatus == PurchaseOrderStatus.draft &&
        event.timestamp != null &&
        event.timestamp!.isBefore(lastSubmission.timestamp!)) {
      if (lastReturn == null ||
          event.timestamp!.isAfter(lastReturn.timestamp!)) {
        lastReturn = event;
      }
    }
  }
  if (lastReturn == null) return null;

  final duration = lastSubmission.timestamp!.difference(lastReturn.timestamp!);
  if (duration.isNegative) return null;
  return duration;
}

String _formatDuration(Duration duration) {
  final totalMinutes = duration.inMinutes;
  if (totalMinutes <= 0) {
    return 'menos de 1 min';
  }

  final days = duration.inDays;
  final hours = duration.inHours % 24;
  final minutes = duration.inMinutes % 60;

  if (days > 0) {
    final dayLabel = days == 1 ? 'día' : 'días';
    final hourPart = hours > 0 ? ' $hours h' : '';
    return '$days $dayLabel$hourPart';
  }
  if (hours > 0) {
    final minutePart = minutes > 0 ? ' $minutes min' : '';
    return '$hours h$minutePart';
  }
  return '$minutes min';
}
