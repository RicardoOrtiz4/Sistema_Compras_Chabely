import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_pdf_preload_gate.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_status_duration.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_summary_lines.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

class PendingOrdersScreen extends ConsumerStatefulWidget {
  const PendingOrdersScreen({super.key});

  @override
  ConsumerState<PendingOrdersScreen> createState() =>
      _PendingOrdersScreenState();
}

class _PendingOrdersScreenState extends ConsumerState<PendingOrdersScreen> {
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
              guardedGo(context, '/home');
            }
          },
        ),
      ),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('No hay órdenes por confirmar.'));
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
                          return _PendingOrderCard(
                            order: order,
                            onReview: () => guardedPdfPush(
                              context,
                              '/orders/review/${order.id}',
                            ),
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
            'Error: ${reportError(error, stack, context: 'PendingOrdersScreen')}',
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

class _PendingOrderCard extends StatelessWidget {
  const _PendingOrderCard({required this.order, required this.onReview});

  final PurchaseOrder order;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final createdLabel = order.createdAt?.toFullDateTime() ?? 'Pendiente';
    final direccionComment = (order.direccionComment ?? '').trim();
    final wasRejectedByDireccion = order.direccionReturnCount > 0;

    final returnCount = order.returnCount;
    final wasReturned =
        returnCount > 0 ||
        (order.lastReturnReason != null &&
            order.lastReturnReason!.trim().isNotEmpty);


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
                _FolioPill(folio: order.id),
                _UrgencyPill(urgency: order.urgency),
                if (wasRejectedByDireccion)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade400),
                    ),
                    child: Text(
                      'Rechazada por DG',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else if (wasReturned)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text('Creada: $createdLabel')),
                if (wasReturned) _PendingOrderReturnTimePill(order: order),
              ],
            ),
            const SizedBox(height: 8),

            // ✅ Reemplazo del widget corrupto:
            _OrderCardSummary(order: order),
            if (wasReturned && order.updatedAt != null)
              Text('Modificada: ${order.updatedAt!.toFullDateTime()}'),

            if (wasRejectedByDireccion && direccionComment.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Motivo: $direccionComment',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.orange.shade900,
                  fontWeight: FontWeight.w600,
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
    return OrderSummaryLines(order: order, includeBudget: true, emptyLabel: '');
  }
}

class _PendingOrderReturnTimePill extends ConsumerWidget {
  const _PendingOrderReturnTimePill({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(orderEventsProvider(order.id));
    return eventsAsync.when(
      data: (events) {
        final timeInCotizaciones = _timeInCotizaciones(order, events);
        final timeInRejected = timeInCotizaciones == null
            ? _timeInRejected(order, events)
            : null;
        if (timeInCotizaciones == null && timeInRejected == null) {
          return const SizedBox.shrink();
        }
        final label = timeInCotizaciones != null
            ? 'Tiempo en cotizaciones: ${_formatDuration(timeInCotizaciones)}'
            : 'Tiempo en rechazadas: ${_formatDuration(timeInRejected!)}';
        return StatusDurationPill(text: label, alignRight: false);
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _FolioPill extends StatelessWidget {
  const _FolioPill({required this.folio});

  final String folio;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.surfaceContainerHighest;
    final textColor = scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        folio,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _UrgencyPill extends StatelessWidget {
  const _UrgencyPill({required this.urgency});

  final PurchaseOrderUrgency urgency;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = urgency.color(scheme);
    final isDark =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        urgency.label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
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

Duration? _timeInCotizaciones(
  PurchaseOrder order,
  List<PurchaseOrderEvent> events,
) {
  if (order.returnCount <= 0) return null;

  PurchaseOrderEvent? lastReturn;
  for (final event in events) {
    if (event.type == 'return' &&
        event.fromStatus == PurchaseOrderStatus.cotizaciones &&
        event.toStatus == PurchaseOrderStatus.pendingCompras &&
        event.timestamp != null) {
      if (lastReturn == null ||
          event.timestamp!.isAfter(lastReturn.timestamp!)) {
        lastReturn = event;
      }
    }
  }
  if (lastReturn == null) return null;

  PurchaseOrderEvent? lastEntry;
  for (final event in events) {
    if (event.fromStatus == PurchaseOrderStatus.pendingCompras &&
        event.toStatus == PurchaseOrderStatus.cotizaciones &&
        event.timestamp != null &&
        event.timestamp!.isBefore(lastReturn.timestamp!)) {
      if (lastEntry == null || event.timestamp!.isAfter(lastEntry.timestamp!)) {
        lastEntry = event;
      }
    }
  }
  if (lastEntry == null) return null;

  final duration = lastReturn.timestamp!.difference(lastEntry.timestamp!);
  if (duration.isNegative) return null;
  return duration;
}

String _formatDuration(Duration duration) {
  final totalMinutes = duration.inMinutes;
  if (totalMinutes <= 0) {
    return '< 1 min';
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



