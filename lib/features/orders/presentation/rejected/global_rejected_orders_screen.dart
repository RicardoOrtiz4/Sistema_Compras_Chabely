import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_pdf_preload_gate.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_status_duration.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_urgency_controls.dart';
import 'package:sistema_compras/features/profile/presentation/profile_sheet.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

class GlobalActionMonitoringScreen extends ConsumerStatefulWidget {
  const GlobalActionMonitoringScreen({super.key});

  @override
  ConsumerState<GlobalActionMonitoringScreen> createState() =>
      _GlobalActionMonitoringScreenState();
}

class _GlobalActionMonitoringScreenState
    extends ConsumerState<GlobalActionMonitoringScreen> {
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
    final user = ref.watch(currentUserProfileProvider).value;
    final compactAppBar = useCompactOrderModuleAppBar(context);
    final canView = user != null &&
        (isAdminRole(user.role) ||
            isComprasLabel(user.areaDisplay) ||
            isDireccionGeneralLabel(user.areaDisplay));
    final ordersAsync = ref.watch(globalActionMonitoringOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: ordersAsync.when(
          data: (orders) => compactAppBar
              ? const Text('Monitoreo de acciones')
              : OrderModuleAppBarTitle(
                  title: 'Monitoreo de acciones',
                  counts: OrderUrgencyCounts.fromOrders(orders),
                  filter: _urgencyFilter,
                  onSelected: _setUrgencyFilter,
                ),
          loading: () => const Text('Monitoreo de acciones'),
          error: (_, __) => const Text('Monitoreo de acciones'),
        ),
        bottom: !compactAppBar
            ? null
            : ordersAsync.maybeWhen(
                data: (orders) => OrderModuleAppBarBottom(
                  counts: OrderUrgencyCounts.fromOrders(orders),
                  filter: _urgencyFilter,
                  onSelected: _setUrgencyFilter,
                ),
                orElse: () => null,
              ),
      ),
      body: !canView
          ? const Center(
              child: Text('No tienes permisos para ver esta vista.'),
            )
          : ordersAsync.when(
              data: (orders) {
                _searchCache.retainFor(orders);
                final filtered = _resolveVisibleOrders(orders);
                final visibleOrders =
                    filtered.take(_limit).toList(growable: false);
                final showLoadMore = filtered.length > visibleOrders.length;
                final rejectedOrders = visibleOrders
                    .where(
                      (order) =>
                          _globalMonitoringTypeFor(order) ==
                          _GlobalMonitoringType.rejected,
                    )
                    .toList(growable: false);
                final awaitingReceiptOrders = visibleOrders
                    .where(
                      (order) =>
                          _globalMonitoringTypeFor(order) ==
                          _GlobalMonitoringType.awaitingReceipt,
                    )
                    .toList(growable: false);

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
                              labelText:
                                  'Buscar por folio, solicitante, area, motivo o seguimiento',
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
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Text(
                        'Vista general para Compras y Direccion General. Aqui se concentran las ordenes rechazadas y las ordenes finalizadas que siguen pendientes de confirmacion por el solicitante.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: visibleOrders.isEmpty
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.inbox_outlined, size: 44),
                                const SizedBox(height: 12),
                                const Text('No hay ordenes por monitorear con ese filtro.'),
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
                          : ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                _MonitoringSection(
                                  title: 'Rechazadas',
                                  subtitle:
                                      'Ordenes que requieren accion del solicitante o seguimiento de Compras.',
                                  icon: Icons.assignment_return_outlined,
                                  accentColor: Colors.red.shade700,
                                  backgroundColor: Colors.red.shade50,
                                  count: rejectedOrders.length,
                                  orders: rejectedOrders,
                                ),
                                const SizedBox(height: 16),
                                _MonitoringSection(
                                  title: 'Finalizadas pendientes',
                                  subtitle:
                                      'Ordenes ya finalizadas que siguen esperando confirmacion de recibido por el solicitante.',
                                  icon: Icons.inventory_2_outlined,
                                  accentColor: Colors.teal.shade700,
                                  backgroundColor: Colors.teal.shade50,
                                  count: awaitingReceiptOrders.length,
                                  orders: awaitingReceiptOrders,
                                ),
                                if (showLoadMore) ...[
                                  const SizedBox(height: 16),
                                  Center(
                                    child: OutlinedButton.icon(
                                      onPressed: _loadMore,
                                      icon: const Icon(Icons.expand_more),
                                      label: const Text('Ver mas'),
                                    ),
                                  ),
                                ],
                              ],
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
                  'Error: ${reportError(error, stack, context: 'GlobalActionMonitoringScreen')}',
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

class _MonitoringSection extends StatelessWidget {
  const _MonitoringSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.backgroundColor,
    required this.count,
    required this.orders,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final Color backgroundColor;
  final int count;
  final List<PurchaseOrder> orders;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accentColor.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accentColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: accentColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Chip(
                label: Text('$count'),
                backgroundColor: Colors.white,
                side: BorderSide(color: accentColor.withValues(alpha: 0.2)),
                labelStyle: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (orders.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              'No hay ordenes en este bloque con el filtro actual.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final order in orders) ...[
            _GlobalRejectedOrderCard(order: order),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _GlobalRejectedOrderCard extends ConsumerStatefulWidget {
  const _GlobalRejectedOrderCard({required this.order});

  final PurchaseOrder order;

  @override
  ConsumerState<_GlobalRejectedOrderCard> createState() =>
      _GlobalRejectedOrderCardState();
}

class _GlobalRejectedOrderCardState
    extends ConsumerState<_GlobalRejectedOrderCard> {
  bool _sendingEmail = false;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final pdfRoute = '/orders/${order.id}/pdf';
    final reason = (order.lastReturnReason ?? '').trim();
    final lastReturn = ref.watch(orderEventsProvider(order.id)).maybeWhen(
      data: (events) {
        PurchaseOrderEvent? event;
        for (final candidate in events) {
          if (candidate.type == 'return') {
            event = candidate;
          }
        }
        return event;
      },
      orElse: () => null,
    );
    final monitoringType = _globalMonitoringTypeFor(order);
    final canSendEmail = _canSendActionEmail(
      ref.watch(currentUserProfileProvider).value,
    );
    final statusChipLabel = switch (monitoringType) {
      _GlobalMonitoringType.rejected =>
        'Rechazada por ${_globalRejectedByLabel(lastReturn?.byRole)}',
      _GlobalMonitoringType.awaitingReceipt => 'Finalizada pendiente de recibido',
    };
    final summaryText = switch (monitoringType) {
      _GlobalMonitoringType.rejected =>
        'Motivo: ${reason.isEmpty ? 'Sin comentario' : reason}',
      _GlobalMonitoringType.awaitingReceipt =>
        'La orden ya fue finalizada y el solicitante aun no confirma que recibio su pedido.',
    };
    final durationLabel = switch (monitoringType) {
      _GlobalMonitoringType.rejected =>
        'Tiempo en ${_globalRejectedFromLabel(lastReturn?.fromStatus)}',
      _GlobalMonitoringType.awaitingReceipt => 'Tiempo pendiente de recibido',
    };
    final palette = _monitoringPaletteFor(
      monitoringType,
    );

    return Card(
      color: palette.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  order.id,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: palette.titleColor,
                  ),
                ),
                Chip(
                  label: Text(order.urgency.label),
                  backgroundColor: palette.secondaryChipBackground,
                  side: BorderSide(color: palette.secondaryChipBorder),
                  labelStyle: TextStyle(color: palette.secondaryChipText),
                ),
                Chip(
                  label: Text(statusChipLabel),
                  backgroundColor: palette.statusChipBackground,
                  side: BorderSide(color: palette.statusChipBorder),
                  labelStyle: TextStyle(
                    color: palette.statusChipText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${order.requesterName} | ${order.areaName}',
              style: TextStyle(color: palette.supportingTextColor),
            ),
            const SizedBox(height: 6),
            Text(
              summaryText,
              style: TextStyle(
                color: palette.summaryTextColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (monitoringType == _GlobalMonitoringType.awaitingReceipt &&
                order.completedAt != null) ...[
              const SizedBox(height: 6),
              Text(
                'Finalizada: ${_formatMonitoringStamp(order.completedAt!)}',
                style: TextStyle(color: palette.supportingTextColor),
              ),
            ],
            const SizedBox(height: 6),
            OrderStatusDurationPill(
              order: order,
              label: durationLabel,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => guardedPdfPush(context, pdfRoute),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Ver PDF'),
                ),
                FilledButton.icon(
                  onPressed: !canSendEmail || _sendingEmail
                      ? null
                      : () => _sendEmail(order, monitoringType),
                  icon: _sendingEmail
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.mail_outline),
                  label: Text(
                    canSendEmail ? 'Preparar aviso' : 'Solo Compras puede enviar',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendEmail(
    PurchaseOrder order,
    _GlobalMonitoringType monitoringType,
  ) async {
    final actor = ref.read(currentUserProfileProvider).value;
    final senderEmail = (actor?.contactEmail ?? '').trim();
    if (senderEmail.isEmpty) {
      final shouldOpenProfile = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Correo requerido'),
          content: const Text(
            'Antes de preparar avisos por correo, registra tu correo en Perfil > Correo de contacto.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ir a perfil'),
            ),
          ],
        ),
      );
      if (shouldOpenProfile == true && mounted) {
        await showProfileSheet(context, ref);
      }
      return;
    }

    setState(() => _sendingEmail = true);
    try {
      final users = await ref.read(allUsersProvider.future);
      AppUser? requester;
      for (final user in users) {
        if (user.id == order.requesterId) {
          requester = user;
          break;
        }
      }
      final receiverEmail = (requester?.contactEmail ?? '').trim();
      if (receiverEmail.isEmpty) {
        throw StateError(
          'El solicitante no tiene correo registrado en Perfil > Correo de contacto.',
        );
      }

      final subject = _emailSubject(order, monitoringType);
      final body = _emailBody(
        order: order,
        monitoringType: monitoringType,
        senderEmail: senderEmail,
      );
      final uri = Uri(
        scheme: 'mailto',
        path: receiverEmail,
        queryParameters: <String, String>{
          'subject': subject,
          'body': body,
        },
      );

      final shouldPrepareEmail = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Aviso interno listo'),
          content: Text(
            monitoringType == _GlobalMonitoringType.rejected
                ? 'La orden ${order.id} ya refleja internamente que requiere accion. Si quieres, ahora puedes preparar el correo opcional al solicitante.'
                : 'La orden ${order.id} ya refleja internamente que sigue pendiente de recibido. Si quieres, ahora puedes preparar el correo opcional al solicitante.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Solo en app'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Preparar correo'),
            ),
          ],
        ),
      );
      if (shouldPrepareEmail != true || !mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El aviso queda visible dentro de la app.')),
        );
        return;
      }

      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (!opened) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo abrir la app de correo en este dispositivo.',
            ),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Aviso preparado para $receiverEmail. Verifica que tu app de correo use $senderEmail como remitente.',
          ),
        ),
      );
    } catch (error, stack) {
      if (!mounted) return;
      final message = reportError(
        error,
        stack,
        context: 'GlobalActionMonitoringScreen.sendEmail',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _sendingEmail = false);
    }
  }
}

enum _GlobalMonitoringType { rejected, awaitingReceipt }

class _MonitoringPalette {
  const _MonitoringPalette({
    required this.cardColor,
    required this.borderColor,
    required this.titleColor,
    required this.supportingTextColor,
    required this.summaryTextColor,
    required this.statusChipBackground,
    required this.statusChipBorder,
    required this.statusChipText,
    required this.secondaryChipBackground,
    required this.secondaryChipBorder,
    required this.secondaryChipText,
  });

  final Color cardColor;
  final Color borderColor;
  final Color titleColor;
  final Color supportingTextColor;
  final Color summaryTextColor;
  final Color statusChipBackground;
  final Color statusChipBorder;
  final Color statusChipText;
  final Color secondaryChipBackground;
  final Color secondaryChipBorder;
  final Color secondaryChipText;
}

_MonitoringPalette _monitoringPaletteFor(
  _GlobalMonitoringType type,
) {
  switch (type) {
    case _GlobalMonitoringType.rejected:
      return _MonitoringPalette(
        cardColor: Colors.red.shade50,
        borderColor: Colors.red.shade200,
        titleColor: Colors.red.shade900,
        supportingTextColor: Colors.red.shade900,
        summaryTextColor: Colors.red.shade800,
        statusChipBackground: Colors.red.shade100,
        statusChipBorder: Colors.red.shade300,
        statusChipText: Colors.red.shade900,
        secondaryChipBackground: Colors.white,
        secondaryChipBorder: Colors.red.shade200,
        secondaryChipText: Colors.red.shade800,
      );
    case _GlobalMonitoringType.awaitingReceipt:
      return _MonitoringPalette(
        cardColor: Colors.teal.shade50,
        borderColor: Colors.teal.shade200,
        titleColor: Colors.teal.shade900,
        supportingTextColor: Colors.teal.shade900,
        summaryTextColor: Colors.teal.shade800,
        statusChipBackground: Colors.teal.shade100,
        statusChipBorder: Colors.teal.shade300,
        statusChipText: Colors.teal.shade900,
        secondaryChipBackground: Colors.white,
        secondaryChipBorder: Colors.teal.shade200,
        secondaryChipText: Colors.teal.shade800,
      );
  }
}

_GlobalMonitoringType _globalMonitoringTypeFor(PurchaseOrder order) {
  return order.isAwaitingRequesterReceipt
      ? _GlobalMonitoringType.awaitingReceipt
      : _GlobalMonitoringType.rejected;
}

bool _canSendActionEmail(AppUser? actor) {
  if (actor == null) return false;
  return isAdminRole(actor.role) || isComprasLabel(actor.areaDisplay);
}

String _formatMonitoringStamp(DateTime value) {
  final minutes = value.minute.toString().padLeft(2, '0');
  final hours = value.hour.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day/$month/${value.year} $hours:$minutes';
}

String _emailSubject(
  PurchaseOrder order,
  _GlobalMonitoringType monitoringType,
) {
  return monitoringType == _GlobalMonitoringType.rejected
      ? 'Accion requerida en orden ${order.id}'
      : 'Confirma de recibido tu orden ${order.id}';
}

String _emailBody({
  required PurchaseOrder order,
  required _GlobalMonitoringType monitoringType,
  required String senderEmail,
}) {
  final header = monitoringType == _GlobalMonitoringType.rejected
      ? 'Tu orden requiere accion para continuar el proceso.'
      : 'Tu orden ya fue finalizada. Por favor confirma de recibido cuando te llegue.';
  final detail = monitoringType == _GlobalMonitoringType.rejected
      ? 'Motivo: ${(order.lastReturnReason ?? '').trim().isEmpty ? 'Sin comentario' : order.lastReturnReason!.trim()}'
      : 'Fecha de finalizacion: ${order.completedAt == null ? 'Sin fecha' : _formatMonitoringStamp(order.completedAt!)}';
  return [
    'Hola ${order.requesterName},',
    '',
    header,
    'Orden: ${order.id}',
    'Area: ${order.areaName}',
    detail,
    '',
    'Correo de seguimiento de Compras: $senderEmail',
    'Este aviso se envia solo como seguimiento de texto.',
  ].join('\n');
}

String _globalRejectedByLabel(String? rawRole) {
  final normalized = normalizeAreaLabel((rawRole ?? '').trim());
  if (normalized.isEmpty) return 'Compras';
  if (isComprasLabel(normalized)) return 'Compras';
  if (isDireccionGeneralLabel(normalized)) return 'Direccion General';
  return normalized;
}

String _globalRejectedFromLabel(PurchaseOrderStatus? status) {
  switch (status) {
    case PurchaseOrderStatus.pendingCompras:
      return 'autorizacion de requerimiento';
    case PurchaseOrderStatus.cotizaciones:
      return 'compras';
    case PurchaseOrderStatus.dataComplete:
      return 'proceso de liberacion';
    case PurchaseOrderStatus.authorizedGerencia:
      return 'autorizacion de pago';
    case PurchaseOrderStatus.paymentDone:
      return 'en transito de llegada';
    case PurchaseOrderStatus.contabilidad:
      return 'contabilidad';
    case PurchaseOrderStatus.orderPlaced:
      return 'orden realizada';
    case PurchaseOrderStatus.eta:
      return 'orden finalizada';
    case PurchaseOrderStatus.draft:
    case null:
      return 'correccion';
  }
}
