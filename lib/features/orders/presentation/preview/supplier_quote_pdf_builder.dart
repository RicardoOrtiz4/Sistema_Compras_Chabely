import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:sistema_compras/core/company_branding.dart';

class SupplierQuotePdfItemData {
  const SupplierQuotePdfItemData({
    required this.line,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.selected,
    this.partNumber,
    this.customer,
    this.amount,
    this.etaDate,
  });

  final int line;
  final String description;
  final num quantity;
  final String unit;
  final bool selected;
  final String? partNumber;
  final String? customer;
  final num? amount;
  final DateTime? etaDate;
}

class SupplierQuotePdfOrderData {
  const SupplierQuotePdfOrderData({
    required this.orderId,
    required this.requesterName,
    required this.areaName,
    required this.items,
  });

  final String orderId;
  final String requesterName;
  final String areaName;
  final List<SupplierQuotePdfItemData> items;

  num get orderTotal {
    var total = 0.0;
    for (final item in items) {
      final amount = item.amount;
      if (amount != null) {
        total += amount.toDouble();
      }
    }
    return total;
  }

  num get selectedTotal {
    var total = 0.0;
    for (final item in items) {
      if (!item.selected) continue;
      final amount = item.amount;
      if (amount != null) {
        total += amount.toDouble();
      }
    }
    return total;
  }
}

class SupplierQuotePdfData {
  const SupplierQuotePdfData({
    required this.branding,
    required this.quoteId,
    required this.supplier,
    required this.links,
    required this.orders,
    this.comprasComment,
    this.createdAt,
    this.processedByName,
    this.processedByArea,
    this.authorizedByName,
    this.authorizedByArea,
  });

  final CompanyBranding branding;
  final String quoteId;
  final String supplier;
  final List<String> links;
  final List<SupplierQuotePdfOrderData> orders;
  final String? comprasComment;
  final DateTime? createdAt;
  final String? processedByName;
  final String? processedByArea;
  final String? authorizedByName;
  final String? authorizedByArea;

  num get totalAmount {
    var total = 0.0;
    for (final order in orders) {
      total += order.selectedTotal.toDouble();
    }
    return total;
  }
}

const String _supplierQuotePdfTemplateVersion = '2026-03-23-proveedor-v11';
const int _maxSupplierQuotePdfCacheEntries = 16;
const int _maxSupplierQuotePdfCacheBytes = 16 * 1024 * 1024;

final LinkedHashMap<String, Uint8List> _supplierQuotePdfCache =
    LinkedHashMap<String, Uint8List>();
final Map<String, Future<Uint8List>> _supplierQuotePdfBuildFutures =
    <String, Future<Uint8List>>{};
final Map<String, Future<ByteData>> _supplierQuoteLogoBytesFutures =
    <String, Future<ByteData>>{};
int _supplierQuotePdfCacheBytes = 0;

void warmUpSupplierQuotePdfAssets(CompanyBranding branding) {
  _loadSupplierQuoteLogo(branding);
}

Future<Uint8List> buildSupplierQuotePdf(SupplierQuotePdfData data) async {
  final cacheKey = supplierQuotePdfCacheKey(data);
  final cached = _getSupplierQuotePdfCacheEntry(cacheKey);
  if (cached != null) {
    return kIsWeb ? Uint8List.fromList(cached) : cached;
  }

  final inFlight = _supplierQuotePdfBuildFutures[cacheKey];
  if (inFlight != null) {
    final shared = await inFlight;
    return kIsWeb ? Uint8List.fromList(shared) : shared;
  }

  final future = Future<Uint8List>(() async {
    final logoBytes = await _loadSupplierQuoteLogo(data.branding);
    final logo = pw.MemoryImage(logoBytes.buffer.asUint8List());
    final bytes = await _buildSupplierQuotePdfWithLogo(data, logo);
    return _putSupplierQuotePdfCacheEntry(cacheKey, bytes);
  });
  _supplierQuotePdfBuildFutures[cacheKey] = future;
  try {
    final bytes = await future;
    return kIsWeb ? Uint8List.fromList(bytes) : bytes;
  } finally {
    _supplierQuotePdfBuildFutures.remove(cacheKey);
  }
}

Uint8List? getCachedSupplierQuotePdf(SupplierQuotePdfData data) {
  final cached = _getSupplierQuotePdfCacheEntry(supplierQuotePdfCacheKey(data));
  if (cached == null) return null;
  return kIsWeb ? Uint8List.fromList(cached) : cached;
}

Future<void> cacheSupplierQuotePdfs(
  List<SupplierQuotePdfData> dataList, {
  int limit = 2,
}) async {
  if (dataList.isEmpty || limit <= 0) return;
  for (final data in dataList.take(limit)) {
    try {
      await buildSupplierQuotePdf(data);
    } catch (_) {}
  }
}

String supplierQuotePdfCacheKey(SupplierQuotePdfData data) {
  final buffer = StringBuffer()
    ..write(_supplierQuotePdfTemplateVersion)
    ..write('|')
    ..write(data.branding.id)
    ..write('|')
    ..write(data.quoteId)
    ..write('|')
    ..write(data.supplier)
    ..write('|')
    ..write(data.links.join('||'))
    ..write('|')
    ..write(data.comprasComment ?? '')
    ..write('|')
    ..write(data.createdAt?.millisecondsSinceEpoch ?? 0);
  for (final order in data.orders) {
    final visibleItems = _selectedItems(order);
    if (visibleItems.isEmpty) continue;
    buffer
      ..write('|')
      ..write(order.orderId)
      ..write(':')
      ..write(order.selectedTotal)
      ..write(':')
      ..write(visibleItems.length);
    for (final item in visibleItems) {
      buffer
        ..write('|')
        ..write(item.line)
        ..write(':')
        ..write(item.amount ?? 0)
        ..write(':')
        ..write(item.etaDate?.millisecondsSinceEpoch ?? 0)
        ..write(':')
        ..write(item.description)
        ..write(':')
        ..write(item.quantity)
        ..write(':')
        ..write(item.unit);
    }
  }
  return buffer.toString();
}

Future<Uint8List> _buildSupplierQuotePdfWithLogo(
  SupplierQuotePdfData data,
  pw.MemoryImage logo,
) async {
  final doc = pw.Document();
  final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
  final visibleOrders = data.orders
      .where((order) => _selectedItems(order).isNotEmpty)
      .toList(growable: false);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => [
        _buildHeader(data, logo, dateFormat),
        pw.SizedBox(height: 16),
        if ((data.comprasComment ?? '').trim().isNotEmpty) ...[
          _commentBlock(data.comprasComment!.trim()),
          pw.SizedBox(height: 14),
        ],
        for (final order in visibleOrders) ...[
          _buildOrderBlock(order),
          pw.SizedBox(height: 14),
        ],
      ],
    ),
  );

  return doc.save();
}

Future<ByteData> _loadSupplierQuoteLogo(CompanyBranding branding) {
  return _supplierQuoteLogoBytesFutures.putIfAbsent(
    branding.id,
    () => rootBundle.load(branding.logoAsset),
  );
}

Uint8List? _getSupplierQuotePdfCacheEntry(String cacheKey) {
  final cached = _supplierQuotePdfCache.remove(cacheKey);
  if (cached == null) return null;
  _supplierQuotePdfCache[cacheKey] = cached;
  return cached;
}

Uint8List _putSupplierQuotePdfCacheEntry(String cacheKey, Uint8List bytes) {
  final stored = Uint8List.fromList(bytes);
  final replaced = _supplierQuotePdfCache.remove(cacheKey);
  if (replaced != null) {
    _supplierQuotePdfCacheBytes -= replaced.lengthInBytes;
  }
  _supplierQuotePdfCache[cacheKey] = stored;
  _supplierQuotePdfCacheBytes += stored.lengthInBytes;
  _trimSupplierQuotePdfCache();
  return stored;
}

void _trimSupplierQuotePdfCache() {
  while (_supplierQuotePdfCache.isNotEmpty &&
      (_supplierQuotePdfCache.length > _maxSupplierQuotePdfCacheEntries ||
          _supplierQuotePdfCacheBytes > _maxSupplierQuotePdfCacheBytes)) {
    final oldestKey = _supplierQuotePdfCache.keys.first;
    final removed = _supplierQuotePdfCache.remove(oldestKey);
    if (removed != null) {
      _supplierQuotePdfCacheBytes -= removed.lengthInBytes;
    }
  }
}

pw.Widget _buildHeader(
  SupplierQuotePdfData data,
  pw.MemoryImage logo,
  DateFormat dateFormat,
) {
  final totalOrders = data.orders
      .where((order) => _selectedItems(order).isNotEmpty)
      .length;
  final totalItems = data.orders.fold<int>(
    0,
    (sum, order) => sum + _selectedItems(order).length,
  );
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 96,
            height: 60,
            alignment: pw.Alignment.centerLeft,
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(width: 16),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  data.supplier,
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey900,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Cotizacion por proveedor',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.teal800,
                  ),
                ),
                if (data.createdAt != null)
                  _detailLine(
                    'Fecha',
                    dateFormat.format(data.createdAt!),
                    labelColor: PdfColors.grey700,
                    valueColor: PdfColors.black,
                  ),
                if (data.authorizedByName?.trim().isNotEmpty == true)
                  _detailLine(
                    'Autorizo',
                    data.authorizedByName!.trim(),
                    labelColor: PdfColors.grey700,
                    valueColor: PdfColors.teal800,
                    valueWeight: pw.FontWeight.bold,
                  ),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: pw.BoxDecoration(
              color: PdfColors.amber50,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColors.amber700, width: 1.2),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'TOTAL',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.orange800,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  _formatMoney(data.totalAmount),
                  style: pw.TextStyle(
                    fontSize: 26,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.orange900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 12),
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: pw.BoxDecoration(
          color: PdfColors.blueGrey50,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Text(
          'Ordenes: $totalOrders   |   Items: $totalItems   |   Monto: solo items de este proveedor',
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blueGrey800,
          ),
        ),
      ),
    ],
  );
}

pw.Widget _buildOrderBlock(SupplierQuotePdfOrderData order) {
  final items = _selectedItems(order);
  if (items.isEmpty) {
    return pw.SizedBox.shrink();
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: pw.BoxDecoration(
          color: PdfColors.blueGrey800,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Text(
          'ORDEN ${order.orderId}',
          style: pw.TextStyle(
            fontSize: 17,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
        ),
      ),
      pw.SizedBox(height: 8),
      _detailLine(
        'Solicitante / Area',
        '${order.requesterName} | ${order.areaName}',
        valueSize: 13,
        labelColor: PdfColors.grey700,
        valueColor: PdfColors.black,
      ),
      pw.SizedBox(height: 10),
      for (final item in items) ...[
        _itemCard(item),
        if (item != items.last) pw.SizedBox(height: 10),
      ],
      pw.Divider(color: PdfColors.grey500, thickness: 1),
    ],
  );
}

pw.Widget _itemCard(SupplierQuotePdfItemData item) {
  final unit = item.unit.trim();
  final quantityLabel = '${_formatNum(item.quantity)} ${unit.isEmpty ? '' : unit}'.trim();
  final etaLabel = item.etaDate == null
      ? null
      : DateFormat('dd/MM/yyyy').format(item.etaDate!);

  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      color: PdfColors.grey100,
      borderRadius: pw.BorderRadius.circular(8),
      border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Item ${item.line} | Cantidad: $quantityLabel',
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey700,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          item.description.trim().isEmpty ? '-' : item.description.trim(),
          style: pw.TextStyle(
            fontSize: 15,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blueGrey900,
          ),
        ),
        pw.SizedBox(height: 5),
        if ((item.partNumber ?? '').trim().isNotEmpty)
          _detailLine(
            'No. parte',
            item.partNumber!.trim(),
            labelColor: PdfColors.grey700,
            valueColor: PdfColors.black,
          ),
        if ((item.customer ?? '').trim().isNotEmpty)
          _detailLine(
            'Cliente',
            item.customer!.trim(),
            labelColor: PdfColors.grey700,
            valueColor: PdfColors.black,
          ),
        if (etaLabel != null)
          _detailLine(
            'Fecha estimada de entrega',
            etaLabel,
            labelColor: PdfColors.grey700,
            valueColor: PdfColors.black,
          ),
        pw.SizedBox(height: 6),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: pw.BoxDecoration(
            color: PdfColors.green50,
            borderRadius: pw.BorderRadius.circular(6),
            border: pw.Border.all(color: PdfColors.green700, width: 1),
          ),
          child: pw.RichText(
            text: pw.TextSpan(
              children: [
                pw.TextSpan(
                  text: 'Monto: ',
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green800,
                  ),
                ),
                pw.TextSpan(
                  text: _formatMoney(item.amount),
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _commentBlock(String comment) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: pw.BoxDecoration(
      color: PdfColors.blue50,
      borderRadius: pw.BorderRadius.circular(6),
      border: pw.Border.all(color: PdfColors.blue200, width: 0.8),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Comentario general de compras',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blueGrey800,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          comment,
          style: pw.TextStyle(
            fontSize: 11,
            color: PdfColors.black,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _detailLine(
  String label,
  String value, {
  double valueSize = 12,
  PdfColor labelColor = PdfColors.black,
  PdfColor valueColor = PdfColors.black,
  pw.FontWeight valueWeight = pw.FontWeight.normal,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label: ',
            style: pw.TextStyle(
              fontSize: valueSize,
              fontWeight: pw.FontWeight.bold,
              color: labelColor,
            ),
          ),
          pw.TextSpan(
            text: value,
            style: pw.TextStyle(
              fontSize: valueSize,
              color: valueColor,
              fontWeight: valueWeight,
            ),
          ),
        ],
      ),
    ),
  );
}

List<SupplierQuotePdfItemData> _selectedItems(SupplierQuotePdfOrderData order) {
  return order.items.where((item) => item.selected).toList(growable: false);
}

String _formatMoney(num? value) {
  if (value == null) return '-';
  final formatter = NumberFormat('#,##0.00');
  return '\$${formatter.format(value)}';
}

String _formatNum(num value) {
  final asInt = value.toInt();
  if (value == asInt) return asInt.toString();
  return value.toString();
}
