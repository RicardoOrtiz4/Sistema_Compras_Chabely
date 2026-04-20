import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/access_control.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/monitoring/monitoring_pdf_view_screen.dart';
import 'package:sistema_compras/features/orders/presentation/monitoring/order_monitoring_support.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_urgency_controls.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

class OrderMonitoringScreen extends ConsumerStatefulWidget {
  const OrderMonitoringScreen({super.key});

  @override
  ConsumerState<OrderMonitoringScreen> createState() =>
      _OrderMonitoringScreenState();
}

class _OrderMonitoringScreenState extends ConsumerState<OrderMonitoringScreen> {
  bool _exportingCsv = false;
  bool _exportingPdf = false;
  OrderUrgencyFilter _urgencyFilter = OrderUrgencyFilter.all;

  void _setUrgencyFilter(OrderUrgencyFilter filter) {
    setState(() => _urgencyFilter = filter);
  }

  Future<Map<String, List<PurchaseOrderEvent>>> _loadEventsForOrders(
    List<PurchaseOrder> orders,
  ) async {
    final repository = ref.read(purchaseOrderRepositoryProvider);
    final entries = await Future.wait(
      [
        for (final order in orders)
          repository.watchEvents(order.id).first.then(
                (events) => MapEntry(order.id, events),
              ),
      ],
    );
    return {for (final entry in entries) entry.key: entry.value};
  }

  Future<void> _exportCsv(
    List<PurchaseOrder> orders,
    Map<String, String> actorNamesById,
  ) async {
    if (_exportingCsv) return;
    setState(() => _exportingCsv = true);
    try {
      final now = DateTime.now();
      final eventsByOrder = await _loadEventsForOrders(orders);
      if (!mounted) return;
      await exportMonitoringCsv(
        context,
        orders: orders,
        now: now,
        eventsByOrder: eventsByOrder,
        actorNamesById: actorNamesById,
      );
    } finally {
      if (mounted) setState(() => _exportingCsv = false);
    }
  }

  Future<void> _exportPdf(
    List<PurchaseOrder> orders,
    CompanyBranding branding,
    Map<String, String> actorNamesById,
  ) async {
    if (_exportingPdf) return;
    setState(() => _exportingPdf = true);
    try {
      final now = DateTime.now();
      final eventsByOrder = await _loadEventsForOrders(orders);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MonitoringPdfViewScreen(
            orders: orders,
            now: now,
            companyName: branding.displayName,
            scopeLabel: 'Ordenes actuales: ${orders.length}',
            eventsByOrder: eventsByOrder,
            actorNamesById: actorNamesById,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProfileProvider);
    final user = userAsync.value;
    final branding = ref.watch(currentBrandingProvider);
    final usersAsync = ref.watch(allUsersProvider);
    final ordersAsync = ref.watch(monitoringOrdersProvider);
    final compactAppBar = useCompactOrderModuleAppBar(context);

    if (userAsync.isLoading || user == null) {
      return const Scaffold(body: AppSplash());
    }

    final canView = canViewMonitoring(user);
    final actorNamesById = _actorNamesById(usersAsync.valueOrNull);

    return Scaffold(
      appBar: AppBar(
        title: ordersAsync.maybeWhen(
          data: (orders) {
            final activeOrders = _activeOrders(orders);
            final filteredOrders = _filteredOrders(activeOrders);
            final counts = OrderUrgencyCounts.fromOrders(activeOrders);
            final exportButtons = _MonitoringExportButtons(
              enabled: canView && filteredOrders.isNotEmpty,
              exportingCsv: _exportingCsv,
              exportingPdf: _exportingPdf,
              onExportCsv: () => _exportCsv(filteredOrders, actorNamesById),
              onExportPdf: () =>
                  _exportPdf(filteredOrders, branding, actorNamesById),
            );
            if (compactAppBar) return const Text('Monitoreo');
            return OrderModuleAppBarTitle(
              title: 'Monitoreo',
              counts: counts,
              filter: _urgencyFilter,
              onSelected: _setUrgencyFilter,
              trailing: exportButtons,
            );
          },
          orElse: () => const Text('Monitoreo'),
        ),
        bottom: compactAppBar
            ? PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: ordersAsync.maybeWhen(
                  data: (orders) {
                    final activeOrders = _activeOrders(orders);
                    final filteredOrders = _filteredOrders(activeOrders);
                    return OrderModuleAppBarBottom(
                      counts: OrderUrgencyCounts.fromOrders(activeOrders),
                      filter: _urgencyFilter,
                      onSelected: _setUrgencyFilter,
                      trailing: _MonitoringExportButtons(
                        enabled: canView && filteredOrders.isNotEmpty,
                        exportingCsv: _exportingCsv,
                        exportingPdf: _exportingPdf,
                        onExportCsv: () =>
                            _exportCsv(filteredOrders, actorNamesById),
                        onExportPdf: () => _exportPdf(
                          filteredOrders,
                          branding,
                          actorNamesById,
                        ),
                      ),
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),
              )
            : null,
      ),
      body: !canView
          ? const Center(child: Text('No tienes permisos para ver monitoreo.'))
          : ordersAsync.when(
              data: (orders) {
                final activeOrders = _activeOrders(orders);
                final filteredOrders = _filteredOrders(activeOrders);
                if (filteredOrders.isEmpty) {
                  return const _EmptyMonitoringTable();
                }
                return _MonitoringStatusTable(
                  orders: filteredOrders,
                  actorNamesById: actorNamesById,
                );
              },
              loading: () => const AppSplash(),
              error: (error, stack) => Center(
                child: Text(
                  'Error: ${reportError(error, stack, context: 'OrderMonitoringScreen')}',
                ),
              ),
            ),
    );
  }

  List<PurchaseOrder> _activeOrders(List<PurchaseOrder> orders) {
    final active = orders.where(isMonitorableOrder).toList(growable: false);
    active.sort((a, b) {
      final aMs = (a.updatedAt ?? a.createdAt)?.millisecondsSinceEpoch ?? 0;
      final bMs = (b.updatedAt ?? b.createdAt)?.millisecondsSinceEpoch ?? 0;
      return bMs.compareTo(aMs);
    });
    return active;
  }

  List<PurchaseOrder> _filteredOrders(List<PurchaseOrder> orders) {
    return orders
        .where((order) => matchesOrderUrgencyFilter(order, _urgencyFilter))
        .toList(growable: false);
  }
}

Map<String, String> _actorNamesById(List<AppUser>? users) {
  if (users == null || users.isEmpty) return const <String, String>{};
  return <String, String>{
    for (final user in users)
      user.id: user.name.trim().isEmpty ? user.id : user.name.trim(),
  };
}

class _MonitoringExportButtons extends StatelessWidget {
  const _MonitoringExportButtons({
    required this.enabled,
    required this.exportingCsv,
    required this.exportingPdf,
    required this.onExportCsv,
    required this.onExportPdf,
  });

  final bool enabled;
  final bool exportingCsv;
  final bool exportingPdf;
  final VoidCallback onExportCsv;
  final VoidCallback onExportPdf;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Descargar CSV',
          onPressed: enabled && !exportingCsv ? onExportCsv : null,
          icon: exportingCsv
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.table_view_outlined),
        ),
        IconButton(
          tooltip: 'Ver PDF',
          onPressed: enabled && !exportingPdf ? onExportPdf : null,
          icon: exportingPdf
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf_outlined),
        ),
      ],
    );
  }
}

class _MonitoringStatusTable extends ConsumerWidget {
  const _MonitoringStatusTable({
    required this.orders,
    required this.actorNamesById,
  });

  final List<PurchaseOrder> orders;
  final Map<String, String> actorNamesById;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    var loadingEvents = false;
    var errorEvents = 0;
    final rows = <MonitoringOrderStatusRow>[];

    for (final order in orders) {
      final eventsAsync = ref.watch(orderEventsProvider(order.id));
      final events = eventsAsync.valueOrNull ?? const <PurchaseOrderEvent>[];
      loadingEvents = loadingEvents || eventsAsync.isLoading;
      if (eventsAsync.hasError) errorEvents++;
      rows.addAll(
        buildMonitoringStatusRows(
          order: order,
          events: events,
          now: now,
          actorNamesById: actorNamesById,
        ),
      );
    }

    return Column(
      children: [
        if (loadingEvents) const LinearProgressIndicator(minHeight: 2),
        if (errorEvents > 0)
          _TableNotice(
            message: 'No se pudieron cargar $errorEvents historial(es).',
          ),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Scrollbar(
                notificationPredicate: (notification) =>
                    notification.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 42,
                    dataRowMinHeight: 44,
                    dataRowMaxHeight: 64,
                    columns: const [
                      DataColumn(label: Text('Folio')),
                      DataColumn(label: Text('Urgencia')),
                      DataColumn(label: Text('Estado actual')),
                      DataColumn(label: Text('Solicitante')),
                      DataColumn(label: Text('Area')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Tiempo')),
                      DataColumn(label: Text('Actuo')),
                      DataColumn(label: Text('Fecha / hora')),
                    ],
                    rows: [
                      for (final row in rows)
                        DataRow(
                          color: WidgetStateProperty.resolveWith(
                            (_) => row.isCurrent
                                ? Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                    .withValues(alpha: 0.35)
                                : null,
                          ),
                          cells: [
                            DataCell(Text(row.order.id)),
                            DataCell(Text(row.order.urgency.label)),
                            DataCell(Text(requesterReceiptStatusLabel(row.order))),
                            DataCell(_TableText(row.order.requesterName)),
                            DataCell(_TableText(row.order.areaName)),
                            DataCell(
                              Text(
                                row.isCurrent
                                    ? '${row.status.label} (actual)'
                                    : row.status.label,
                              ),
                            ),
                            DataCell(Text(formatMonitoringDuration(row.elapsed))),
                            DataCell(_TableText(row.actor)),
                            DataCell(Text(_dateLabel(row.enteredAt))),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TableText extends StatelessWidget {
  const _TableText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _TableNotice extends StatelessWidget {
  const _TableNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.colorScheme.errorContainer,
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}

class _EmptyMonitoringTable extends StatelessWidget {
  const _EmptyMonitoringTable();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('No hay ordenes actuales con ese filtro.'),
    );
  }
}

String _dateLabel(DateTime? value) {
  if (value == null) return '-';
  return value.toFullDateTime();
}
