import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/session_drafts.dart';
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

class AlmacenOrdersScreen extends ConsumerStatefulWidget {
  const AlmacenOrdersScreen({super.key});

  @override
  ConsumerState<AlmacenOrdersScreen> createState() => _AlmacenOrdersScreenState();
}

class _AlmacenOrdersScreenState extends ConsumerState<AlmacenOrdersScreen> {
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
    final ordersAsync = ref.watch(almacenOrdersPagedProvider(_limit));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Almacen'),
        actions: [
          infoAction(
            context,
            title: 'Almacen',
            message:
                'Lista de ordenes listas para recepcion.\n'
                'Usa el buscador para filtrar.\n'
                'Abre una orden para registrar recepcion.',
          ),
        ],
      ),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('No hay ordenes pendientes.'));
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
                          return _AlmacenOrderCard(
                            order: order,
                            onReview: () =>
                                guardedPush(context, '/orders/almacen/${order.id}'),
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
            'Error: ${reportError(error, stack, context: 'AlmacenOrdersScreen')}',
          ),
        ),
      ),
    );
  }
}

class _AlmacenOrderCard extends StatelessWidget {
  const _AlmacenOrderCard({
    required this.order,
    required this.onReview,
  });

  final PurchaseOrder order;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final createdLabel = order.createdAt?.toFullDateTime() ?? 'Pendiente';
    final hasFactura = _facturaLinks(order).isNotEmpty;
    final hasReceived = order.items.any((item) => item.receivedQuantity != null);

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
                if (hasFactura)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade400),
                    ),
                    child: Text(
                      'Factura lista',
                      style: TextStyle(
                        color: Colors.green.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (hasReceived)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade400),
                    ),
                    child: Text(
                      'Recepcion iniciada',
                      style: TextStyle(
                        color: Colors.blue.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Folio: ${order.id}'),
            Text('Solicitante: ${order.requesterName}'),
            Text('Area: ${order.areaName}'),
            Text('Urgencia: ${order.urgency.label}'),
            Text('Creada: $createdLabel'),
            const SizedBox(height: 8),
            _OrderCardSummary(order: order),
            const SizedBox(height: 6),
            OrderStatusDurationPill(order: order),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onReview,
              child: Text(hasReceived ? 'Ver recepcion' : 'Registrar recepcion'),
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
        Text('Estado: ${order.status.label}'),
        if (supplier.isNotEmpty) Text('Proveedor: $supplier'),
        if (internalOrder.isNotEmpty) Text('OC interna: $internalOrder'),
        if (order.budget != null) Text('Presupuesto: ${order.budget}'),
      ],
    );
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
  final _commentController = TextEditingController();
  final Map<int, String> _qtyErrors = {};
  final List<_ReceivedItemDraft> _drafts = [];
  String? _seededOrderId;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _commentController.addListener(() => _saveDraft(widget.orderId));
  }

  @override
  void dispose() {
    _commentController.dispose();
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
        actions: [
          infoAction(
            context,
            title: 'Recepcion en almacen',
            message:
                'Registra cantidades recibidas y comentarios.\n'
                'Finalizar avanza la orden al siguiente paso.',
          ),
        ],
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
                    _OrderHeaderSummary(order: order),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => guardedPush(context, '/orders/${order.id}/pdf'),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Ver PDF'),
                    ),
                    const SizedBox(height: 12),
                    _FacturaLinksSection(order: order),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _commentController,
                      decoration: const InputDecoration(
                        labelText: 'Comentario general (opcional)',
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
                          if (_qtyErrors.containsKey(i)) {
                            setState(() => _qtyErrors.remove(i));
                          }
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
                    onPressed: _isSubmitting ? null : () => _handleSubmit(order),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: AppSplash(compact: true, size: 20),
                          )
                        : const Text('Finalizar recepcion'),
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
      _commentController.text = cachedDraft.comment;
      for (final draft in _drafts) {
        final line = draft.item.line;
        final cachedQty = cachedDraft.qtyByLine[line];
        if (cachedQty != null) {
          draft.qtyController.text = cachedQty;
        }
        final cachedComment = cachedDraft.commentByLine[line];
        if (cachedComment != null) {
          draft.commentController.text = cachedComment;
        }
      }
    } else {
      _commentController.text = (order.almacenComment ?? '').trim();
    }

    _qtyErrors.clear();
    _seededOrderId = order.id;
    _attachDraftListeners(order.id);
  }

  void _attachDraftListeners(String orderId) {
    for (final draft in _drafts) {
      draft.qtyController.addListener(() => _saveDraft(orderId));
      draft.commentController.addListener(() => _saveDraft(orderId));
    }
  }

  void _saveDraft(String orderId) {
    final qtyByLine = <int, String>{};
    final commentByLine = <int, String>{};

    for (final draft in _drafts) {
      qtyByLine[draft.item.line] = draft.qtyController.text;
      commentByLine[draft.item.line] = draft.commentController.text;
    }

    SessionDraftStore.saveAlmacen(
      orderId,
      AlmacenDraft(
        comment: _commentController.text,
        qtyByLine: qtyByLine,
        commentByLine: commentByLine,
      ),
    );
  }

  Future<void> _handleSubmit(PurchaseOrder order) async {
    final nextErrors = <int, String>{};
    final updatedItems = <PurchaseOrderItem>[];

    for (var i = 0; i < _drafts.length; i++) {
      final draft = _drafts[i];
      final raw = draft.qtyController.text.trim();

      num? received;
      if (raw.isEmpty) {
        received = draft.item.quantity;
      } else {
        received = num.tryParse(_normalizeNumber(raw));
      }

      if (received == null || received < 0) {
        nextErrors[i] = 'Cantidad no valida';
        continue;
      }

      final comment = draft.commentController.text.trim();

      updatedItems.add(
        draft.item.copyWith(
          receivedQuantity: received,
          receivedComment: comment.isEmpty ? null : comment,
        ),
      );
    }

    if (nextErrors.isNotEmpty) {
      setState(() => _qtyErrors
        ..clear()
        ..addAll(nextErrors));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Corrige las cantidades en rojo.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final actor = ref.read(currentUserProfileProvider).value;
      if (actor == null) {
        throw StateError('Perfil no disponible.');
      }

      final repo = ref.read(purchaseOrderRepositoryProvider);
      await repo.finalizeFromAlmacen(
        order: order,
        items: updatedItems,
        actor: actor,
        comment: _commentController.text.trim(),
      );

      if (!mounted) return;

      SessionDraftStore.clearAlmacen(order.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recepcion guardada.')),
      );
      guardedGo(context, '/orders/almacen');
    } catch (error, stack) {
      if (!mounted) return;
      final message =
          reportError(error, stack, context: 'AlmacenOrderReview.submit');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}

class _OrderHeaderSummary extends StatelessWidget {
  const _OrderHeaderSummary({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    final created = order.createdAt?.toFullDateTime() ?? 'Pendiente';
    final updated = order.updatedAt?.toFullDateTime();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(order.urgency.label)),
                Chip(label: Text(order.status.label)),
              ],
            ),
            const SizedBox(height: 12),
            Text('Folio: ${order.id}'),
            Text('Solicitante: ${order.requesterName}'),
            Text('Area: ${order.areaName}'),
            const SizedBox(height: 8),
            Text('Creada: $created'),
            if (updated != null) Text('Actualizada: $updated'),
          ],
        ),
      ),
    );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El link no es valido.')),
      );
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
            Text('Solicitado: ${item.quantity} ${item.unit}'),
            const SizedBox(height: 8),
            TextField(
              controller: draft.qtyController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Recibido',
                errorText: errorText,
              ),
              onChanged: (_) => onQuantityChanged(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: draft.commentController,
              decoration: const InputDecoration(
                labelText: 'Comentario (opcional)',
              ),
              minLines: 1,
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceivedItemDraft {
  _ReceivedItemDraft({
    required this.item,
    required this.qtyController,
    required this.commentController,
  });

  final PurchaseOrderItem item;
  final TextEditingController qtyController;
  final TextEditingController commentController;

  factory _ReceivedItemDraft.fromItem(PurchaseOrderItem item) {
    final initialQty = item.receivedQuantity ?? item.quantity;
    final initialComment = (item.receivedComment ?? '').trim();

    return _ReceivedItemDraft(
      item: item,
      qtyController: TextEditingController(text: _formatNum(initialQty)),
      commentController: TextEditingController(text: initialComment),
    );
  }

  void dispose() {
    qtyController.dispose();
    commentController.dispose();
  }
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

String _normalizeNumber(String raw) => raw.replaceAll(',', '.');

String _formatNum(num value) {
  if (value is int) return value.toString();
  final asInt = value.toInt();
  if (value == asInt) return asInt.toString();
  return value.toString();
}


