import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/optimistic_action.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/core/widgets/info_action.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/shared/item_review_dialog.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_rejection_history.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

class DireccionOrderReviewScreen extends ConsumerStatefulWidget {
  const DireccionOrderReviewScreen({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<DireccionOrderReviewScreen> createState() =>
      _DireccionOrderReviewScreenState();
}

class _DireccionOrderReviewScreenState extends ConsumerState<DireccionOrderReviewScreen> {
  bool _isBusy = false;
  bool _hasPreviewedPdf = false;

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdStreamProvider(widget.orderId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dirección General'),
        actions: [
          infoAction(
            context,
            title: 'Dirección General',
            message:
                'Consulta los links de cotizacion.\n'
                'Revisa el PDF y el historial.\n'
                'Autoriza o rechaza la orden.',
          ),
        ],
      ),
      body: orderAsync.when(
        data: (order) {
          if (order == null) {
            return const AppSplash();
          }
          final maxCorrectionsReached = order.returnCount >= _maxCorrections;
          final cotizacionLinks = _cotizacionLinks(order);
          final eventsAsync = ref.watch(orderEventsProvider(order.id));
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  children: [
                    if (cotizacionLinks.isNotEmpty)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cotización',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            for (final link in cotizacionLinks) ...[
                              if (link.supplier.trim().isNotEmpty)
                                Text(
                                  'Proveedor: ${link.supplier.trim()}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              Text(
                                link.url,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  onPressed: () => _openLink(link.url),
                                  icon: const Icon(Icons.open_in_new),
                                  label: const Text('Abrir link'),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ],
                        ),
                      ),
                    if (maxCorrectionsReached)
                      Text(
                        'Máximo de correcciones alcanzado. Solicita una nueva requisición.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    eventsAsync.when(
                      data: (events) => OrderRejectionHistory(
                        order: order,
                        events: events,
                        hideLatestResubmission: true,
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (error, stack) => Text(
                        'Error en historial de rechazos: ${reportError(error, stack, context: 'DireccionOrderReviewScreen.rejections')}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await guardedPush(context, '/orders/${order.id}/pdf');
                        if (mounted) {
                          setState(() => _hasPreviewedPdf = true);
                        }
                      },
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Revisar PDF'),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              if (_hasPreviewedPdf)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 360;
                      final returnButton = OutlinedButton.icon(
                        onPressed:
                            _isBusy || maxCorrectionsReached ? null : () => _handleReturn(order),
                        icon: const Icon(Icons.reply_outlined),
                        label: const Text('Regresar a Compras'),
                      );
                      final payButton = FilledButton(
                        onPressed: _isBusy ? null : () => _handlePaymentDone(order),
                        child: _isBusy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: AppSplash(compact: true, size: 20),
                              )
                            : const Text('Autorizar'),
                      );
                      if (isNarrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            returnButton,
                            const SizedBox(height: 8),
                            payButton,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: returnButton),
                          const SizedBox(width: 12),
                          Expanded(child: payButton),
                        ],
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
            'Error: ${reportError(error, stack, context: 'DireccionOrderReviewScreen')}',
          ),
        ),
      ),
    );
  }

  Future<void> _handlePaymentDone(PurchaseOrder order) async {
    final confirmed = await _confirmPaymentDone(order.id);
    if (!confirmed!) return;
    setState(() => _isBusy = true);
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) {
      if (mounted) {
        setState(() => _isBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil no disponible.')),
        );
      }
      return;
    }

    await runOptimisticAction(
      context: context,
      onNavigate: () => Navigator.pop(context),
      pendingLabel: 'Autorizando orden...',
      successMessage: 'Orden autorizada.',
      errorContext: 'DireccionOrderReviewScreen.paymentDone',
      action: () => ref.read(purchaseOrderRepositoryProvider).markPaymentDone(
            order: order,
            actor: actor,
          ),
    );

    if (mounted) {
      setState(() => _isBusy = false);
    }
  }

  Future<void> _handleReturn(PurchaseOrder order) async {
    if (order.returnCount >= _maxCorrections) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Máximo de correcciones alcanzado. Crea otra requisición.'),
        ),
      );
      return;
    }
    final review = await showItemReviewDialog(
      context: context,
      order: order,
      title: 'Regresar orden ${order.id}',
      confirmLabel: 'Regresar',
    );
    if (review == null) return;
    setState(() => _isBusy = true);
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) {
      if (mounted) {
        setState(() => _isBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil no disponible.')),
        );
      }
      return;
    }

    await runOptimisticAction(
      context: context,
      onNavigate: () => Navigator.pop(context),
      pendingLabel: 'Regresando a Compras...',
      successMessage: 'Orden regresada a Compras.',
      errorContext: 'DireccionOrderReviewScreen.return',
      action: () => ref.read(purchaseOrderRepositoryProvider).returnToCompras(
            order: order,
            comment: review.summary,
            items: review.items,
            actor: actor,
          ),
    );

    if (mounted) {
      setState(() => _isBusy = false);
    }
  }

  Future<bool?> _confirmPaymentDone(String orderId) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Autorizar orden $orderId'),
        content: const Text(
          'Al autorizar, la orden regresara a Compras para fecha estimada.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Autorizar'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _openLink(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.isAbsolute) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El link no es valido.')),
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

const _maxCorrections = 3;

List<CotizacionLink> _cotizacionLinks(PurchaseOrder order) {
  if (order.cotizacionLinks.isNotEmpty) {
    return order.cotizacionLinks;
  }
  final links = <CotizacionLink>[];
  for (final url in order.cotizacionPdfUrls) {
    final trimmed = url.trim();
    if (trimmed.isNotEmpty) {
      links.add(CotizacionLink(supplier: '', url: trimmed));
    }
  }
  final single = order.cotizacionPdfUrl?.trim();
  if (single != null && single.isNotEmpty && !links.any((link) => link.url == single)) {
    links.insert(0, CotizacionLink(supplier: '', url: single));
  }
  return links;
}


