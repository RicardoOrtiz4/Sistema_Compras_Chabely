import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
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
        actions: [
          IconButton(
            onPressed: _downloadingPdf
                ? null
                : () => _downloadPreviewPdf(controller, userAsync.value),
            tooltip: 'Descargar PDF',
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

          final modificationDate =
              controller.returnCount > 0 && hasEdits
                  ? controller.previewUpdatedAt
                  : null;
          final requiresPreviewAcceptance =
              controller.returnCount > 0 && hasEdits && hasScheduleChange;
          final hasAcceptedPreview =
              !requiresPreviewAcceptance || controller.previewAccepted;

          final submitLabel =
              folio == null ? 'Enviar a revisión' : 'Reenviar a revisión';

          final maxCorrectionsReached =
              controller.returnCount >= _maxCorrections;

          final isLastAttempt = controller.returnCount == _maxCorrections - 1;

          return Column(
            children: [
              if (folio == null)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text('Folio pendiente. Se asignará al enviar.'),
                ),
              if (isLastAttempt && !maxCorrectionsReached)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _LastAttemptWarning(draftId: controller.draftId),
                ),
              if (maxCorrectionsReached)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    'Máximo de correcciones alcanzado. Crea otra requisición.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
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
              if (requiresPreviewAcceptance)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasAcceptedPreview
                            ? 'PDF aceptado. El reenvio pendiente ya se refleja en el documento. La hora se registrara cuando reenvies la orden.'
                            : 'El reenvio pendiente ya se refleja en el PDF. Acepta este PDF para continuar; la hora quedara registrada hasta que reenvies la orden.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: hasAcceptedPreview
                              ? null
                              : () => ref
                                  .read(createOrderControllerProvider.notifier)
                                  .acceptPreview(),
                          icon: const Icon(Icons.verified_outlined),
                          label: Text(
                            hasAcceptedPreview
                                ? 'PDF aceptado'
                                : 'Aceptar PDF',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                    child: FilledButton(
                    onPressed: controller.isSubmitting ||
                            maxCorrectionsReached ||
                            !hasScheduleChange ||
                            !hasAcceptedPreview
                        ? null
                        : () async {
                            if (controller.returnCount > 0) {
                              final confirmed = await _confirmResubmission(
                                context,
                                hasEdits: hasEdits,
                              );
                              if (confirmed != true) return;
                            }
                            final orderId = await ref
                                .read(createOrderControllerProvider.notifier)
                                .submit();
                            if (orderId != null) {
                              unawaited(_warmPendingCache(orderId));
                              if (!mounted) return;
                              if (controller.returnCount > 0) {
                                _returnToRejectedOrders(context);
                              } else {
                                final navigator = Navigator.of(context);
                                if (navigator.canPop()) {
                                  navigator.pop();
                                } else {
                                  context.go('/orders/create');
                                }
                              }
                            }
                          },
                    child: controller.isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: AppSplash(compact: true, size: 20),
                          )
                        : Text(
                            maxCorrectionsReached
                                ? 'Requiere nueva requisición'
                                : submitLabel,
                          ),
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
      PurchaseOrder? order;
      for (var attempt = 0; attempt < 2; attempt++) {
        order = await repo.fetchOrderById(orderId);
        if (order != null && order.createdAt != null) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (order == null) return;

      final branding = ref.read(currentBrandingProvider);
      prefetchOrderPdfsForOrders([order], branding: branding, limit: 1);
    } catch (error, stack) {
      logError(error, stack, context: 'OrderPdfPreviewScreen.warmCache');
    }
  }

  Future<void> _downloadPreviewPdf(
    CreateOrderState controller,
    AppUser? user,
  ) async {
    if (_downloadingPdf || user == null) return;
    setState(() => _downloadingPdf = true);
    try {
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
      final modificationDate =
          controller.returnCount > 0 && hasEdits ? controller.previewUpdatedAt : null;
      final requiresPreviewAcceptance =
          controller.returnCount > 0 && hasEdits && hasScheduleChange;
      final hasAcceptedPreview =
          !requiresPreviewAcceptance || controller.previewAccepted;
      final branding = ref.read(currentBrandingProvider);
      final isNewOrderPreview = folio == null && controller.returnCount <= 0;
      final pdfData = OrderPdfData(
        branding: branding,
        folio: folio ?? '',
        requesterName: user.name,
        requesterArea: user.areaDisplay,
        areaName: user.areaDisplay,
        urgency: controller.urgency,
        items: controller.items,
        createdAt: controller.previewCreatedAt ?? DateTime.now(),
        updatedAt: modificationDate,
        observations: controller.notes,
        urgentJustification: controller.urgentJustification,
        requestedDeliveryDate: controller.requestedDeliveryDate,
        pendingResubmissionLabel: _pendingResubmissionLabel(
          controller,
          modificationDate: modificationDate,
        ),
        suppressCreatedTime: isNewOrderPreview,
        resubmissionDates: controller.resubmissionDates,
        cacheSalt: hasAcceptedPreview ? null : 'preview-pending',
      );
      final bytes = await buildOrderPdf(pdfData, useIsolate: false);
      if (!mounted) return;
      await savePdfBytes(
        context,
        bytes: bytes,
        suggestedName: 'requisicion_${folio ?? 'borrador'}.pdf',
      );
    } finally {
      if (mounted) {
        setState(() => _downloadingPdf = false);
      }
    }
  }
}

void _returnToRejectedOrders(BuildContext context) {
  final navigator = Navigator.of(context);
  var foundRejectedRoute = false;
  navigator.popUntil((route) {
    if (route.settings.name == 'rejectedOrders') {
      foundRejectedRoute = true;
      return true;
    }
    return false;
  });
  if (!foundRejectedRoute) {
    context.go('/orders/rejected');
  }
}

String? _folioFromDraft(String? draftId) {
  return normalizeFolio(draftId);
}

String _lastAttemptMessage(String? contactArea) {
  final area = contactArea?.trim().isNotEmpty == true
      ? contactArea!.trim()
      : 'Compras';
  return 'Advertencia: este es el último intento para enviar la requisición. '
      'Antes de enviarla, contacta a $area.';
}

class _LastAttemptWarning extends ConsumerWidget {
  const _LastAttemptWarning({required this.draftId});

  final String? draftId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = _lastReturnContact(ref, draftId);
    return Text(
      _lastAttemptMessage(contact),
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.error),
    );
  }
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
    final isNewOrderPreview = folio == null && controller.returnCount <= 0;
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
      pendingResubmissionLabel: _pendingResubmissionLabel(
        controller,
        modificationDate: modificationDate,
      ),
      suppressCreatedTime: isNewOrderPreview,
      resubmissionDates: controller.resubmissionDates,
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
    ..write(body.controller.returnCount)
    ..write('|')
    ..write(
      _pendingResubmissionLabel(
            body.controller,
            modificationDate: body.modificationDate,
          ) ??
          '',
    )
    ..write('|')
    ..write(body.controller.previewCreatedAt?.millisecondsSinceEpoch ?? 0)
    ..write('|')
    ..write(body.modificationDate?.millisecondsSinceEpoch ?? 0);
  for (final date in body.controller.resubmissionDates) {
    buffer
      ..write('|')
      ..write(date.millisecondsSinceEpoch);
  }
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

String? _pendingResubmissionLabel(
  CreateOrderState controller, {
  required DateTime? modificationDate,
}) {
  final returnCount = controller.returnCount;
  if (returnCount <= 0 || modificationDate == null) return null;
  final dateText = DateFormat('dd/MM/yyyy').format(modificationDate);
  return 'REENVIO $returnCount: $dateText';
}

String _lastReturnContact(WidgetRef ref, String? draftId) {
  if (draftId == null || draftId.trim().isEmpty) return 'Compras';
  final eventsAsync = ref.watch(orderEventsProvider(draftId));
  return eventsAsync.maybeWhen(
    data: (events) {
      PurchaseOrderEvent? lastReturn;
      for (final event in events) {
        if (event.type == 'return') {
          lastReturn = event;
        }
      }
      return _contactLabel(lastReturn?.byRole);
    },
    orElse: () => 'Compras',
  );
}

String _contactLabel(String? rawRole) {
  final normalized = normalizeAreaLabel((rawRole ?? '').trim());
  if (normalized.isEmpty) return 'Compras';
  if (isDireccionGeneralLabel(normalized)) return 'Dirección General';
  if (isComprasLabel(normalized)) return 'Compras';
  return normalized;
}

const int _maxCorrections = 3;

Future<bool?> _confirmResubmission(
  BuildContext context, {
  required bool hasEdits,
}) {
  final warning = hasEdits
      ? ''
      : '\n\nNo detectamos cambios en la orden. '
          'Es posible que la vuelvan a rechazar.';
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Confirmar reenvío'),
      content: Text(
        'Esta orden regresará a órdenes por confirmar. ¿Deseas continuar?$warning',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Reenviar'),
        ),
      ],
    ),
  );
}
