import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/create_order_controller.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/order_folio.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_inline_view.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

class OrderPdfPreviewScreen extends ConsumerStatefulWidget {
  const OrderPdfPreviewScreen({super.key});

  @override
  ConsumerState<OrderPdfPreviewScreen> createState() =>
      _OrderPdfPreviewScreenState();
}

class _OrderPdfPreviewScreenState extends ConsumerState<OrderPdfPreviewScreen> {
  ScaffoldMessengerState? _messenger;
  GoRouter? _router;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
    _router = GoRouter.of(context);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(createOrderControllerProvider);

    ref.listen(createOrderControllerProvider, (previous, next) {
      if (!mounted) return;

      if (previous?.message != next.message && next.message != null) {
        _messenger?.showSnackBar(SnackBar(content: Text(next.message!)));
        if (next.message == 'Orden enviada a Compras') {
          _router?.go('/home');
        }
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

    final userAsync = ref.watch(currentUserProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Previsualizar PDF')),
      body: userAsync.when(
        data: (user) {
          if (user == null) {
            return const AppSplash();
          }

          final folio = _folioFromDraft(controller.draftId);
          final requestedDate = _requestedDeliveryDate(controller.items);
          final branding = ref.watch(currentBrandingProvider);

          final modificationDate =
              controller.returnCount > 0 ? DateTime.now() : null;

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
            requestedDeliveryDate: requestedDate,
            resubmissionDates: controller.resubmissionDates,
          );

          final submitLabel =
              folio == null ? 'Enviar a revisión' : 'Reenviar a revisión';

          final maxCorrectionsReached =
              controller.returnCount >= _maxCorrections;

          final isLastAttempt = controller.returnCount == _maxCorrections - 1;
          final lastAttemptContact = isLastAttempt
              ? _lastReturnContact(ref, controller.draftId)
              : null;

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
                  child: Text(
                    _lastAttemptMessage(lastAttemptContact),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              if (maxCorrectionsReached)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    'Máximo de correcciones alcanzado. Crea otra requisición.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Expanded(child: OrderPdfInlineView(data: pdfData)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: controller.isSubmitting || maxCorrectionsReached
                        ? null
                        : () async {
                            await ref
                                .read(createOrderControllerProvider.notifier)
                                .submit();
                          },
                    child: controller.isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
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

DateTime? _requestedDeliveryDate(List<OrderItemDraft> items) {
  DateTime? selected;
  for (final item in items) {
    final date = item.estimatedDate;
    if (date == null) continue;
    if (selected == null || date.isBefore(selected)) {
      selected = date;
    }
  }
  return selected;
}

const int _maxCorrections = 3;
