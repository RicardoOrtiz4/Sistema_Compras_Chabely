import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/save_bytes.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';

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
  return order.isRejectedDraft;
}

bool isFinishedMonitoringOrder(PurchaseOrder order) {
  return order.isWorkflowFinished;
}

bool isConfirmedRejectedMonitoringOrder(PurchaseOrder order) {
  return order.isRejectedDraft && order.isRejectionAcknowledged;
}

bool isMonitorableOrder(PurchaseOrder order) {
  return (!order.isDraft || isOperationalRejectedOrder(order)) &&
      !isFinishedMonitoringOrder(order) &&
      !isConfirmedRejectedMonitoringOrder(order);
}

class MonitoringOrderStatusRow {
  const MonitoringOrderStatusRow({
    required this.order,
    required this.status,
    required this.elapsed,
    required this.actor,
    required this.enteredAt,
    required this.isCurrent,
  });

  final PurchaseOrder order;
  final PurchaseOrderStatus status;
  final Duration elapsed;
  final String actor;
  final DateTime? enteredAt;
  final bool isCurrent;
}

List<MonitoringOrderStatusRow> buildMonitoringStatusRows({
  required PurchaseOrder order,
  required List<PurchaseOrderEvent> events,
  required DateTime now,
  Map<String, String> actorNamesById = const {},
}) {
  final rows = <MonitoringOrderStatusRow>[];
  for (final status in PurchaseOrderStatus.values) {
    final isCurrent = order.status == status;
    final elapsed = accumulatedStatusElapsed(order, status, now);
    final event = latestEventForStatus(events, status);
    final enteredAt = _enteredAtForStatus(
      order: order,
      status: status,
      event: event,
    );
    final shouldInclude = isCurrent ||
        elapsed > Duration.zero ||
        event != null ||
        (status == PurchaseOrderStatus.draft && order.createdAt != null);
    if (!shouldInclude) continue;

    rows.add(
      MonitoringOrderStatusRow(
        order: order,
        status: status,
        elapsed: elapsed,
        actor: _actorForStatus(
          order: order,
          status: status,
          event: event,
          actorNamesById: actorNamesById,
        ),
        enteredAt: enteredAt,
        isCurrent: isCurrent,
      ),
    );
  }

  if (rows.isNotEmpty) return rows;
  return [
    MonitoringOrderStatusRow(
      order: order,
      status: order.status,
      elapsed: currentStatusElapsed(order, now),
      actor: _actorForStatus(
        order: order,
        status: order.status,
        event: null,
        actorNamesById: actorNamesById,
      ),
      enteredAt: order.statusEnteredAt ?? order.updatedAt ?? order.createdAt,
      isCurrent: true,
    ),
  ];
}

DateTime? _enteredAtForStatus({
  required PurchaseOrder order,
  required PurchaseOrderStatus status,
  required PurchaseOrderEvent? event,
}) {
  if (order.status == status) {
    return order.statusEnteredAt ?? event?.timestamp ?? order.updatedAt ?? order.createdAt;
  }
  if (event != null) return event.timestamp;
  if (status == PurchaseOrderStatus.draft) return order.createdAt;
  return null;
}

String _actorForStatus({
  required PurchaseOrder order,
  required PurchaseOrderStatus status,
  required PurchaseOrderEvent? event,
  required Map<String, String> actorNamesById,
}) {
  if (event != null) return _eventActorLabel(event, actorNamesById);
  switch (status) {
    case PurchaseOrderStatus.draft:
    case PurchaseOrderStatus.intakeReview:
      return describeActor(order.requesterName, order.areaName) ??
          order.requesterName;
    case PurchaseOrderStatus.sourcing:
    case PurchaseOrderStatus.readyForApproval:
      return 'Operacion';
    case PurchaseOrderStatus.approvalQueue:
    case PurchaseOrderStatus.paymentDone:
      return 'Validacion';
    case PurchaseOrderStatus.contabilidad:
    case PurchaseOrderStatus.orderPlaced:
      return describeActor(order.contabilidadName, order.contabilidadArea) ??
          'Cierre documental';
    case PurchaseOrderStatus.eta:
      return describeActor(order.requesterReceivedName, order.requesterReceivedArea) ??
          describeActor(order.materialArrivedName, order.materialArrivedArea) ??
          describeActor(order.contabilidadName, order.contabilidadArea) ??
          'Sistema';
  }
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

String? describeActor(String? name, String? area) {
  final trimmedName = name?.trim() ?? '';
  final trimmedArea = area?.trim() ?? '';
  if (trimmedName.isEmpty && trimmedArea.isEmpty) return null;
  if (trimmedName.isEmpty) return trimmedArea;
  if (trimmedArea.isEmpty) return trimmedName;
  return '$trimmedName ($trimmedArea)';
}

String _eventActorLabel(
  PurchaseOrderEvent? event,
  Map<String, String> actorNamesById,
) {
  if (event == null) return '';
  final byUser = event.byUser.trim();
  final resolvedName = byUser.isEmpty
      ? 'Sistema'
      : (actorNamesById[byUser]?.trim().isNotEmpty == true
            ? actorNamesById[byUser]!.trim()
            : byUser);
  final role = event.byRole.trim();
  if (role.isEmpty) return resolvedName;
  return '$resolvedName ($role)';
}

Future<void> exportMonitoringCsv(
  BuildContext context, {
  required List<PurchaseOrder> orders,
  required DateTime now,
  Map<String, List<PurchaseOrderEvent>> eventsByOrder = const {},
  Map<String, String> actorNamesById = const {},
}) async {
  final csv = buildMonitoringCsv(
    orders,
    now: now,
    eventsByOrder: eventsByOrder,
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
  Map<String, String> actorNamesById = const {},
}) {
  final rows = <List<String>>[
    <String>[
      'folio',
      'urgencia',
      'estadoActual',
      'solicitante',
      'area',
      'status',
      'statusActual',
      'tiempoEnStatus',
      'actuo',
      'fechaHora',
    ],
    for (final order in orders)
      for (final row in buildMonitoringStatusRows(
        order: order,
        events: eventsByOrder[order.id] ?? const <PurchaseOrderEvent>[],
        now: now,
        actorNamesById: actorNamesById,
      ))
        _monitoringStatusCsvRow(row),
  ];
  return const ListToCsvConverter().convert(rows);
}

List<String> _monitoringStatusCsvRow(MonitoringOrderStatusRow row) {
  final order = row.order;
  return <String>[
    order.id,
    order.urgency.label,
    requesterReceiptStatusLabel(order),
    order.requesterName,
    order.areaName,
    row.status.label,
    row.isCurrent ? 'Si' : 'No',
    formatMonitoringDuration(row.elapsed),
    row.actor,
    _formatMonitoringDateTime(row.enteredAt),
  ];
}

Future<void> exportMonitoringPdf(
  BuildContext context, {
  required List<PurchaseOrder> orders,
  required DateTime now,
  required String companyName,
  required String scopeLabel,
  Map<String, List<PurchaseOrderEvent>> eventsByOrder = const {},
  Map<String, String> actorNamesById = const {},
}) async {
  final bytes = await buildMonitoringPdf(
    orders: orders,
    now: now,
    companyName: companyName,
    scopeLabel: scopeLabel,
    eventsByOrder: eventsByOrder,
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
  Map<String, String> actorNamesById = const {},
}) async {
  final rows = [
    for (final order in orders)
      for (final row in buildMonitoringStatusRows(
        order: order,
        events: eventsByOrder[order.id] ?? const <PurchaseOrderEvent>[],
        now: now,
        actorNamesById: actorNamesById,
      ))
        row,
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
        pw.SizedBox(height: 14),
        pw.Text(
          'Ordenes actuales por status',
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
            'Urgencia',
            'Estado actual',
            'Solicitante',
            'Area',
            'Status',
            'Tiempo en status',
            'Actuo',
            'Fecha / hora',
          ],
          data: [
            for (final row in rows)
              <String>[
                row.order.id,
                row.order.urgency.label,
                requesterReceiptStatusLabel(row.order),
                row.order.requesterName,
                row.order.areaName,
                row.isCurrent ? '${row.status.label} *' : row.status.label,
                formatMonitoringDuration(row.elapsed),
                row.actor,
                _formatMonitoringDateTime(row.enteredAt),
              ],
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          '* Status actual de la orden.',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ],
    ),
  );
  return pdf.save();
}

String _formatMonitoringDateTime(DateTime? value) {
  if (value == null) return '';
  return _monitoringExportDateTime.format(value);
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
    final path = await pickSavePath(
      suggestedName: suggestedName,
      allowedExtensions: mimeType == 'application/pdf'
          ? const <String>['pdf']
          : const <String>['csv'],
    );
    if (path == null) return;
    await saveBytesToSelectedPath(path, bytes);
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
