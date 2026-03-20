import 'package:flutter/material.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/navigation_guard.dart';
import 'package:sistema_compras/features/orders/application/create_order_controller.dart';
import 'package:sistema_compras/features/orders/domain/order_event_labels.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_inline_view.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';

class OrderRejectionHistory extends StatelessWidget {
  const OrderRejectionHistory({
    required this.branding,
    required this.order,
    required this.events,
    this.hideLatestResubmission = false,
    this.showOnlyOriginal = false,
    this.showOriginalWithReturns = false,
    super.key,
  });

  final CompanyBranding branding;
  final PurchaseOrder order;
  final List<PurchaseOrderEvent> events;
  final bool hideLatestResubmission;
  final bool showOnlyOriginal;
  final bool showOriginalWithReturns;

  @override
  Widget build(BuildContext context) {
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

    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade50,
              border: Border(
                bottom: BorderSide(color: Colors.blueGrey.shade100),
              ),
            ),
            child: const Text(
              'Historial de cambios',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
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

    runGuardedPdfNavigation<void>(
      'order-history-pdf:${order.id}:${entry.title}',
      () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _OrderHistoryPdfScreen(title: entry.title, data: pdfData),
        ),
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
      appBar: AppBar(
        title: Text(title),
      ),
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
  final sorted = _eventsSortedByTime(events);
  final itemsSignatureCache = <List<PurchaseOrderItem>, String>{};
  String itemsSignatureFor(List<PurchaseOrderItem> items) {
    final cached = itemsSignatureCache[items];
    if (cached != null) return cached;
    final computed = _itemsSignature(items);
    itemsSignatureCache[items] = computed;
    return computed;
  }

  PurchaseOrderEvent? originalEvent;
  for (final event in sorted) {
    if (_isSubmissionEvent(event)) {
      originalEvent = event;
      break;
    }
  }

  if (showOnlyOriginal) {
    final hasReturns = sorted.any(_isReturnEvent);
    if (!hasReturns) return const [];
    if (originalEvent == null) return const [];
    PurchaseOrderEvent? firstReturnEvent;
    for (final event in sorted) {
      if (_isReturnEvent(event)) {
        firstReturnEvent = event;
        break;
      }
    }
    final title = _titleForEvent(
      originalEvent,
      submissionCount: 0,
      returnCount: 0,
    );
    if (title == null) return const [];
    return [
      _HistoryEntry(
        title: _appendRejectionStage(title, firstReturnEvent),
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
  final hasReturns = sorted.any(_isReturnEvent);

  final skipSubmissionId = hideLatestResubmission && submissionEvents.length > 1
      ? submissionEvents.last.id
      : null;

  var submissionCount = 0;
  var returnCount = 0;
  final entries = <_HistoryEntry>[];
  String? lastIncludedItemsSignature;
  final baseItemsSignature = itemsSignatureFor(order.items);
  final originalItemsSignature = showOriginalWithReturns && originalEvent != null
      ? (originalEvent.itemsSnapshot.isNotEmpty
          ? itemsSignatureFor(originalEvent.itemsSnapshot)
          : baseItemsSignature)
      : null;

  for (final event in sorted) {
    final isSubmission = _isSubmissionEvent(event);
    final isReturn = _isReturnEvent(event);

    final includeEvent = showOriginalWithReturns
        ? (isReturn || (!hasReturns && event.id == originalEvent!.id))
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

    if (showOriginalWithReturns && isReturn) {
      final candidate = event.itemsSnapshot.isNotEmpty
          ? itemsSignatureFor(event.itemsSnapshot)
          : baseItemsSignature;
      final compareWith = lastIncludedItemsSignature ?? originalItemsSignature;
      if (compareWith != null && candidate == compareWith) {
        continue;
      }
    }

    var title = _titleForEvent(
      event,
      submissionCount: submissionCount,
      returnCount: returnCount,
    );
    if (title == null) continue;
    if (showOriginalWithReturns && isReturn && returnCount == 0) {
      title = _appendRejectionStage('Orden original', event);
    }

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

    lastIncludedItemsSignature = event.itemsSnapshot.isNotEmpty
        ? itemsSignatureFor(event.itemsSnapshot)
        : baseItemsSignature;
  }

  return entries;
}

List<PurchaseOrderEvent> _eventsSortedByTime(List<PurchaseOrderEvent> events) {
  if (events.length < 2) return events;

  var previous = events.first.timestamp?.millisecondsSinceEpoch ?? 0;
  for (var index = 1; index < events.length; index++) {
    final current = events[index].timestamp?.millisecondsSinceEpoch ?? 0;
    if (current < previous) {
      final sorted = [...events];
      sorted.sort((a, b) {
        final aTime = a.timestamp?.millisecondsSinceEpoch ?? 0;
        final bTime = b.timestamp?.millisecondsSinceEpoch ?? 0;
        return aTime.compareTo(bTime);
      });
      return sorted;
    }
    previous = current;
  }

  return events;
}

bool _isSubmissionEvent(PurchaseOrderEvent event) {
  return event.type == 'advance' &&
      event.fromStatus == PurchaseOrderStatus.draft &&
      event.toStatus == PurchaseOrderStatus.pendingCompras;
}

bool _isReturnEvent(PurchaseOrderEvent event) => event.type == 'return';

String _itemsSignature(List<PurchaseOrderItem> items) {
  if (items.isEmpty) return '';
  final sorted = [...items]..sort((a, b) => a.line.compareTo(b.line));
  final buffer = StringBuffer();
  for (final item in sorted) {
    buffer
      ..write(item.line)
      ..write('|')
      ..write(item.pieces)
      ..write('|')
      ..write(item.partNumber)
      ..write('|')
      ..write(item.description)
      ..write('|')
      ..write(item.quantity)
      ..write('|')
      ..write(item.unit)
      ..write('|')
      ..write(item.customer ?? '')
      ..write('|')
      ..write(item.supplier ?? '')
      ..write('|')
      ..write(item.budget?.toString() ?? '')
      ..write('|')
      ..write(item.estimatedDate?.millisecondsSinceEpoch.toString() ?? '')
      ..write('|')
      ..write(item.reviewFlagged)
      ..write('|')
      ..write(item.reviewComment ?? '')
      ..write(';');
  }
  return buffer.toString();
}

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
    return next == 1 ? 'Orden original' : 'Reenvio ${next - 1}';
  }

  if (_isReturnEvent(event)) {
    final next = returnCount + 1;
    return 'Regreso $next';
  }

  switch (toStatus) {
    case PurchaseOrderStatus.pendingCompras:
      return 'Enviada a Compras';
    case PurchaseOrderStatus.cotizaciones:
      return 'Enviada a Cotizaciones';
    case PurchaseOrderStatus.dataComplete:
      return 'Datos completos';
    case PurchaseOrderStatus.authorizedGerencia:
      return 'Enviada a Direccion General';
    case PurchaseOrderStatus.paymentDone:
      return 'En proceso';
    case PurchaseOrderStatus.contabilidad:
      return 'Enviada a Contabilidad';
    case PurchaseOrderStatus.orderPlaced:
      return 'Orden realizada';
    case PurchaseOrderStatus.eta:
      return 'Orden finalizada';
    case PurchaseOrderStatus.draft:
      return 'Solicitante';
  }
}

String _appendRejectionStage(
  String title,
  PurchaseOrderEvent? event,
) {
  final stage = _rejectionStageLabel(event);
  if (stage == null || stage.isEmpty) return title;
  return '$title - $stage';
}

String? _rejectionStageLabel(PurchaseOrderEvent? event) {
  final status = event?.fromStatus;
  if (status == null) return null;

  switch (status) {
    case PurchaseOrderStatus.pendingCompras:
      return returnStageLabel(status);
    case PurchaseOrderStatus.cotizaciones:
      return returnStageLabel(status);
    case PurchaseOrderStatus.dataComplete:
      return returnStageLabel(status);
    case PurchaseOrderStatus.authorizedGerencia:
      return returnStageLabel(status);
    case PurchaseOrderStatus.paymentDone:
      return returnStageLabel(status);
    case PurchaseOrderStatus.contabilidad:
      return returnStageLabel(status);
    case PurchaseOrderStatus.orderPlaced:
      return returnStageLabel(status);
    case PurchaseOrderStatus.eta:
      return returnStageLabel(status);
    case PurchaseOrderStatus.draft:
      return returnStageLabel(status);
  }
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

