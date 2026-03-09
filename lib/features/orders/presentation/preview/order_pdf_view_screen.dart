import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/core/widgets/info_action.dart';
import 'package:sistema_compras/features/orders/application/create_order_controller.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_inline_view.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_rejection_history.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

class OrderPdfViewScreen extends ConsumerStatefulWidget {
  const OrderPdfViewScreen({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<OrderPdfViewScreen> createState() => _OrderPdfViewScreenState();
}

class _OrderPdfViewScreenState extends ConsumerState<OrderPdfViewScreen> {
  static const int _maxCorrections = 3;
  bool _isBusy = false;

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdStreamProvider(widget.orderId));
    final actions = orderAsync.maybeWhen(
      data: (order) {
        if (order == null) return const <Widget>[];
        final eventsAsync = ref.watch(orderEventsProvider(order.id));
        final hasReturns = order.returnCount > 0;
        return [
          eventsAsync.when(
            data: (events) {
              final canShow =
                  hasReturns && events.any((event) => event.type == 'return');
              return IconButton(
                icon: const Icon(Icons.history),
                tooltip: 'Historial de cambios',
                onPressed:
                    canShow ? () => _showHistory(context, order, events) : null,
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
          infoAction(
            context,
            title: 'PDF de orden',
            message:
                'Consulta el PDF generado.\n'
                'Si es borrador, veras acciones de editar o eliminar.',
          ),
        ],
      ),
      body: orderAsync.when(
        data: (order) {
          if (order == null) {
            return const AppSplash();
          }
          final branding = ref.watch(currentBrandingProvider);
          final pdfData = buildPdfDataFromOrder(order, branding: branding);
          final showDraftActions = order.status == PurchaseOrderStatus.draft;
          final maxCorrectionsReached = order.returnCount >= _maxCorrections;
          return Column(
            children: [
              Expanded(child: OrderPdfInlineView(data: pdfData)),
              if (showDraftActions)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 360;
                      final scheme = Theme.of(context).colorScheme;
                      final info = maxCorrectionsReached
                          ? const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text(
                                'Máximo de correcciones alcanzado. Crea otra requisición.',
                              ),
                            )
                          : const SizedBox.shrink();
                      final deleteButton = FilledButton.icon(
                        onPressed: _isBusy ? null : () => _handleDelete(order),
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.error,
                          foregroundColor: scheme.onError,
                        ),
                        icon: _isBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: AppSplash(compact: true, size: 18),
                              )
                            : const Icon(Icons.delete_outline),
                        label: const Text('Borrar'),
                      );
                      final editButton = FilledButton.icon(
                        onPressed: _isBusy || maxCorrectionsReached
                            ? null
                            : () => _handleEdit(order),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Editar'),
                      );
                      if (isNarrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            info,
                            deleteButton,
                            if (!maxCorrectionsReached) ...[
                              const SizedBox(height: 8),
                              editButton,
                            ],
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                info,
                                deleteButton,
                              ],
                            ),
                          ),
                          if (!maxCorrectionsReached) ...[
                            const SizedBox(width: 12),
                            Expanded(child: editButton),
                          ],
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
            'Error: ${reportError(error, stack, context: 'OrderPdfViewScreen')}',
          ),
        ),
      ),
    );
  }

  Future<void> _handleEdit(PurchaseOrder order) async {
    if (order.returnCount >= _maxCorrections) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Máximo de correcciones alcanzado. Crea otra requisición.'),
        ),
      );
      return;
    }
    setState(() => _isBusy = true);
    try {
      await ref.read(createOrderControllerProvider.notifier).loadDraft(order.id);
      final state = ref.read(createOrderControllerProvider);
      if (state.error != null) {
        throw state.error!;
      }
      if (!mounted) return;
      guardedPush(context, '/orders/create?draftId=${order.id}');
    } catch (error, stack) {
      if (!mounted) return;
      final message = reportError(error, stack, context: 'OrderPdfViewScreen.edit');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _handleDelete(PurchaseOrder order) async {
    final confirmed = await _showDeleteDialog(order);
    if (!confirmed!) return;
    setState(() => _isBusy = true);
    try {
      final repo = ref.read(purchaseOrderRepositoryProvider);
      await repo.deleteOrder(order.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Orden eliminada.')));
      context.pop();
    } catch (error, stack) {
      if (!mounted) return;
      final message = reportError(error, stack, context: 'OrderPdfViewScreen.delete');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: OrderRejectionHistory(
              order: order,
              events: events,
              showOnlyOriginal: true,
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _showDeleteDialog(PurchaseOrder order) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Borrar orden ${order.id}'),
        content: const Text('Esta accion elimina la orden de forma definitiva.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Borrar'),
          ),
        ],
      ),
    );
    return result;   
  }
}

