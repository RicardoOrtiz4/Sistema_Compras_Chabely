import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/core/widgets/info_action.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_status_duration.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

class PendingOrdersScreen extends ConsumerStatefulWidget {
  const PendingOrdersScreen({super.key});

  @override
  ConsumerState<PendingOrdersScreen> createState() => _PendingOrdersScreenState();
}

class _PendingOrdersScreenState extends ConsumerState<PendingOrdersScreen> {
  late final TextEditingController _searchController;
  final OrderSearchCache _searchCache = OrderSearchCache();
  Timer? _searchDebounce;
  String _searchQuery = '';
  int _limit = defaultOrderPageSize;
  bool _prefetching = false;
  String? _lastPrefetchKey;
  bool _prefetchScheduled = false;

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

  void _warmPendingCache(List<PurchaseOrder> orders) {
    if (orders.isEmpty) return;
    final key = orders
        .take(defaultOrderPageSize)
        .map((order) => '${order.id}:${order.updatedAt?.millisecondsSinceEpoch ?? 0}')
        .join('|');
    if (_lastPrefetchKey == key) return;
    _lastPrefetchKey = key;
    if (_prefetchScheduled) return;
    _prefetchScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefetchScheduled = false;
      if (!mounted) return;
      setState(() => _prefetching = true);
      final branding = ref.read(currentBrandingProvider);
      final dataList = orders
          .take(defaultOrderPageSize)
          .map((order) => buildPdfDataFromOrder(order, branding: branding))
          .toList(growable: false);
      if (dataList.isEmpty) {
        if (mounted) setState(() => _prefetching = false);
        return;
      }
      Future(() async {
        try {
          for (final data in dataList) {
            try {
              await buildOrderPdf(data, useIsolate: true);
            } catch (error, stack) {
              logError(error, stack, context: 'PendingOrders.prefetch');
            }
          }
        } finally {
          if (mounted) setState(() => _prefetching = false);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(pendingComprasOrdersPagedProvider(_limit));

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
        actions: [
          infoAction(
            context,
            title: 'Ordenes por confirmar',
            message:
                'Lista de ordenes pendientes de aprobacion.\n'
                'Abre el PDF para revisar y autorizar o rechazar.\n'
                'Usa el buscador y "Ver mas" para mas resultados.',
          ),
        ],
      ),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('No hay órdenes por confirmar.'));
          }

          _searchCache.retainFor(orders);
          final trimmedQuery = _searchQuery.trim();
          final filtered = trimmedQuery.isEmpty
              ? orders
              : orders
                  .where((order) =>
                      orderMatchesSearch(order, trimmedQuery, cache: _searchCache))
                  .toList();
          final canLoadMore = orders.length >= _limit;
          final showLoadMore =
              canLoadMore && filtered.length >= defaultOrderPageSize;
          _warmPendingCache(filtered);

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
                child: filtered.isEmpty
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
                        itemCount: filtered.length + (showLoadMore ? 1 : 0),
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
                          return _PendingOrderCard(
                            order: order,
                            onReview: () => guardedPush(context, '/orders/review/${order.id}'),
                          );
                        },
                      ),
              ),
            ],
          );
          return Stack(
            children: [
              content,
              if (_prefetching) const Positioned.fill(child: AppSplash()),
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

    final resubmissions = order.resubmissionDates;

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
                _FolioPill(folio: order.id),
                _UrgencyPill(urgency: order.urgency),
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
            if (resubmissions.isNotEmpty)
              Text(
                'Reenvío: ${_formatResubmissionStamp(resubmissions.last, order.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text('Creada: $createdLabel')),
                if (wasReturned)
                  eventsAsync!.when(
                    data: (events) {
                      final timeInCotizaciones =
                          _timeInCotizaciones(order, events);
                      final timeInRejected = timeInCotizaciones == null
                          ? _timeInRejected(order, events)
                          : null;
                      if (timeInCotizaciones == null &&
                          timeInRejected == null) {
                        return const SizedBox.shrink();
                      }
                      final label = timeInCotizaciones != null
                          ? 'Tiempo en cotizaciones: ${_formatDuration(timeInCotizaciones)}'
                          : 'Tiempo en rechazadas: ${_formatDuration(timeInRejected!)}';
                      return StatusDurationPill(
                        text: label,
                        alignRight: false,
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // ✅ Reemplazo del widget corrupto:
            _OrderCardSummary(order: order),
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
        if (supplier.isNotEmpty) Text('Proveedor: $supplier'),
        if (internalOrder.isNotEmpty) Text('OC interna: $internalOrder'),
        if (order.budget != null) Text('Presupuesto: ${order.budget}'),
      ],
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
    final isDark = ThemeData.estimateBrightnessForColor(color) == Brightness.dark;
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
      if (lastEntry == null ||
          event.timestamp!.isAfter(lastEntry.timestamp!)) {
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

final DateFormat _resubmissionTimeFormat = DateFormat('HH:mm');
final DateFormat _resubmissionDateTimeFormat = DateFormat('dd MMM yyyy â€¢ HH:mm');

String _formatResubmissionStamp(DateTime stamp, DateTime? createdAt) {
  if (createdAt != null && _isSameDate(createdAt, stamp)) {
    return _resubmissionTimeFormat.format(stamp);
  }
  return _resubmissionDateTimeFormat.format(stamp);
}

bool _isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}




