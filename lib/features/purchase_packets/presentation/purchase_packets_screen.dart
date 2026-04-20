import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sistema_compras/features/orders/presentation/shared/order_status_duration.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sistema_compras/core/access_control.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/application/create_order_controller.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_inline_view.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_view_screen.dart';
import 'package:sistema_compras/features/orders/presentation/preview/pdf_download_helper.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_urgency_controls.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/features/purchase_packets/application/purchase_packet_use_cases.dart';
import 'package:sistema_compras/features/purchase_packets/domain/purchase_packet_domain.dart';

enum PurchasePacketsViewMode { combined, comprasDashboard, direccionGeneral }

class PurchasePacketsScreen extends ConsumerStatefulWidget {
  const PurchasePacketsScreen({
    super.key,
    this.mode = PurchasePacketsViewMode.combined,
  });

  const PurchasePacketsScreen.comprasDashboard({super.key})
      : mode = PurchasePacketsViewMode.comprasDashboard;

  const PurchasePacketsScreen.direccionGeneral({super.key})
      : mode = PurchasePacketsViewMode.direccionGeneral;

  final PurchasePacketsViewMode mode;

  @override
  ConsumerState<PurchasePacketsScreen> createState() => _PurchasePacketsScreenState();
}

class _PurchasePacketsScreenState extends ConsumerState<PurchasePacketsScreen> {
  final TextEditingController _supplierController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _evidenceController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedItemRefIds = <String>{};
  OrderUrgencyFilter _urgencyFilter = OrderUrgencyFilter.all;
  Timer? _searchDebounce;
  String _searchQuery = '';
  DateTimeRange? _createdDateRangeFilter;
  bool _creating = false;

  @override
  void dispose() {
    _supplierController.dispose();
    _amountController.dispose();
    _evidenceController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
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

  void _clearCreatedDateFilter() {
    if (_createdDateRangeFilter == null) return;
    setState(() => _createdDateRangeFilter = null);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProfileProvider).value;
    final allOrdersAsync = ref.watch(allOrdersProvider);
    final canUseModule = switch (widget.mode) {
      PurchasePacketsViewMode.comprasDashboard => hasComprasAccess(user),
      PurchasePacketsViewMode.direccionGeneral => hasDireccionApprovalAccess(user),
      PurchasePacketsViewMode.combined =>
        hasComprasAccess(user) || hasDireccionApprovalAccess(user),
    };
    final readyOrdersAsync = ref.watch(readyOrdersProvider);
    final packetsAsync = ref.watch(packetBundlesProvider);
    final scheme = Theme.of(context).colorScheme;
    final compactAppBar = useCompactOrderModuleAppBar(context);
    final title = switch (widget.mode) {
      PurchasePacketsViewMode.comprasDashboard => 'Compras / Dashboard',
      PurchasePacketsViewMode.direccionGeneral => 'Direccion General',
      PurchasePacketsViewMode.combined => 'Compras y Direccion',
    };
    final dgCounts = _direccionGeneralUrgencyCounts(
      packetsAsync.valueOrNull ?? const <PacketBundle>[],
      allOrdersAsync.valueOrNull ?? const <PurchaseOrder>[],
    );

    return Scaffold(
      appBar: AppBar(
        title: widget.mode == PurchasePacketsViewMode.direccionGeneral && !compactAppBar
            ? OrderModuleAppBarTitle(
                title: title,
                counts: dgCounts,
                filter: _urgencyFilter,
                onSelected: (filter) => setState(() => _urgencyFilter = filter),
              )
            : Text(title),
        bottom: widget.mode == PurchasePacketsViewMode.direccionGeneral && compactAppBar
            ? OrderModuleAppBarBottom(
                counts: dgCounts,
                filter: _urgencyFilter,
                onSelected: (filter) => setState(() => _urgencyFilter = filter),
              )
            : null,
      ),
      body: !canUseModule
          ? Center(
              child: Text(
                'Tu perfil no tiene acceso al modulo.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 1050;
                final readyOrdersPanel = _Panel(
                  title: 'Ordenes listas para agrupar',
                  subtitle: 'Solo usa entidades nuevas o lectura legacy compatible.',
                  expandChild: !isNarrow,
                  child: readyOrdersAsync.when(
                    data: (orders) => _ReadyOrdersList(
                      orders: orders,
                      selectedItemRefIds: _selectedItemRefIds,
                      shrinkWrap: isNarrow,
                      onSelectionChanged: (refId, selected) {
                        setState(() {
                          if (selected) {
                            _selectedItemRefIds.add(refId);
                          } else {
                            _selectedItemRefIds.remove(refId);
                          }
                        });
                      },
                    ),
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (error, stack) => Center(
                      child: Text(reportError(error, stack, context: 'PurchasePacketsScreen.readyOrders')),
                    ),
                  ),
                );
                final createPacketPanel = _Panel(
                  title: 'Crear paquete',
                  subtitle: 'Agrupa por proveedor y persiste separado de la orden.',
                  expandChild: !isNarrow,
                  child: _CreatePacketForm(
                    supplierController: _supplierController,
                    amountController: _amountController,
                    evidenceController: _evidenceController,
                    selectedCount: _selectedItemRefIds.length,
                    creating: _creating,
                    shrinkWrap: isNarrow,
                    onCreate: () => _createPacket(context),
                  ),
                );
                final packetsPanel = _Panel(
                  title: widget.mode == PurchasePacketsViewMode.direccionGeneral
                      ? 'Paquetes por aprobar'
                      : 'Paquetes',
                  subtitle: widget.mode == PurchasePacketsViewMode.direccionGeneral
                      ? 'Revision ejecutiva separada de Compras.'
                      : 'Versionados, con decisiones append-only y telemetria.',
                  expandChild: !isNarrow,
                  child: packetsAsync.when(
                    data: (bundles) {
                      final allOrders = allOrdersAsync.valueOrNull;
                      final baseVisibleBundles = widget.mode ==
                              PurchasePacketsViewMode.direccionGeneral
                          ? bundles
                              .where(
                                _bundleCountsAsPendingDireccion,
                              )
                              .toList(growable: false)
                          : bundles;
                      final visibleBundles = widget.mode ==
                              PurchasePacketsViewMode.direccionGeneral
                          ? _filterDireccionGeneralBundlesByUrgency(
                              baseVisibleBundles,
                              allOrders ?? const <PurchaseOrder>[],
                              _urgencyFilter,
                            ).where(
                              (bundle) => allOrders == null
                                  ? true
                                  : _bundleMatchesOrderFilters(
                                      bundle,
                                      allOrders,
                                      searchQuery: _searchQuery,
                                      createdDateRangeFilter: _createdDateRangeFilter,
                                    ),
                            ).toList(growable: false)
                          : baseVisibleBundles;
                      return _PacketList(
                      bundles: visibleBundles,
                      canSubmit: widget.mode != PurchasePacketsViewMode.direccionGeneral &&
                          hasComprasAccess(user),
                      canApprove: widget.mode != PurchasePacketsViewMode.comprasDashboard &&
                          hasDireccionApprovalAccess(user),
                      shrinkWrap: isNarrow,
                      onSubmit: (bundle) => _submitPacket(context, bundle),
                      onApprove: (bundle) => _approvePacket(context, bundle),
                      onReturn: (bundle) => _returnPacket(context, bundle),
                      onCloseItems: (bundle) => _closeItems(context, bundle),
                      onViewEvidence: (bundle) => _showEvidenceLinks(context, bundle),
                    );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (error, stack) => Center(
                      child: Text(reportError(error, stack, context: 'PurchasePacketsScreen.packets')),
                    ),
                  ),
                );

                if (widget.mode == PurchasePacketsViewMode.direccionGeneral) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _PacketOrderSearchDateToolbar(
                          controller: _searchController,
                          searchQuery: _searchQuery,
                          onChanged: _updateSearch,
                          onClear: _clearSearch,
                          selectedRange: _createdDateRangeFilter,
                          onPickDate: _pickCreatedDateFilter,
                          onClearDate: _clearCreatedDateFilter,
                        ),
                        const SizedBox(height: 16),
                        Expanded(child: packetsPanel),
                      ],
                    ),
                  );
                }

                if (isNarrow) {
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      readyOrdersPanel,
                      const SizedBox(height: 16),
                      createPacketPanel,
                      const SizedBox(height: 16),
                      packetsPanel,
                    ],
                  );
                }

                return Column(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: readyOrdersPanel),
                            const SizedBox(width: 16),
                            Expanded(child: createPacketPanel),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: packetsPanel,
                      ),
                    ),
                  ],
                );
              },
            ),
      backgroundColor: scheme.surfaceContainerLowest,
    );
  }

  Future<void> _createPacket(BuildContext context) async {
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) return;

    final totalAmount = num.tryParse(_amountController.text.trim()) ?? 0;
    setState(() => _creating = true);
    try {
      await ref.read(createPacketFromReadyOrdersProvider).call(
            actor: actor,
            supplierName: _supplierController.text,
            totalAmount: totalAmount,
            evidenceUrls: _evidenceController.text
                .split('\n')
                .map((line) => line.trim())
                .where((line) => line.isNotEmpty)
                .toList(growable: false),
            itemRefIds: _selectedItemRefIds.toList(growable: false),
          );
      if (!mounted) return;
      setState(() {
        _selectedItemRefIds.clear();
        _supplierController.clear();
        _amountController.clear();
        _evidenceController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paquete creado.')),
      );
    } catch (error, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reportError(error, stack, context: 'PurchasePacketsScreen.create'))),
      );
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  Future<void> _submitPacket(BuildContext context, PacketBundle bundle) async {
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) return;
    try {
      await ref.read(submitPacketForExecutiveApprovalProvider).call(
            actor: actor,
            packetId: bundle.packet.id,
            expectedVersion: bundle.packet.version,
          );
      await _advanceLinkedOrders(
        bundle.packet.itemRefs,
        actor: actor,
        nextStatus: PurchaseOrderStatus.approvalQueue,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paquete enviado a aprobacion.')),
      );
    } catch (error, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reportError(error, stack, context: 'PurchasePacketsScreen.submit'))),
      );
    }
  }

  Future<void> _approvePacket(BuildContext context, PacketBundle bundle) async {
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) return;
    final confirmed = await _confirmApproval(context);
    if (!mounted || confirmed != true) return;
    try {
      await ref.read(approvePacketProvider).call(
            actor: actor,
            packetId: bundle.packet.id,
            expectedVersion: bundle.packet.version,
          );
      final bundles = ref.read(packetBundlesProvider).valueOrNull ?? const <PacketBundle>[];
      await _advanceApprovedLinkedOrders(
        bundle,
        allBundles: bundles,
        actor: actor,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paquete aprobado.')),
      );
    } catch (error, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reportError(error, stack, context: 'PurchasePacketsScreen.approve'))),
      );
    }
  }

  Future<void> _returnPacket(BuildContext context, PacketBundle bundle) async {
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) return;
    final reason = await _promptText(context, title: 'Regresar paquete', hint: 'Motivo requerido');
    if (!mounted || reason == null) return;
    try {
      await ref.read(returnPacketForReworkProvider).call(
            actor: actor,
            packetId: bundle.packet.id,
            expectedVersion: bundle.packet.version,
            reason: reason,
          );
      await _returnLinkedOrdersToDashboard(
        bundle.packet.itemRefs,
        actor: actor,
        reason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paquete regresado a retrabajo.')),
      );
    } catch (error, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reportError(error, stack, context: 'PurchasePacketsScreen.return'))),
      );
    }
  }

  Future<void> _closeItems(BuildContext context, PacketBundle bundle) async {
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) return;
    final result = await _promptItemClosure(context, bundle.packet.itemRefs);
    if (!mounted || result == null) return;
    try {
      await ref.read(closePacketItemsAsUnpurchasableProvider).call(
            actor: actor,
            packetId: bundle.packet.id,
            expectedVersion: bundle.packet.version,
            itemRefIds: result.itemRefIds,
            reason: result.reason,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Items cerrados como no comprables.')),
      );
    } catch (error, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reportError(error, stack, context: 'PurchasePacketsScreen.closeItems'))),
      );
    }
  }

  Future<void> _advanceLinkedOrders(
    List<PacketItemRef> itemRefs, {
    required AppUser actor,
    required PurchaseOrderStatus nextStatus,
  }) async {
    final repository = ref.read(purchaseOrderRepositoryProvider);
    final orderIds = itemRefs.map((item) => item.orderId).toSet();
    for (final orderId in orderIds) {
      final order = await repository.fetchOrderById(orderId);
      if (order == null || order.status == nextStatus) continue;
      await repository.advanceOrderStage(
        order: order,
        nextStatus: nextStatus,
        actor: actor,
      );
    }
    refreshOrderModuleTransitionData(ref, orderIds: orderIds);
  }


  Future<void> _returnLinkedOrdersToDashboard(
    List<PacketItemRef> itemRefs, {
    required AppUser actor,
    required String reason,
  }) async {
    final repository = ref.read(purchaseOrderRepositoryProvider);
    final orderIds = itemRefs.map((item) => item.orderId).toSet();
    for (final orderId in orderIds) {
      final order = await repository.fetchOrderById(orderId);
      if (order == null) continue;
      await repository.advanceOrderStage(
        order: order,
        nextStatus: PurchaseOrderStatus.sourcing,
        actor: actor,
        comment: reason,
      );
    }
    refreshOrderModuleTransitionData(ref, orderIds: orderIds);
  }

  Future<void> _advanceApprovedLinkedOrders(
    PacketBundle approvedBundle, {
    required List<PacketBundle> allBundles,
    required AppUser actor,
  }) async {
    final repository = ref.read(purchaseOrderRepositoryProvider);
    final orderIds = approvedBundle.packet.itemRefs.map((item) => item.orderId).toSet();
    for (final orderId in orderIds) {
      final hasOtherApprovalQueue = allBundles.any(
        (bundle) =>
            bundle.packet.id != approvedBundle.packet.id &&
            bundle.packet.status == PurchasePacketStatus.approvalQueue &&
            bundle.packet.itemRefs.any((item) => item.orderId == orderId),
      );
      if (hasOtherApprovalQueue) continue;
      final order = await repository.fetchOrderById(orderId);
      if (order == null || order.status == PurchaseOrderStatus.paymentDone) {
        continue;
      }
      await repository.advanceOrderStage(
        order: order,
        nextStatus: PurchaseOrderStatus.paymentDone,
        actor: actor,
        comment: 'Todos los paquetes del proveedor fueron aprobados por Direccion General.',
      );
    }
    refreshOrderModuleTransitionData(ref, orderIds: orderIds);
  }

  Future<void> _showEvidenceLinks(
    BuildContext context,
    PacketBundle bundle,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Links de cotizacion - ${bundle.packet.supplierName}'),
          content: SizedBox(
            width: 560,
            child: bundle.packet.evidenceUrls.isEmpty
                ? const Text('Este paquete no tiene links de cotizacion.')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final url in bundle.packet.evidenceUrls)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            onTap: () => _openExternalLink(dialogContext, url),
                            child: Text(
                              url,
                              style: TextStyle(
                                color: Theme.of(dialogContext).colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _confirmApproval(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirmar aprobacion'),
          content: const Text(
            'Al aprobar este PDF de paquete por proveedor se dara por hecho que el pago se realizo o esta por realizarse. ¿Deseas continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: _positiveFilledButtonStyle(context),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Aprobar'),
            ),
          ],
        );
      },
    );
  }
}

Future<void> _openExternalLink(BuildContext context, String raw) async {
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.isAbsolute) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('El link no es valido.')),
    );
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched && messenger.mounted) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No se pudo abrir el link.')),
    );
  }
}

OrderUrgencyCounts _direccionGeneralUrgencyCounts(
  List<PacketBundle> bundles,
  List<PurchaseOrder> orders,
) {
  final relevantOrders = _direccionGeneralOrdersForBundles(bundles, orders);
  return OrderUrgencyCounts.fromOrders(relevantOrders);
}

List<PurchaseOrder> _direccionGeneralOrdersForBundles(
  List<PacketBundle> bundles,
  List<PurchaseOrder> orders,
) {
  final orderIds = bundles
      .where(_bundleCountsAsPendingDireccion)
      .expand((bundle) => bundle.packet.itemRefs)
      .map((item) => item.orderId)
      .toSet();
  return orders.where((order) => orderIds.contains(order.id)).toList(growable: false);
}

bool _bundleCountsAsPendingDireccion(PacketBundle bundle) {
  if (bundle.packet.status == PurchasePacketStatus.approvalQueue) {
    return true;
  }
  if (bundle.packet.status != PurchasePacketStatus.draft ||
      !bundle.packet.isSubmitted) {
    return false;
  }
  if (bundle.decisions.isEmpty) return true;
  final sorted = [...bundle.decisions]
    ..sort((left, right) => right.timestamp.compareTo(left.timestamp));
  return sorted.first.action != PacketDecisionAction.returnForRework;
}

bool _bundleMatchesOrderFilters(
  PacketBundle bundle,
  List<PurchaseOrder> orders, {
  required String searchQuery,
  required DateTimeRange? createdDateRangeFilter,
}) {
  final orderIds = bundle.packet.itemRefs.map((item) => item.orderId).toSet();
  return orders.any(
    (order) =>
        orderIds.contains(order.id) &&
        matchesOrderCreatedDateRange(order, createdDateRangeFilter) &&
        orderMatchesSearch(order, searchQuery, includeDates: false),
  );
}

class _PacketOrderSearchDateToolbar extends StatelessWidget {
  const _PacketOrderSearchDateToolbar({
    required this.controller,
    required this.searchQuery,
    required this.onChanged,
    required this.onClear,
    required this.selectedRange,
    required this.onPickDate,
    required this.onClearDate,
  });

  final TextEditingController controller;
  final String searchQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final DateTimeRange? selectedRange;
  final Future<void> Function() onPickDate;
  final VoidCallback onClearDate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 720;
        final searchField = TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Buscar por folio, solicitante o area',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: searchQuery.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: onClear,
                  ),
          ),
          onChanged: onChanged,
        );
        final dateFilter = OrderDateRangeFilterButton(
          selectedRange: selectedRange,
          onPickDate: onPickDate,
          onClearDate: onClearDate,
        );
        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: dateFilter),
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
    );
  }
}

ButtonStyle _positiveFilledButtonStyle(BuildContext context) {
  return FilledButton.styleFrom(
    backgroundColor: Colors.green.shade700,
    foregroundColor: Colors.white,
    disabledBackgroundColor: Theme.of(context).disabledColor.withOpacity(0.12),
    disabledForegroundColor: Theme.of(context).disabledColor,
  );
}

ButtonStyle _negativeFilledButtonStyle(BuildContext context) {
  return FilledButton.styleFrom(
    backgroundColor: Colors.red.shade700,
    foregroundColor: Colors.white,
    disabledBackgroundColor: Theme.of(context).disabledColor.withOpacity(0.12),
    disabledForegroundColor: Theme.of(context).disabledColor,
  );
}

ButtonStyle _negativeOutlinedButtonStyle(BuildContext context) {
  return OutlinedButton.styleFrom(
    foregroundColor: Colors.red.shade700,
    side: BorderSide(color: Colors.red.shade700),
  );
}

List<PacketBundle> _filterDireccionGeneralBundlesByUrgency(
  List<PacketBundle> bundles,
  List<PurchaseOrder> orders,
  OrderUrgencyFilter filter,
) {
  if (filter == OrderUrgencyFilter.all) return bundles;
  final ordersById = <String, PurchaseOrder>{
    for (final order in orders) order.id: order,
  };
  return bundles.where((bundle) {
    for (final item in bundle.packet.itemRefs) {
      final order = ordersById[item.orderId];
      if (order != null && matchesOrderUrgencyFilter(order, filter)) {
        return true;
      }
    }
    return false;
  }).toList(growable: false);
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.expandChild = true,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool expandChild;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          if (expandChild) Expanded(child: child) else child,
        ],
      ),
    );
  }
}

class _ReadyOrdersList extends StatelessWidget {
  const _ReadyOrdersList({
    required this.orders,
    required this.selectedItemRefIds,
    required this.onSelectionChanged,
    this.shrinkWrap = false,
  });

  final List<RequestOrder> orders;
  final Set<String> selectedItemRefIds;
  final void Function(String refId, bool selected) onSelectionChanged;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const Center(
        child: Text('No hay ordenes nuevas listas para agrupar.'),
      );
    }
    return ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final order = orders[index];
        return ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('${order.id} - ${order.requesterName}'),
          subtitle: Text('${order.areaName} | ${order.source}'),
          children: [
            for (final item in order.items)
              CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: selectedItemRefIds.contains(buildPacketItemRefId(order.id, item.id)),
                onChanged: item.isClosed
                    ? null
                    : (selected) {
                        onSelectionChanged(
                          buildPacketItemRefId(order.id, item.id),
                          selected ?? false,
                        );
                      },
                title: Text('${item.partNumber} · ${item.description}'),
                subtitle: Text(
                  'Item ${item.id} | ${item.quantity} ${item.unit} | Prov: ${item.supplierName ?? 'sin definir'} | Monto: ${item.estimatedAmount ?? 0}',
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CreatePacketForm extends StatelessWidget {
  const _CreatePacketForm({
    required this.supplierController,
    required this.amountController,
    required this.evidenceController,
    required this.selectedCount,
    required this.creating,
    this.shrinkWrap = false,
    required this.onCreate,
  });

  final TextEditingController supplierController;
  final TextEditingController amountController;
  final TextEditingController evidenceController;
  final int selectedCount;
  final bool creating;
  final bool shrinkWrap;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final children = [
      TextField(
        controller: supplierController,
        decoration: const InputDecoration(
          labelText: 'Proveedor',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: amountController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Monto total',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: evidenceController,
        minLines: 3,
        maxLines: 5,
        decoration: const InputDecoration(
          labelText: 'Evidencia (una URL por linea)',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      Text('Items seleccionados: $selectedCount'),
      const SizedBox(height: 12),
      FilledButton.icon(
        style: _positiveFilledButtonStyle(context),
        onPressed: creating || selectedCount == 0 ? null : onCreate,
        icon: creating
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.inventory_2_outlined),
        label: const Text('Crear paquete'),
      ),
    ];
    if (shrinkWrap) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }
    return ListView(
      children: [
        ...children,
      ],
    );
  }
}

class _DireccionGeneralPacketPdfScreen extends ConsumerWidget {
  const _DireccionGeneralPacketPdfScreen({
    required this.bundle,
  });

  final PacketBundle bundle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(currentBrandingProvider);
    final issuedAt = bundle.packet.submittedAt ??
        bundle.packet.updatedAt ??
        bundle.packet.createdAt ??
        DateTime.now();
    final batch = _packetBatchFromBundle(bundle);
    final data = _buildPacketPdfData(
      branding: branding,
      bundle: bundle,
      issuedAt: issuedAt,
      batch: batch,
    );
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text('PDF de paquete por proveedor - ${bundle.packet.folio ?? bundle.packet.supplierName}'),
        actions: [
          IconButton(
            tooltip: 'Descargar PDF',
            onPressed: () async {
              final bytes = await _buildPacketPdfDocument(
                branding: branding,
                bundle: bundle,
                issuedAt: issuedAt,
                batch: batch,
              );
              if (!context.mounted) return;
              await savePdfBytes(
                context,
                bytes: bytes,
                suggestedName:
                    'paquete_por_proveedor_${bundle.packet.folio ?? bundle.packet.id}.pdf',
              );
            },
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          children: [
            Expanded(
              child: OrderPdfInlineView(
                data: data,
                pdfBuilder: (
                  _, {
                  bool useIsolate = false,
                }) =>
                    _buildPacketPdfDocument(
                  branding: branding,
                  bundle: bundle,
                  issuedAt: issuedAt,
                  batch: batch,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PacketList extends StatelessWidget {
  const _PacketList({
    required this.bundles,
    required this.canSubmit,
    required this.canApprove,
    this.shrinkWrap = false,
    required this.onSubmit,
    required this.onApprove,
    required this.onReturn,
    required this.onCloseItems,
    required this.onViewEvidence,
  });

  final List<PacketBundle> bundles;
  final bool canSubmit;
  final bool canApprove;
  final bool shrinkWrap;
  final Future<void> Function(PacketBundle bundle) onSubmit;
  final Future<void> Function(PacketBundle bundle) onApprove;
  final Future<void> Function(PacketBundle bundle) onReturn;
  final Future<void> Function(PacketBundle bundle) onCloseItems;
  final Future<void> Function(PacketBundle bundle) onViewEvidence;

  @override
  Widget build(BuildContext context) {
    if (bundles.isEmpty) {
      return const Center(
        child: Text('Aun no hay paquetes creados.'),
      );
    }
    return ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      itemCount: bundles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final bundle = bundles[index];
        final packet = bundle.packet;
        final orderIds = packet.itemRefs
            .map((item) => item.orderId)
            .toSet()
            .toList(growable: false)
          ..sort();
        final isDireccionCard = canApprove && !canSubmit;
        final direccionGeneralDuration = packet.submittedAt == null
            ? Duration.zero
            : DateTime.now().difference(packet.submittedAt!);
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${packet.folio?.trim().isNotEmpty == true ? packet.folio!.trim() : packet.id} · ${packet.supplierName}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (!isDireccionCard) Chip(label: Text(packet.status.storageKey)),
                  ],
                ),
                const SizedBox(height: 8),
                if (!isDireccionCard)
                  Text('Monto ${packet.totalAmount} | Items ${packet.itemRefs.length}'),
                if (isDireccionCard) ...[
                  Text(
                    'TOTAL A PAGAR',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    packet.totalAmount.toString(),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 12),
                  StatusDurationPill(
                    text:
                        'Tiempo en Direccion General: ${formatDurationLabel(direccionGeneralDuration)}',
                  ),
                ],
                if (!isDireccionCard && bundle.decisions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Ultima decision: ${bundle.decisions.first.action.storageKey} · ${bundle.decisions.first.actorName}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Ordenes involucradas',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final orderId in orderIds) ...[
                        OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => OrderPdfViewScreen(orderId: orderId),
                              ),
                            );
                          },
                          child: Text(orderId),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (isDireccionCard)
                      FilledButton.tonal(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              fullscreenDialog: true,
                              builder: (_) => _DireccionGeneralPacketPdfScreen(
                                bundle: bundle,
                              ),
                            ),
                          );
                        },
                        child: const Text('Ver PDF'),
                      ),
                    if (isDireccionCard)
                      OutlinedButton(
                        style: _negativeOutlinedButtonStyle(context),
                        onPressed: () => unawaited(onReturn(bundle)),
                        child: const Text('Regresar'),
                      ),
                    if (isDireccionCard)
                      FilledButton(
                        style: _positiveFilledButtonStyle(context),
                        onPressed: () => unawaited(onApprove(bundle)),
                        child: const Text('Aprobar'),
                      ),
                    if (canSubmit && packet.status == PurchasePacketStatus.draft)
                      OutlinedButton(
                        onPressed: () => unawaited(onSubmit(bundle)),
                        child: const Text('Enviar a aprobacion'),
                      ),
                    if (!isDireccionCard &&
                        canApprove &&
                        packet.status == PurchasePacketStatus.approvalQueue)
                      FilledButton(
                        style: _positiveFilledButtonStyle(context),
                        onPressed: () => unawaited(onApprove(bundle)),
                        child: const Text('Aprobar'),
                      ),
                    if (!isDireccionCard &&
                        canApprove &&
                        packet.status == PurchasePacketStatus.approvalQueue)
                      OutlinedButton(
                        style: _negativeOutlinedButtonStyle(context),
                        onPressed: () => unawaited(onReturn(bundle)),
                        child: const Text('Regresar'),
                      ),
                    if (!isDireccionCard &&
                        canApprove &&
                        packet.status == PurchasePacketStatus.approvalQueue)
                      OutlinedButton(
                        onPressed: () => unawaited(onCloseItems(bundle)),
                        child: const Text('Cerrar no comprables'),
                      ),
                    if (packet.evidenceUrls.isNotEmpty)
                      OutlinedButton(
                        onPressed: () => unawaited(onViewEvidence(bundle)),
                        child: const Text('Ver links'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<String?> _promptText(
  BuildContext context, {
  required String title,
  required String hint,
}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Aceptar'),
          ),
        ],
      );
    },
  );
  controller.dispose();
  return result;
}

_PacketPdfBatch _packetBatchFromBundle(PacketBundle bundle) {
  final rows = <_PacketPdfItem>[];
  for (var index = 0; index < bundle.packet.itemRefs.length; index++) {
    final item = bundle.packet.itemRefs[index];
    rows.add(
      _PacketPdfItem(
        orderId: item.orderId,
        lineNumber: item.lineNumber > 0 ? item.lineNumber : index + 1,
        description: item.description,
        quantity: item.quantity,
        unit: item.unit,
        amount: item.amount ?? 0,
      ),
    );
  }
  return _PacketPdfBatch(
    supplier: bundle.packet.supplierName,
    items: rows,
  );
}

OrderPdfData _buildPacketPdfData({
  required CompanyBranding branding,
  required PacketBundle bundle,
  required DateTime issuedAt,
  required _PacketPdfBatch batch,
}) {
  return OrderPdfData(
    branding: branding,
    requesterName: 'Direccion General',
    requesterArea: 'Direccion General',
    areaName: 'Direccion General',
    urgency: PurchaseOrderUrgency.normal,
    items: batch.items
        .map(
          (item) => OrderItemDraft(
            line: item.lineNumber,
            pieces: 1,
            partNumber: '',
            description: item.description,
            quantity: item.quantity,
            unit: item.unit,
            supplier: batch.supplier,
            budget: item.amount,
          ),
        )
        .toList(growable: false),
    createdAt: issuedAt,
    observations: 'Resumen de paquete por proveedor.',
    folio: bundle.packet.folio,
    supplier: batch.supplier,
    budget: batch.totalAmount,
    supplierBudgets: <String, num>{batch.supplier: batch.totalAmount},
    cacheSalt: 'direccion:${bundle.packet.id}:${bundle.packet.version}:${bundle.packet.folio ?? ''}',
  );
}

Future<Uint8List> _buildPacketPdfDocument({
  required CompanyBranding branding,
  required PacketBundle bundle,
  required DateTime issuedAt,
  required _PacketPdfBatch batch,
}) async {
  final logo = await _loadPacketDashboardLogo(branding);
  final doc = pw.Document();
  final titleBarColor = PdfColor.fromInt(branding.pdfTitleBarColor.toARGB32());
  final accentColor = PdfColor.fromInt(branding.pdfAccentColor.toARGB32());
  final titleTextColor = branding.pdfTitleBarColor.computeLuminance() < 0.45
      ? PdfColors.white
      : PdfColors.black;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(20),
      build: (context) {
        return [
          pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 0.8, color: PdfColors.grey700),
            ),
            padding: const pw.EdgeInsets.all(8),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 110,
                  height: 50,
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Image(logo, height: 44, fit: pw.BoxFit.contain),
                ),
                pw.Expanded(
                  child: pw.Container(
                    height: 50,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(width: 0.8, color: PdfColors.grey700),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        pw.Container(
                          color: titleBarColor,
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: pw.Text(
                            'COTIZACION GENERAL POR PROVEEDOR',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              color: titleTextColor,
                            ),
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Center(
                            child: pw.Column(
                              mainAxisAlignment: pw.MainAxisAlignment.center,
                              children: [
                                pw.Text(
                                  branding.pdfHeaderLine1,
                                  style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                                pw.Text(
                                  branding.pdfHeaderLine2,
                                  style: const pw.TextStyle(fontSize: 8),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.Container(
                  width: 118,
                  height: 50,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(width: 0.8, color: PdfColors.grey700),
                  ),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text(
                        'FOLIO',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        bundle.packet.folio ?? bundle.packet.id,
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(top: 8),
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 0.8, color: PdfColors.grey700),
              color: PdfColor.fromHex('#F7F9FC'),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'Fecha y hora de emision',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Text(
                  issuedAt.toLocal().toFullDateTime(),
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
          pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(top: 10),
            padding: const pw.EdgeInsets.all(18),
            decoration: pw.BoxDecoration(
              color: accentColor,
              border: pw.Border.all(width: 1.0, color: PdfColors.grey700),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'TOTAL A PAGAR',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  batch.totalAmount.toString(),
                  style: pw.TextStyle(
                    fontSize: 30,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          _packetPdfSectionTitle('DATOS GENERALES', titleBarColor, titleTextColor),
          pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 0.8, color: PdfColors.grey700),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(child: _packetPdfField('PROVEEDOR', batch.supplier)),
                pw.Expanded(
                  child: _packetPdfField(
                    'ORDENES INVOLUCRADAS',
                    batch.orderIds.join(', '),
                  ),
                ),
                pw.SizedBox(
                  width: 110,
                  child: _packetPdfField(
                    'ITEMS',
                    '${batch.items.length}',
                    showRightBorder: false,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          _packetPdfSectionTitle('DETALLE DE ARTICULOS', titleBarColor, titleTextColor),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.8),
            columnWidths: const <int, pw.TableColumnWidth>{
              0: pw.FixedColumnWidth(88),
              1: pw.FlexColumnWidth(4.4),
              2: pw.FixedColumnWidth(70),
              3: pw.FixedColumnWidth(64),
              4: pw.FixedColumnWidth(96),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: titleBarColor),
                children: [
                  _packetPdfCell('Orden / Item', isHeader: true, color: titleTextColor),
                  _packetPdfCell('Descripcion', isHeader: true, color: titleTextColor),
                  _packetPdfCell('Cantidad', isHeader: true, color: titleTextColor),
                  _packetPdfCell('Unidad', isHeader: true, color: titleTextColor),
                  _packetPdfCell('Monto', isHeader: true, color: titleTextColor),
                ],
              ),
              for (var index = 0; index < batch.items.length; index++)
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: index.isEven ? PdfColors.white : PdfColor.fromHex('#F4F7FB'),
                  ),
                  children: [
                    _packetPdfCell(
                      '${batch.items[index].orderId}\n#${batch.items[index].lineNumber}',
                    ),
                    _packetPdfCell(batch.items[index].description),
                    _packetPdfCell('${batch.items[index].quantity}'),
                    _packetPdfCell(batch.items[index].unit),
                    _packetPdfCell(batch.items[index].amount.toString()),
                  ],
                ),
            ],
          ),
        ];
      },
    ),
  );
  return doc.save();
}

Future<pw.MemoryImage> _loadPacketDashboardLogo(CompanyBranding branding) async {
  final bytes = await rootBundle.load(branding.logoAsset);
  return pw.MemoryImage(bytes.buffer.asUint8List());
}

class _PacketPdfItem {
  const _PacketPdfItem({
    required this.orderId,
    required this.lineNumber,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.amount,
  });

  final String orderId;
  final int lineNumber;
  final String description;
  final num quantity;
  final String unit;
  final num amount;
}

class _PacketPdfBatch {
  const _PacketPdfBatch({
    required this.supplier,
    required this.items,
  });

  final String supplier;
  final List<_PacketPdfItem> items;

  num get totalAmount => items.fold<num>(0, (sum, item) => sum + item.amount);
  List<String> get orderIds => items.map((item) => item.orderId).toSet().toList(growable: false)
    ..sort();
}

pw.Widget _packetPdfSectionTitle(
  String text,
  PdfColor background,
  PdfColor foreground,
) {
  return pw.Container(
    width: double.infinity,
    color: background,
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 10,
        fontWeight: pw.FontWeight.bold,
        color: foreground,
      ),
    ),
  );
}

pw.Widget _packetPdfField(
  String label,
  String value, {
  bool showRightBorder = true,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border(
        right: showRightBorder
            ? const pw.BorderSide(width: 0.8, color: PdfColors.grey700)
            : pw.BorderSide.none,
      ),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: const pw.TextStyle(fontSize: 10),
        ),
      ],
    ),
  );
}

pw.Widget _packetPdfCell(
  String text, {
  bool isHeader = false,
  PdfColor? color,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 8),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: isHeader ? 10 : 9,
        fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color,
      ),
    ),
  );
}

class _ClosureDialogResult {
  const _ClosureDialogResult({
    required this.itemRefIds,
    required this.reason,
  });

  final List<String> itemRefIds;
  final String reason;
}

Future<_ClosureDialogResult?> _promptItemClosure(
  BuildContext context,
  List<PacketItemRef> itemRefs,
) async {
  final selected = <String>{};
  final controller = TextEditingController();
  final result = await showDialog<_ClosureDialogResult>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Cerrar items como no comprables'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final item in itemRefs)
                      CheckboxListTile(
                        value: selected.contains(item.id),
                        onChanged: item.closedAsUnpurchasable
                            ? null
                            : (value) {
                                setState(() {
                                  if (value ?? false) {
                                    selected.add(item.id);
                                  } else {
                                    selected.remove(item.id);
                                  }
                                });
                              },
                        title: Text(item.description),
                        subtitle: Text('${item.orderId} / ${item.itemId}'),
                      ),
                    TextField(
                      controller: controller,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Motivo',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: _negativeFilledButtonStyle(context),
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(
                          _ClosureDialogResult(
                            itemRefIds: selected.toList(growable: false),
                            reason: controller.text.trim(),
                          ),
                        ),
                child: const Text('Cerrar items'),
              ),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
  return result;
}
