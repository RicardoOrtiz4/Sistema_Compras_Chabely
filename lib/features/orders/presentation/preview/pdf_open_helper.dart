import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_pdf_preload_gate.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_status_duration.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

class RejectedOrdersScreen extends ConsumerStatefulWidget {
  const RejectedOrdersScreen({super.key});

  @override
  ConsumerState<RejectedOrdersScreen> createState() =>
      _RejectedOrdersScreenState();
}

class _RejectedOrdersScreenState extends ConsumerState<RejectedOrdersScreen> {
  List<PurchaseOrder>? _cachedSourceOrders;
  String? _cachedVisibleKey;
  List<PurchaseOrder>? _cachedVisibleOrders;

  late final TextEditingController _searchController;
  final OrderSearchCache _searchCache = OrderSearchCache();
  Timer? _searchDebounce;
  String _searchQuery = '';
  int _limit = defaultOrderPageSize;

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
      _searchDebounce = null;
      setState(() => _searchQuery = value);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = null;
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  void _loadMore() {
    setState(() => _limit += orderPageSizeStep);
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(rejectedOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ordenes rechazadas'),
      ),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('No hay órdenes rechazadas.'));
          }

          _searchCache.retainFor(orders);
          final filtered = _resolveVisibleOrders(orders);
          final visibleOrders = filtered.take(_limit).toList(growable: false);
          final showLoadMore = filtered.length > visibleOrders.length;

          final content = Column(
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
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'Las limpiezas se ejecutan de forma anual mediante un programa externo. '
                  'Considera respaldar las órdenes rechazadas si las necesitas.',
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: visibleOrders.isEmpty
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('No hay órdenes con ese filtro.'),
                          if (showLoadMore) ...[
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
                        itemCount: visibleOrders.length + (showLoadMore ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index >= visibleOrders.length) {
                            return Center(
                              child: OutlinedButton.icon(
                                onPressed: _loadMore,
                                icon: const Icon(Icons.expand_more),
                                label: const Text('Ver más'),
                              ),
                            );
                          }
                          final order = visibleOrders[index];
                          return _RejectedOrderCard(
                            order: order,
                          );
                        },
                      ),
              ),
            ],
          );
          return OrderPdfPreloadGate(
            orders: visibleOrders,
            enabled: _searchDebounce == null && _searchQuery.trim().isEmpty,
            child: content,
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            'Error: ${reportError(error, stack, context: 'RejectedOrdersScreen')}',
          ),
        ),
      ),
    );
  }

  List<PurchaseOrder> _resolveVisibleOrders(List<PurchaseOrder> orders) {
    final key = _visibleOrdersKey();
    final cached = _cachedVisibleOrders;
    if (cached != null &&
        identical(_cachedSourceOrders, orders) &&
        _cachedVisibleKey == key) {
      return cached;
    }

    final trimmedQuery = _searchQuery.trim();
    final resolved = trimmedQuery.isEmpty
        ? orders
        : orders
              .where(
                (order) => orderMatchesSearch(
                  order,
                  trimmedQuery,
                  cache: _searchCache,
                ),
              )
              .toList(growable: false);
    _cachedSourceOrders = orders;
    _cachedVisibleKey = key;
    _cachedVisibleOrders = resolved;
    return resolved;
  }

  String _visibleOrdersKey() => _searchQuery.trim().toLowerCase();
}

class _RejectedOrderCard extends ConsumerWidget {
  const _RejectedOrderCard({
    required this.order,
  });

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pdfRoute = '/orders/${order.id}/pdf';

    final reason = (order.lastReturnReason ?? '').trim();
    final lastReturn = ref.watch(orderEventsProvider(order.id)).maybeWhen(
      data: (events) {
        PurchaseOrderEvent? lastReturn;
        for (final event in events) {
          if (event.type == 'return') {
            lastReturn = event;
          }
        }
        return lastReturn;
      },
      orElse: () => null,
    );
    final rejectedBy = _rejectedByLabel(lastReturn?.byRole);
    final rejectedFrom = _rejectedFromLabel(lastReturn?.fromStatus);

    /*
      data: (events) {
        PurchaseOrderEvent? lastReturn;
        for (final event in events) {
          if (event.type == 'return') {
            lastReturn = event; // quedarnos con el último
          }
        }
        return _rejectedByLabel(lastReturn?.byRole);
      },
      orElse: () => 'Compras',
    );
    */

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Chip(label: Text('Rechazada por $rejectedBy'))]),
            const SizedBox(height: 8),
            Text('Motivo: ${reason.isEmpty ? 'Sin comentario' : reason}'),
            const SizedBox(height: 6),
            OrderStatusDurationPill(
              order: order,
              label: 'Tiempo en $rejectedFrom',
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => guardedPdfPush(context, pdfRoute),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Ver PDF'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _rejectedByLabel(String? rawRole) {
  final normalized = normalizeAreaLabel((rawRole ?? '').trim());
  if (normalized.isEmpty) {
    return 'Compras';
  }
  if (isComprasLabel(normalized)) {
    return 'Compras';
  }
  if (isDireccionGeneralLabel(normalized)) {
    return 'Dirección General';
  }

  return normalized;
}

String _rejectedFromLabel(PurchaseOrderStatus? status) {
  switch (status) {
    case PurchaseOrderStatus.pendingCompras:
      return 'ordenes por confirmar';
    case PurchaseOrderStatus.cotizaciones:
      return 'cotizaciones';
    case PurchaseOrderStatus.authorizedGerencia:
      return 'Direccion General';
    case PurchaseOrderStatus.paymentDone:
      return 'pendientes de fecha estimada';
    case PurchaseOrderStatus.contabilidad:
      return 'contabilidad';
    case PurchaseOrderStatus.almacen:
      return 'almacen';
    case PurchaseOrderStatus.orderPlaced:
      return 'orden realizada';
    case PurchaseOrderStatus.eta:
      return 'orden finalizada';
    case PurchaseOrderStatus.draft:
    case null:
      return 'correccion';
  }
}

