import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/core/widgets/info_action.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_status_duration.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

class DireccionOrdersScreen extends ConsumerStatefulWidget {
  const DireccionOrdersScreen({super.key});

  @override
  ConsumerState<DireccionOrdersScreen> createState() =>
      _DireccionOrdersScreenState();
}

class _DireccionOrdersScreenState extends ConsumerState<DireccionOrdersScreen> {
  late final TextEditingController _searchController;
  final OrderSearchCache _searchCache = OrderSearchCache();
  Timer? _searchDebounce;
  String _searchQuery = '';
  int _limit = defaultOrderPageSize;
  final Set<String> _busyOrders = <String>{};

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _updateSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _searchQuery = value);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  void _loadMore() {
    setState(() => _limit += orderPageSizeStep);
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(pendingDireccionOrdersPagedProvider(_limit));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dirección General'),
        actions: [
          infoAction(
            context,
            title: 'Dirección General',
            message:
                'Revisa ordenes con cotizacion asignada.\n'
                'Abre una orden para decidir.\n'
                'El dashboard muestra links agrupados.',
          ),
        ],
      ),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('No hay órdenes pendientes.'));
          }

          _searchCache.retainFor(orders);
          final filtered = orders
              .where((order) => orderMatchesSearch(order, _searchQuery, cache: _searchCache))
              .toList();
          final canLoadMore = orders.length >= _limit;

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
                            onPressed: _clearSearch,
                          ),
                  ),
                  onChanged: _updateSearch,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filtered.isEmpty
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('No hay órdenes con ese filtro.'),
                          if (canLoadMore) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _loadMore,
                              icon: const Icon(Icons.expand_more),
                              label: const Text('Ver más'),
                            ),
                          ],
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length + (canLoadMore ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index >= filtered.length) {
                            return Center(
                              child: OutlinedButton.icon(
                                onPressed: _loadMore,
                                icon: const Icon(Icons.expand_more),
                                label: const Text('Ver más'),
                              ),
                            );
                          }
                          final order = filtered[index];
                          final busy = _busyOrders.contains(order.id);
                          return _DireccionOrderCard(
                            order: order,
                            busy: busy,
                            onReview: () =>
                                guardedPush(context, '/orders/direccion/${order.id}'),
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
            'Error: ${reportError(error, stack, context: 'DireccionOrdersScreen')}',
          ),
        ),
      ),
    );
  }
}

class _DireccionOrderCard extends ConsumerWidget {
  const _DireccionOrderCard({
    required this.order,
    required this.busy,
    required this.onReview,
  });

  final PurchaseOrder order;
  final bool busy;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authorizedBy = order.comprasReviewerName?.trim() ?? '';
    final resubmissionCount = order.direccionReturnCount;
    final eventsAsync = ref.watch(orderEventsProvider(order.id));

    final baseSmall = Theme.of(context).textTheme.bodySmall;
    final smallBlue = (baseSmall?.copyWith(color: Colors.blue.shade900)) ??
        TextStyle(color: Colors.blue.shade900);

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
                if (resubmissionCount > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade400),
                    ),
                    child: Text(
                      'Reenvío ${resubmissionCount}x',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Solicitante: ${order.requesterName}'),
            Text('Urgencia: ${order.urgency.label}'),
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: DefaultTextStyle(
                style: smallBlue,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Área: ${order.areaName}'),
                    const SizedBox(height: 4),

                    // ✅ Reemplazo del widget corrupto:
                    _OrderCardSummary(order: order),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            eventsAsync.when(
              data: (events) {
                final prev = _previousStatusDuration(order, events);
                if (prev == null) return const SizedBox.shrink();
                return StatusDurationPill(
                  text:
                      'Tiempo en ${prev.status.label}: ${formatDurationLabel(prev.duration)}',
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            if (authorizedBy.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Autorizó: $authorizedBy'),
            ],
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 360;

                final button = FilledButton.tonal(
                  onPressed: busy ? null : onReview,
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: AppSplash(compact: true, size: 18),
                        )
                      : const Text('Ver orden'),
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [button],
                  );
                }

                return Align(
                  alignment: Alignment.centerLeft,
                  child: button,
                );
              },
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
    final comprasComment = (order.comprasComment ?? '').trim();
    final clientNote = (order.clientNote ?? '').trim();

    final lines = <String>[
      'Estado: ${order.status.label}',
      if (supplier.isNotEmpty) 'Proveedor: $supplier',
      if (internalOrder.isNotEmpty) 'OC interna: $internalOrder',
      if (order.budget != null) 'Presupuesto: ${order.budget}',
      if (comprasComment.isNotEmpty) 'Compras: $comprasComment',
      if (clientNote.isNotEmpty) 'Nota: $clientNote',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines) ...[
          Text(line),
          const SizedBox(height: 2),
        ],
      ],
    );
  }
}

class _PreviousStatusDuration {
  const _PreviousStatusDuration(this.status, this.duration);

  final PurchaseOrderStatus status;
  final Duration duration;
}

_PreviousStatusDuration? _previousStatusDuration(
  PurchaseOrder order,
  List<PurchaseOrderEvent> events,
) {
  if (events.isEmpty) return null;

  PurchaseOrderEvent? enterCurrent;
  for (final event in events.reversed) {
    if (event.toStatus == order.status && event.timestamp != null) {
      enterCurrent = event;
      break;
    }
  }
  if (enterCurrent == null) return null;

  final prevStatus = enterCurrent.fromStatus;
  final currentTimestamp = enterCurrent.timestamp;
  if (prevStatus == null || currentTimestamp == null) return null;

  PurchaseOrderEvent? enterPrev;
  for (final event in events.reversed) {
    if (event.toStatus == prevStatus &&
        event.timestamp != null &&
        !event.timestamp!.isAfter(currentTimestamp)) {
      enterPrev = event;
      break;
    }
  }
  if (enterPrev == null) return null;

  final duration = currentTimestamp.difference(enterPrev.timestamp!);
  if (duration.isNegative) return null;

  return _PreviousStatusDuration(prevStatus, duration);
}



