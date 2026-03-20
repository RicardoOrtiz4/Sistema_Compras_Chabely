import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sistema_compras/core/company_branding.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/optimistic_action.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_inline_view.dart';
import 'package:sistema_compras/features/orders/presentation/shared/item_review_dialog.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_rejection_history.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

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
  int _pdfRefreshToken = 0;

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdStreamProvider(widget.orderId));

    final actions = orderAsync.maybeWhen(
      data: (order) {
        if (order == null) return const <Widget>[];
        return [
          _PendingReviewHistoryActionButton(
            order: order,
            onShowHistory: (events) => _showHistory(context, order, events),
          ),
        ];
      },
      orElse: () => const <Widget>[],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisar PDF'),
        actions: [
          ...actions,
        ],
      ),
      body: orderAsync.when(
        data: (order) {
          if (order == null) {
            return const AppSplash();
          }

          final maxCorrectionsReached = order.returnCount >= _maxCorrections;

          return Column(
            children: [
              Expanded(
                child: _PendingReviewPdfBody(
                  key: ValueKey('review-pdf-$_pdfRefreshToken'),
                  order: order,
                  preferOrderCache: true,
                ),
              ),
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
                              child: AppSplash(compact: true, size: 18),
                            )
                          : const Text('Rechazar'),
                    );

                    final approveButton = FilledButton(
                      onPressed: _isBusy
                          ? null
                          : () async {
                              await guardedPush(
                                context,
                                '/orders/review/${order.id}/approve',
                              );
                              if (mounted) {
                                setState(() => _pdfRefreshToken += 1);
                              }
                            },
                      child: const Text('Confirmar'),
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
    if (!mounted) return;
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
      onNavigate: () => context.pop(),
      pendingLabel: 'Regresando al solicitante...',
      successMessage: 'Orden devuelta al solicitante.',
      errorContext: 'PendingOrderReviewScreen.reject',
      action: () async {
        final repo = ref.read(purchaseOrderRepositoryProvider);
        final branding = ref.read(currentBrandingProvider);
        await repo.requestEdit(
          order: order,
          comment: review.summary,
          items: review.items,
          actor: actor,
        );
        try {
          PurchaseOrder? refreshed;
          for (var attempt = 0; attempt < 2; attempt++) {
            refreshed = await repo.fetchOrderById(order.id);
            if (refreshed != null) {
              break;
            }
            await Future.delayed(const Duration(milliseconds: 300));
          }
          if (refreshed == null) return;
          final pdfData = buildPdfDataFromOrder(
            refreshed,
            branding: branding,
          );
          await buildOrderPdf(pdfData, useIsolate: false);
        } catch (error, stack) {
          logError(
            error,
            stack,
            context: 'PendingOrderReviewScreen.warmRejectedCache',
          );
        }
      },
    );

    if (mounted) {
      setState(() => _isBusy = false);
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

class _PendingReviewPdfBody extends ConsumerWidget {
  const _PendingReviewPdfBody({
    required this.order,
    required this.preferOrderCache,
    super.key,
  });

  final PurchaseOrder order;
  final bool preferOrderCache;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(currentBrandingProvider);
    final pdfData = buildPdfDataFromOrder(order, branding: branding);
    return OrderPdfInlineView(
      data: pdfData,
      preferOrderCache: preferOrderCache,
    );
  }
}

class _PendingReviewHistoryActionButton extends ConsumerWidget {
  const _PendingReviewHistoryActionButton({
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
  int _pdfRefreshToken = 0;
  OrderPdfData? _frozenPdfData;

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdStreamProvider(widget.orderId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirmar orden'),
      ),
      body: orderAsync.when(
        data: (order) {
          if (order == null) {
            return const AppSplash();
          }

          return Column(
            children: [
              Expanded(
                child: _PendingApprovalPdfBody(
                  key: ValueKey('approve-pdf-$_pdfRefreshToken'),
                  order: order,
                  isSubmitting: _isSubmitting,
                  frozenPdfData: _frozenPdfData,
                ),
              ),
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
                            child: AppSplash(compact: true, size: 20),
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
    setState(() {
      _isSubmitting = true;
      _frozenPdfData = _buildPdfData(order);
    });
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _frozenPdfData = null;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil no disponible.')),
      );
      return;
    }

    final confirmed =
        await _confirmSendToCotizaciones(actor.name, actor.areaDisplay);
    if (!mounted) return;
    if (!confirmed) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _frozenPdfData = null;
          _pdfRefreshToken += 1;
        });
      }
      return;
    }

    final reviewerName = (order.comprasReviewerName ?? '').trim().isEmpty
        ? actor.name
        : order.comprasReviewerName;
    final reviewerArea = (order.comprasReviewerArea ?? '').trim().isEmpty
        ? actor.areaDisplay
        : order.comprasReviewerArea;

    await runOptimisticAction(
      context: context,
      onNavigate: () => guardedGo(context, '/orders/pending'),
      pendingLabel: 'Enviando a Cotizaciones...',
      successMessage: 'Orden enviada a Cotizaciones.',
      errorContext: 'PendingOrderApprovalScreen.approve',
      action: () => ref.read(purchaseOrderRepositoryProvider).transitionStatus(
            order: order,
            targetStatus: PurchaseOrderStatus.cotizaciones,
            actor: actor,
            comprasReviewerName: reviewerName,
            comprasReviewerArea: reviewerArea,
          ),
    );

    if (mounted) {
      setState(() {
        _isSubmitting = false;
        _frozenPdfData = null;
      });
    }
  }

  OrderPdfData _buildPdfData(PurchaseOrder order) {
    final branding = ref.read(currentBrandingProvider);
    final actor = ref.read(currentUserProfileProvider).value;
    final reviewerName = (order.comprasReviewerName ?? '').trim().isEmpty
        ? actor?.name
        : order.comprasReviewerName;
    final reviewerArea = (order.comprasReviewerArea ?? '').trim().isEmpty
        ? actor?.areaDisplay
        : order.comprasReviewerArea;
    return buildPdfDataFromOrder(
      order,
      branding: branding,
      comprasReviewerName: reviewerName,
      comprasReviewerArea: reviewerArea,
      resubmissionDates: const [],
    );
  }

  Future<bool> _confirmSendToCotizaciones(String name, String area) async {
    final trimmedName = name.trim().isEmpty ? 'Tu nombre' : name.trim();
    final trimmedArea = area.trim().isEmpty ? 'Tu area' : area.trim();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enviar a Cotizaciones'),
        content: Text(
          'En el PDF, la casilla AUTORIZÓ mostrara "$trimmedName" y el area "$trimmedArea".',
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

class _PendingApprovalPdfBody extends ConsumerWidget {
  const _PendingApprovalPdfBody({
    required this.order,
    required this.isSubmitting,
    required this.frozenPdfData,
    super.key,
  });

  final PurchaseOrder order;
  final bool isSubmitting;
  final OrderPdfData? frozenPdfData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(currentBrandingProvider);
    final actor = ref.watch(currentUserProfileProvider).value;
    final reviewerName = (order.comprasReviewerName ?? '').trim().isEmpty
        ? actor?.name
        : order.comprasReviewerName;
    final reviewerArea = (order.comprasReviewerArea ?? '').trim().isEmpty
        ? actor?.areaDisplay
        : order.comprasReviewerArea;
    final computedPdfData = buildPdfDataFromOrder(
      order,
      branding: branding,
      comprasReviewerName: reviewerName,
      comprasReviewerArea: reviewerArea,
    );
    final pdfData =
        isSubmitting && frozenPdfData != null ? frozenPdfData! : computedPdfData;
    return OrderPdfInlineView(data: pdfData);
  }
}
