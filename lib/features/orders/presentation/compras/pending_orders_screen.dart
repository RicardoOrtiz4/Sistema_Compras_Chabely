import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/optimistic_action.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_pdf_preload_gate.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_status_duration.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_summary_lines.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_urgency_controls.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
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
  OrderUrgencyFilter _urgencyFilter = OrderUrgencyFilter.all;
  DateTimeRange? _createdDateRangeFilter;
  int _limit = defaultOrderPageSize;
  bool _isAcceptingAll = false;

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

  void _setUrgencyFilter(OrderUrgencyFilter filter) {
    setState(() {
      _urgencyFilter = filter;
      _limit = defaultOrderPageSize;
    });
  }

  Future<void> _pickCreatedDateFilter() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      currentDate: now,
      initialDateRange: _createdDateRangeFilter,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _createdDateRangeFilter = DateTimeRange(
        start: DateTime(picked.start.year, picked.start.month, picked.start.day),
        end: DateTime(picked.end.year, picked.end.month, picked.end.day),
      );
      _limit = defaultOrderPageSize;
    });
  }

  void _clearCreatedDateFilter() {
    if (_createdDateRangeFilter == null) return;
    setState(() {
      _createdDateRangeFilter = null;
      _limit = defaultOrderPageSize;
    });
  }

  void _loadMore() {
    setState(() => _limit += orderPageSizeStep);
  }

  Future<void> _handleAcceptAll(List<PurchaseOrder> orders) async {
    if (_isAcceptingAll || orders.isEmpty) return;

    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil no disponible.')),
      );
      return;
    }

    final confirmed = await _confirmAcceptAll(actor, orders.length);
    if (!mounted || !confirmed) return;

    setState(() => _isAcceptingAll = true);

    final reviewerName = actor.name.trim().isEmpty ? actor.id : actor.name.trim();
    final reviewerArea = actor.areaDisplay.trim().isEmpty
        ? actor.areaId
        : actor.areaDisplay.trim();
    final repo = ref.read(purchaseOrderRepositoryProvider);
    final count = orders.length;

    await runOptimisticAction(
      context: context,
      pendingLabel: 'Enviando $count orden(es) a Compras...',
      successMessage: count == 1
          ? '1 orden enviada a Compras.'
          : '$count Ã³rdenes enviadas a Compras.',
      errorContext: 'PendingOrdersScreen.acceptAll',
      action: () async {
        for (final order in orders) {
          await repo.transitionStatus(
            order: order,
            targetStatus: PurchaseOrderStatus.cotizaciones,
            actor: actor,
            comprasReviewerName: reviewerName,
            comprasReviewerArea: reviewerArea,
          );
        }
      },
    );

    if (mounted) {
      setState(() => _isAcceptingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(pendingComprasOrdersProvider);
    final compactAppBar = useCompactOrderModuleAppBar(context);

    return Scaffold(
      appBar: AppBar(
        title: ordersAsync.when(
          data: (orders) {
            final filteredOrders = _resolveVisibleOrders(orders);
            final acceptAllButton = _PendingOrdersAcceptAllButton(
              visibleCount: filteredOrders.length,
              isBusy: _isAcceptingAll,
              onPressed: filteredOrders.isEmpty || _isAcceptingAll
                  ? null
                  : () => _handleAcceptAll(filteredOrders),
            );
            if (compactAppBar) {
              return const Text(pendingRequirementAuthorizationLabel);
            }
            return OrderModuleAppBarTitle(
              title: pendingRequirementAuthorizationLabel,
              counts: OrderUrgencyCounts.fromOrders(orders),
              filter: _urgencyFilter,
              onSelected: _setUrgencyFilter,
              trailing: acceptAllButton,
            );
          },
          loading: () => const Text(pendingRequirementAuthorizationLabel),
          error: (_, __) => const Text(pendingRequirementAuthorizationLabel),
        ),
        bottom: !compactAppBar
            ? null
            : ordersAsync.maybeWhen(
                data: (orders) {
                  final filteredOrders = _resolveVisibleOrders(orders);
                  return OrderModuleAppBarBottom(
                    counts: OrderUrgencyCounts.fromOrders(orders),
                    filter: _urgencyFilter,
                    onSelected: _setUrgencyFilter,
                    trailing: _PendingOrdersAcceptAllButton(
                      visibleCount: filteredOrders.length,
                      isBusy: _isAcceptingAll,
                      onPressed: filteredOrders.isEmpty || _isAcceptingAll
                          ? null
                          : () => _handleAcceptAll(filteredOrders),
                    ),
                  );
                },
                orElse: () => null,
              ),
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

          _searchCache.retainFor(orders);
          final filtered = _resolveVisibleOrders(orders);
          final visibleOrders = filtered.take(_limit).toList(growable: false);
          final showLoadMore = filtered.length > visibleOrders.length;

          final content = Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 720;
                    final searchField = TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: 'Buscar por folio (000001), solicitante, cliente...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: _clearSearch,
                              ),
                      ),
                      onChanged: _updateSearch,
                    );

                    final dateFilter = _PendingOrdersDateFilterButton(
                      selectedRange: _createdDateRangeFilter,
                      onPickDate: _pickCreatedDateFilter,
                      onClearDate: _clearCreatedDateFilter,
                    );

                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          searchField,
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: dateFilter,
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: searchField),
                        const SizedBox(width: 12),
                        dateFilter,
                      ],
                    );
                  },
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
                              label: const Text('Ver mÃ¡s'),
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
                                label: const Text('Ver mÃ¡s'),
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
                  includeDates: false,
                ),
              )
              .toList(growable: false);
    final dateFiltered = resolved
        .where(_matchesCreatedDateFilter)
        .toList(growable: false);
    final urgencyFiltered = dateFiltered
        .where((order) => matchesOrderUrgencyFilter(order, _urgencyFilter))
        .toList(growable: false);
    _cachedSourceOrders = orders;
    _cachedVisibleKey = key;
    _cachedVisibleOrders = urgencyFiltered;
    return urgencyFiltered;
  }

  String _visibleOrdersKey() =>
      '${_searchQuery.trim().toLowerCase()}|${_urgencyFilter.name}|'
      '${_createdDateRangeFilter?.start.millisecondsSinceEpoch ?? ''}|'
      '${_createdDateRangeFilter?.end.millisecondsSinceEpoch ?? ''}';

  bool _matchesCreatedDateFilter(PurchaseOrder order) {
    final selectedRange = _createdDateRangeFilter;
    if (selectedRange == null) return true;
    final createdAt = order.createdAt;
    if (createdAt == null) return false;
    final createdDate = DateTime(createdAt.year, createdAt.month, createdAt.day);
    final rangeStart = DateTime(
      selectedRange.start.year,
      selectedRange.start.month,
      selectedRange.start.day,
    );
    final rangeEnd = DateTime(
      selectedRange.end.year,
      selectedRange.end.month,
      selectedRange.end.day,
    );
    return !createdDate.isBefore(rangeStart) && !createdDate.isAfter(rangeEnd);
  }

  Future<bool> _confirmAcceptAll(AppUser actor, int count) async {
    final reviewerName = actor.name.trim().isEmpty ? actor.id : actor.name.trim();
    final reviewerArea = actor.areaDisplay.trim().isEmpty
        ? actor.areaId
        : actor.areaDisplay.trim();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Aceptar todas'),
        content: Text(
          'Vas a aceptar $count orden(es) visibles con los filtros actuales. '
          'Todas quedarÃ¡n firmadas por "$reviewerName" del Ã¡rea "$reviewerArea" '
          'y pasarÃ¡n directamente a Compras sin revisiÃ³n individual. '
          'Riesgo: si alguna orden trae errores en materiales, cantidades, cliente '
          'o urgencia, el error avanzarÃ¡ en lote. AdemÃ¡s, si algo falla a mitad del '
          'proceso, puede quedar un avance parcial y tendrÃ¡s que revisarlo manualmente. '
          'Â¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Aceptar todas'),
          ),
        ],
      ),
    );

    return result ?? false;
  }
}


class _PendingOrdersAcceptAllButton extends StatelessWidget {
  const _PendingOrdersAcceptAllButton({
    required this.visibleCount,
    required this.isBusy,
    required this.onPressed,
  });

  final int visibleCount;
  final bool isBusy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
      child: isBusy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              visibleCount > 0
                  ? 'Aceptar todas ($visibleCount)'
                  : 'Aceptar todas',
            ),
    );
  }
}

class _PendingOrdersDateFilterButton extends StatelessWidget {
  const _PendingOrdersDateFilterButton({
    required this.selectedRange,
    required this.onPickDate,
    required this.onClearDate,
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
          label: Text(
            _rangeLabel(),
          ),
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

class _PendingOrderCard extends StatelessWidget {
  const _PendingOrderCard({required this.order, required this.onReview});

  final PurchaseOrder order;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final createdLabel = order.createdAt?.toFullDateTime() ?? 'Pendiente';
    final direccionComment = (order.direccionComment ?? '').trim();
    final urgentJustification = (order.urgentJustification ?? '').trim();
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
                if (order.urgency == PurchaseOrderUrgency.urgente &&
                    urgentJustification.isNotEmpty)
                  Text(
                    urgentJustification,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.red.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
                      'Rechazada por autorizacion de pago',
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
                      returnCount > 1
                          ? 'Con historial de rechazo x$returnCount'
                          : 'Con historial de rechazo',
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
            Text('Solicitante / Area: ${order.requesterName} | ${order.areaName}'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text('Creada: $createdLabel')),
                if (wasReturned) _PendingOrderReturnTimePill(order: order),
              ],
            ),
            const SizedBox(height: 8),

            // âœ… Reemplazo del widget corrupto:
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
    return OrderSummaryLines(
      order: order,
      includeBudget: true,
      includeUrgentJustification: false,
      emptyLabel: '',
    );
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
            ? 'Tiempo en compras: ${_formatDuration(timeInCotizaciones)}'
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
    final dayLabel = days == 1 ? 'dÃ­a' : 'dÃ­as';
    final hourPart = hours > 0 ? ' $hours h' : '';
    return '$days $dayLabel$hourPart';
  }
  if (hours > 0) {
    final minutePart = minutes > 0 ? ' $minutes min' : '';
    return '$hours h$minutePart';
  }
  return '$minutes min';
}
