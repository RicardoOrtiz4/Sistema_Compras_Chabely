import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'package:sistema_compras/features/orders/domain/purchase_order.dart';

Future<void> exportOrderCsv(BuildContext context, PurchaseOrder order) async {
  final csv = buildOrderCsv(order);
  final bytes = Uint8List.fromList(utf8.encode('\uFEFF$csv'));
  final fileName = 'requisicion_${order.id}.csv';

  try {
    final location = await getSaveLocation(suggestedName: fileName);
    if (location == null) return;

    final file = XFile.fromData(
      bytes,
      mimeType: 'text/csv',
      name: fileName,
    );

    await file.saveTo(location.path);

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
  'cantidad',
  'unidad',
  'cliente',
  'fechaEstimada',
];

List<String> _itemRow(PurchaseOrderItem item) {
  return [
    item.line.toString(),
    item.partNumber,
    item.description,
    _formatQuantity(item.quantity),
    item.unit,
    (item.customer ?? '').trim(),
    _formatDate(item.estimatedDate),
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
