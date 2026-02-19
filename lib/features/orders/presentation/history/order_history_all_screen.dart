import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

class OrderHistoryAllScreen extends ConsumerStatefulWidget {
  const OrderHistoryAllScreen({super.key});

  @override
  ConsumerState<OrderHistoryAllScreen> createState() =>
      _OrderHistoryAllScreenState();
}

class _OrderHistoryAllScreenState extends ConsumerState<OrderHistoryAllScreen> {
  PurchaseOrderStatus? statusFilter;
  PurchaseOrderUrgency? urgencyFilter;
  DateTimeRange? dateRange;

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
    final userAsync = ref.watch(currentUserProfileProvider);
    final user = userAsync.value;

    if (userAsync.isLoading) {
      return const Scaffold(body: AppSplash());
    }
    if (user == null) {
      return const Scaffold(body: AppSplash());
    }

    final canViewAll =
        isAdminRole(user.role) || isDireccionGeneralLabel(user.areaDisplay);

    final ordersAsync = ref.watch(allOrdersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Historial general')),
      body: !canViewAll
          ? const Center(
              child: Text('No tienes permisos para ver el historial general.'),
            )
          : ordersAsync.when(
              data: (orders) {
                if (orders.isEmpty) {
                  return const _EmptyHistory();
                }

                final filtered = orders
                    .where(_isHistoryVisible)
                    .where(_filterOrder)
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
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Text(
                        'Las limpiezas se ejecutan de forma anual mediante un programa externo. '
                        'Considera respaldar las órdenes finalizadas si las necesitas.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    _FiltersBar(
                      statusFilter: statusFilter,
                      urgencyFilter: urgencyFilter,
                      dateRange: dateRange,
                      onStatusChanged: (value) =>
                          setState(() => statusFilter = value),
                      onUrgencyChanged: (value) =>
                          setState(() => urgencyFilter = value),
                      onDateRangeChanged: (range) =>
                          setState(() => dateRange = range),
                      onClear: () => setState(() {
                        statusFilter = null;
                        urgencyFilter = null;
                        dateRange = null;
                      }),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? _EmptyResults(
                              onClear: () => setState(() {
                                statusFilter = null;
                                urgencyFilter = null;
                                dateRange = null;
                              }),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final order = filtered[index];
                                return _OrderHistoryCard(order: order);
                              },
                            ),
                    ),
                  ],
                );
              },
              loading: () => const AppSplash(),
              error: (error, stack) => Center(
                child: Text(
                  'Error: ${reportError(error, stack, context: 'OrderHistoryAllScreen')}',
                ),
              ),
            ),
    );
  }

  bool _filterOrder(PurchaseOrder order) {
    final statusOk = statusFilter == null || order.status == statusFilter;
    final urgencyOk = urgencyFilter == null || order.urgency == urgencyFilter;

    final dateOk = dateRange == null ||
        (order.createdAt != null &&
            order.createdAt!
                .isAfter(dateRange!.start.subtract(const Duration(days: 1))) &&
            order.createdAt!
                .isBefore(dateRange!.end.add(const Duration(days: 1))));

    return statusOk && urgencyOk && dateOk;
  }

  bool _isHistoryVisible(PurchaseOrder order) {
    switch (order.status) {
      case PurchaseOrderStatus.cotizaciones:
      case PurchaseOrderStatus.authorizedGerencia:
      case PurchaseOrderStatus.paymentDone:
      case PurchaseOrderStatus.contabilidad:
      case PurchaseOrderStatus.almacen:
      case PurchaseOrderStatus.eta:
        return true;

      case PurchaseOrderStatus.draft:
      case PurchaseOrderStatus.pendingCompras:
      case PurchaseOrderStatus.orderPlaced:
        return false;
    }
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
    const statusOptions = [
      PurchaseOrderStatus.cotizaciones,
      PurchaseOrderStatus.authorizedGerencia,
      PurchaseOrderStatus.paymentDone,
      PurchaseOrderStatus.contabilidad,
      PurchaseOrderStatus.almacen,
      PurchaseOrderStatus.eta,
    ];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 600;
          final fieldWidth = isNarrow ? constraints.maxWidth : 220.0;
          final urgencyWidth = isNarrow ? constraints.maxWidth : 200.0;
          final dateButtonWidth = isNarrow ? constraints.maxWidth : null;

          return Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: fieldWidth,
                child: DropdownButtonFormField<PurchaseOrderStatus?>(
                  initialValue: statusFilter,
                  decoration: const InputDecoration(labelText: 'Estado'),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Todos'),
                    ),
                    ...statusOptions.map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(
                          status.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: onStatusChanged,
                ),
              ),
              SizedBox(
                width: urgencyWidth,
                child: DropdownButtonFormField<PurchaseOrderUrgency?>(
                  initialValue: urgencyFilter,
                  decoration: const InputDecoration(labelText: 'Urgencia'),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Todas'),
                    ),
                    ...PurchaseOrderUrgency.values.map(
                      (urgency) => DropdownMenuItem(
                        value: urgency,
                        child: Text(
                          urgency.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: onUrgencyChanged,
                ),
              ),
              SizedBox(
                width: dateButtonWidth,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate:
                          DateTime.now().subtract(const Duration(days: 365)),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              TextButton(
                onPressed: onClear,
                child: const Text('Limpiar filtros'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

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
            const Text('Aún no hay órdenes registradas'),
          ],
        ),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 48),
            const SizedBox(height: 12),
            const Text('No hay órdenes con esos filtros.'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onClear,
              child: const Text('Limpiar filtros'),
            ),
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
    final resendCount = order.returnCount;
    final resendLabel = resendCount <= 0
        ? null
        : (resendCount == 1 ? 'Reenviada' : 'Reenviada x$resendCount');

    final canRepeat = order.status == PurchaseOrderStatus.eta;
    final copyRoute =
        '/orders/create?copyFromId=${Uri.encodeComponent(order.id)}';

    final createdLabel = order.createdAt?.toFullDateTime() ?? 'Pendiente';

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
                  Chip(label: Text(order.urgency.label)),
                ],
              ),
              if (resendLabel != null) ...[
                const SizedBox(height: 8),
                Text(resendLabel),
              ],
              const SizedBox(height: 8),
              Text('Solicitante: ${order.requesterName}'),
              Text('Área: ${order.areaName}'),
              const SizedBox(height: 8),
              Text('Estado: ${order.status.label}'),
              const SizedBox(height: 8),

              // ✅ Reemplazo del widget corrupto
              _OrderCardSummary(order: order),

              const SizedBox(height: 8),
              Text('Creada: $createdLabel'),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _statusProgress(order.status)),
              const SizedBox(height: 12),
              if (canRepeat) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(copyRoute),
                    icon: const Icon(Icons.content_copy_outlined),
                    label: const Text('Volver a generar'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  double _statusProgress(PurchaseOrderStatus status) {
    final normalized =
        status == PurchaseOrderStatus.orderPlaced ? PurchaseOrderStatus.eta : status;
    final index = defaultStatusFlow.indexOf(normalized);
    if (index == -1) return 0;
    return (index + 1) / defaultStatusFlow.length;
  }
}

class _OrderCardSummary extends StatelessWidget {
  const _OrderCardSummary({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final supplier = (order.supplier ?? '').trim();
    final internalOrder = (order.internalOrder ?? '').trim();
    final comprasComment = (order.comprasComment ?? '').trim();
    final clientNote = (order.clientNote ?? '').trim();

    final lines = <String>[
      if (supplier.isNotEmpty) 'Proveedor: $supplier',
      if (internalOrder.isNotEmpty) 'OC interna: $internalOrder',
      if (order.budget != null) 'Presupuesto: ${order.budget}',
      if (comprasComment.isNotEmpty) 'Compras: $comprasComment',
      if (clientNote.isNotEmpty) 'Nota: $clientNote',
    ];

    if (lines.isEmpty) {
      return Text('Sin detalles adicionales.', style: theme.textTheme.bodySmall);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines) ...[
          Text(line, style: theme.textTheme.bodySmall),
          const SizedBox(height: 2),
        ],
      ],
    );
  }
}
