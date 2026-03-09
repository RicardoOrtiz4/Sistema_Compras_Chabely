import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
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

class ContabilidadOrdersScreen extends ConsumerStatefulWidget {
  const ContabilidadOrdersScreen({super.key});

  @override
  ConsumerState<ContabilidadOrdersScreen> createState() =>
      _ContabilidadOrdersScreenState();
}

class _ContabilidadOrdersScreenState
    extends ConsumerState<ContabilidadOrdersScreen> {
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
    final ordersAsync = ref.watch(contabilidadOrdersPagedProvider(_limit));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contabilidad'),
        actions: [
          infoAction(
            context,
            title: 'Contabilidad',
            message:
                'Aqui ves ordenes autorizadas para facturar.\n'
                'Usa el buscador por folio, solicitante o fecha.\n'
                'Abre una orden para cargar la factura y avanzar.',
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
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
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
                          return _ContabilidadOrderCard(
                            order: order,
                            onReview: () => context
                                .push('/orders/contabilidad/${order.id}'),
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
            'Error: ${reportError(error, stack, context: 'ContabilidadOrdersScreen')}',
          ),
        ),
      ),
    );
  }
}

class _ContabilidadOrderCard extends StatelessWidget {
  const _ContabilidadOrderCard({
    required this.order,
    required this.onReview,
  });

  final PurchaseOrder order;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final createdLabel = order.createdAt?.toFullDateTime() ?? 'Pendiente';

    final hasFactura = order.facturaPdfUrls.isNotEmpty ||
        ((order.facturaPdfUrl != null) &&
            order.facturaPdfUrl!.trim().isNotEmpty);

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
                      'Factura cargada',
                      style: TextStyle(
                        color: Colors.green.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Solicitante: ${order.requesterName}'),
            Text('Área: ${order.areaName}'),
            Text('Urgencia: ${order.urgency.label}'),
            Text('Creada: $createdLabel'),
            const SizedBox(height: 8),

            // ✅ Reemplazo del widget corrupto:
            _OrderCardSummary(order: order),
            const SizedBox(height: 6),
            OrderStatusDurationPill(order: order),

            const SizedBox(height: 12),
            FilledButton(
              onPressed: onReview,
              child: const Text('Revisar factura'),
            ),
          ],
        ),
      ),
    );
  }
}

class ContabilidadOrderReviewScreen extends ConsumerStatefulWidget {
  const ContabilidadOrderReviewScreen({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<ContabilidadOrderReviewScreen> createState() =>
      _ContabilidadOrderReviewScreenState();
}

class _ContabilidadOrderReviewScreenState
    extends ConsumerState<ContabilidadOrderReviewScreen> {
  final _linkController = TextEditingController();
  final List<_FacturaLinkDraft> _facturaLinks = [];
  bool _prefilled = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdStreamProvider(widget.orderId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Factura de contabilidad'),
        actions: [
          infoAction(
            context,
            title: 'Factura de contabilidad',
            message:
                'Pega uno o varios links de factura.\n'
                'Verifica que los links sean validos.\n'
                'Guardar envia la orden al siguiente paso.',
          ),
        ],
      ),
      body: orderAsync.when(
        data: (order) {
          if (order == null) {
            return const AppSplash();
          }
          if (!_prefilled) {
            _prefilled = true;
            final cachedDraft = SessionDraftStore.contabilidad(order.id);
            if (cachedDraft != null) {
              _facturaLinks
                ..clear()
                ..addAll(
                  cachedDraft.facturaLinks
                      .map((url) => _FacturaLinkDraft(url: url)),
                );
              _linkController.text = cachedDraft.pendingLink;
            } else {
              _seedFacturaLinks(order);
            }
          }

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  children: [
                    // ✅ Reemplazo del widget corrupto:
                    _OrderHeaderSummary(order: order),

                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => guardedPush(context, '/orders/${order.id}/pdf'),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Ver PDF'),
                    ),
                    const SizedBox(height: 16),
                    const Text('Agrega uno o varios links del PDF de la factura.'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _linkController,
                            decoration: const InputDecoration(
                              labelText: 'Link del PDF de la factura',
                              prefixIcon: Icon(Icons.link),
                            ),
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.done,
                            autocorrect: false,
                            onChanged: (_) => _saveDraft(order.id),
                            onSubmitted: (_) => _addFacturaLink(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _addFacturaLink,
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_facturaLinks.isEmpty)
                      const Text('Aún no hay links agregados.')
                    else
                      Column(
                        children: [
                          for (final link in _facturaLinks)
                            Card(
                              child: ListTile(
                                title: Text(
                                  link.url,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                leading: const Icon(Icons.link),
                                trailing: Wrap(
                                  spacing: 4,
                                  children: [
                                    IconButton(
                                      tooltip: 'Editar',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () => _editFacturaLink(link),
                                    ),
                                    IconButton(
                                      tooltip: 'Abrir link',
                                      icon: const Icon(Icons.open_in_new),
                                      onPressed: () => _openLink(link.url),
                                    ),
                                    IconButton(
                                      tooltip: 'Quitar',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _removeFacturaLink(link),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSubmitting || _facturaLinks.isEmpty
                        ? null
                        : () => _handleSend(order),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: AppSplash(compact: true, size: 20),
                          )
                        : const Text('Enviar a Almacén'),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            'Error: ${reportError(error, stack, context: 'ContabilidadOrderReview')}',
          ),
        ),
      ),
    );
  }

  void _seedFacturaLinks(PurchaseOrder order) {
    _facturaLinks.clear();
    final urls = <String>[
      ...order.facturaPdfUrls,
      if (order.facturaPdfUrl != null) order.facturaPdfUrl!.trim(),
    ].where((link) => link.trim().isNotEmpty).toList();

    for (final url in urls) {
      _facturaLinks.add(_FacturaLinkDraft(url: _normalizeLink(url)));
    }
  }

  void _addFacturaLink() {
    final raw = _linkController.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa el link de la factura.')),
      );
      return;
    }

    final link = _normalizeLink(raw);
    final uri = Uri.tryParse(link);
    if (uri == null ||
        !uri.isAbsolute ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El link no es válido.')),
      );
      return;
    }

    if (_facturaLinks.any((entry) => entry.url == link)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El link ya fue agregado.')),
      );
      return;
    }

    setState(() {
      _facturaLinks.add(_FacturaLinkDraft(url: link));
      _linkController.clear();
    });
    _saveDraft(widget.orderId);
  }

  void _removeFacturaLink(_FacturaLinkDraft link) {
    setState(() => _facturaLinks.removeWhere((entry) => entry.url == link.url));
    _saveDraft(widget.orderId);
  }

  Future<void> _editFacturaLink(_FacturaLinkDraft link) async {
    final urlController = TextEditingController(text: link.url);

    final updated = await showDialog<_FacturaLinkDraft>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar link de factura'),
        content: TextFormField(
          controller: urlController,
          decoration: const InputDecoration(
            labelText: 'Link del PDF de la factura',
            prefixIcon: Icon(Icons.link),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final raw = urlController.text.trim();
              if (raw.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Completa el link.')),
                );
                return;
              }

              final normalized = _normalizeLink(raw);
              final uri = Uri.tryParse(normalized);
              if (uri == null ||
                  !uri.isAbsolute ||
                  (uri.scheme != 'http' && uri.scheme != 'https') ||
                  uri.host.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('El link no es válido.')),
                );
                return;
              }

              final exists = _facturaLinks.any(
                (entry) => entry.url == normalized && entry != link,
              );
              if (exists) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('El link ya fue agregado.')),
                );
                return;
              }

              Navigator.pop(context, _FacturaLinkDraft(url: normalized));
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    urlController.dispose();
    if (updated == null) return;

    setState(() {
      final index = _facturaLinks.indexWhere((entry) => entry.url == link.url);
      if (index != -1) {
        _facturaLinks[index] = updated;
      }
    });
    _saveDraft(widget.orderId);
  }

  Future<void> _handleSend(PurchaseOrder order) async {
    if (_facturaLinks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos un link de factura.')),
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
      await repo.sendFacturaToAlmacen(
        order: order,
        facturaUrls: _facturaLinks.map((entry) => entry.url).toList(),
        actor: actor,
      );

      if (!mounted) return;

      SessionDraftStore.clearContabilidad(order.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Factura enviada a almacén.')),
      );
      guardedGo(context, '/orders/contabilidad');
    } catch (error, stack) {
      if (!mounted) return;
      final message =
          reportError(error, stack, context: 'ContabilidadOrderReview.send');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _saveDraft(String orderId) {
    SessionDraftStore.saveContabilidad(
      orderId,
      ContabilidadDraft(
        facturaLinks: _facturaLinks.map((entry) => entry.url).toList(),
        pendingLink: _linkController.text,
      ),
    );
  }

  Future<void> _openLink(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;

    final link = _normalizeLink(trimmed);
    final uri = Uri.tryParse(link);

    if (uri == null ||
        !uri.isAbsolute ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El link no es válido.')),
      );
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el link.')),
      );
    }
  }
}

class _FacturaLinkDraft {
  const _FacturaLinkDraft({required this.url});
  final String url;
}

String _normalizeLink(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme) return trimmed;
  return 'https://$trimmed';
}

/// Resumen pequeño para tarjetas (reemplaza el widget corrupto).
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

/// Resumen para el header del review (compact: false antes).
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
            Text('Área: ${order.areaName}'),
            const SizedBox(height: 8),
            Text('Creada: $created'),
            if (updated != null) Text('Actualizada: $updated'),
          ],
        ),
      ),
    );
  }
}


