import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/features/orders/domain/order_event_labels.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/domain/supplier_quote.dart';

final DateFormat _monitoringExportDateTime = DateFormat('dd/MM/yyyy HH:mm:ss');

class MonitoringStatusSnapshot {
  const MonitoringStatusSnapshot({
    required this.status,
    required this.count,
    required this.averageElapsed,
    required this.longestElapsed,
  });

  final PurchaseOrderStatus status;
  final int count;
  final Duration averageElapsed;
  final Duration longestElapsed;
}

bool isOperationalRejectedOrder(PurchaseOrder order) {
  final reason = order.lastReturnReason?.trim() ?? '';
  return order.status == PurchaseOrderStatus.draft &&
      (reason.isNotEmpty || order.returnCount > 0);
}

bool isMonitorableOrder(PurchaseOrder order) {
  if (!order.isDraft) return true;
  return isOperationalRejectedOrder(order);
}

Duration currentStatusElapsed(PurchaseOrder order, DateTime now) {
  final since = order.statusEnteredAt ?? order.updatedAt ?? order.createdAt;
  if (since == null) return Duration.zero;
  final diff = now.difference(since);
  return diff.isNegative ? Duration.zero : diff;
}

Duration accumulatedStatusElapsed(
  PurchaseOrder order,
  PurchaseOrderStatus status,
  DateTime now,
) {
  var total = Duration(milliseconds: order.statusDurations[status.name] ?? 0);
  if (order.status == status) {
    total += currentStatusElapsed(order, now);
  }
  return total;
}

List<MonitoringStatusSnapshot> buildMonitoringStatusSnapshots(
  List<PurchaseOrder> orders,
  DateTime now,
) {
  return [
    for (final status in PurchaseOrderStatus.values)
      _buildStatusSnapshot(orders, status, now),
  ];
}

MonitoringStatusSnapshot _buildStatusSnapshot(
  List<PurchaseOrder> orders,
  PurchaseOrderStatus status,
  DateTime now,
) {
  final matching = orders.where((order) => order.status == status).toList();
  if (matching.isEmpty) {
    return MonitoringStatusSnapshot(
      status: status,
      count: 0,
      averageElapsed: Duration.zero,
      longestElapsed: Duration.zero,
    );
  }
  var totalMs = 0;
  var max = Duration.zero;
  for (final order in matching) {
    final elapsed = currentStatusElapsed(order, now);
    totalMs += elapsed.inMilliseconds;
    if (elapsed > max) {
      max = elapsed;
    }
  }
  return MonitoringStatusSnapshot(
    status: status,
    count: matching.length,
    averageElapsed: Duration(milliseconds: totalMs ~/ matching.length),
    longestElapsed: max,
  );
}

PurchaseOrderEvent? latestEventForStatus(
  List<PurchaseOrderEvent> events,
  PurchaseOrderStatus status,
) {
  PurchaseOrderEvent? selected;
  for (final event in events) {
    if (event.toStatus != status) continue;
    if (selected == null) {
      selected = event;
      continue;
    }
    final currentMs = event.timestamp?.millisecondsSinceEpoch ?? 0;
    final selectedMs = selected.timestamp?.millisecondsSinceEpoch ?? 0;
    if (currentMs >= selectedMs) {
      selected = event;
    }
  }
  return selected;
}

List<PurchaseOrderEvent> newestEventsFirst(List<PurchaseOrderEvent> events) {
  final copy = [...events];
  copy.sort((a, b) {
    final aMs = a.timestamp?.millisecondsSinceEpoch ?? 0;
    final bMs = b.timestamp?.millisecondsSinceEpoch ?? 0;
    return bMs.compareTo(aMs);
  });
  return copy;
}

String formatMonitoringDuration(Duration duration) {
  if (duration <= Duration.zero) return '0 s';
  final days = duration.inDays;
  final hours = duration.inHours % 24;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  if (days > 0) {
    return '$days d $hours h $minutes min $seconds s';
  }
  if (hours > 0) {
    return '${duration.inHours} h $minutes min $seconds s';
  }
  if (minutes > 0) {
    return '$minutes min $seconds s';
  }
  return '${duration.inSeconds} s';
}

String buildMonitoringActorSummary(PurchaseOrder order) {
  final parts = <String>[];
  _appendActor(parts, 'Solicita', order.requesterName, order.areaName);
  _appendActor(
    parts,
    'Compras',
    order.comprasReviewerName,
    order.comprasReviewerArea,
  );
  _appendActor(
    parts,
    'Aut. pago',
    order.direccionGeneralName,
    order.direccionGeneralArea,
  );
  _appendActor(
    parts,
    'Contabilidad',
    order.contabilidadName,
    order.contabilidadArea,
  );
  return parts.isEmpty ? 'Sin firmas registradas' : parts.join(' | ');
}

void _appendActor(
  List<String> target,
  String label,
  String? name,
  String? area,
) {
  final actor = describeActor(name, area);
  if (actor == null) return;
  target.add('$label: $actor');
}

String? describeActor(String? name, String? area) {
  final trimmedName = name?.trim() ?? '';
  final trimmedArea = area?.trim() ?? '';
  if (trimmedName.isEmpty && trimmedArea.isEmpty) return null;
  if (trimmedName.isEmpty) return trimmedArea;
  if (trimmedArea.isEmpty) return trimmedName;
  return '$trimmedName ($trimmedArea)';
}

class _MonitoringTimelineEntry {
  const _MonitoringTimelineEntry({
    required this.timestamp,
    required this.title,
    required this.actor,
    required this.detail,
    this.untilNext,
  });

  final DateTime? timestamp;
  final String title;
  final String actor;
  final String detail;
  final Duration? untilNext;
}

class _MonitoringOrderAudit {
  const _MonitoringOrderAudit({
    required this.order,
    required this.events,
    required this.relatedQuotes,
    required this.timeline,
    required this.createdAt,
    required this.submittedAt,
    required this.firstQuoteCreatedAt,
    required this.firstQuoteSentToDireccionAt,
    required this.lastQuoteApprovedAt,
    required this.completedByContabilidadAt,
    required this.receivedByRequesterAt,
    required this.firstReturn,
    required this.secondReturn,
  });

  final PurchaseOrder order;
  final List<PurchaseOrderEvent> events;
  final List<SupplierQuote> relatedQuotes;
  final List<_MonitoringTimelineEntry> timeline;
  final DateTime? createdAt;
  final DateTime? submittedAt;
  final DateTime? firstQuoteCreatedAt;
  final DateTime? firstQuoteSentToDireccionAt;
  final DateTime? lastQuoteApprovedAt;
  final DateTime? completedByContabilidadAt;
  final DateTime? receivedByRequesterAt;
  final PurchaseOrderEvent? firstReturn;
  final PurchaseOrderEvent? secondReturn;
}

Future<void> exportMonitoringCsv(
  BuildContext context, {
  required List<PurchaseOrder> orders,
  required DateTime now,
  Map<String, List<PurchaseOrderEvent>> eventsByOrder = const {},
  List<SupplierQuote> quotes = const [],
  Map<String, String> actorNamesById = const {},
}) async {
  final csv = buildMonitoringCsv(
    orders,
    now: now,
    eventsByOrder: eventsByOrder,
    quotes: quotes,
    actorNamesById: actorNamesById,
  );
  final bytes = Uint8List.fromList(utf8.encode('\uFEFF$csv'));
  await _saveBytesToFile(
    context,
    bytes: bytes,
    suggestedName:
        'monitoreo_ordenes_${DateFormat('yyyyMMdd_HHmm').format(now)}.csv',
    mimeType: 'text/csv',
    successMessage: 'CSV descargado.',
    errorMessage: 'No se pudo descargar el CSV.',
  );
}

String buildMonitoringCsv(
  List<PurchaseOrder> orders, {
  required DateTime now,
  Map<String, List<PurchaseOrderEvent>> eventsByOrder = const {},
  List<SupplierQuote> quotes = const [],
  Map<String, String> actorNamesById = const {},
}) {
  final audits = [
    for (final order in orders)
      _buildMonitoringOrderAudit(
        order: order,
        events: eventsByOrder[order.id] ?? const <PurchaseOrderEvent>[],
        quotes: quotes,
        actorNamesById: actorNamesById,
        now: now,
      ),
  ];

  final rows = <List<String>>[
    <String>[
      'folio',
      'urgencia',
      'estadoActual',
      'tiempoActualEnEstado',
      'creadaFechaHora',
      'enviadaComprasFechaHora',
      'primeraCompraFechaHora',
      'primeraCompraEnviadaAutorizacionPagoFechaHora',
      'ultimaAutorizacionPagoFechaHora',
      'finalizadaContabilidadFechaHora',
      'recibidaSolicitanteFechaHora',
      'actualizadaFechaHora',
      'fechaRequerida',
      'eta',
      'solicitante',
      'area',
      'proveedor',
      'items',
      'compras',
      'direccionGeneral',
      'contabilidad',
      'primerRechazoFechaHora',
      'primerRechazoActor',
      'primerRechazoDe',
      'primerRechazoA',
      'primerRechazoComentario',
      'primerRechazoTiempoHastaSiguiente',
      'segundoRechazoFechaHora',
      'segundoRechazoActor',
      'segundoRechazoDe',
      'segundoRechazoA',
      'segundoRechazoComentario',
      'segundoRechazoTiempoHastaSiguiente',
      'ultimoComentario',
      'actores',
      'comprasRelacionadas',
      'trazabilidadCompleta',
      for (final status in PurchaseOrderStatus.values) 'acumulado_${status.name}',
    ],
    for (final audit in audits) _monitoringCsvRow(audit, now, actorNamesById),
  ];
  return const ListToCsvConverter().convert(rows);
}

List<String> _monitoringCsvRow(
  _MonitoringOrderAudit audit,
  DateTime now,
  Map<String, String> actorNamesById,
) {
  final order = audit.order;
  final firstReturn = audit.firstReturn;
  final secondReturn = audit.secondReturn;
  return <String>[
    order.id,
    order.urgency.label,
    order.status.label,
    formatMonitoringDuration(currentStatusElapsed(order, now)),
    _formatMonitoringDateTime(audit.createdAt),
    _formatMonitoringDateTime(audit.submittedAt),
    _formatMonitoringDateTime(audit.firstQuoteCreatedAt),
    _formatMonitoringDateTime(audit.firstQuoteSentToDireccionAt),
    _formatMonitoringDateTime(audit.lastQuoteApprovedAt),
    _formatMonitoringDateTime(audit.completedByContabilidadAt),
    _formatMonitoringDateTime(audit.receivedByRequesterAt),
    _formatMonitoringDateTime(order.updatedAt),
    order.requestedDeliveryDate?.toShortDate() ?? '',
    order.etaDate?.toShortDate() ?? '',
    order.requesterName,
    order.areaName,
    order.supplier ?? '',
    order.items.length.toString(),
    describeActor(order.comprasReviewerName, order.comprasReviewerArea) ?? '',
    describeActor(order.direccionGeneralName, order.direccionGeneralArea) ?? '',
    describeActor(order.contabilidadName, order.contabilidadArea) ?? '',
    _formatMonitoringDateTime(firstReturn?.timestamp),
    firstReturn == null ? '' : _eventActorLabel(firstReturn, actorNamesById),
    firstReturn?.fromStatus?.label ?? '',
    firstReturn?.toStatus?.label ?? '',
    firstReturn?.comment?.trim() ?? '',
    _formatDurationUntilNext(audit.timeline, firstReturn?.timestamp),
    _formatMonitoringDateTime(secondReturn?.timestamp),
    secondReturn == null ? '' : _eventActorLabel(secondReturn, actorNamesById),
    secondReturn?.fromStatus?.label ?? '',
    secondReturn?.toStatus?.label ?? '',
    secondReturn?.comment?.trim() ?? '',
    _formatDurationUntilNext(audit.timeline, secondReturn?.timestamp),
    order.lastReturnReason ?? order.comprasComment ?? order.direccionComment ?? '',
    buildMonitoringActorSummary(order),
    _relatedQuotesSummary(audit.relatedQuotes),
    _timelineSummary(audit.timeline),
    for (final status in PurchaseOrderStatus.values)
      formatMonitoringDuration(accumulatedStatusElapsed(order, status, now)),
  ];
}

Future<void> exportMonitoringPdf(
  BuildContext context, {
  required List<PurchaseOrder> orders,
  required DateTime now,
  required String companyName,
  required String scopeLabel,
  Map<String, List<PurchaseOrderEvent>> eventsByOrder = const {},
  List<SupplierQuote> quotes = const [],
  Map<String, String> actorNamesById = const {},
}) async {
  final bytes = await buildMonitoringPdf(
    orders: orders,
    now: now,
    companyName: companyName,
    scopeLabel: scopeLabel,
    eventsByOrder: eventsByOrder,
    quotes: quotes,
    actorNamesById: actorNamesById,
  );
  await _saveBytesToFile(
    context,
    bytes: bytes,
    suggestedName:
        'monitoreo_ordenes_${DateFormat('yyyyMMdd_HHmm').format(now)}.pdf',
    mimeType: 'application/pdf',
    successMessage: 'PDF descargado.',
    errorMessage: 'No se pudo descargar el PDF.',
  );
}

Future<Uint8List> buildMonitoringPdf({
  required List<PurchaseOrder> orders,
  required DateTime now,
  required String companyName,
  required String scopeLabel,
  Map<String, List<PurchaseOrderEvent>> eventsByOrder = const {},
  List<SupplierQuote> quotes = const [],
  Map<String, String> actorNamesById = const {},
}) async {
  final snapshots = buildMonitoringStatusSnapshots(orders, now);
  final audits = [
    for (final order in orders)
      _buildMonitoringOrderAudit(
        order: order,
        events: eventsByOrder[order.id] ?? const <PurchaseOrderEvent>[],
        quotes: quotes,
        actorNamesById: actorNamesById,
        now: now,
      ),
  ];
  final pdf = pw.Document();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => <pw.Widget>[
        pw.Text(
          companyName,
          style: pw.TextStyle(
            fontSize: 10,
            color: PdfColors.grey700,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'MONITOREO DE ORDENES',
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Generado: ${_monitoringExportDateTime.format(now)}',
          style: const pw.TextStyle(fontSize: 10),
        ),
        pw.Text(
          scopeLabel,
          style: const pw.TextStyle(fontSize: 10),
        ),
        pw.SizedBox(height: 18),
        pw.Text(
          'Resumen por estatus',
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: const pw.BoxDecoration(
            color: PdfColors.blueGrey800,
          ),
          cellAlignment: pw.Alignment.centerLeft,
          headers: const <String>[
            'Estatus',
            'Ordenes',
            'Promedio actual',
            'Mayor espera',
          ],
          data: [
            for (final snapshot in snapshots)
              <String>[
                snapshot.status.label,
                snapshot.count.toString(),
                formatMonitoringDuration(snapshot.averageElapsed),
                formatMonitoringDuration(snapshot.longestElapsed),
              ],
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Text(
          'Ordenes visibles',
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: const pw.BoxDecoration(
            color: PdfColors.black,
          ),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headers: const <String>[
            'Folio',
            'Solicitante',
            'Area',
            'Urgencia',
            'Estado',
            'Tiempo actual',
            'Compras / Aut. pago / Contabilidad',
          ],
          data: [
            for (final audit in audits)
              <String>[
                audit.order.id,
                audit.order.requesterName,
                audit.order.areaName,
                audit.order.urgency.label,
                audit.order.status.label,
                formatMonitoringDuration(currentStatusElapsed(audit.order, now)),
                [
                  describeActor(
                        audit.order.comprasReviewerName,
                        audit.order.comprasReviewerArea,
                      ) ??
                      '-',
                  describeActor(
                        audit.order.direccionGeneralName,
                        audit.order.direccionGeneralArea,
                      ) ??
                      '-',
                  describeActor(
                        audit.order.contabilidadName,
                        audit.order.contabilidadArea,
                      ) ??
                      '-',
                ].join(' / '),
              ],
          ],
        ),
        pw.SizedBox(height: 18),
        for (final audit in audits) ...[
          _buildMonitoringOrderAuditSection(audit, now, actorNamesById),
          pw.SizedBox(height: 18),
        ],
      ],
    ),
  );
  return pdf.save();
}

_MonitoringOrderAudit _buildMonitoringOrderAudit({
  required PurchaseOrder order,
  required List<PurchaseOrderEvent> events,
  required List<SupplierQuote> quotes,
  required Map<String, String> actorNamesById,
  required DateTime now,
}) {
  final sortedEvents = [...events]
    ..sort((a, b) {
      final aMs = a.timestamp?.millisecondsSinceEpoch ?? 0;
      final bMs = b.timestamp?.millisecondsSinceEpoch ?? 0;
      return aMs.compareTo(bMs);
    });
  final relatedQuotes = quotes
      .where((quote) => quote.orderIds.contains(order.id))
      .toList(growable: false)
    ..sort((a, b) {
      final aMs = (a.createdAt ?? a.updatedAt)?.millisecondsSinceEpoch ?? 0;
      final bMs = (b.createdAt ?? b.updatedAt)?.millisecondsSinceEpoch ?? 0;
      return aMs.compareTo(bMs);
    });
  final returnEvents = sortedEvents
      .where((event) => (event.type ?? '').trim().toLowerCase() == 'return')
      .toList(growable: false);

  return _MonitoringOrderAudit(
    order: order,
    events: sortedEvents,
    relatedQuotes: relatedQuotes,
    timeline: _buildTimeline(
      order: order,
      events: sortedEvents,
      relatedQuotes: relatedQuotes,
      actorNamesById: actorNamesById,
      now: now,
    ),
    createdAt: order.createdAt,
    submittedAt: _firstEventToStatus(sortedEvents, PurchaseOrderStatus.pendingCompras)
            ?.timestamp ??
        order.createdAt,
    firstQuoteCreatedAt: _minDateTime(
      relatedQuotes.map((quote) => quote.createdAt).whereType<DateTime>(),
    ),
    firstQuoteSentToDireccionAt: _minDateTime(
      relatedQuotes.map((quote) => quote.sentToDireccionAt).whereType<DateTime>(),
    ),
    lastQuoteApprovedAt: _maxDateTime(
      relatedQuotes.map((quote) => quote.approvedAt).whereType<DateTime>(),
    ),
    completedByContabilidadAt:
        _firstEventToStatus(sortedEvents, PurchaseOrderStatus.eta)?.timestamp ??
            order.completedAt,
    receivedByRequesterAt:
        _firstEventByType(sortedEvents, 'received')?.timestamp ??
            _firstEventByType(sortedEvents, 'received_timeout')?.timestamp ??
            order.requesterReceivedAt,
    firstReturn: returnEvents.isNotEmpty ? returnEvents.first : null,
    secondReturn: returnEvents.length > 1 ? returnEvents[1] : null,
  );
}

List<_MonitoringTimelineEntry> _buildTimeline({
  required PurchaseOrder order,
  required List<PurchaseOrderEvent> events,
  required List<SupplierQuote> relatedQuotes,
  required Map<String, String> actorNamesById,
  required DateTime now,
}) {
  final rawEntries = <_MonitoringTimelineEntry>[
    _MonitoringTimelineEntry(
      timestamp: order.createdAt,
      title: 'Orden creada',
      actor: describeActor(order.requesterName, order.areaName) ?? order.requesterName,
      detail: 'La orden se registrÃ³ en el sistema.',
    ),
    for (final event in events)
      _MonitoringTimelineEntry(
        timestamp: event.timestamp,
        title: _eventTitle(events, event),
        actor: _eventActorLabel(event, actorNamesById),
        detail: _monitoringEventDetail(event),
      ),
    for (final quote in relatedQuotes) ...[
      if (quote.createdAt != null)
        _MonitoringTimelineEntry(
          timestamp: quote.createdAt,
          title: 'Compra creada',
          actor:
              describeActor(quote.processedByName, quote.processedByArea) ??
                  _quoteSupplierLabel(quote),
          detail:
              'Proveedor ${_quoteSupplierLabel(quote)} - compra ${quote.displayId}.',
        ),
      if (quote.sentToDireccionAt != null)
        _MonitoringTimelineEntry(
          timestamp: quote.sentToDireccionAt,
          title: 'Compra enviada a autorizacion de pago',
          actor:
              describeActor(quote.processedByName, quote.processedByArea) ??
                  _quoteSupplierLabel(quote),
          detail:
              'Proveedor ${_quoteSupplierLabel(quote)} - compra ${quote.displayId}.',
        ),
      if (quote.approvedAt != null)
        _MonitoringTimelineEntry(
          timestamp: quote.approvedAt,
          title: 'Compra aprobada',
          actor:
              describeActor(quote.approvedByName, quote.approvedByArea) ??
                  'DirecciÃ³n General',
          detail:
              'Proveedor ${_quoteSupplierLabel(quote)} - compra ${quote.displayId}.',
        ),
      if (quote.rejectedAt != null)
        _MonitoringTimelineEntry(
          timestamp: quote.rejectedAt,
          title: 'Compra rechazada',
          actor:
              describeActor(quote.rejectedByName, quote.rejectedByArea) ??
                  'Direccion General',
          detail:
              'Proveedor ${_quoteSupplierLabel(quote)} - ${_withTrailingPeriod(quote.rejectionComment)}',
        ),
    ],
  ]
      .where((entry) => entry.timestamp != null)
      .toList(growable: false)
    ..sort((a, b) {
      final aMs = a.timestamp?.millisecondsSinceEpoch ?? 0;
      final bMs = b.timestamp?.millisecondsSinceEpoch ?? 0;
      return aMs.compareTo(bMs);
    });

  final timeline = <_MonitoringTimelineEntry>[];
  for (var index = 0; index < rawEntries.length; index++) {
    final current = rawEntries[index];
    final next = index + 1 < rawEntries.length ? rawEntries[index + 1] : null;
    Duration? untilNext;
    if (current.timestamp != null && next?.timestamp != null) {
      final diff = next!.timestamp!.difference(current.timestamp!);
      untilNext = diff.isNegative ? Duration.zero : diff;
    } else if (current.timestamp != null && index == rawEntries.length - 1) {
      final diff = now.difference(current.timestamp!);
      untilNext = diff.isNegative ? Duration.zero : diff;
    }
    timeline.add(
      _MonitoringTimelineEntry(
        timestamp: current.timestamp,
        title: current.title,
        actor: current.actor,
        detail: current.detail,
        untilNext: untilNext,
      ),
    );
  }
  return timeline;
}

PurchaseOrderEvent? _firstEventToStatus(
  List<PurchaseOrderEvent> events,
  PurchaseOrderStatus status,
) {
  for (final event in events) {
    if (event.toStatus == status) return event;
  }
  return null;
}

PurchaseOrderEvent? _firstEventByType(
  List<PurchaseOrderEvent> events,
  String type,
) {
  final normalized = type.trim().toLowerCase();
  for (final event in events) {
    if ((event.type ?? '').trim().toLowerCase() == normalized) return event;
  }
  return null;
}

DateTime? _minDateTime(Iterable<DateTime> values) {
  DateTime? selected;
  for (final value in values) {
    if (selected == null || value.isBefore(selected)) {
      selected = value;
    }
  }
  return selected;
}

DateTime? _maxDateTime(Iterable<DateTime> values) {
  DateTime? selected;
  for (final value in values) {
    if (selected == null || value.isAfter(selected)) {
      selected = value;
    }
  }
  return selected;
}

String _eventTitle(
  List<PurchaseOrderEvent> events,
  PurchaseOrderEvent event,
) {
  final type = (event.type ?? '').trim().toLowerCase();
  if (type == 'return') return returnEventTitle(events, event);
  if (type == 'items_arrived') return 'Llegada parcial registrada';
  if (type == 'material_arrived') return 'Material llegado';
  if (type == 'received_timeout') return 'Llegado pero no confirmado';
  if (type == 'received') return 'Recibida por solicitante';
  return 'Movimiento';
}


String _eventActorLabel(
  PurchaseOrderEvent event,
  Map<String, String> actorNamesById,
) {
  final resolvedName = actorNamesById[event.byUser] ?? event.byUser;
  final role = event.byRole.trim();
  if (role.isEmpty) return resolvedName;
  return '$resolvedName ($role)';
}

String _monitoringEventDetail(PurchaseOrderEvent event) {
  final base = orderEventTransitionLabel(event);
  final comment = event.comment?.trim() ?? '';
  if (isReturnOrderEvent(event)) {
    final stage = returnStageLabel(event.fromStatus);
    if (comment.isEmpty) return '$base | rechazo en $stage';
    return '$base | rechazo en $stage | $comment';
  }
  if (comment.isEmpty) return base;
  return '$base | $comment';
}

String _quoteSupplierLabel(SupplierQuote quote) {
  final supplier = quote.supplier.trim();
  return supplier.isEmpty ? quote.displayId : supplier;
}

String _withTrailingPeriod(String? text) {
  final trimmed = text?.trim() ?? '';
  if (trimmed.isEmpty) return 'sin comentario.';
  if (trimmed.endsWith('.')) return trimmed;
  return '$trimmed.';
}

String _formatMonitoringDateTime(DateTime? value) {
  if (value == null) return '';
  return _monitoringExportDateTime.format(value);
}

String _formatDurationUntilNext(
  List<_MonitoringTimelineEntry> timeline,
  DateTime? timestamp,
) {
  if (timestamp == null) return '';
  for (final entry in timeline) {
    if (entry.timestamp == timestamp) {
      return entry.untilNext == null ? '' : formatMonitoringDuration(entry.untilNext!);
    }
  }
  return '';
}

String _relatedQuotesSummary(List<SupplierQuote> quotes) {
  if (quotes.isEmpty) return '';
  final parts = <String>[];
  for (final quote in quotes) {
    parts.add(
      [
        'Proveedor ${_quoteSupplierLabel(quote)}',
        'folio ${quote.displayId}',
        if (quote.createdAt != null)
          'creada ${_formatMonitoringDateTime(quote.createdAt)}',
        if (quote.sentToDireccionAt != null)
          'enviada a autorizacion de pago ${_formatMonitoringDateTime(quote.sentToDireccionAt)}',
        if (quote.approvedAt != null)
          'aprobada ${_formatMonitoringDateTime(quote.approvedAt)}',
        if (quote.rejectedAt != null)
          'rechazada ${_formatMonitoringDateTime(quote.rejectedAt)}',
      ].join(' | '),
    );
  }
  return parts.join(' || ');
}

String _buildRejectionSummary(
  List<PurchaseOrderEvent> events,
  PurchaseOrderEvent? event,
  List<_MonitoringTimelineEntry> timeline,
  Map<String, String> actorNamesById,
) {
  if (event == null) return '';
  final parts = <String>[
    _eventTitle(events, event),
    _formatMonitoringDateTime(event.timestamp),
    _eventActorLabel(event, actorNamesById),
    orderEventTransitionLabel(event),
  ];
  final comment = event.comment?.trim() ?? '';
  if (comment.isNotEmpty) {
    parts.add(comment);
  }
  final duration = _formatDurationUntilNext(timeline, event.timestamp);
  if (duration.isNotEmpty) {
    parts.add('hasta siguiente: $duration');
  }
  return parts.join(' | ');
}

String _timelineSummary(List<_MonitoringTimelineEntry> timeline) {
  return timeline
      .map((entry) {
        final parts = <String>[
          '[${_formatMonitoringDateTime(entry.timestamp)}]',
          entry.title,
          if (entry.actor.trim().isNotEmpty) entry.actor.trim(),
          entry.detail,
          if (entry.untilNext != null)
            'hasta siguiente: ${formatMonitoringDuration(entry.untilNext!)}',
        ];
        return parts.join(' | ');
      })
      .join(' || ');
}

pw.Widget _buildMonitoringOrderAuditSection(
  _MonitoringOrderAudit audit,
  DateTime now,
  Map<String, String> actorNamesById,
) {
  final order = audit.order;
  final firstReturn = audit.firstReturn;
  final secondReturn = audit.secondReturn;
  final firstReturnSummary = _buildRejectionSummary(
    audit.events,
    firstReturn,
    audit.timeline,
    actorNamesById,
  );
  final secondReturnSummary = _buildRejectionSummary(
    audit.events,
    secondReturn,
    audit.timeline,
    actorNamesById,
  );

  pw.Widget row(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 170,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value.isEmpty ? '-' : value,
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }

  return pw.Container(
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey600, width: 0.8),
      borderRadius: pw.BorderRadius.circular(8),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Orden ${order.id}',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          '${order.requesterName} - ${order.areaName} - ${order.status.label}',
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Hitos exactos',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        row('Creada', _formatMonitoringDateTime(audit.createdAt)),
        row('Enviada a Compras', _formatMonitoringDateTime(audit.submittedAt)),
        row(
          'Primera compra creada',
          _formatMonitoringDateTime(audit.firstQuoteCreatedAt),
        ),
        row(
          'Primera compra enviada a autorizacion de pago',
          _formatMonitoringDateTime(audit.firstQuoteSentToDireccionAt),
        ),
        row(
          'Ultima autorizacion de pago',
          _formatMonitoringDateTime(audit.lastQuoteApprovedAt),
        ),
        row(
          'Finalizada por Contabilidad',
          _formatMonitoringDateTime(audit.completedByContabilidadAt),
        ),
        row(
          'Recibida por solicitante',
          _formatMonitoringDateTime(audit.receivedByRequesterAt),
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Regresos',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        row(
          'Regreso 1',
          firstReturnSummary,
        ),
        row(
          'Regreso 2',
          secondReturnSummary,
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Compras relacionadas',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        if (audit.relatedQuotes.isEmpty)
          pw.Text('-', style: pw.TextStyle(fontSize: 9))
        else
          for (final quote in audit.relatedQuotes)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(
                _relatedQuotesSummary([quote]),
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Trazabilidad completa',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
            fontSize: 8,
          ),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headers: const <String>[
            'Fecha / hora',
            'AcciÃ³n',
            'Actor',
            'Detalle',
            'Tiempo hasta siguiente',
          ],
          data: [
            for (final entry in audit.timeline)
              <String>[
                _formatMonitoringDateTime(entry.timestamp),
                entry.title,
                entry.actor,
                entry.detail,
                entry.untilNext == null
                    ? ''
                    : formatMonitoringDuration(entry.untilNext!),
              ],
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Tiempo actual en estado: ${formatMonitoringDuration(currentStatusElapsed(order, now))}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ],
    ),
  );
}

Future<void> _saveBytesToFile(
  BuildContext context, {
  required Uint8List bytes,
  required String suggestedName,
  required String mimeType,
  required String successMessage,
  required String errorMessage,
}) async {
  try {
    final location = await getSaveLocation(suggestedName: suggestedName);
    if (location == null) return;
    final file = XFile.fromData(
      bytes,
      mimeType: mimeType,
      name: suggestedName,
    );
    await file.saveTo(location.path);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
  }
}
