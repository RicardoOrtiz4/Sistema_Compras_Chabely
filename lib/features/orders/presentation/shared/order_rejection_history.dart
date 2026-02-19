import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/features/orders/application/create_order_controller.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_inline_view.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';

class OrderRejectionHistory extends ConsumerWidget {
  const OrderRejectionHistory({
    required this.order,
    required this.events,
    this.hideLatestResubmission = false,
    this.showOnlyOriginal = false,
    this.showOriginalWithReturns = false,
    super.key,
  });

  final PurchaseOrder order;
  final List<PurchaseOrderEvent> events;
  final bool hideLatestResubmission;
  final bool showOnlyOriginal;
  final bool showOriginalWithReturns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = _buildEntries(
      order,
      events,
      hideLatestResubmission: hideLatestResubmission,
      showOnlyOriginal: showOnlyOriginal,
      showOriginalWithReturns: showOriginalWithReturns,
    );

    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    final branding = ref.read(currentBrandingProvider);

    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('Historial de cambios')),
          for (final entry in entries)
            ListTile(
              title: Text(entry.title),
              trailing: const Icon(Icons.picture_as_pdf_outlined),
              onTap: () => _openPdf(context, branding, order, entry),
            ),
        ],
      ),
    );
  }

  void _openPdf(
    BuildContext context,
    CompanyBranding branding,
    PurchaseOrder order,
    _HistoryEntry entry,
  ) {
    final hideComprasData = _shouldHideComprasData(entry.event);
    final showComprasSignature = _shouldShowComprasSignature(entry.event.toStatus);
    final showDireccionSignature = _shouldShowDireccionSignature(entry.event.toStatus);

    final snapshotItems = entry.items.isEmpty ? order.items : entry.items;
    final mappedItems = snapshotItems.map(OrderItemDraft.fromModel).toList();

    final createdAt = order.createdAt;
    final updatedAt =
        entry.isOriginalSubmission ? createdAt : entry.event.timestamp;

    final pdfData = buildPdfDataFromOrder(
      order,
      branding: branding,
      supplier: hideComprasData ? '' : null,
      internalOrder: hideComprasData ? '' : null,
      comprasComment: hideComprasData ? '' : null,
      comprasReviewerName: showComprasSignature ? null : '',
      comprasReviewerArea: showComprasSignature ? null : '',
      direccionGeneralName: showDireccionSignature ? null : '',
      direccionGeneralArea: showDireccionSignature ? null : '',
      items: mappedItems,
      createdAt: createdAt,
      updatedAt: updatedAt,
      resubmissionDates: entry.resubmissionDates,
      hideBudget: hideComprasData,
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _OrderHistoryPdfScreen(title: entry.title, data: pdfData),
      ),
    );
  }
}

class _HistoryEntry {
  _HistoryEntry({
    required this.title,
    required this.event,
    required this.items,
    required this.resubmissionDates,
    required this.isOriginalSubmission,
  });

  final String title;
  final PurchaseOrderEvent event;
  final List<PurchaseOrderItem> items;
  final List<DateTime> resubmissionDates;
  final bool isOriginalSubmission;
}

class _OrderHistoryPdfScreen extends StatelessWidget {
  const _OrderHistoryPdfScreen({required this.title, required this.data});

  final String title;
  final OrderPdfData data;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: OrderPdfInlineView(data: data),
    );
  }
}

List<_HistoryEntry> _buildEntries(
  PurchaseOrder order,
  List<PurchaseOrderEvent> events, {
  bool hideLatestResubmission = false,
  bool showOnlyOriginal = false,
  bool showOriginalWithReturns = false,
}) {
  final sorted = [...events];
  sorted.sort((a, b) {
    final aTime = a.timestamp?.millisecondsSinceEpoch ?? 0;
    final bTime = b.timestamp?.millisecondsSinceEpoch ?? 0;
    return aTime.compareTo(bTime);
  });

  PurchaseOrderEvent? originalEvent;
  for (final event in sorted) {
    if (_isSubmissionEvent(event)) {
      originalEvent = event;
      break;
    }
  }

  if (showOnlyOriginal) {
    if (originalEvent == null) return const [];
    final title = _titleForEvent(
      originalEvent,
      submissionCount: 0,
      returnCount: 0,
    );
    if (title == null) return const [];
    return [
      _HistoryEntry(
        title: title,
        event: originalEvent,
        items: originalEvent.itemsSnapshot,
        resubmissionDates: const [],
        isOriginalSubmission: true,
      ),
    ];
  }

  if (showOriginalWithReturns && originalEvent == null) {
    return const [];
  }

  final submissionEvents =
      sorted.where(_isSubmissionEvent).toList(growable: false);

  final skipSubmissionId = hideLatestResubmission && submissionEvents.length > 1
      ? submissionEvents.last.id
      : null;

  var submissionCount = 0;
  var returnCount = 0;
  final entries = <_HistoryEntry>[];

  for (final event in sorted) {
    final isSubmission = _isSubmissionEvent(event);
    final isReturn = _isReturnEvent(event);

    final includeEvent = showOriginalWithReturns
        ? (event.id == originalEvent!.id || isReturn)
        : true;

    if (skipSubmissionId != null && event.id == skipSubmissionId) {
      if (isSubmission) {
        submissionCount += 1;
      } else if (isReturn) {
        returnCount += 1;
      }
      continue;
    }

    if (!includeEvent) {
      if (isSubmission) {
        submissionCount += 1;
      } else if (isReturn) {
        returnCount += 1;
      }
      continue;
    }

    final title = _titleForEvent(
      event,
      submissionCount: submissionCount,
      returnCount: returnCount,
    );
    if (title == null) continue;

    final resubmissionDates = _resubmissionDatesForEntry(
      order,
      event,
      submissionCount,
    );

    final isOriginalSubmission = isSubmission && submissionCount == 0;

    if (isSubmission) {
      submissionCount += 1;
    } else if (isReturn) {
      returnCount += 1;
    }

    entries.add(
      _HistoryEntry(
        title: title,
        event: event,
        items: event.itemsSnapshot,
        resubmissionDates: resubmissionDates,
        isOriginalSubmission: isOriginalSubmission,
      ),
    );
  }

  return entries;
}

bool _isSubmissionEvent(PurchaseOrderEvent event) {
  return event.type == 'advance' &&
      event.fromStatus == PurchaseOrderStatus.draft &&
      event.toStatus == PurchaseOrderStatus.pendingCompras;
}

bool _isReturnEvent(PurchaseOrderEvent event) => event.type == 'return';

List<DateTime> _resubmissionDatesForEntry(
  PurchaseOrder order,
  PurchaseOrderEvent event,
  int submissionCount,
) {
  final totalResubmissions = _isSubmissionEvent(event)
      ? submissionCount
      : submissionCount > 0
          ? submissionCount - 1
          : 0;

  if (totalResubmissions <= 0 || order.resubmissionDates.isEmpty) {
    return const [];
  }

  return order.resubmissionDates.take(totalResubmissions).toList();
}

String? _titleForEvent(
  PurchaseOrderEvent event, {
  required int submissionCount,
  required int returnCount,
}) {
  final toStatus = event.toStatus;
  if (toStatus == null) return null;

  if (_isSubmissionEvent(event)) {
    final next = submissionCount + 1;
    return next == 1 ? 'Orden original' : 'Reenvío ${next - 1}';
  }

  if (_isReturnEvent(event)) {
    final next = returnCount + 1;
    if (toStatus == PurchaseOrderStatus.pendingCompras) {
      return 'Rechazo $next (Regreso a Compras)';
    }
    if (toStatus == PurchaseOrderStatus.draft) {
      return 'Rechazo $next (Regreso a Solicitante)';
    }
    return 'Rechazo $next';
  }

  if (event.type == 'advance' && toStatus == PurchaseOrderStatus.cotizaciones) {
    return 'Autorizada por Compras';
  }

  if (event.type == 'advance' &&
      toStatus == PurchaseOrderStatus.authorizedGerencia) {
    return 'Después de Cotizaciones';
  }

  if (event.type == 'advance') {
    return 'Estado: ${toStatus.label}';
  }

  return null;
}

bool _shouldHideComprasData(PurchaseOrderEvent event) {
  return event.type == 'advance' &&
      (event.toStatus == PurchaseOrderStatus.pendingCompras ||
          event.toStatus == PurchaseOrderStatus.cotizaciones);
}

bool _shouldShowComprasSignature(PurchaseOrderStatus? status) {
  if (status == null) return false;
  final index = defaultStatusFlow.indexOf(status);
  final comprasIndex = defaultStatusFlow.indexOf(PurchaseOrderStatus.cotizaciones);
  return index >= comprasIndex;
}

bool _shouldShowDireccionSignature(PurchaseOrderStatus? status) {
  if (status == null) return false;
  final index = defaultStatusFlow.indexOf(status);
  final direccionIndex = defaultStatusFlow.indexOf(PurchaseOrderStatus.paymentDone);
  return index >= direccionIndex;
}
