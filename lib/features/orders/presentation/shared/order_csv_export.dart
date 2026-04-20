import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/save_bytes.dart';

import 'package:sistema_compras/features/orders/domain/purchase_order.dart';

Future<void> exportOrderCsv(
  BuildContext context,
  PurchaseOrder order, {
  String? suggestedFileName,
}) async {
  final csv = buildOrderCsv(order);
  final bytes = Uint8List.fromList(utf8.encode('\uFEFF$csv'));
  final fileName = suggestedFileName ?? 'requisicion_${order.id}.csv';

  try {
    final path = await pickSavePath(
      suggestedName: fileName,
      allowedExtensions: const <String>['csv'],
    );
    if (path == null) return;
    await saveBytesToSelectedPath(path, bytes);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV descargado.')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo descargar el CSV.')),
      );
    }
  }
}

String buildOrderCsv(PurchaseOrder order) {
  final rows = <List<String>>[
    <String>['folio', order.id],
    <String>['solicitante', order.requesterName],
    <String>['areaSolicitante', order.areaName],
    <String>['urgencia', order.urgency.label],
    <String>['justificacionUrgencia', (order.urgentJustification ?? '').trim()],
    <String>['estadoActual', order.status.label],
    <String>['autorizo', (order.authorizedByName ?? '').trim()],
    <String>['areaAutorizo', (order.authorizedByArea ?? '').trim()],
    <String>['procesoPor', (order.processByName ?? '').trim()],
    <String>['areaProceso', (order.processByArea ?? '').trim()],
    const <String>[],
    _csvHeader,
    for (final item in order.items) _itemRow(item),
  ];

  const converter = ListToCsvConverter();
  return converter.convert(rows);
}

const _csvHeader = <String>[
  'linea',
  'noParte',
  'descripcion',
  'piezas',
  'cantidad',
  'unidad',
  'cliente',
  'proveedor',
  'monto',
  'ocInterna',
  'fechaEstimada',
  'fechaEtaEntrega',
  'cantidadRecibida',
  'comentarioRecepcion',
  'marcadoNoComprable',
  'motivoNoComprable',
];

List<String> _itemRow(PurchaseOrderItem item) {
  return [
    item.line.toString(),
    item.partNumber,
    item.description,
    item.pieces.toString(),
    _formatQuantity(item.quantity),
    item.unit,
    (item.customer ?? '').trim(),
    (item.supplier ?? '').trim(),
    item.budget == null ? '' : _formatQuantity(item.budget!),
    (item.internalOrder ?? '').trim(),
    _formatDate(item.estimatedDate),
    _formatDate(item.deliveryEtaDate),
    item.receivedQuantity == null ? '' : _formatQuantity(item.receivedQuantity!),
    (item.receivedComment ?? '').trim(),
    item.isNotPurchased ? 'si' : 'no',
    (item.notPurchasedReason ?? '').trim(),
  ];
}

String _formatQuantity(num value) {
  final asInt = value.toInt();
  if (value == asInt) return asInt.toString();
  return value.toString();
}

String _formatDate(DateTime? value) {
  if (value == null) return '';
  return value.toIso8601String().split('T').first;
}
