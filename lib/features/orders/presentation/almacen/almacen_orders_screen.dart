import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/session_drafts.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_card_pills.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_pdf_preload_gate.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_status_duration.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_summary_lines.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

class AlmacenOrdersScreen extends ConsumerStatefulWidget {
  const AlmacenOrdersScreen({super.key});

  @override
  ConsumerState<AlmacenOrdersScreen> createState() =>
      _AlmacenOrdersScreenState();
}

class _AlmacenOrdersScreenState extends ConsumerState<AlmacenOrdersScreen> {
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
    final ordersAsync = ref.watch(almacenOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Almacen'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              guardedGo(context, '/home');
            }
          },
        ),
      ),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('No hay ordenes pendientes.'));
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
                          const Text('No hay ordenes con ese filtro.'),
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
                          return _AlmacenOrderCard(
                            order: order,
                            onReview: () =>
                                guardedPdfPush(context, '/orders/${order.id}/pdf'),
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
            'Error: ${reportError(error, stack, context: 'AlmacenOrdersScreen')}',
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

class _AlmacenOrderCard extends StatelessWidget {
  const _AlmacenOrderCard({required this.order, required this.onReview});

  final PurchaseOrder order;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final createdLabel = order.createdAt?.toFullDateTime() ?? 'Pendiente';
    final hasFactura = _facturaLinks(order).isNotEmpty;
    final hasReceived = order.items.any(
      (item) => item.receivedQuantity != null,
    );
    final contabilidadDuration = _contabilidadDuration(order);

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
                if (hasFactura)
                  OrderTagPill(
                    label: 'Factura lista',
                    backgroundColor: Colors.green.shade100,
                    borderColor: Colors.green.shade400,
                    textColor: Colors.green.shade800,
                  ),
                if (hasReceived)
                  OrderTagPill(
                    label: 'Recepcion iniciada',
                    backgroundColor: Colors.blue.shade100,
                    borderColor: Colors.blue.shade400,
                    textColor: Colors.blue.shade800,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Solicitante: ${order.requesterName}'),
            Text('Area: ${order.areaName}'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text('Creada: $createdLabel')),
                if (contabilidadDuration == null)
                  const StatusDurationPill(
                    text: 'Tiempo en Contabilidad: sin registro',
                  )
                else
                  OrderStatusDurationPill(
                    order: order,
                    label: 'Tiempo en Contabilidad',
                    durationOverride: contabilidadDuration,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _OrderCardSummary(order: order),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onReview,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Ver PDF'),
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
    return OrderSummaryLines(order: order, emptyLabel: '');
  }
}

class AlmacenOrderReviewScreen extends ConsumerStatefulWidget {
  const AlmacenOrderReviewScreen({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<AlmacenOrderReviewScreen> createState() =>
      _AlmacenOrderReviewScreenState();
}

class _AlmacenOrderReviewScreenState
    extends ConsumerState<AlmacenOrderReviewScreen> {
  final _generalCommentController = TextEditingController();
  final Map<int, String> _qtyErrors = {};
  final List<_ReceivedItemDraft> _drafts = [];
  String? _seededOrderId;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _generalCommentController.addListener(() => _saveDraft(widget.orderId));
  }

  @override
  void dispose() {
    _generalCommentController.dispose();
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdStreamProvider(widget.orderId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recepcion en almacen'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              guardedGo(context, '/orders/almacen');
            }
          },
        ),
      ),
      body: orderAsync.when(
        data: (order) {
          if (order == null) {
            return const AppSplash();
          }

          _ensureDrafts(order);

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  children: [
                    _FacturaLinksSection(order: order),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _generalCommentController,
                      decoration: const InputDecoration(
                        labelText: 'Nota de almacen (opcional)',
                      ),
                      minLines: 1,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Recepcion por articulo',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _drafts.length; i++) ...[
                      _ReceivedItemCard(
                        draft: _drafts[i],
                        errorText: _qtyErrors[i],
                        onQuantityChanged: () {
                          setState(() => _qtyErrors.remove(i));
                        },
                      ),
                      if (i != _drafts.length - 1) const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => _handleSubmit(order),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: AppSplash(compact: true, size: 20),
                          )
                        : const Text('Finalizar y cerrar orden'),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            'Error: ${reportError(error, stack, context: 'AlmacenOrderReview')}',
          ),
        ),
      ),
    );
  }

  void _ensureDrafts(PurchaseOrder order) {
    if (_seededOrderId == order.id && _drafts.length == order.items.length) {
      return;
    }

    for (final draft in _drafts) {
      draft.dispose();
    }
    _drafts
      ..clear()
      ..addAll(order.items.map(_ReceivedItemDraft.fromItem));

    final cachedDraft = SessionDraftStore.almacen(order.id);
    if (cachedDraft != null) {
      _generalCommentController.text = cachedDraft.comment;
      for (final draft in _drafts) {
        final line = draft.item.line;
        final cachedQty = cachedDraft.qtyByLine[line];
        if (cachedQty != null) {
          draft.qtyController.text = cachedQty;
        }
      }
    } else {
      _generalCommentController.text = (order.almacenComment ?? '').trim();
    }

    _qtyErrors.clear();
    _seededOrderId = order.id;
    _attachDraftListeners(order.id);
  }

  void _attachDraftListeners(String orderId) {
    for (final draft in _drafts) {
      draft.qtyController.addListener(() => _saveDraft(orderId));
    }
  }

  void _saveDraft(String orderId) {
    final qtyByLine = <int, String>{};

    for (final draft in _drafts) {
      qtyByLine[draft.item.line] = draft.qtyController.text;
    }

    SessionDraftStore.saveAlmacen(
      orderId,
      AlmacenDraft(
        comment: _generalCommentController.text,
        qtyByLine: qtyByLine,
        commentByLine: const {},
      ),
    );
  }

  Future<void> _handleSubmit(PurchaseOrder order) async {
    final nextErrors = <int, String>{};
    final updatedItems = <PurchaseOrderItem>[];

    for (var i = 0; i < _drafts.length; i++) {
      final draft = _drafts[i];
      final raw = draft.qtyController.text.trim();

      if (raw.isEmpty) {
        nextErrors[i] = 'Captura la cantidad recibida';
        continue;
      }

      final received = num.tryParse(_normalizeNumber(raw));

      if (received == null || received < 0) {
        nextErrors[i] = 'Cantidad no valida';
        continue;
      }

      updatedItems.add(
        draft.item.copyWith(
          receivedQuantity: received,
          clearReceivedQuantity: false,
          clearReceivedComment: true,
        ),
      );
    }

    if (nextErrors.isNotEmpty) {
      setState(
        () => _qtyErrors
          ..clear()
          ..addAll(nextErrors),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Corrige las cantidades en rojo.')),
      );
      return;
    }

    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Perfil no disponible.')));
      return;
    }

    final diffs = _warehouseDiffs(updatedItems);
    final confirmed = diffs.isNotEmpty
        ? await _confirmDifferenceSubmission(
            order,
            diffs,
            warehouseName: actor.name,
            warehouseArea: actor.areaDisplay,
          )
        : await _confirmWarehouseFinalize(
            warehouseName: actor.name,
            warehouseArea: actor.areaDisplay,
          );
    if (!confirmed) return;

    setState(() => _isSubmitting = true);

    try {
      final repo = ref.read(purchaseOrderRepositoryProvider);
      await repo.finalizeFromAlmacen(
        order: order,
        items: updatedItems,
        actor: actor,
        comment: _generalCommentController.text.trim(),
      );

      if (!mounted) return;

      SessionDraftStore.clearAlmacen(order.id);
      guardedPdfGo(context, '/orders/${order.id}/pdf');
    } catch (error, stack) {
      if (!mounted) return;
      final message = reportError(
        error,
        stack,
        context: 'AlmacenOrderReview.submit',
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<bool> _confirmDifferenceSubmission(
    PurchaseOrder order,
    List<_WarehouseDiff> diffs, {
    required String warehouseName,
    required String warehouseArea,
  }) async {
    final displayName = warehouseName.trim().isEmpty
        ? 'Tu nombre'
        : warehouseName.trim();
    final displayArea = warehouseArea.trim().isEmpty
        ? 'Tu area'
        : warehouseArea.trim();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar descuadre'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'La orden ${order.id} tiene descuadre entre lo solicitado en el PDF y lo recibido en almacen. '
                    'Si confirmas, el PDF final marcara el descuadre y la orden se enviara a ordenes finalizadas.\n\n'
                    'En el PDF, la casilla RECIBIO mostrara "$displayName" y el area "$displayArea".',
                  ),
                  const SizedBox(height: 12),
                  for (final diff in diffs) ...[
                    Text(
                      diff.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Solicitado: ${diff.requestedLabel} | Recibido: ${diff.receivedLabel} | Diferencia: ${diff.deltaLabel}',
                    ),
                    if (diff != diffs.last) const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirmar y finalizar'),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  Future<bool> _confirmWarehouseFinalize({
    required String warehouseName,
    required String warehouseArea,
  }) async {
    final displayName = warehouseName.trim().isEmpty
        ? 'Tu nombre'
        : warehouseName.trim();
    final displayArea = warehouseArea.trim().isEmpty
        ? 'Tu area'
        : warehouseArea.trim();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finalizar recepcion'),
        content: Text(
          'En el PDF, la casilla RECIBIO mostrara "$displayName" y el area "$displayArea".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirmar y finalizar'),
          ),
        ],
      ),
    );

    return result == true;
  }
}

class _FacturaLinksSection extends StatelessWidget {
  const _FacturaLinksSection({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    final links = _facturaLinks(order);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Factura', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (links.isEmpty)
              const Text('Sin links de factura.')
            else
              for (final link in links) ...[
                Text(link, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _openLink(context, link),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Abrir link'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }

  Future<void> _openLink(BuildContext context, String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.isAbsolute) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('El link no es valido.')));
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el link.')),
      );
    }
  }
}

class _ReceivedItemCard extends StatelessWidget {
  const _ReceivedItemCard({
    required this.draft,
    required this.errorText,
    required this.onQuantityChanged,
  });

  final _ReceivedItemDraft draft;
  final String? errorText;
  final VoidCallback onQuantityChanged;

  @override
  Widget build(BuildContext context) {
    final item = draft.item;
    final received = num.tryParse(
      _normalizeNumber(draft.qtyController.text.trim()),
    );
    final diff = received == null ? null : received - item.quantity;
    final hasDifference = diff != null && diff != 0;
    final diffLabel = hasDifference
        ? (diff > 0 ? '+${_formatNum(diff)}' : _formatNum(diff))
        : null;
    final expectedLabel = '${_formatNum(item.quantity)} ${item.unit}'.trim();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Item ${item.line}: ${item.description}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            if (item.partNumber.trim().isNotEmpty)
              Text('No. parte: ${item.partNumber}'),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _QtyInfoBox(
                    label: 'Cantidad solicitada',
                    value: expectedLabel,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: draft.qtyController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [_quantityInputFormatter],
                    decoration: InputDecoration(
                      labelText: 'Cantidad recibida',
                      helperText: hasDifference
                          ? 'Revisa esta cantidad antes de finalizar.'
                          : null,
                      errorText: errorText,
                    ),
                    onChanged: (_) => onQuantityChanged(),
                  ),
                ),
              ],
            ),
            if (hasDifference) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Text(
                  'La cantidad capturada no coincide con lo que indica el PDF. '
                  'Diferencia: $diffLabel ${item.unit}. '
                  'Si la dejas asi, el sistema te pedira confirmar el descuadre antes de finalizar.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QtyInfoBox extends StatelessWidget {
  const _QtyInfoBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _WarehouseDiff {
  const _WarehouseDiff({
    required this.title,
    required this.requestedLabel,
    required this.receivedLabel,
    required this.deltaLabel,
  });

  final String title;
  final String requestedLabel;
  final String receivedLabel;
  final String deltaLabel;
}

class _ReceivedItemDraft {
  _ReceivedItemDraft({required this.item, required this.qtyController});

  final PurchaseOrderItem item;
  final TextEditingController qtyController;

  factory _ReceivedItemDraft.fromItem(PurchaseOrderItem item) {
    final initialQty = item.receivedQuantity;

    return _ReceivedItemDraft(
      item: item,
      qtyController: TextEditingController(
        text: initialQty == null ? '' : _formatNum(initialQty),
      ),
    );
  }

  void dispose() {
    qtyController.dispose();
  }
}

List<_WarehouseDiff> _warehouseDiffs(List<PurchaseOrderItem> items) {
  final diffs = <_WarehouseDiff>[];
  for (final item in items) {
    final received = item.receivedQuantity;
    if (received == null) continue;

    final delta = received - item.quantity;
    if (delta == 0) continue;

    final unit = item.unit.trim();
    final description = item.description.trim().isEmpty
        ? 'Item ${item.line}'
        : 'Item ${item.line}: ${item.description.trim()}';
    final deltaText = delta > 0 ? '+${_formatNum(delta)}' : _formatNum(delta);
    final unitSuffix = unit.isEmpty ? '' : ' $unit';

    diffs.add(
      _WarehouseDiff(
        title: description,
        requestedLabel: '${_formatNum(item.quantity)}$unitSuffix',
        receivedLabel: '${_formatNum(received)}$unitSuffix',
        deltaLabel: '$deltaText$unitSuffix',
      ),
    );
  }
  return diffs;
}

Duration? _contabilidadDuration(PurchaseOrder order) {
  final stored = order.statusDurations[PurchaseOrderStatus.contabilidad.name];
  if (stored == null || stored < 0) return null;
  return Duration(milliseconds: stored);
}

List<String> _facturaLinks(PurchaseOrder order) {
  final links = <String>[];

  for (final url in order.facturaPdfUrls) {
    final trimmed = url.trim();
    if (trimmed.isNotEmpty) {
      links.add(trimmed);
    }
  }

  final single = order.facturaPdfUrl?.trim();
  if (single != null && single.isNotEmpty && !links.contains(single)) {
    links.insert(0, single);
  }

  return links;
}

final TextInputFormatter _quantityInputFormatter =
    TextInputFormatter.withFunction((oldValue, newValue) {
      final text = newValue.text;
      if (text.isEmpty) return newValue;
      final normalized = text.replaceAll(',', '.');
      final valid = RegExp(r'^\d*([.]\d{0,3})?$').hasMatch(normalized);
      return valid ? newValue : oldValue;
    });

String _normalizeNumber(String raw) => raw.replaceAll(',', '.');

String _formatNum(num value) {
  if (value is int) return value.toString();
  final asInt = value.toInt();
  if (value == asInt) return asInt.toString();
  return value.toString();
}
