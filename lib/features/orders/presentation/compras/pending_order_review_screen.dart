import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_inline_view.dart';
import 'package:sistema_compras/features/orders/presentation/shared/item_review_dialog.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_rejection_history.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

class PendingOrderReviewScreen extends ConsumerStatefulWidget {
  const PendingOrderReviewScreen({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<PendingOrderReviewScreen> createState() =>
      _PendingOrderReviewScreenState();
}

class _PendingOrderReviewScreenState
    extends ConsumerState<PendingOrderReviewScreen> {
  bool _isBusy = false;

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdStreamProvider(widget.orderId));

    final actions = orderAsync.maybeWhen(
      data: (order) {
        if (order == null) return const <Widget>[];
        final eventsAsync = ref.watch(orderEventsProvider(order.id));
        return [
          eventsAsync.when(
            data: (events) => IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Historial de cambios',
              onPressed:
                  events.isEmpty ? null : () => _showHistory(context, order, events),
            ),
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
        title: const Text('Revisar PDF'),
        actions: actions,
      ),
      body: orderAsync.when(
        data: (order) {
          if (order == null) {
            return const AppSplash();
          }

          final maxCorrectionsReached = order.returnCount >= _maxCorrections;
          final branding = ref.watch(currentBrandingProvider);
          final pdfData = buildPdfDataFromOrder(order, branding: branding);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _OrderHeaderSummary(order: order, compact: false),
              ),
              if (maxCorrectionsReached)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Máximo de correcciones alcanzado. Solicita una nueva requisición.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Expanded(child: OrderPdfInlineView(data: pdfData)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 360;

                    final rejectButton = OutlinedButton(
                      onPressed: _isBusy || maxCorrectionsReached
                          ? null
                          : () => _handleReject(order),
                      child: _isBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Rechazar'),
                    );

                    final approveButton = FilledButton(
                      onPressed: _isBusy
                          ? null
                          : () => context.push('/orders/review/${order.id}/approve'),
                      child: const Text('Autorizar'),
                    );

                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          rejectButton,
                          const SizedBox(height: 8),
                          approveButton,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: rejectButton),
                        const SizedBox(width: 12),
                        Expanded(child: approveButton),
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
            'Error: ${reportError(error, stack, context: 'PendingOrderReviewScreen')}',
          ),
        ),
      ),
    );
  }

  Future<void> _handleReject(PurchaseOrder order) async {
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
      title: 'Rechazar orden ${order.id}',
      confirmLabel: 'Rechazar',
    );
    if (review == null) return;

    setState(() => _isBusy = true);
    try {
      final actor = ref.read(currentUserProfileProvider).value;
      if (actor == null) {
        throw StateError('Perfil no disponible.');
      }

      final repo = ref.read(purchaseOrderRepositoryProvider);
      await repo.requestEdit(
        order: order,
        comment: review.summary,
        items: review.items,
        actor: actor,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Orden devuelta al solicitante.')),
      );
      context.pop();
    } catch (error, stack) {
      if (!mounted) return;
      final message =
          reportError(error, stack, context: 'PendingOrderReviewScreen.reject');
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
}

const _maxCorrections = 3;

class PendingOrderApprovalScreen extends ConsumerStatefulWidget {
  const PendingOrderApprovalScreen({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<PendingOrderApprovalScreen> createState() =>
      _PendingOrderApprovalScreenState();
}

class _PendingOrderApprovalScreenState
    extends ConsumerState<PendingOrderApprovalScreen> {
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdStreamProvider(widget.orderId));

    return Scaffold(
      appBar: AppBar(title: const Text('Autorizar orden')),
      body: orderAsync.when(
        data: (order) {
          if (order == null) {
            return const AppSplash();
          }

          final branding = ref.watch(currentBrandingProvider);
          final pdfData = buildPdfDataFromOrder(order, branding: branding);

          return Column(
            children: [
              Expanded(child: OrderPdfInlineView(data: pdfData)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSubmitting ? null : () => _handleApprove(order),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Enviar a Cotizaciones'),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            'Error: ${reportError(error, stack, context: 'PendingOrderApprovalScreen')}',
          ),
        ),
      ),
    );
  }

  Future<void> _handleApprove(PurchaseOrder order) async {
    setState(() => _isSubmitting = true);
    try {
      final actor = ref.read(currentUserProfileProvider).value;
      if (actor == null) {
        throw StateError('Perfil no disponible.');
      }

      final confirmed =
          await _confirmSendToCotizaciones(actor.name, actor.areaDisplay);
      if (!confirmed) {
        if (mounted) setState(() => _isSubmitting = false);
        return;
      }

      await ref.read(purchaseOrderRepositoryProvider).transitionStatus(
        order: order,
        targetStatus: PurchaseOrderStatus.cotizaciones,
        actor: actor,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Orden enviada a Cotizaciones.')),
      );
      context.go('/orders/pending');
    } catch (error, stack) {
      if (!mounted) return;
      final message =
          reportError(error, stack, context: 'PendingOrderApprovalScreen.approve');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<bool> _confirmSendToCotizaciones(String name, String area) async {
    final trimmedName = name.trim().isEmpty ? 'Tu nombre' : name.trim();
    final trimmedArea = area.trim().isEmpty ? 'Tu área' : area.trim();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enviar a Cotizaciones'),
        content: Text(
          'En el PDF, la casilla RECIBIÓ mostrará "$trimmedName" y el área "$trimmedArea".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );

    return result ?? false;
  }
}

/// Reemplazo del widget corrupto (compact true/false).
class _OrderHeaderSummary extends StatelessWidget {
  const _OrderHeaderSummary({required this.order, required this.compact});

  final PurchaseOrder order;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final created = order.createdAt?.toFullDateTime() ?? 'Pendiente';
    final updated = order.updatedAt?.toFullDateTime();

    final children = <Widget>[
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
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
      ),
    );
  }
}
