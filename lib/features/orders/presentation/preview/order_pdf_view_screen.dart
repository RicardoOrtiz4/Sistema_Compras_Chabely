import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/navigation_guard.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_inline_view.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_rejection_history.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

const int _maxCorrections = 3;

class OrderPdfViewScreen extends ConsumerStatefulWidget {
  const OrderPdfViewScreen({
    required this.orderId,
    super.key,
  });

  final String orderId;

  @override
  ConsumerState<OrderPdfViewScreen> createState() => _OrderPdfViewScreenState();
}

class _OrderPdfViewScreenState extends ConsumerState<OrderPdfViewScreen> {
  bool _isBusy = false;

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdStreamProvider(widget.orderId));

    final actions = orderAsync.maybeWhen(
      data: (order) {
        if (order == null) return const <Widget>[];

        return <Widget>[
          _PdfViewHistoryActionButton(
            order: order,
            onShowHistory: (events) => _showHistory(context, order, events),
          ),
        ];
      },
      orElse: () => const <Widget>[],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF de orden'),
        actions: [
          ...actions,
        ],
      ),
      body: orderAsync.when(
        data: (order) {
          if (order == null) {
            return const AppSplash();
          }

          final showAlmacenAction =
              order.status == PurchaseOrderStatus.almacen;
          final isRejectedDraft = _isRejectedDraft(order);
          final maxCorrectionsReached = order.returnCount >= _maxCorrections;
          final draftRoute =
              '/orders/create?draftId=${Uri.encodeComponent(order.id)}';
          final copyRoute =
              '/orders/create?copyFromId=${Uri.encodeComponent(order.id)}';

          return Column(
            children: [
              Expanded(
                child: _OrderPdfBody(order: order),
              ),
              if (isRejectedDraft)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: maxCorrectionsReached
                        ? OutlinedButton.icon(
                            onPressed: () => guardedPush(context, copyRoute),
                            icon: const Icon(Icons.content_copy_outlined),
                            label: const Text('Volver a generar'),
                          )
                        : FilledButton.icon(
                            onPressed: () => guardedPush(context, draftRoute),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Editar y reenviar'),
                          ),
                  ),
                ),
              if (showAlmacenAction)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isBusy
                              ? null
                              : () => _handleReturnToContabilidad(order),
                          icon: const Icon(Icons.reply_outlined),
                          label: const Text('Regresar a contabilidad'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isBusy
                              ? null
                              : () => guardedPush(
                                    context,
                                    '/orders/almacen/${order.id}',
                                  ),
                          icon: const Icon(
                            Icons.playlist_add_check_circle_outlined,
                          ),
                          label: const Text('Registrar recepción'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            'Error: ${reportError(error, stack, context: 'OrderPdfViewScreen')}',
          ),
        ),
      ),
    );
  }

  Future<void> _handleReturnToContabilidad(PurchaseOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Regresar a contabilidad'),
        content: Text(
          'La orden ${order.id} volverá a contabilidad y se limpiará cualquier captura de recepción en almacén.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Regresar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isBusy = true);

    try {
      final actor = ref.read(currentUserProfileProvider).value;
      if (actor == null) {
        throw StateError('Perfil no disponible.');
      }

      final repo = ref.read(purchaseOrderRepositoryProvider);
      await repo.returnToContabilidad(order: order, actor: actor);

      if (!mounted) return;
      guardedGo(context, '/orders/contabilidad');
    } catch (error, stack) {
      if (!mounted) return;

      final message = reportError(
        error,
        stack,
        context: 'OrderPdfViewScreen.returnToContabilidad',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  void _showHistory(
    BuildContext context,
    PurchaseOrder order,
    List<PurchaseOrderEvent> events,
  ) {
    final branding = ref.read(currentBrandingProvider);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: OrderRejectionHistory(
              branding: branding,
              order: order,
              events: events,
              showOnlyOriginal: true,
            ),
          ),
        );
      },
    );
  }
}

bool _isRejectedDraft(PurchaseOrder order) {
  final reason = order.lastReturnReason;
  return order.status == PurchaseOrderStatus.draft &&
      reason != null &&
      reason.trim().isNotEmpty;
}

class _OrderPdfBody extends ConsumerWidget {
  const _OrderPdfBody({
    required this.order,
  });

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(currentBrandingProvider);
    final pdfData = buildPdfDataFromOrder(
      order,
      branding: branding,
      suppressUpdatedAt: _isRejectedDraft(order),
    );
    return OrderPdfInlineView(data: pdfData);
  }
}

class _PdfViewHistoryActionButton extends ConsumerWidget {
  const _PdfViewHistoryActionButton({
    required this.order,
    required this.onShowHistory,
  });

  final PurchaseOrder order;
  final ValueChanged<List<PurchaseOrderEvent>> onShowHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (order.returnCount <= 0) {
      return IconButton(
        icon: const Icon(Icons.history),
        tooltip: 'Historial de cambios',
        onPressed: null,
      );
    }

    final eventsAsync = ref.watch(orderEventsProvider(order.id));

    return eventsAsync.when(
      data: (events) {
        final canShow = events.any((event) => event.type == 'return');

        return IconButton(
          icon: const Icon(Icons.history),
          tooltip: 'Historial de cambios',
          onPressed: canShow ? () => onShowHistory(events) : null,
        );
      },
      loading: () => IconButton(
        icon: const Icon(Icons.history),
        tooltip: 'Historial de cambios',
        onPressed: null,
      ),
      error: (_, __) => IconButton(
        icon: const Icon(Icons.history),
        tooltip: 'Historial de cambios',
        onPressed: null,
      ),
    );
  }
}
