import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/navigation_guard.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/create_order_controller.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/order_folio.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_inline_view.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';
import 'package:sistema_compras/features/orders/presentation/preview/pdf_download_helper.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

class OrderPdfPreviewScreen extends ConsumerStatefulWidget {
  const OrderPdfPreviewScreen({super.key});

  @override
  ConsumerState<OrderPdfPreviewScreen> createState() =>
      _OrderPdfPreviewScreenState();
}

class _OrderPdfPreviewScreenState extends ConsumerState<OrderPdfPreviewScreen> {
  ScaffoldMessengerState? _messenger;
  ProviderSubscription<CreateOrderState>? _controllerSubscription;
  bool _downloadingPdf = false;

  @override
  void initState() {
    super.initState();
    _controllerSubscription =
        ref.listenManual<CreateOrderState>(createOrderControllerProvider, (
      previous,
      next,
    ) {
      if (!mounted) return;

      if (previous?.message != next.message && next.message != null) {
        _messenger?.showSnackBar(SnackBar(content: Text(next.message!)));
      }

      if (previous?.error != next.error && next.error != null) {
        final message = reportError(
          next.error!,
          StackTrace.current,
          context: 'OrderPdfPreviewScreen',
        );
        _messenger?.showSnackBar(SnackBar(content: Text(message)));
      }
    });
  }

  @override
  void dispose() {
    _controllerSubscription?.close();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(createOrderControllerProvider);

    final userAsync = ref.watch(currentUserProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisar PDF'),
        actions: userAsync.valueOrNull == null
            ? null
            : [
                IconButton(
                  tooltip: 'Descargar PDF',
                  onPressed: _downloadingPdf
                      ? null
                      : () => _downloadDraftPdf(
                            userName: userAsync.valueOrNull!.name,
                            userArea: userAsync.valueOrNull!.areaDisplay,
                            controller: controller,
                          ),
                  icon: _downloadingPdf
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined),
                ),
              ],
      ),
      body: userAsync.when(
        data: (user) {
          if (user == null) {
            return const AppSplash();
          }

          final folio = _folioFromDraft(controller.draftId);
          final baselineSignature = controller.baselineSignature;
          final currentSignature = buildCreateOrderSignature(
            urgency: controller.urgency,
            requestedDeliveryDate: controller.requestedDeliveryDate,
            notes: controller.notes,
            urgentJustification: controller.urgentJustification,
            items: controller.items,
          );
          final hasEdits = baselineSignature == null
              ? true
              : baselineSignature != currentSignature;
          final hasScheduleChange = controller.hasScheduleChange;

          final modificationDate = hasEdits ? controller.previewUpdatedAt : null;
          const hasAcceptedPreview = true;
          const submitLabel = 'Enviar orden';

          return Column(
            children: [
              if (folio == null)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text('Folio pendiente. Se asignará al enviar.'),
                ),
              Expanded(
                child: _PersistentDraftPdfBody(
                  controller: controller,
                  userName: user.name,
                  userArea: user.areaDisplay,
                  folio: folio,
                  modificationDate: modificationDate,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                    child: FilledButton(
                    onPressed: controller.isSubmitting ||
                            !hasScheduleChange ||
                            !hasAcceptedPreview
                        ? null
                        : () async {
                            final orderId = await ref
                                .read(createOrderControllerProvider.notifier)
                                .submit();
                            if (orderId != null) {
                              refreshOrderModuleData(
                                ref,
                                orderIds: <String>[orderId],
                              );
                              if (!useManualOrderRefreshOnWindowsRelease) {
                                unawaited(_warmPendingCache(orderId));
                              }
                              if (!mounted) return;
                              guardedGo(context, '/home');
                            }
                          },
                    child: controller.isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: AppSplash(compact: true, size: 20),
                          )
                        : const Text(submitLabel),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            'Error: ${reportError(error, stack, context: 'OrderPdfPreviewScreen')}',
          ),
        ),
      ),
    );
  }

  Future<void> _warmPendingCache(String orderId) async {
    try {
      final repo = ref.read(purchaseOrderRepositoryProvider);
      final branding = ref.read(currentBrandingProvider);
      PurchaseOrder? order;
      for (var attempt = 0; attempt < 2; attempt++) {
        order = await repo.fetchOrderById(orderId);
        if (order != null && order.createdAt != null) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (order == null) return;

      prefetchOrderPdfsForOrders([order], branding: branding, limit: 1);
    } catch (error, stack) {
      logError(error, stack, context: 'OrderPdfPreviewScreen.warmCache');
    }
  }

  Future<void> _downloadDraftPdf({
    required String userName,
    required String userArea,
    required CreateOrderState controller,
  }) async {
    if (_downloadingPdf) return;
    setState(() => _downloadingPdf = true);
    try {
      final branding = ref.read(currentBrandingProvider);
      final folio = _folioFromDraft(controller.draftId);
      final pdfData = OrderPdfData(
        branding: branding,
        folio: folio ?? '',
        requesterName: userName,
        requesterArea: userArea,
        areaName: userArea,
        urgency: controller.urgency,
        items: controller.items,
        createdAt: controller.previewCreatedAt ?? DateTime.now(),
        updatedAt: controller.previewUpdatedAt,
        observations: controller.notes,
        urgentJustification: controller.urgentJustification,
        requestedDeliveryDate: controller.requestedDeliveryDate,
        suppressCreatedTime: folio == null,
      );
      final bytes = await buildOrderPdf(pdfData, useIsolate: false);
      if (!mounted) return;
      await savePdfBytes(
        context,
        bytes: bytes,
        suggestedName: '${folio ?? 'orden_borrador'}.pdf',
      );
    } finally {
      if (mounted) {
        setState(() => _downloadingPdf = false);
      }
    }
  }

}


String? _folioFromDraft(String? draftId) {
  return normalizeFolio(draftId);
}

class _DraftPdfBody extends ConsumerWidget {
  const _DraftPdfBody({
    required this.controller,
    required this.userName,
    required this.userArea,
    required this.folio,
    required this.modificationDate,
  });

  final CreateOrderState controller;
  final String userName;
  final String userArea;
  final String? folio;
  final DateTime? modificationDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(currentBrandingProvider);
    final isNewOrderPreview = folio == null;
    final pdfData = OrderPdfData(
      branding: branding,
      folio: folio ?? '',
      requesterName: userName,
      requesterArea: userArea,
      areaName: userArea,
      urgency: controller.urgency,
      items: controller.items,
      createdAt: controller.previewCreatedAt ?? DateTime.now(),
      updatedAt: modificationDate,
      observations: controller.notes,
      urgentJustification: controller.urgentJustification,
      requestedDeliveryDate: controller.requestedDeliveryDate,
      suppressCreatedTime: isNewOrderPreview,
    );
    return OrderPdfInlineView(data: pdfData);
  }
}

class _PersistentDraftPdfBody extends ConsumerStatefulWidget {
  const _PersistentDraftPdfBody({
    required this.controller,
    required this.userName,
    required this.userArea,
    required this.folio,
    required this.modificationDate,
  });

  final CreateOrderState controller;
  final String userName;
  final String userArea;
  final String? folio;
  final DateTime? modificationDate;

  @override
  ConsumerState<_PersistentDraftPdfBody> createState() =>
      _PersistentDraftPdfBodyState();
}

class _PersistentDraftPdfBodyState
    extends ConsumerState<_PersistentDraftPdfBody> {
  String? _signature;
  Widget? _cachedChild;

  @override
  Widget build(BuildContext context) {
    final nextSignature = _pdfSignature(widget);
    if (_cachedChild == null || _signature != nextSignature) {
      _signature = nextSignature;
      _cachedChild = _DraftPdfBody(
        controller: widget.controller,
        userName: widget.userName,
        userArea: widget.userArea,
        folio: widget.folio,
        modificationDate: widget.modificationDate,
      );
    }
    return _cachedChild!;
  }

}
String _pdfSignature(_PersistentDraftPdfBody body) {
  final buffer = StringBuffer()
    ..write(body.folio ?? '')
    ..write('|')
    ..write(body.userName)
    ..write('|')
    ..write(body.userArea)
    ..write('|')
    ..write(body.controller.urgency.name)
    ..write('|')
    ..write(body.controller.requestedDeliveryDate?.millisecondsSinceEpoch ?? 0)
    ..write('|')
    ..write(body.controller.notes)
    ..write('|')
    ..write(body.controller.urgentJustification)
    ..write('|')
    ..write(body.controller.previewCreatedAt?.millisecondsSinceEpoch ?? 0)
    ..write('|')
    ..write(body.modificationDate?.millisecondsSinceEpoch ?? 0);
  for (final item in body.controller.items) {
    buffer
      ..write('|')
      ..write(item.line)
      ..write(':')
      ..write(item.pieces)
      ..write(':')
      ..write(item.partNumber)
      ..write(':')
      ..write(item.description)
      ..write(':')
      ..write(item.quantity)
      ..write(':')
      ..write(item.unit)
      ..write(':')
      ..write(item.customer ?? '')
      ..write(':')
      ..write(item.supplier ?? '')
      ..write(':')
      ..write(item.budget?.toString() ?? '')
      ..write(':')
      ..write(item.estimatedDate?.millisecondsSinceEpoch ?? 0)
      ..write(':')
      ..write(item.reviewFlagged ? 1 : 0)
      ..write(':')
      ..write(item.reviewComment ?? '');
  }
  return buffer.toString();
}

