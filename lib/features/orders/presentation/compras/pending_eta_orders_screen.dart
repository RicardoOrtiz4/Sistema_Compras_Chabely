import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/core/widgets/info_action.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_status_duration.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

class PendingEtaOrdersScreen extends ConsumerStatefulWidget {
  const PendingEtaOrdersScreen({super.key});

  @override
  ConsumerState<PendingEtaOrdersScreen> createState() =>
      _PendingEtaOrdersScreenState();
}

class _PendingEtaOrdersScreenState extends ConsumerState<PendingEtaOrdersScreen> {
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
    final ordersAsync = ref.watch(pendingEtaOrdersPagedProvider(_limit));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pendientes de fecha estimada'),
        actions: [
          infoAction(
            context,
            title: 'Pendientes de fecha estimada',
            message:
                'Asigna fecha estimada de entrega por orden.\n'
                'Usa el buscador para localizar folios.\n'
                'Guardar avanza la orden al siguiente paso.',
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
          final showLoadMore =
              canLoadMore && filtered.length >= defaultOrderPageSize;

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
                          final busy = _busyOrders.contains(order.id);
                          return _PendingEtaOrderCard(
                            order: order,
                            busy: busy,
                            onViewPdf: () => guardedPush(context, '/orders/${order.id}/pdf'),
                            onSetEta: () => _handleSetEta(order),
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
            'Error: ${reportError(error, stack, context: 'PendingEtaOrdersScreen')}',
          ),
        ),
      ),
    );
  }

  Future<void> _handleSetEta(PurchaseOrder order) async {
    final requested = _requestedDeliveryDate(order);
    final initialDate = requested ?? DateTime.now();

    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: initialDate.isAfter(DateTime.now()) ? initialDate : DateTime.now(),
    );

    if (picked == null) return;

    _setBusy(order.id, true);
    try {
      final actor = ref.read(currentUserProfileProvider).value;
      if (actor == null) {
        throw StateError('Perfil no disponible.');
      }
      final repo = ref.read(purchaseOrderRepositoryProvider);
      await repo.setEstimatedDeliveryDate(
        order: order,
        etaDate: picked,
        actor: actor,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fecha estimada registrada.')),
      );
    } catch (error, stack) {
      if (!mounted) return;
      final message = reportError(error, stack, context: 'PendingEtaOrdersScreen.setEta');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        _setBusy(order.id, false);
      }
    }
  }

  DateTime? _requestedDeliveryDate(PurchaseOrder order) {
    DateTime? selected;
    for (final item in order.items) {
      final date = item.estimatedDate;
      if (date == null) continue;
      if (selected == null || date.isBefore(selected)) {
        selected = date;
      }
    }
    return selected;
  }

  void _setBusy(String orderId, bool value) {
    setState(() {
      if (value) {
        _busyOrders.add(orderId);
      } else {
        _busyOrders.remove(orderId);
      }
    });
  }
}

class _PendingEtaOrderCard extends StatelessWidget {
  const _PendingEtaOrderCard({
    required this.order,
    required this.busy,
    required this.onViewPdf,
    required this.onSetEta,
  });

  final PurchaseOrder order;
  final bool busy;
  final VoidCallback onViewPdf;
  final VoidCallback onSetEta;

  @override
  Widget build(BuildContext context) {
    final createdLabel = order.createdAt?.toFullDateTime() ?? 'Pendiente';
    final requestedDate = _requestedDeliveryDate(order);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Solicitante: ${order.requesterName}'),
            Text('Área: ${order.areaName}'),
            Text('Urgencia: ${order.urgency.label}'),
            Text('Creada: $createdLabel'),
            const SizedBox(height: 8),

            // ✅ Reemplazo del widget corrupto:
            _OrderSummary(order: order),
            const SizedBox(height: 6),
            OrderStatusDurationPill(order: order),

            if (requestedDate != null)
              Text('Fecha solicitada: ${requestedDate.toShortDate()}'),

            if (order.direccionGeneralName != null &&
                order.direccionGeneralName!.trim().isNotEmpty)
              Text('Autorizó: ${order.direccionGeneralName}'),

            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 360;

                final viewPdf = OutlinedButton.icon(
                  onPressed: busy ? null : onViewPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Ver PDF'),
                );

                final etaButton = FilledButton(
                  onPressed: busy ? null : onSetEta,
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: AppSplash(compact: true, size: 18),
                        )
                      : const Text('Definir fecha estimada'),
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      viewPdf,
                      const SizedBox(height: 8),
                      etaButton,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: viewPdf),
                    const SizedBox(width: 12),
                    Expanded(child: etaButton),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  DateTime? _requestedDeliveryDate(PurchaseOrder order) {
    DateTime? selected;
    for (final item in order.items) {
      final date = item.estimatedDate;
      if (date == null) continue;
      if (selected == null || date.isBefore(selected)) {
        selected = date;
      }
    }
    return selected;
  }
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({required this.order});
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

