import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/navigation_guard.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/order_event_labels.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_card_pills.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_urgency_controls.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

class UserInProcessOrdersScreen extends ConsumerStatefulWidget {
  const UserInProcessOrdersScreen({super.key});

  @override
  ConsumerState<UserInProcessOrdersScreen> createState() =>
      _UserInProcessOrdersScreenState();
}

class _UserInProcessOrdersScreenState
    extends ConsumerState<UserInProcessOrdersScreen> {
  List<PurchaseOrder>? _cachedSourceOrders;
  String? _cachedVisibleKey;
  List<PurchaseOrder>? _cachedVisibleOrders;

  String? _lastCompletionNoticeKey;
  String? _lastArrivalNoticeKey;
  final Set<String> _autoFinalizeInFlight = <String>{};
  late final TextEditingController _searchController;
  final OrderSearchCache _searchCache = OrderSearchCache();
  Timer? _searchDebounce;
  String _searchQuery = '';
  OrderUrgencyFilter _urgencyFilter = OrderUrgencyFilter.all;
  DateTimeRange? _createdDateRangeFilter;
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

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(userOrdersProvider);
    final compactAppBar = useCompactOrderModuleAppBar(context);

    return Scaffold(
      appBar: AppBar(
        title: ordersAsync.when(
          data: (orders) {
            final activeOrders = _activeOrders(orders);
            final counts = OrderUrgencyCounts.fromOrders(activeOrders);
            if (compactAppBar) {
              return const Text('Ordenes en proceso');
            }
            return OrderModuleAppBarTitle(
              title: 'Ordenes en proceso',
              counts: counts,
              filter: _urgencyFilter,
              onSelected: _setUrgencyFilter,
            );
          },
          loading: () => const Text('Ordenes en proceso'),
          error: (_, __) => const Text('Ordenes en proceso'),
        ),
        bottom: !compactAppBar
            ? null
            : ordersAsync.maybeWhen(
                data: (orders) => OrderModuleAppBarBottom(
                  counts: OrderUrgencyCounts.fromOrders(_activeOrders(orders)),
                  filter: _urgencyFilter,
                  onSelected: _setUrgencyFilter,
                ),
                orElse: () => null,
              ),
      ),
      body: ordersAsync.when(
        data: (orders) {
          final activeOrders = _activeOrders(orders);
          _searchCache.retainFor(activeOrders);
          final filtered = _resolveVisibleOrders(activeOrders);
          final visibleOrders = filtered.take(_limit).toList(growable: false);
          final showLoadMore = filtered.length > visibleOrders.length;
          final completedOrders = activeOrders
              .where((order) => order.isAwaitingRequesterReceipt)
              .toList(growable: false);
          final arrivalOrders = activeOrders
              .where((order) => hasAnyArrivedItems(order))
              .toList(growable: false);

          _scheduleAutoFinalize(activeOrders);
          _scheduleCompletionNotice(completedOrders);
          _scheduleArrivalNotice(arrivalOrders);

          if (activeOrders.isEmpty) {
            return const Center(
              child: Text('No tienes ordenes activas en proceso.'),
            );
          }

          return Column(
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

                    final dateFilter = OrderDateRangeFilterButton(
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
                          const Text('No hay ordenes con ese filtro.'),
                          if (showLoadMore) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _loadMore,
                              icon: const Icon(Icons.expand_more),
                              label: const Text('Ver mas'),
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
                                label: const Text('Ver mas'),
                              ),
                            );
                          }
                          final order = visibleOrders[index];
                          return _UserInProcessOrderCard(order: order);
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            'Error: ${reportError(error, stack, context: 'UserInProcessOrdersScreen')}',
          ),
        ),
      ),
    );
  }

  void _scheduleCompletionNotice(List<PurchaseOrder> orders) {
    if (orders.isEmpty) {
      _lastCompletionNoticeKey = null;
      return;
    }

    final key = orders.map((order) => order.id).join('|');
    if (_lastCompletionNoticeKey == key) return;
    _lastCompletionNoticeKey = key;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Ordenes finalizadas'),
          content: Text(
            orders.length == 1
                ? 'Tu orden ${orders.first.id} ya fue finalizada. Mantente pendiente de la llegada y, cuando la recibas, confirma de recibido para mandarla al historial.'
                : 'Tienes ${orders.length} ordenes finalizadas pendientes de llegada. Cuando las recibas, entra a cada una y confirma de recibido para mandarlas al historial.',
          ),
          actions: [
            if (orders.isNotEmpty)
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => UserOrderTrackingScreen(orderId: orders.first.id),
                    ),
                  );
                },
                child: Text(orders.length == 1 ? 'Ir a la orden' : 'Ir a una orden'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    });
  }

  void _scheduleAutoFinalize(List<PurchaseOrder> orders) {
    for (final order in orders) {
      if (!isOrderAutoReceiptDue(order)) continue;
      if (_autoFinalizeInFlight.contains(order.id)) continue;
      _autoFinalizeInFlight.add(order.id);
      unawaited(_autoFinalizeOrder(order));
    }
  }

  Future<void> _autoFinalizeOrder(PurchaseOrder order) async {
    try {
      await ref.read(purchaseOrderRepositoryProvider).autoConfirmRequesterReceived(
            order: order,
          );
      refreshRequesterReceiptWorkflowData(
        ref,
        orderIds: <String>[order.id],
      );
    } catch (error, stack) {
      logError(
        error,
        stack,
        context: 'UserInProcessOrdersScreen.autoConfirmRequesterReceived',
      );
    } finally {
      _autoFinalizeInFlight.remove(order.id);
    }
  }

  void _scheduleArrivalNotice(List<PurchaseOrder> orders) {
    if (orders.isEmpty) {
      _lastArrivalNoticeKey = null;
      return;
    }

    final key = orders
        .map((order) => '${order.id}:${countArrivedItems(order)}:${countPendingArrivalItems(order)}')
        .join('|');
    if (_lastArrivalNoticeKey == key) return;
    _lastArrivalNoticeKey = key;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Actualizacion interna de llegadas'),
          content: Text(
            orders.length == 1
                ? 'Tu orden ${orders.first.id} ya tiene items llegados. Revisa cuales llegaron, cuales faltan y la diferencia contra la fecha estimada.'
                : 'Tienes ${orders.length} ordenes con llegadas parciales registradas. Revisa en la app cuales items llegaron, cuales faltan y si van en tiempo o con atraso.',
          ),
          actions: [
            if (orders.isNotEmpty)
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => UserOrderTrackingScreen(orderId: orders.first.id),
                    ),
                  );
                },
                child: Text(orders.length == 1 ? 'Ir a la orden' : 'Ir a una orden'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Revisar despues'),
            ),
          ],
        ),
      );
    });
  }

  List<PurchaseOrder> _activeOrders(List<PurchaseOrder> orders) {
    return orders
        .where(
          (order) =>
              order.status != PurchaseOrderStatus.draft &&
              !order.isWorkflowFinished,
        )
        .toList(growable: false);
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
        .where((order) => matchesOrderCreatedDateRange(order, _createdDateRangeFilter))
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
}

class _UserInProcessOrderCard extends ConsumerStatefulWidget {
  const _UserInProcessOrderCard({required this.order});

  final PurchaseOrder order;

  @override
  ConsumerState<_UserInProcessOrderCard> createState() =>
      _UserInProcessOrderCardState();
}

class _UserInProcessOrderCardState
    extends ConsumerState<_UserInProcessOrderCard> {
  bool _confirmingReceived = false;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final committedItems = countItemsWithCommittedDeliveryDate(order);
    final totalItems = countFulfillmentItems(order);
    final arrivedItems = countArrivedItems(order);
    final pendingArrivalItems = countPendingArrivalItems(order);
    final committedDate = resolveCommittedDeliveryDate(order);
    final requestedDate = resolveRequestedDeliveryDate(order);
    final urgentJustification = (order.urgentJustification ?? '').trim();
    final notPurchasedCount = countItemsMarkedAsNotPurchased(order);
    final currentUser = ref.watch(currentUserProfileProvider).value;

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
                OrderFolioPill(folio: order.id),
                OrderUrgencyPill(urgency: order.urgency),
                if (order.urgency == PurchaseOrderUrgency.urgente &&
                    urgentJustification.isNotEmpty)
                  Text(
                    urgentJustification,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.red.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Chip(label: Text(_orderTrackingStatusLabel(order))),
              ],
            ),
            const SizedBox(height: 8),
            Text('Solicitante / Area: ${order.requesterName} | ${order.areaName}'),
            const SizedBox(height: 8),
            Text(
              arrivedItems > 0 || pendingArrivalItems > 0
                  ? 'Llegadas registradas: $arrivedItems item(s) | Faltan: $pendingArrivalItems'
                  : order.isAwaitingRequesterReceipt
                  ? order.isMaterialArrivalRegistered
                      ? 'Material reportado como llegado. Pendiente de tu confirmacion.'
                      : 'Orden finalizada. Pendiente de confirmar recibido.'
                  : 'Avance de fechas estimadas: $committedItems/$totalItems item(s)',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (notPurchasedCount > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Items cerrados sin compra: $notPurchasedCount',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (requestedDate != null) ...[
              const SizedBox(height: 4),
              Text('Fecha requerida: ${requestedDate.toShortDate()}'),
            ],
            if (committedDate != null) ...[
              const SizedBox(height: 4),
              Text(
                'Ultima fecha estimada de entrega: ${committedDate.toShortDate()}',
              ),
            ],
            if (order.isAwaitingRequesterReceipt) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  order.isMaterialArrivalRegistered
                      ? 'El sistema ya tiene registrada la llegada del material. Confirma aqui cuando ya te entreguen fisicamente los items.'
                      : 'La orden ya quedo finalizada internamente. Cuando realmente recibas los items, confirmala aqui y pasara al historial.',
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => UserOrderTrackingScreen(orderId: order.id),
                    ),
                  ),
                  icon: const Icon(Icons.route_outlined),
                  label: const Text('Ver rastreo'),
                ),
                if (order.isAwaitingRequesterReceipt && currentUser != null)
                  FilledButton.icon(
                    onPressed: _confirmingReceived
                        ? null
                        : () => _confirmReceived(order, currentUser),
                    icon: _confirmingReceived
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.task_alt_outlined),
                    label: const Text('Confirmar de recibido'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReceived(PurchaseOrder order, AppUser actor) async {
    setState(() => _confirmingReceived = true);
    try {
      final success = await _confirmRequesterReceipt(
        context,
        ref,
        order: order,
        actor: actor,
        errorContext: 'UserInProcessOrdersScreen.confirmRequesterReceived',
      );
      if (!mounted || !success) return;
    } finally {
      if (mounted) {
        setState(() => _confirmingReceived = false);
      }
    }
  }
}

class UserOrderTrackingScreen extends ConsumerStatefulWidget {
  const UserOrderTrackingScreen({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<UserOrderTrackingScreen> createState() =>
      _UserOrderTrackingScreenState();
}

class _UserOrderTrackingScreenState
    extends ConsumerState<UserOrderTrackingScreen> {
  bool _confirmingReceived = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdStreamProvider(widget.orderId));
    final eventsAsync = ref.watch(orderEventsProvider(widget.orderId));
    final currentUser = ref.watch(currentUserProfileProvider).value;
    final actorNamesById = {
      for (final user in ref.watch(allUsersProvider).valueOrNull ?? const <AppUser>[])
        user.id: user.name,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rastreo de orden'),
      ),
      body: orderAsync.when(
        data: (order) {
          if (order == null) return const AppSplash();
          final selection = _TrackingSelection.group(
            supplier: 'Orden completa',
            lines: order.items.map((item) => item.line).toList(),
          );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      'Rastreo de la orden',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () =>
                        guardedPdfPush(
                          context,
                          '/orders/${order.id}/pdf?tracking=1',
                        ),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Ver PDF de la orden'),
                  ),
                ],
              ),
              if (order.isAwaitingRequesterReceipt && currentUser != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.isMaterialArrivalRegistered
                              ? 'Tu material ya fue reportado como llegado'
                              : 'Confirma cuando la orden ya te haya llegado',
                          style:
                              Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          order.isMaterialArrivalRegistered
                              ? 'Cuando te entreguen fisicamente los items, presiona este boton para cerrar la orden y mandarla a los historiales.'
                              : 'En cuanto recibas los items, presiona este boton para cerrar la orden y mandarla a los historiales.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _confirmingReceived
                              ? null
                              : () => _confirmReceived(order, currentUser),
                          icon: _confirmingReceived
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.task_alt_outlined),
                          label: const Text('Confirmar de recibido'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (hasAnyArrivedItems(order) || countPendingArrivalItems(order) > 0) ...[
                const SizedBox(height: 16),
                _PartialArrivalStatusCard(order: order),
              ],
              const SizedBox(height: 8),
              Text(
                _trackingSelectionTitle(order),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              eventsAsync.when(
                data: (events) => _TrackingTimelineCard(
                  order: order,
                  events: events,
                  selection: selection,
                  actorNamesById: actorNamesById,
                ),
                loading: () => const AppSplash(compact: true),
                error: (error, stack) => Text(
                  reportError(
                    error,
                    stack,
                    context: 'UserOrderTrackingScreen.events',
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            'Error: ${reportError(error, stack, context: 'UserOrderTrackingScreen.order')}',
          ),
        ),
      ),
    );
  }

  Future<void> _confirmReceived(PurchaseOrder order, AppUser actor) async {
    setState(() => _confirmingReceived = true);
    try {
      final success = await _confirmRequesterReceipt(
        context,
        ref,
        order: order,
        actor: actor,
        errorContext: 'UserOrderTrackingScreen.confirmRequesterReceived',
      );
      if (!mounted || !success) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() => _confirmingReceived = false);
      }
    }
  }
}

Future<bool> _confirmRequesterReceipt(
  BuildContext context,
  WidgetRef ref, {
  required PurchaseOrder order,
  required AppUser actor,
  required String errorContext,
}) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Confirmar recibido'),
      content: const Text(
        'Esto cerrara la orden para ti y la movera al historial. Hazlo solo cuando realmente hayas recibido los items.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Confirmar'),
        ),
      ],
    ),
  );
  if (accepted != true || !context.mounted) return false;

  try {
    await ref.read(purchaseOrderRepositoryProvider).confirmRequesterReceived(
          order: order,
          actor: actor,
        );
    if (!context.mounted) return false;
    final rating = await _promptServiceRating(context);
    if (rating != null) {
      await ref.read(purchaseOrderRepositoryProvider).submitServiceRating(
            order: order,
            rating: rating.rating,
            comment: rating.comment,
          );
    }
    refreshRequesterReceiptWorkflowData(
      ref,
      orderIds: <String>[order.id],
    );
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('La orden se movio al historial.')),
    );
    return true;
  } catch (error, stack) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          reportError(
            error,
            stack,
            context: errorContext,
          ),
        ),
      ),
    );
    return false;
  }
}

class _ServiceRatingResult {
  const _ServiceRatingResult({
    required this.rating,
    this.comment,
  });

  final int rating;
  final String? comment;
}

Future<_ServiceRatingResult?> _promptServiceRating(BuildContext context) async {
  var selectedRating = 0;
  final commentController = TextEditingController();
  try {
    return await showDialog<_ServiceRatingResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              title: const Text('Calificar el proceso'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Califica el servicio y atencion que recibio tu requisicion. Esto se usara despues en reportes.',
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: List<Widget>.generate(
                        5,
                        (index) => ChoiceChip(
                          label: Text('${index + 1}'),
                          selected: selectedRating == index + 1,
                          onSelected: (_) => setState(() => selectedRating = index + 1),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: commentController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Comentario opcional',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Omitir'),
                ),
                FilledButton(
                  onPressed: selectedRating <= 0
                      ? null
                      : () => Navigator.of(dialogContext).pop(
                            _ServiceRatingResult(
                              rating: selectedRating,
                              comment: commentController.text.trim(),
                            ),
                          ),
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    commentController.dispose();
  }
}

class _PartialArrivalStatusCard extends StatelessWidget {
  const _PartialArrivalStatusCard({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    final trackedItems = order.items
        .where(
          (item) =>
              item.requiresFulfillment &&
              (item.deliveryEtaDate != null || item.isArrivalRegistered),
        )
        .toList(growable: false)
      ..sort((a, b) => a.line.compareTo(b.line));
    if (trackedItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Llegadas parciales',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Llegaron ${countArrivedItems(order)} item(s) y faltan ${countPendingArrivalItems(order)}.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            for (final item in trackedItems) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Item ${item.line}: ${item.description}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.deliveryEtaDate != null)
                      Text('Fecha estimada: ${item.deliveryEtaDate!.toShortDate()}'),
                    if (item.arrivedAt != null)
                      Text('Llegada registrada: ${item.arrivedAt!.toFullDateTime()}'),
                    Text(
                      item.isArrivalRegistered
                          ? itemArrivalComplianceLabel(item)
                          : itemPendingArrivalLabel(item),
                    ),
                  ],
                ),
                trailing: Chip(
                  label: Text(item.isArrivalRegistered ? 'Llegado' : 'Pendiente'),
                ),
              ),
              if (item != trackedItems.last) const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrackingTimelineCard extends StatelessWidget {
  const _TrackingTimelineCard({
    required this.order,
    required this.events,
    required this.selection,
    required this.actorNamesById,
  });

  final PurchaseOrder order;
  final List<PurchaseOrderEvent> events;
  final _TrackingSelection selection;
  final Map<String, String> actorNamesById;

  @override
  Widget build(BuildContext context) {
    final currentStatus = _selectedCurrentStatus(order);
    final statuses = _reachedTrackingStatuses();
    final pdfCreatedAt = order.createdAt ?? order.updatedAt;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (pdfCreatedAt != null)
              _TrackingPdfCreatedTile(
                createdAt: pdfCreatedAt,
                isLast:
                    statuses.isEmpty &&
                    order.status != PurchaseOrderStatus.eta &&
                    !order.isWorkflowFinished,
              ),
            for (var index = 0; index < statuses.length; index++)
              _TrackingTimelineTile(
                order: order,
                status: statuses[index],
                currentStatus: currentStatus,
                isLast: index == statuses.length - 1 &&
                    order.status != PurchaseOrderStatus.eta,
                duration: _statusDurationFor(order, statuses[index], currentStatus),
                event: _latestEventForStatus(events, statuses[index]),
                rejectionEvent: _latestReturnForStatus(events, statuses[index]),
                allEvents: events,
                actorNamesById: actorNamesById,
                note: _noteForStatus(
                  order,
                  statuses[index],
                  selection.lines.toSet(),
                ),
                itemCount: _shouldShowItemBreakdown(order, statuses[index])
                    ? _itemsForTrackingStatus(order, statuses[index]).length
                    : 0,
                onShowItems: _shouldShowItemBreakdown(order, statuses[index])
                    ? () => _showTrackingStatusItemsSheet(
                          context,
                          status: statuses[index],
                          items: _itemsForTrackingStatus(order, statuses[index]),
                        )
                    : null,
              ),
            if (order.status == PurchaseOrderStatus.eta || order.isWorkflowFinished)
              _RequesterReceiptTimelineTile(
                order: order,
                events: events,
                actorNamesById: actorNamesById,
              ),
          ],
        ),
      ),
    );
  }
}

class _TrackingPdfCreatedTile extends StatelessWidget {
  const _TrackingPdfCreatedTile({
    required this.createdAt,
    required this.isLast,
  });

  final DateTime createdAt;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(Icons.picture_as_pdf_outlined, color: color),
            if (!isLast)
              Container(
                width: 2,
                height: 64,
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: color,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card(
            color: color.withValues(alpha: color.a * 0.1),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Orden creada',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Inicio',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: color,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Fecha base con la que inicio el flujo de la orden.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      createdAt.toFullDateTime(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TrackingTimelineTile extends StatelessWidget {
  const _TrackingTimelineTile({
    required this.order,
    required this.status,
    required this.currentStatus,
    required this.isLast,
    required this.duration,
    required this.event,
    required this.rejectionEvent,
    required this.allEvents,
    required this.actorNamesById,
    required this.note,
    this.itemCount = 0,
    this.onShowItems,
  });

  final PurchaseOrder order;
  final PurchaseOrderStatus status;
  final PurchaseOrderStatus currentStatus;
  final bool isLast;
  final Duration duration;
  final PurchaseOrderEvent? event;
  final PurchaseOrderEvent? rejectionEvent;
  final List<PurchaseOrderEvent> allEvents;
  final Map<String, String> actorNamesById;
  final String? note;
  final int itemCount;
  final VoidCallback? onShowItems;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stageProgress = _trackingStageProgressFor(order, status);
    final isCompleted = status.index <= currentStatus.index;
    final isCurrent = status == currentStatus;
    final isRejectedPending = !isCompleted && rejectionEvent != null;
    final statusText = isRejectedPending
        ? 'Rechazada'
        : isCurrent
            ? 'Actual'
            : isCompleted
                ? 'Completado'
                : 'Pendiente';
    final color = isCompleted ? status.statusColor(scheme) : scheme.outlineVariant;
    final statusBadgeBackground = isCompleted
        ? color.withValues(alpha: isCurrent ? 0.22 : 0.14)
        : scheme.surfaceContainerHighest;
    final statusBadgeForeground = isCurrent
        ? const Color(0xFF1F2937)
        : isCompleted
            ? color
            : scheme.onSurfaceVariant;
    final stageActorEvent =
        isCompleted && !isCurrent
            ? _latestStageCompletionEvent(allEvents, status)
            : null;
    final displayedActor = _eventActorLabel(stageActorEvent, actorNamesById);
    final rejectionActor = _eventActorLabel(rejectionEvent, actorNamesById);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(status.icon, color: color),
            if (!isLast)
              Container(
                width: 2,
                height: 64,
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: color,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card(
            color: isCompleted
                ? color.withValues(alpha: color.a * 0.1)
                : Theme.of(context).cardColor,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _trackingStageLabel(status),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusBadgeBackground,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          statusText,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: statusBadgeForeground,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isCurrent
                        ? 'Tiempo en estatus actual: ${_formatTrackingDuration(duration)}'
                        : isCompleted
                            ? 'Tiempo en este estatus: ${_formatTrackingDuration(duration)}'
                            : 'Aún no entra a este estatus.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (event?.timestamp != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        event!.timestamp!.toFullDateTime(),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (displayedActor.isNotEmpty || isRejectedPending)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (displayedActor.isNotEmpty)
                            _TrackingMetaTag(
                              text: 'Actor de etapa: $displayedActor',
                            ),
                          if (isRejectedPending)
                            _TrackingMetaTag(
                              text: [
                                returnEventTitle(allEvents, rejectionEvent!),
                                orderEventTransitionLabel(rejectionEvent!),
                                'rechazo en ${returnStageLabel(rejectionEvent!.fromStatus)}',
                                if (rejectionActor.isNotEmpty) rejectionActor,
                                if (rejectionEvent!.timestamp != null)
                                  rejectionEvent!.timestamp!.toFullDateTime(),
                              ].join(' | '),
                              highlighted: true,
                            ),
                        ],
                      ),
                    ),
                  if (stageProgress != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _TrackingMetaTag(
                            text:
                                '${stageProgress.atStage}/${stageProgress.total} items aqui',
                            highlighted: isCurrent,
                          ),
                          if (stageProgress.ahead > 0)
                            _TrackingMetaTag(
                              text: '${stageProgress.ahead} ya avanzaron',
                            ),
                          if (stageProgress.behind > 0)
                            _TrackingMetaTag(
                              text: '${stageProgress.behind} siguen atras',
                            ),
                        ],
                      ),
                    ),
                  if (note != null && note!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        note!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (isRejectedPending &&
                      rejectionEvent!.comment?.trim().isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Motivo: ${rejectionEvent!.comment!.trim()}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (itemCount > 0 && onShowItems != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutlinedButton.icon(
                        onPressed: onShowItems,
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: Text('Ver items ($itemCount)'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RequesterReceiptTimelineTile extends StatelessWidget {
  const _RequesterReceiptTimelineTile({
    required this.order,
    required this.events,
    required this.actorNamesById,
  });

  final PurchaseOrder order;
  final List<PurchaseOrderEvent> events;
  final Map<String, String> actorNamesById;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCompleted = order.isWorkflowFinished;
    final color = isCompleted ? scheme.primary : scheme.outlineVariant;
    final receiptEvent = _latestReceiptEvent(events);
    final etaEvent = _latestEventForStatus(events, PurchaseOrderStatus.eta);
    final receiptActorFromEvent = _eventActorLabel(receiptEvent, actorNamesById);
    final receiptActor = receiptActorFromEvent.isNotEmpty
        ? receiptActorFromEvent
        : _requesterReceiptActorSummary(order);
    final startedAt = etaEvent?.timestamp;
    final finishedAt =
        order.requesterReceivedAt ?? order.completedAt ?? order.updatedAt ?? DateTime.now();
    var duration = Duration.zero;
    if (startedAt != null) {
      duration = finishedAt.difference(startedAt);
      if (duration.isNegative) duration = Duration.zero;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(Icons.inventory_2_outlined, color: color),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card(
            color: isCompleted
                ? scheme.primary.withValues(alpha: scheme.primary.a * 0.08)
                : Theme.of(context).cardColor,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.isClosedWithoutPurchase
                        ? 'Cierre sin compra'
                        : order.isRequesterReceiptAutoConfirmed
                        ? 'Llegado pero no confirmado'
                        : 'Confirmacion de recibido',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isCompleted
                        ? 'Tiempo en esta etapa: ${_formatTrackingDuration(duration)}'
                        : 'Tiempo esperando confirmacion: ${_formatTrackingDuration(duration)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (order.requesterReceivedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        order.requesterReceivedAt!.toFullDateTime(),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (receiptActor != null && receiptActor.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Responsable: $receiptActor',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      order.isRequesterReceiptAutoConfirmed
                          ? 'La orden se cerro automaticamente despues de 10 dias sin confirmacion del solicitante.'
                          : order.isClosedWithoutPurchase
                          ? 'Todos los items quedaron resueltos sin compra y la orden ya se cerro.'
                          : isCompleted
                          ? 'La orden ya fue confirmada como recibida y paso al historial.'
                          : 'La orden ya fue finalizada internamente y esta pendiente de que la confirmes como recibida.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (receiptEvent?.comment?.trim().isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        receiptEvent!.comment!.trim(),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TrackingMetaTag extends StatelessWidget {
  const _TrackingMetaTag({
    required this.text,
    this.highlighted = false,
  });

  final String text;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = highlighted
        ? scheme.errorContainer
        : scheme.surfaceContainerHighest;
    final foreground = highlighted
        ? scheme.onErrorContainer
        : scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlighted
              ? scheme.error.withValues(alpha: 0.24)
              : scheme.outlineVariant,
        ),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _TrackingSelection {
  const _TrackingSelection._({
    required this.supplier,
    required this.lines,
    required this.isGroup,
  });

  factory _TrackingSelection.group({
    required String supplier,
    required List<int> lines,
  }) {
    return _TrackingSelection._(
      supplier: supplier,
      lines: lines,
      isGroup: true,
    );
  }

  final String supplier;
  final List<int> lines;
  final bool isGroup;
}

class _TrackingStageProgress {
  const _TrackingStageProgress({
    required this.total,
    required this.atStage,
    required this.ahead,
    required this.behind,
  });

  final int total;
  final int atStage;
  final int ahead;
  final int behind;
}

void _showTrackingStatusItemsSheet(
  BuildContext context, {
  required PurchaseOrderStatus status,
  required List<PurchaseOrderItem> items,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Text(
                '${_trackingStageLabel(status)} (${items.length} item(s))',
                style: Theme.of(context).textTheme.titleMedium,
              );
            }

            final item = items[index - 1];
            return Card(
              child: ListTile(
                title: Text('Item ${item.line}: ${item.description}'),
                subtitle: Text(
                  [
                    '${item.partNumber} | ${item.quantity} ${item.unit}',
                    if (item.deliveryEtaDate != null)
                      'ETA ${item.deliveryEtaDate!.toShortDate()}',
                    if (item.arrivedAt != null)
                      'Llegada ${item.arrivedAt!.toShortDate()}',
                    item.isArrivalRegistered
                        ? itemArrivalComplianceLabel(item)
                        : itemPendingArrivalLabel(item),
                  ].join('\n'),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

String _trackingSelectionTitle(PurchaseOrder order) {
  return 'Seguimiento completo de la orden.';
}

String _formatTrackingDuration(Duration duration) {
  if (duration.isNegative) duration = Duration.zero;
  final days = duration.inDays;
  final hours = duration.inHours % 24;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;

  if (days > 0) {
    return '${days}d ${hours}h ${minutes}m ${seconds}s';
  }
  if (duration.inHours > 0) {
    return '${duration.inHours}h ${minutes}m ${seconds}s';
  }
  if (duration.inMinutes > 0) {
    return '${duration.inMinutes}m ${seconds}s';
  }
  return '${duration.inSeconds}s';
}

PurchaseOrderStatus _selectedCurrentStatus(PurchaseOrder order) {
  return _normalizeTrackingStatus(order.status);
}

Duration _statusDurationFor(
  PurchaseOrder order,
  PurchaseOrderStatus status,
  PurchaseOrderStatus currentStatus,
) {
  var total = Duration(milliseconds: order.statusDurations[status.name] ?? 0);
  if (status == currentStatus && order.status == status) {
    final since = order.statusEnteredAt ?? order.updatedAt ?? order.createdAt;
    if (since != null) {
      var current = DateTime.now().difference(since);
      if (current.isNegative) current = Duration.zero;
      total += current;
    }
  }
  return total;
}

PurchaseOrderStatus _normalizeTrackingStatus(PurchaseOrderStatus status) {
  if (status == PurchaseOrderStatus.orderPlaced) {
    return PurchaseOrderStatus.eta;
  }
  return status;
}

List<PurchaseOrderStatus> _reachedTrackingStatuses(
) {
  return const <PurchaseOrderStatus>[
    PurchaseOrderStatus.intakeReview,
    PurchaseOrderStatus.sourcing,
    PurchaseOrderStatus.readyForApproval,
    PurchaseOrderStatus.approvalQueue,
    PurchaseOrderStatus.paymentDone,
    PurchaseOrderStatus.contabilidad,
    PurchaseOrderStatus.eta,
  ];
}

bool _shouldShowGroupedTracking(PurchaseOrder order) {
  return false;
}

bool _shouldShowItemBreakdown(
  PurchaseOrder order,
  PurchaseOrderStatus status,
) {
  return false;
}

List<PurchaseOrderItem> _itemsForTrackingStatus(
  PurchaseOrder order,
  PurchaseOrderStatus status,
) {
  final items = order.items
      .where((item) => _itemTrackingStatus(order, item) == status)
      .toList(growable: false);
  items.sort((a, b) => a.line.compareTo(b.line));
  return items;
}

_TrackingStageProgress? _trackingStageProgressFor(
  PurchaseOrder order,
  PurchaseOrderStatus status,
) {
  final total = order.items.length;
  if (total <= 1) return null;

  var atStage = 0;
  var ahead = 0;
  var behind = 0;
  for (final item in order.items) {
    final itemStatus = _itemTrackingStatus(order, item);
    if (itemStatus == status) {
      atStage++;
    } else if (itemStatus.index > status.index) {
      ahead++;
    } else {
      behind++;
    }
  }

  if (atStage == 0 || (ahead == 0 && behind == 0)) {
    return null;
  }
  return _TrackingStageProgress(
    total: total,
    atStage: atStage,
    ahead: ahead,
    behind: behind,
  );
}

PurchaseOrderStatus _itemTrackingStatus(
  PurchaseOrder order,
  PurchaseOrderItem item,
) {
  if (item.isNotPurchased) return PurchaseOrderStatus.eta;
  return order.status;
}

PurchaseOrderEvent? _latestEventForStatus(
  List<PurchaseOrderEvent> events,
  PurchaseOrderStatus status,
) {
  PurchaseOrderEvent? selected;
  for (final event in events) {
    if (event.toStatus != status) continue;
    if (selected == null) {
      selected = event;
      continue;
    }
    final currentMs = event.timestamp?.millisecondsSinceEpoch ?? 0;
    final selectedMs = selected.timestamp?.millisecondsSinceEpoch ?? 0;
    if (currentMs >= selectedMs) {
      selected = event;
    }
  }
  return selected;
}

PurchaseOrderEvent? _latestReceiptEvent(List<PurchaseOrderEvent> events) {
  PurchaseOrderEvent? selected;
  for (final event in events) {
    if (event.type != 'received' && event.type != 'received_timeout') continue;
    if (selected == null) {
      selected = event;
      continue;
    }
    final currentMs = event.timestamp?.millisecondsSinceEpoch ?? 0;
    final selectedMs = selected.timestamp?.millisecondsSinceEpoch ?? 0;
    if (currentMs >= selectedMs) {
      selected = event;
    }
  }
  return selected;
}

PurchaseOrderEvent? _latestReturnForStatus(
  List<PurchaseOrderEvent> events,
  PurchaseOrderStatus status,
) {
  PurchaseOrderEvent? selected;
  for (final event in events) {
    if (event.type != 'return') continue;
    if (_normalizeTrackingStatus(event.fromStatus ?? PurchaseOrderStatus.draft) !=
        status) {
      continue;
    }
    if (selected == null) {
      selected = event;
      continue;
    }
    final currentMs = event.timestamp?.millisecondsSinceEpoch ?? 0;
    final selectedMs = selected.timestamp?.millisecondsSinceEpoch ?? 0;
    if (currentMs >= selectedMs) {
      selected = event;
    }
  }
  return selected;
}

PurchaseOrderEvent? _latestStageCompletionEvent(
  List<PurchaseOrderEvent> events,
  PurchaseOrderStatus status,
) {
  PurchaseOrderEvent? selected;
  for (final event in events) {
    if (event.type != 'advance') continue;
    final fromStatus = event.fromStatus;
    if (fromStatus == null || _normalizeTrackingStatus(fromStatus) != status) {
      continue;
    }
    if (selected == null) {
      selected = event;
      continue;
    }
    final currentMs = event.timestamp?.millisecondsSinceEpoch ?? 0;
    final selectedMs = selected.timestamp?.millisecondsSinceEpoch ?? 0;
    if (currentMs >= selectedMs) {
      selected = event;
    }
  }
  return selected;
}

String? _actorSummary(String? name, String? area) {
  final trimmedName = name?.trim() ?? '';
  final trimmedArea = area?.trim() ?? '';
  if (trimmedName.isEmpty && trimmedArea.isEmpty) return null;
  if (trimmedName.isEmpty) return trimmedArea;
  if (trimmedArea.isEmpty) return trimmedName;
  return '$trimmedName ($trimmedArea)';
}

String? _requesterReceiptActorSummary(PurchaseOrder order) {
  final fromOrder = _actorSummary(
    order.requesterReceivedName,
    order.requesterReceivedArea,
  );
  if (fromOrder != null) return fromOrder;
  final requester = order.requesterName.trim();
  return requester.isEmpty ? null : requester;
}

String? _noteForStatus(
  PurchaseOrder order,
  PurchaseOrderStatus status,
  Set<int> currentLines,
) {
  if (status == PurchaseOrderStatus.eta) {
    if (countFulfillmentItems(order) == 0 && order.hasItemsMarkedAsNotPurchased) {
      return 'Todos los items de esta orden se cerraron sin compra.';
    }
    if (order.isMaterialArrivalRegistered) {
      return 'Material reportado como llegado: ${order.materialArrivedAt!.toFullDateTime()}';
    }
    return 'Pendiente de confirmacion de recibido por el solicitante.';
  }

  if (status != PurchaseOrderStatus.paymentDone) {
    return null;
  }

  final selectedItems = order.items
      .where((item) => currentLines.contains(item.line))
      .toList(growable: false);
  final withEta = selectedItems.where((item) => item.deliveryEtaDate != null).length;
  if (withEta == 0) {
    return 'Aun no tiene fecha estimada de entrega.';
  }
  final latest = selectedItems
      .map((item) => item.deliveryEtaDate)
      .whereType<DateTime>()
      .fold<DateTime?>(null, (latest, value) {
    final normalized = DateTime(value.year, value.month, value.day);
    if (latest == null || normalized.isAfter(latest)) {
      return normalized;
    }
    return latest;
  });
  if (latest == null) {
    return null;
  }
  return 'Fecha estimada de entrega: ${latest.toShortDate()}';
}


String _orderTrackingStatusLabel(PurchaseOrder order) {
  return requesterReceiptStatusLabel(order);
}

String _trackingStageLabel(PurchaseOrderStatus status) {
  switch (status) {
    case PurchaseOrderStatus.intakeReview:
      return 'Autorizar ordenes';
    case PurchaseOrderStatus.sourcing:
      return 'Compras / Pendientes';
    case PurchaseOrderStatus.readyForApproval:
      return 'Compras / Dashboard';
    case PurchaseOrderStatus.approvalQueue:
      return 'Direccion General';
    case PurchaseOrderStatus.paymentDone:
      return 'Agregar fecha estimada';
    case PurchaseOrderStatus.contabilidad:
      return 'Facturas y evidencias';
    case PurchaseOrderStatus.eta:
      return 'Ordenes en proceso';
    case PurchaseOrderStatus.orderPlaced:
      return 'Ordenes en proceso';
    case PurchaseOrderStatus.draft:
      return 'Requiere correccion';
  }
}

String _eventActorLabel(
  PurchaseOrderEvent? event,
  Map<String, String> actorNamesById,
) {
  if (event == null) return '';
  final byUser = event.byUser.trim();
  final resolvedName = byUser.isEmpty
      ? 'Sistema'
      : (actorNamesById[byUser]?.trim().isNotEmpty == true
            ? actorNamesById[byUser]!.trim()
            : byUser);
  final role = event.byRole.trim();
  if (role.isEmpty) return resolvedName;
  return '$resolvedName ($role)';
}
