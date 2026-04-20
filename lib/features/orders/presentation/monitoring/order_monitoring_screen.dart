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
import 'package:sistema_compras/features/orders/domain/order_event_labels.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/monitoring/monitoring_pdf_view_screen.dart';
import 'package:sistema_compras/features/orders/presentation/monitoring/order_monitoring_support.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_view_screen.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_urgency_controls.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

class OrderMonitoringScreen extends ConsumerStatefulWidget {
  const OrderMonitoringScreen({super.key});

  @override
  ConsumerState<OrderMonitoringScreen> createState() =>
      _OrderMonitoringScreenState();
}

class MonitoreoPage extends OrderMonitoringScreen {
  const MonitoreoPage({super.key});
}

class _OrderMonitoringScreenState extends ConsumerState<OrderMonitoringScreen> {
  bool _exportingCsv = false;
  bool _exportingPdf = false;
  late final TextEditingController _searchController;
  final OrderSearchCache _searchCache = OrderSearchCache();
  Timer? _searchDebounce;
  String _searchQuery = '';
  DateTimeRange? _createdDateRangeFilter;

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
    });
  }

  Future<Map<String, List<PurchaseOrderEvent>>> _loadEventsForOrders(
    List<PurchaseOrder> orders,
  ) async {
    final repository = ref.read(purchaseOrderRepositoryProvider);
    final entries = await Future.wait([
      for (final order in orders)
        repository.watchEvents(order.id).first.then(
              (events) => MapEntry(order.id, events),
            ),
    ]);
    return {
      for (final entry in entries) entry.key: entry.value,
    };
  }

  Future<void> _handleExportCsv(
    List<PurchaseOrder> orders,
    Map<String, String> actorNamesById,
  ) async {
    if (_exportingCsv || orders.isEmpty) return;
    setState(() => _exportingCsv = true);
    final now = DateTime.now();
    try {
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
      if (mounted) {
        setState(() => _exportingCsv = false);
      }
    }
  }

  Future<void> _handleExportPdf(
    List<PurchaseOrder> orders,
    CompanyBranding branding,
    Map<String, String> actorNamesById,
  ) async {
    if (_exportingPdf || orders.isEmpty) return;
    setState(() => _exportingPdf = true);
    final now = DateTime.now();
    try {
      final eventsByOrder = await _loadEventsForOrders(orders);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MonitoringPdfViewScreen(
            orders: orders,
            now: now,
            companyName: branding.displayName,
            scopeLabel: 'Visibles: ${orders.length} | Monitoreo operativo',
            eventsByOrder: eventsByOrder,
            actorNamesById: actorNamesById,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exportingPdf = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProfileProvider);
    final branding = ref.watch(currentBrandingProvider);
    final usersAsync = ref.watch(allUsersProvider);
    final user = userAsync.value;

    if (userAsync.isLoading || user == null) {
      return const Scaffold(body: AppSplash());
    }

    final canView = canViewMonitoring(user);
    final ordersAsync = ref.watch(monitoringOrdersProvider);
    final actorNamesById = _actorNamesById(usersAsync.valueOrNull);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F7FB),
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: Navigator.of(context).canPop(),
        titleSpacing: 16,
        title: _MonitoringHeader(
          controller: _searchController,
          searchQuery: _searchQuery,
          onChanged: _updateSearch,
          onClear: _clearSearch,
          onPickRange: _pickCreatedDateFilter,
          onExportCsv: ordersAsync.valueOrNull == null
              ? null
              : () => _handleExportCsv(
                    _filterOrders(ordersAsync.valueOrNull!),
                    actorNamesById,
                  ),
          onExportPdf: ordersAsync.valueOrNull == null
              ? null
              : () => _handleExportPdf(
                    _filterOrders(ordersAsync.valueOrNull!),
                    branding,
                    actorNamesById,
                  ),
          exportingCsv: _exportingCsv,
          exportingPdf: _exportingPdf,
        ),
      ),
      body: !canView
          ? const Center(
              child: Text('No tienes permisos para ver el monitoreo.'),
            )
          : ordersAsync.when(
              data: (orders) {
                final filteredOrders = _filterOrders(orders);
                final normalCount = filteredOrders
                    .where((order) => order.urgency == PurchaseOrderUrgency.normal)
                    .length;
                final urgentCount = filteredOrders
                    .where((order) => order.urgency == PurchaseOrderUrgency.urgente)
                    .length;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: KPIBox(
                            title: 'Activas',
                            subtitle: 'órdenes visibles',
                            value: '${filteredOrders.length}',
                            tone: const Color(0xFF2563EB),
                            icon: Icons.inventory_2_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: KPIBox(
                            title: 'Normales',
                            subtitle: 'carga operativa',
                            value: '$normalCount',
                            tone: const Color(0xFF64748B),
                            icon: Icons.remove_circle_outline,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: KPIBox(
                            title: 'Urgentes',
                            subtitle: 'prioridad alta',
                            value: '$urgentCount',
                            tone: const Color(0xFFDC2626),
                            icon: Icons.priority_high_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _MonitoringActivitySection(
                      orders: filteredOrders,
                      actorNamesById: actorNamesById,
                      hasActiveFilters:
                          _searchQuery.trim().isNotEmpty ||
                          _createdDateRangeFilter != null,
                    ),
                  ],
                );
              },
              loading: () => const AppSplash(),
              error: (error, stack) => Center(
                child: Text(
                  reportError(error, stack, context: 'OrderMonitoringScreen'),
                ),
              ),
            ),
    );
  }

  List<PurchaseOrder> _filterOrders(List<PurchaseOrder> orders) {
    final monitorable = orders.where(isMonitorableOrder).toList(growable: false);
    _searchCache.retainFor(monitorable);
    final trimmedQuery = _searchQuery.trim();
    return monitorable
        .where((order) => matchesOrderCreatedDateRange(order, _createdDateRangeFilter))
        .where(
          (order) => orderMatchesSearch(
            order,
            trimmedQuery,
            cache: _searchCache,
            includeDates: false,
          ),
        )
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

String _localEventActorLabel(
  PurchaseOrderEvent event,
  Map<String, String> actorNamesById,
) {
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

class _MonitoringHeader extends StatelessWidget {
  const _MonitoringHeader({
    required this.controller,
    required this.searchQuery,
    required this.onChanged,
    required this.onClear,
    required this.onPickRange,
    required this.onExportCsv,
    required this.onExportPdf,
    required this.exportingCsv,
    required this.exportingPdf,
  });

  final TextEditingController controller;
  final String searchQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onPickRange;
  final VoidCallback? onExportCsv;
  final VoidCallback? onExportPdf;
  final bool exportingCsv;
  final bool exportingPdf;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 900;
        final title = Text(
          'Monitoreo',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        );
        final search = SizedBox(
          width: isNarrow ? double.infinity : 360,
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: 'Buscar por folio, solicitante o área',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: onClear,
                    ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
            ),
          ),
        );
        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: onPickRange,
              icon: const Icon(Icons.date_range_outlined),
              label: const Text('Rango de fechas'),
            ),
            FilledButton.tonalIcon(
              onPressed: onExportCsv,
              icon: exportingCsv
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.table_chart_outlined),
              label: const Text('Exportar CSV'),
            ),
            FilledButton.icon(
              onPressed: onExportPdf,
              icon: exportingPdf
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Exportar PDF'),
            ),
          ],
        );
        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 12),
              search,
              const SizedBox(height: 12),
              actions,
            ],
          );
        }
        return Row(
          children: [
            title,
            const SizedBox(width: 16),
            search,
            const Spacer(),
            actions,
          ],
        );
      },
    );
  }
}

class KPIBox extends StatelessWidget {
  const KPIBox({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.tone,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String value;
  final Color tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: _softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tone.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: tone),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6B7280),
                ),
          ),
        ],
      ),
    );
  }
}

class StatusIndicator extends StatelessWidget {
  const StatusIndicator({
    super.key,
    required this.label,
    required this.tone,
  });

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: tone,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _MonitoringActivitySection extends ConsumerWidget {
  const _MonitoringActivitySection({
    required this.orders,
    required this.actorNamesById,
    required this.hasActiveFilters,
  });

  final List<PurchaseOrder> orders;
  final Map<String, String> actorNamesById;
  final bool hasActiveFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (orders.isEmpty) {
      return _EmptyMonitoringCard(
        message: hasActiveFilters
            ? 'No hay órdenes con ese filtro.'
            : 'No hay órdenes monitorizables en este momento.',
      );
    }

    final activities = <_MonitoringActivity>[];
    var loadingCount = 0;
    for (final order in orders) {
      final eventsAsync = ref.watch(orderEventsProvider(order.id));
      eventsAsync.when(
        data: (events) {
          final sorted = newestEventsFirst(events)
              .where((event) => event.timestamp != null)
              .toList(growable: false);
          activities.add(_MonitoringActivity(order: order, events: sorted));
        },
        loading: () => loadingCount += 1,
        error: (_, __) => activities.add(
          _MonitoringActivity(order: order, events: const <PurchaseOrderEvent>[]),
        ),
      );
    }

    activities.sort((left, right) {
      return right.latestTimestamp.compareTo(left.latestTimestamp);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (loadingCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Actualizando actividad...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
            ),
          ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: activities.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) => OrderCard(
            activity: activities[index],
            actorNamesById: actorNamesById,
          ),
        ),
      ],
    );
  }
}

class OrderCard extends StatelessWidget {
  const OrderCard({
    super.key,
    required this.activity,
    required this.actorNamesById,
  });

  final _MonitoringActivity activity;
  final Map<String, String> actorNamesById;

  @override
  Widget build(BuildContext context) {
    final order = activity.order;
    final latestEvent = activity.latestEvent;
    final stageTone = _stageTone(order);
    final leftBarColor = _leftBarColor(order);
    final movementLabel = latestEvent == null
        ? order.status.label
        : orderEventTransitionLabel(latestEvent);
    final actorLabel =
        describeActor(order.requesterName, order.areaName) ?? order.requesterName;
    final elapsed = currentStatusElapsed(order, DateTime.now());
    final resolvedCount = order.items.where((item) => item.isResolved).length;
    final pendingCount = order.items.length - resolvedCount;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 1.5,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openDetail(context),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 192,
                decoration: BoxDecoration(
                  color: leftBarColor,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(16),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  order.id,
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  actorLabel,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: const Color(0xFF6B7280),
                                      ),
                                ),
                                const SizedBox(height: 12),
                                StatusIndicator(
                                  label: order.status.label,
                                  tone: stageTone,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  movementLabel,
                                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _MetricMeta(
                                icon: Icons.timer_outlined,
                                value: formatMonitoringDuration(elapsed),
                              ),
                              const SizedBox(height: 8),
                              _MetricMeta(
                                icon: Icons.sync_alt_outlined,
                                value: '${activity.events.length}',
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _openDetail(context),
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('Ver detalle'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => OrderPdfViewScreen(orderId: order.id),
                                ),
                              );
                            },
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('Ver PDF'),
                          ),
                          PopupMenuButton<String>(
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'detail',
                                child: Text('Ver detalle'),
                              ),
                              PopupMenuItem(
                                value: 'pdf',
                                child: Text('Ver PDF'),
                              ),
                            ],
                            onSelected: (value) {
                              if (value == 'detail') {
                                _openDetail(context);
                                return;
                              }
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => OrderPdfViewScreen(orderId: order.id),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _SummaryBadge(
                              label: '$resolvedCount enviados',
                              tone: const Color(0xFFDBEAFE),
                              textColor: const Color(0xFF1D4ED8),
                            ),
                            _SummaryBadge(
                              label: '$pendingCount pendientes',
                              tone: const Color(0xFFFFEDD5),
                              textColor: const Color(0xFFC2410C),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDetail(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF8FAFC),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.48,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.order.id,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${activity.order.requesterName} | ${activity.order.areaName}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF6B7280),
                        ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: activity.events.isEmpty
                        ? const Center(
                            child: Text('Aún no hay movimientos registrados.'),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: activity.events.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final event = activity.events[index];
                              final comment = event.comment?.trim() ?? '';
                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      orderEventTransitionLabel(event),
                                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _localEventActorLabel(event, actorNamesById),
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: const Color(0xFF6B7280),
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      event.timestamp?.toFullDateTime() ?? 'Sin fecha',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    if (comment.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Text(comment),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _MetricMeta extends StatelessWidget {
  const _MetricMeta({
    required this.icon,
    required this.value,
  });

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF64748B)),
        const SizedBox(width: 6),
        Text(
          value,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: const Color(0xFF475569),
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _SummaryBadge extends StatelessWidget {
  const _SummaryBadge({
    required this.label,
    required this.tone,
    required this.textColor,
  });

  final String label;
  final Color tone;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _EmptyMonitoringCard extends StatelessWidget {
  const _EmptyMonitoringCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: _softShadow,
      ),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _MonitoringActivity {
  const _MonitoringActivity({
    required this.order,
    required this.events,
  });

  final PurchaseOrder order;
  final List<PurchaseOrderEvent> events;

  PurchaseOrderEvent? get latestEvent => events.isEmpty ? null : events.first;

  int get latestTimestamp =>
      latestEvent?.timestamp?.millisecondsSinceEpoch ??
      order.updatedAt?.millisecondsSinceEpoch ??
      order.createdAt?.millisecondsSinceEpoch ??
      0;
}

Color _leftBarColor(PurchaseOrder order) {
  if (order.urgency == PurchaseOrderUrgency.urgente) {
    return const Color(0xFFDC2626);
  }
  switch (order.status) {
    case PurchaseOrderStatus.approvalQueue:
      return const Color(0xFF2563EB);
    case PurchaseOrderStatus.sourcing:
    case PurchaseOrderStatus.readyForApproval:
    case PurchaseOrderStatus.paymentDone:
    case PurchaseOrderStatus.contabilidad:
      return const Color(0xFFEAB308);
    default:
      return const Color(0xFF16A34A);
  }
}

Color _stageTone(PurchaseOrder order) {
  if (order.urgency == PurchaseOrderUrgency.urgente) {
    return const Color(0xFFDC2626);
  }
  switch (order.status) {
    case PurchaseOrderStatus.approvalQueue:
      return const Color(0xFF2563EB);
    case PurchaseOrderStatus.sourcing:
    case PurchaseOrderStatus.readyForApproval:
    case PurchaseOrderStatus.paymentDone:
    case PurchaseOrderStatus.contabilidad:
      return const Color(0xFFD97706);
    default:
      return const Color(0xFF16A34A);
  }
}

const List<BoxShadow> _softShadow = [
  BoxShadow(
    color: Color(0x120F172A),
    blurRadius: 24,
    offset: Offset(0, 10),
  ),
];
