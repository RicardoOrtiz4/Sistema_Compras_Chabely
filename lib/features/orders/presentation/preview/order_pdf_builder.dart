import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/features/orders/application/create_order_controller.dart';

class OrderPdfData {
  const OrderPdfData({
    required this.branding,
    required this.requesterName,
    required this.requesterArea,
    required this.areaName,
    required this.urgency,
    required this.items,
    required this.createdAt,
    required this.observations,
    this.folio,
    this.updatedAt,
    this.supplier,
    this.internalOrder,
    this.budget,
    this.supplierBudgets = const {},
    this.comprasComment,
    this.comprasReviewerName,
    this.comprasReviewerArea,
    this.direccionGeneralName,
    this.direccionGeneralArea,
    this.requestedDeliveryDate,
    this.etaDate,
    this.resubmissionDates = const [],
  });

  final CompanyBranding branding;
  final String requesterName;
  final String requesterArea;
  final String areaName;
  final PurchaseOrderUrgency urgency;
  final List<OrderItemDraft> items;
  final DateTime createdAt;
  final String observations;

  final String? folio;
  final DateTime? updatedAt;

  final String? supplier;
  final String? internalOrder;

  final num? budget;
  final Map<String, num> supplierBudgets;

  final String? comprasComment;
  final String? comprasReviewerName;
  final String? comprasReviewerArea;

  final String? direccionGeneralName;
  final String? direccionGeneralArea;

  final DateTime? requestedDeliveryDate;
  final DateTime? etaDate;

  final List<DateTime> resubmissionDates;
}

const int defaultPdfPrefetchLimit = 10;

void warmUpPdfAssets(CompanyBranding branding) {
  _loadLogo(branding);
}

void warmUpPdfEngine(CompanyBranding branding) {
  if (_warmedBrandings.contains(branding.id)) return;
  _warmedBrandings.add(branding.id);

  Future(() async {
    try {
      await _loadLogo(branding);
    } catch (error, stack) {
      logError(error, stack, context: 'warmUpPdfEngine');
    }
  });
}

void resetPdfCaches() {
  _pdfCache.clear();
  _logoImageFutures.clear();
  _logoBytesFutures.clear();
  _warmedBrandings.clear();
  _pdfInFlight.clear();
}

Future<Uint8List> buildOrderPdf(
  OrderPdfData data, {
  PdfPageFormat? format,
  bool useIsolate = false,
}) async {
  final cacheKey = _pdfCacheKey(data, format);
  final cached = _pdfCache[cacheKey];
  if (cached != null) {
    return kIsWeb ? Uint8List.fromList(cached) : cached;
  }

  final bytes = useIsolate
      ? await _buildOrderPdfIsolated(data, format)
      : await _buildOrderPdfLocal(data, format);

  _pdfCache[cacheKey] = kIsWeb ? Uint8List.fromList(bytes) : bytes;
  if (_pdfCache.length > _maxPdfCacheEntries) {
    _pdfCache.remove(_pdfCache.keys.first);
  }

  return bytes;
}

void prefetchOrderPdfs(
  List<OrderPdfData> dataList, {
  int limit = defaultPdfPrefetchLimit,
}) {
  if (dataList.isEmpty || limit <= 0) return;
  if (kIsWeb) return;

  final entries = dataList.take(limit).toList(growable: false);
  if (entries.isEmpty) return;

  Future(() async {
    for (final data in entries) {
      final cacheKey = _pdfCacheKey(data, null);
      if (_pdfCache.containsKey(cacheKey) || _pdfInFlight.contains(cacheKey)) {
        continue;
      }
      _pdfInFlight.add(cacheKey);
      try {
        await buildOrderPdf(data, useIsolate: !kIsWeb);
      } catch (error, stack) {
        logError(error, stack, context: 'prefetchOrderPdfs');
      } finally {
        _pdfInFlight.remove(cacheKey);
      }
    }
  });
}

Future<Uint8List> _buildOrderPdfLocal(
  OrderPdfData data,
  PdfPageFormat? format,
) async {
  final logo = await _loadLogo(data.branding);
  return _buildOrderPdfWithLogo(data, format, logo);
}

Future<Uint8List> _buildOrderPdfIsolated(
  OrderPdfData data,
  PdfPageFormat? format,
) async {
  final logoBytes = await _loadLogoBytes(data.branding);
  final payload = _serializePdfPayload(data, format, logoBytes);
  return compute(_buildOrderPdfInIsolate, payload);
}

Future<Uint8List> _buildOrderPdfWithLogo(
  OrderPdfData data,
  PdfPageFormat? format,
  pw.MemoryImage logo,
) async {
  final baseFont = pw.Font.helvetica();
  final boldFont = pw.Font.helveticaBold();

  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
  );

  final pageFormat = (format ?? PdfPageFormat.a4).landscape;
  final dateFormat = _dateFormat;
  final timeFormat = _timeFormat;

  doc.addPage(
    pw.Page(
      pageFormat: pageFormat,
      margin: const pw.EdgeInsets.all(20),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _buildHeader(logo, data.branding),
            pw.SizedBox(height: 8),
            _buildMetaSection(data, dateFormat, timeFormat),
            pw.SizedBox(height: 8),
            _buildItemsTable(data, dateFormat),
            pw.SizedBox(height: 8),
            _buildFooter(data),
          ],
        );
      },
    ),
  );

  return doc.save();
}

Future<pw.MemoryImage> _loadLogo(CompanyBranding branding) {
  final asset = branding.logoAsset;
  return _logoImageFutures.putIfAbsent(
    asset,
    () => rootBundle
        .load(asset)
        .then((bytes) => pw.MemoryImage(bytes.buffer.asUint8List())),
  );
}

Future<Uint8List> _loadLogoBytes(CompanyBranding branding) {
  final asset = branding.logoAsset;
  return _logoBytesFutures.putIfAbsent(
    asset,
    () => rootBundle.load(asset).then((bytes) => bytes.buffer.asUint8List()),
  );
}

final Map<String, Future<Uint8List>> _logoBytesFutures =
    <String, Future<Uint8List>>{};

final Map<String, Future<pw.MemoryImage>> _logoImageFutures =
    <String, Future<pw.MemoryImage>>{};

pw.Widget _buildHeader(pw.MemoryImage logo, CompanyBranding branding) {
  final border = pw.Border.all(width: 0.8, color: PdfColors.grey700);
  final titleBarColor = _pdfColor(branding.pdfTitleBarColor);
  final accentColor = _pdfColor(branding.pdfAccentColor);
  final titleTextColor = branding.pdfTitleBarColor.computeLuminance() < 0.45
      ? PdfColors.white
      : PdfColors.black;

  final isAcerpro = branding.company == Company.acerpro;
  final logoHeight = isAcerpro ? 44.0 : 50.0;
  final logoPadding = isAcerpro
      ? const pw.EdgeInsets.only(left: 6)
      : pw.EdgeInsets.zero;

  return pw.Container(
    decoration: pw.BoxDecoration(border: border),
    padding: const pw.EdgeInsets.all(8),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 110,
          height: 50,
          alignment: pw.Alignment.centerLeft,
          child: pw.Padding(
            padding: logoPadding,
            child: pw.Image(logo, height: logoHeight, fit: pw.BoxFit.contain),
          ),
        ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                branding.pdfHeaderLine1,
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                branding.pdfHeaderLine2,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Container(
                width: double.infinity,
                color: titleBarColor,
                padding: const pw.EdgeInsets.symmetric(vertical: 4),
                child: pw.Text(
                  branding.pdfTitle,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: titleTextColor,
                  ),
                ),
              ),
              pw.Container(height: 2, color: accentColor),
            ],
          ),
        ),
        pw.Container(
          width: 120,
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('HOJA 1 DE 1', style: const pw.TextStyle(fontSize: 8)),
              if (branding.company == Company.acerpro ||
                  branding.company == Company.chabely)
                pw.Text(
                  _acerproRefLine(branding),
                  style: const pw.TextStyle(fontSize: 8),
                )
              else ...[
                pw.Text(
                  'REF: ${branding.pdfRefCode}',
                  style: const pw.TextStyle(fontSize: 8),
                ),
                if (branding.pdfRevision != null &&
                    branding.pdfRevision!.trim().isNotEmpty)
                  pw.Text(
                    'REV: ${branding.pdfRevision}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Widget _buildMetaSection(
  OrderPdfData data,
  DateFormat dateFormat,
  DateFormat timeFormat,
) {
  final border = pw.Border.all(width: 0.8, color: PdfColors.grey700);
  final labelStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
  final valueStyle = const pw.TextStyle(fontSize: 8);

  final requestedDate = data.requestedDeliveryDate;
  final hasFolio = _hasText(data.folio);
  final hasInternalOrder = _hasText(data.internalOrder);

  final resubmissionLabel = _resubmissionLabel(data.resubmissionDates);
  final hasResubmissions = resubmissionLabel != null;
  final modification = _modificationDate(data);
  final showModification = hasResubmissions && modification != null;
  final sameDay = showModification && _isSameDate(data.createdAt, modification);

  return pw.Container(
    decoration: pw.BoxDecoration(border: border),
    padding: const pw.EdgeInsets.all(8),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Container(
                decoration: pw.BoxDecoration(border: border),
                padding: const pw.EdgeInsets.all(6),
                child: pw.Row(
                  children: [
                    pw.Text('NOMBRE DEL SOLICITANTE: ', style: labelStyle),
                    pw.Expanded(
                      child: pw.Text(data.requesterName, style: valueStyle),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Container(
                decoration: pw.BoxDecoration(border: border),
                padding: const pw.EdgeInsets.all(6),
                child: pw.Row(
                  children: [
                    pw.Text('PROCESO: ', style: labelStyle),
                    pw.Expanded(
                      child: pw.Text(data.areaName, style: valueStyle),
                    ),
                  ],
                ),
              ),
              if (requestedDate != null) ...[
                pw.SizedBox(height: 6),
                pw.Container(
                  decoration: pw.BoxDecoration(border: border),
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Row(
                    children: [
                      pw.Text('FECHA MÁXIMA SOLICITADA: ', style: labelStyle),
                      pw.Expanded(
                        child: pw.Text(
                          dateFormat.format(requestedDate),
                          style: valueStyle,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              pw.SizedBox(height: 6),
              pw.Text('URGENCIA:', style: labelStyle),
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  _checkBox('BAJA', data.urgency == PurchaseOrderUrgency.baja),
                  pw.SizedBox(width: 8),
                  _checkBox(
                    'MEDIA',
                    data.urgency == PurchaseOrderUrgency.media,
                  ),
                  pw.SizedBox(width: 8),
                  _checkBox('ALTA', data.urgency == PurchaseOrderUrgency.alta),
                  pw.SizedBox(width: 8),
                  _checkBox(
                    'URGENTE',
                    data.urgency == PurchaseOrderUrgency.urgente,
                  ),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Container(
          width: 200,
          decoration: pw.BoxDecoration(border: border),
          padding: const pw.EdgeInsets.all(6),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              if (hasFolio) ...[
                pw.Row(
                  children: [
                    pw.Text('No. ', style: labelStyle),
                    pw.Expanded(
                      child: pw.Container(
                        decoration: pw.BoxDecoration(border: border),
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: pw.Text(data.folio ?? '', style: valueStyle),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
              ],
              if (hasInternalOrder) ...[
                pw.Row(
                  children: [
                    pw.Text('OC INT. ', style: labelStyle),
                    pw.Expanded(
                      child: pw.Container(
                        decoration: pw.BoxDecoration(border: border),
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: pw.Text(
                          data.internalOrder ?? '',
                          style: valueStyle,
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
              ],
              pw.Container(
                decoration: pw.BoxDecoration(border: border),
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4,
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'FECHA DE CREACIÓN: ${dateFormat.format(data.createdAt)}',
                      style: valueStyle,
                    ),
                    pw.SizedBox(height: 2),
                    if (hasResubmissions) ...[
                      pw.Text(
                        'HORA: ${timeFormat.format(data.createdAt)}',
                        style: valueStyle,
                      ),
                    ] else if (showModification && sameDay) ...[
                      pw.Row(
                        children: [
                          pw.Text(
                            'HORA: ${timeFormat.format(data.createdAt)}',
                            style: valueStyle,
                          ),
                          pw.SizedBox(width: 8),
                          pw.Text(
                            'HORA DE MODIFICACIÓN: ${timeFormat.format(modification)}',
                            style: valueStyle,
                          ),
                        ],
                      ),
                    ] else ...[
                      pw.Text(
                        'HORA: ${timeFormat.format(data.createdAt)}',
                        style: valueStyle,
                      ),
                      if (showModification && !hasResubmissions) ...[
                        pw.SizedBox(height: 2),
                        pw.Text(
                          sameDay
                              ? 'HORA DE MODIFICACIÓN: ${timeFormat.format(modification)}'
                              : 'FECHA DE MODIFICACIÓN: ${dateFormat.format(modification)}',
                          style: valueStyle,
                        ),
                      ],
                    ],
                    if (resubmissionLabel != null) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        resubmissionLabel,
                        style: pw.TextStyle(
                          fontSize: 7,
                          color: PdfColors.grey700,
                          fontStyle: pw.FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Widget _buildBudgetFooter(OrderPdfData data) {
  final budgets = _normalizedBudgets(data.supplierBudgets);
  final total = budgets.isNotEmpty ? _sumBudgets(budgets) : data.budget;
  if (total == null) return pw.SizedBox.shrink();

  final border = pw.Border.all(width: 0.8, color: PdfColors.grey700);
  final entries = budgets.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));

  final supplierColumn = pw.Container(
    decoration: pw.BoxDecoration(border: border, color: PdfColors.yellow200),
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'MONTOS POR PROVEEDOR',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        if (entries.isEmpty)
          pw.Text('Sin desglose', style: const pw.TextStyle(fontSize: 8))
        else
          for (final entry in entries)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Text(
                '${entry.key}: \$${_formatBudget(entry.value)}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
      ],
    ),
  );

  final totalColumn = pw.Container(
    decoration: pw.BoxDecoration(border: border, color: PdfColors.yellow200),
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    child: pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          'MONTO TOTAL A PAGAR',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          '\$${_formatBudget(total)}',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Expanded(flex: 2, child: supplierColumn),
      pw.SizedBox(width: 8),
      pw.Expanded(child: totalColumn),
    ],
  );
}

pw.Widget _checkBox(String label, bool checked) {
  final border = pw.Border.all(width: 0.8, color: PdfColors.grey700);
  return pw.Row(
    children: [
      pw.Container(
        width: 12,
        height: 12,
        decoration: pw.BoxDecoration(border: border),
        alignment: pw.Alignment.center,
        child: checked
            ? pw.Text(
                'X',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
              )
            : null,
      ),
      pw.SizedBox(width: 4),
      pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
    ],
  );
}

pw.Widget _buildItemsTable(OrderPdfData data, DateFormat dateFormat) {
  final headerStyle = pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold);
  final bodyStyle = const pw.TextStyle(fontSize: 7);

  final etaLabel = data.etaDate == null ? '' : dateFormat.format(data.etaDate!);
  final items = _sortItemsForPdf(data.items);

  final hasPartNumber = items.any((item) => _hasText(item.partNumber));
  final hasCustomer = items.any((item) => _hasText(item.customer));
  final hasSupplier =
      _hasText(data.supplier) || items.any((item) => _hasText(item.supplier));
  final hasEta = data.etaDate != null;

  final columns = <_PdfColumn>[
    _PdfColumn(
      label: 'ITEM',
      width: 0.4,
      alignment: pw.Alignment.center,
      value: (item) => item.line.toString(),
    ),
    if (hasPartNumber)
      _PdfColumn(
        label: 'NO. DE PARTE',
        width: 1.1,
        value: (item) => item.partNumber,
      ),
    _PdfColumn(
      label: 'DESCRIPCIÓN',
      width: 2.4,
      value: (item) => item.description,
    ),
    _PdfColumn(
      label: 'CANTIDAD',
      width: 0.7,
      alignment: pw.Alignment.center,
      value: (item) => item.pieces.toString(),
    ),
    _PdfColumn(
      label: 'UNIDAD DE MEDIDA',
      width: 0.9,
      alignment: pw.Alignment.center,
      value: (item) => item.unit,
    ),
    if (hasSupplier)
      _PdfColumn(
        label: 'PROVEEDOR',
        width: 1.0,
        value: (item) => _pickSupplier(item, data),
      ),
    if (hasCustomer)
      _PdfColumn(
        label: 'CLIENTE',
        width: 1.0,
        value: (item) => item.customer ?? '',
      ),
    if (hasEta)
      _PdfColumn(
        label: 'FECHA ESTIMADA DE ENTREGA',
        width: 1.1,
        alignment: pw.Alignment.center,
        value: (_) => etaLabel,
      ),
  ];

  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        for (final column in columns) _headerCell(column.label, headerStyle),
      ],
    ),
  ];

  for (final item in items) {
    rows.add(
      pw.TableRow(
        children: [
          for (final column in columns)
            _bodyCell(
              column.value(item),
              bodyStyle,
              alignment: column.alignment,
            ),
        ],
      ),
    );
  }

  final columnWidths = <int, pw.TableColumnWidth>{
    for (var i = 0; i < columns.length; i++)
      i: pw.FlexColumnWidth(columns[i].width),
  };

  return pw.Table(
    border: pw.TableBorder.all(width: 0.8, color: PdfColors.grey700),
    columnWidths: columnWidths,
    children: rows,
  );
}

List<OrderItemDraft> _sortItemsForPdf(List<OrderItemDraft> items) {
  final sorted = [...items];
  sorted.sort((a, b) {
    final supplierA = _normalizeGroupValue(a.supplier);
    final supplierB = _normalizeGroupValue(b.supplier);
    final supplierEmptyA = supplierA.isEmpty;
    final supplierEmptyB = supplierB.isEmpty;
    if (supplierEmptyA != supplierEmptyB) {
      return supplierEmptyA ? 1 : -1;
    }
    final supplierCompare = supplierA.compareTo(supplierB);
    if (supplierCompare != 0) return supplierCompare;

    final customerA = _normalizeGroupValue(a.customer);
    final customerB = _normalizeGroupValue(b.customer);
    final customerEmptyA = customerA.isEmpty;
    final customerEmptyB = customerB.isEmpty;
    if (customerEmptyA != customerEmptyB) {
      return customerEmptyA ? 1 : -1;
    }
    final customerCompare = customerA.compareTo(customerB);
    if (customerCompare != 0) return customerCompare;

    return a.line.compareTo(b.line);
  });
  return sorted;
}

String _normalizeGroupValue(String? value) {
  if (value == null) return '';
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

pw.Widget _headerCell(String text, pw.TextStyle style) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(4),
    alignment: pw.Alignment.center,
    child: pw.Text(text, style: style, textAlign: pw.TextAlign.center),
  );
}

pw.Widget _bodyCell(
  String text,
  pw.TextStyle style, {
  pw.Alignment alignment = pw.Alignment.centerLeft,
  int maxLines = 2,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    alignment: alignment,
    child: pw.Text(text, style: style, maxLines: maxLines),
  );
}

class _PdfColumn {
  const _PdfColumn({
    required this.label,
    required this.width,
    required this.value,
    this.alignment = pw.Alignment.centerLeft,
  });

  final String label;
  final double width;
  final pw.Alignment alignment;
  final String Function(OrderItemDraft item) value;
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

String _pickSupplier(OrderItemDraft item, OrderPdfData data) {
  final supplier = item.supplier;
  if (_hasText(supplier)) return supplier!.trim();
  return data.supplier ?? '';
}

String _acerproRefLine(CompanyBranding branding) {
  final ref = branding.pdfRefCode.trim();
  final rev = branding.pdfRevision?.trim() ?? '';
  if (rev.isEmpty) return ref;
  return '$ref $rev';
}

String? _resubmissionLabel(List<DateTime> dates) {
  final count = dates.length;
  if (count <= 0) return null;
  if (count == 1) return 'PRIMER REENVÍO';
  return 'REENVIADA $count VECES';
}


DateTime? _modificationDate(OrderPdfData data) {
  final updatedAt = data.updatedAt;
  if (updatedAt == null) return null;
  if (updatedAt.millisecondsSinceEpoch == data.createdAt.millisecondsSinceEpoch) {
    return null;
  }
  return updatedAt;
}

bool _isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

pw.Widget _buildFooter(OrderPdfData data) {
  final border = pw.Border.all(width: 0.8, color: PdfColors.grey700);
  final labelStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
  final valueStyle = const pw.TextStyle(fontSize: 8);

  final hasObservations = data.observations.trim().isNotEmpty;
  final hasComprasInfo =
      _hasText(data.supplier) ||
      data.budget != null ||
      _hasText(data.comprasComment);

  final footerSections = <pw.Widget>[];

  if (hasObservations || hasComprasInfo) {
    if (hasObservations && hasComprasInfo) {
      footerSections.add(
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _buildObservationsBox(
                data,
                border: border,
                labelStyle: labelStyle,
                valueStyle: valueStyle,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _buildComprasBox(
                data,
                border: border,
                labelStyle: labelStyle,
                valueStyle: valueStyle,
              ),
            ),
          ],
        ),
      );
    } else if (hasObservations) {
      footerSections.add(
        _buildObservationsBox(
          data,
          border: border,
          labelStyle: labelStyle,
          valueStyle: valueStyle,
        ),
      );
    } else if (hasComprasInfo) {
      footerSections.add(
        _buildComprasBox(
          data,
          border: border,
          labelStyle: labelStyle,
          valueStyle: valueStyle,
        ),
      );
    }
    footerSections.add(pw.SizedBox(height: 6));
  }

  final showBudgetFooter =
      data.budget != null || data.supplierBudgets.isNotEmpty;

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      ...footerSections,
      _buildSignatureRow(data),
      if (showBudgetFooter) ...[
        pw.SizedBox(height: 6),
        _buildBudgetFooter(data),
      ],
    ],
  );
}

pw.Widget _buildObservationsBox(
  OrderPdfData data, {
  required pw.Border border,
  required pw.TextStyle labelStyle,
  required pw.TextStyle valueStyle,
}) {
  return pw.Container(
    decoration: pw.BoxDecoration(border: border),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          color: const PdfColor(0.86, 0.93, 1),
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: pw.Text('OBSERVACIONES', style: labelStyle),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(data.observations, style: valueStyle),
        ),
      ],
    ),
  );
}

pw.Widget _buildComprasBox(
  OrderPdfData data, {
  required pw.Border border,
  required pw.TextStyle labelStyle,
  required pw.TextStyle valueStyle,
}) {
  return pw.Container(
    decoration: pw.BoxDecoration(border: border),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          color: const PdfColor(0.9, 0.98, 0.9),
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: pw.Text('REVISIÓN COMPRAS', style: labelStyle),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (_hasText(data.supplier)) ...[
                pw.Text('Proveedor: ${data.supplier}', style: valueStyle),
                pw.SizedBox(height: 4),
              ],
              if (_hasText(data.comprasComment)) ...[
                pw.Text(
                  'Comentarios compras: ${data.comprasComment}',
                  style: valueStyle,
                ),
              ],
              if (!_hasText(data.supplier) &&
                  data.budget == null &&
                  !_hasText(data.comprasComment))
                pw.Text('Sin comentarios.', style: valueStyle),
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Widget _buildSignatureRow(OrderPdfData data) {
  final signatures = <pw.Widget>[
    _signatureBox('ELABORÓ', data.requesterName, null),
  ];

  final hasCompras =
      _hasText(data.comprasReviewerName) || _hasText(data.comprasReviewerArea);
  final hasDireccion =
      _hasText(data.direccionGeneralName) || _hasText(data.direccionGeneralArea);

  if (hasCompras) {
    signatures.add(
      _signatureBox(
        'RECIBIÓ',
        data.comprasReviewerName ?? '',
        data.comprasReviewerArea,
      ),
    );
  }
  if (hasDireccion) {
    signatures.add(
      _signatureBox(
        'APROBÓ',
        data.direccionGeneralName ?? '',
        data.direccionGeneralArea,
      ),
    );
  }

  return pw.Row(
    children: [
      for (var i = 0; i < signatures.length; i++) ...[
        if (i > 0) pw.SizedBox(width: 8),
        signatures[i],
      ],
    ],
  );
}

Map<String, num> _normalizedBudgets(Map<String, num> raw) {
  if (raw.isEmpty) return const {};
  final normalized = <String, num>{};
  for (final entry in raw.entries) {
    final key = entry.key.trim();
    if (key.isEmpty) continue;
    normalized[key] = entry.value;
  }
  return normalized;
}

num _sumBudgets(Map<String, num> budgets) {
  var total = 0.0;
  for (final value in budgets.values) {
    total += value.toDouble();
  }
  return total;
}

String _formatBudget(num? value) {
  if (value == null) return '';
  final formatter = NumberFormat('#,##0.##');
  return formatter.format(value);
}

pw.Widget _signatureBox(String label, String value, String? area) {
  final border = pw.Border.all(width: 0.8, color: PdfColors.grey700);
  final areaLabel = (area == null || area.trim().isEmpty) ? '' : area.trim();

  return pw.Expanded(
    child: pw.Container(
      decoration: pw.BoxDecoration(border: border),
      padding: const pw.EdgeInsets.all(6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          pw.Text(value, style: const pw.TextStyle(fontSize: 8)),
          if (areaLabel.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text('Área: $areaLabel', style: const pw.TextStyle(fontSize: 7)),
          ],
        ],
      ),
    ),
  );
}

String _pdfCacheKey(OrderPdfData data, PdfPageFormat? format) {
  final buffer = StringBuffer();

  if (format != null) {
    buffer
      ..write('f:')
      ..write(format.width.toStringAsFixed(2))
      ..write('x')
      ..write(format.height.toStringAsFixed(2))
      ..write(';');
  }

  buffer
    ..write('brand:')
    ..write(data.branding.id)
    ..write(';')
    ..write('folio:')
    ..write(data.folio ?? '')
    ..write(';req:')
    ..write(data.requesterName)
    ..write('|')
    ..write(data.requesterArea)
    ..write(';area:')
    ..write(data.areaName)
    ..write(';urg:')
    ..write(data.urgency.name)
    ..write(';created:')
    ..write(data.createdAt.millisecondsSinceEpoch)
    ..write(';updated:')
    ..write(data.updatedAt?.millisecondsSinceEpoch.toString() ?? '')
    ..write(';obs:')
    ..write(data.observations)
    ..write(';supplier:')
    ..write(data.supplier ?? '')
    ..write(';internal:')
    ..write(data.internalOrder ?? '')
    ..write(';budget:')
    ..write(data.budget?.toString() ?? '')
    ..write(';supplierBudgets:');

  if (data.supplierBudgets.isNotEmpty) {
    final entries = data.supplierBudgets.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in entries) {
      buffer
        ..write(entry.key)
        ..write('=')
        ..write(entry.value)
        ..write(',');
    }
  }

  buffer
    ..write(';comment:')
    ..write(data.comprasComment ?? '')
    ..write(';rev:')
    ..write(data.comprasReviewerName ?? '')
    ..write('|')
    ..write(data.comprasReviewerArea ?? '')
    ..write(';dg:')
    ..write(data.direccionGeneralName ?? '')
    ..write('|')
    ..write(data.direccionGeneralArea ?? '')
    ..write(';reqDate:')
    ..write(data.requestedDeliveryDate?.millisecondsSinceEpoch.toString() ?? '')
    ..write(';eta:')
    ..write(data.etaDate?.millisecondsSinceEpoch.toString() ?? '')
    ..write(';resub:');

  for (final date in data.resubmissionDates) {
    buffer.write('${date.millisecondsSinceEpoch},');
  }

  buffer.write(';items:');
  for (final item in data.items) {
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
      ..write(item.reviewFlagged ? '1' : '0')
      ..write('|')
      ..write(item.reviewComment ?? '')
      ..write(';');
  }

  return buffer.toString();
}

const int _maxPdfCacheEntries = 24;
final LinkedHashMap<String, Uint8List> _pdfCache =
    LinkedHashMap<String, Uint8List>();
final Set<String> _pdfInFlight = <String>{};
final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
final DateFormat _timeFormat = DateFormat('HH:mm');
final Set<String> _warmedBrandings = <String>{};

PdfColor _pdfColor(Color color) => PdfColor.fromInt(color.toARGB32());

Uint8List? getCachedOrderPdf(
  OrderPdfData data, {
  PdfPageFormat? format,
}) {
  final cacheKey = _pdfCacheKey(data, format);
  final cached = _pdfCache[cacheKey];
  if (cached == null) return null;
  return kIsWeb ? Uint8List.fromList(cached) : cached;
}

Map<String, dynamic> _serializePdfPayload(
  OrderPdfData data,
  PdfPageFormat? format,
  Uint8List logoBytes,
) {
  return {
    // OJO: para reconstruir branding en isolate, guardamos el company name
    'company': data.branding.company.name,
    'brandingId': data.branding.id,
    'logoBytes': logoBytes,
    'formatWidth': format?.width,
    'formatHeight': format?.height,
    'requesterName': data.requesterName,
    'requesterArea': data.requesterArea,
    'areaName': data.areaName,
    'urgency': data.urgency.name,
    'items': data.items
        .map(
          (item) => {
            'line': item.line,
            'pieces': item.pieces,
            'partNumber': item.partNumber,
            'description': item.description,
            'quantity': item.quantity,
            'unit': item.unit,
            'customer': item.customer,
            'supplier': item.supplier,
            'budget': item.budget,
            'estimatedDate': item.estimatedDate?.millisecondsSinceEpoch,
            'reviewFlagged': item.reviewFlagged,
            'reviewComment': item.reviewComment,
          },
        )
        .toList(),
    'createdAt': data.createdAt.millisecondsSinceEpoch,
    'updatedAt': data.updatedAt?.millisecondsSinceEpoch,
    'observations': data.observations,
    'folio': data.folio,
    'supplier': data.supplier,
    'internalOrder': data.internalOrder,
    'budget': data.budget,
    'supplierBudgets': data.supplierBudgets,
    'comprasComment': data.comprasComment,
    'comprasReviewerName': data.comprasReviewerName,
    'comprasReviewerArea': data.comprasReviewerArea,
    'direccionGeneralName': data.direccionGeneralName,
    'direccionGeneralArea': data.direccionGeneralArea,
    'requestedDeliveryDate': data.requestedDeliveryDate?.millisecondsSinceEpoch,
    'etaDate': data.etaDate?.millisecondsSinceEpoch,
    'resubmissionDates': data.resubmissionDates
        .map((date) => date.millisecondsSinceEpoch)
        .toList(),
  };
}

Future<Uint8List> _buildOrderPdfInIsolate(Map<String, dynamic> payload) async {
  final companyName = payload['company'] as String?;
  final company = Company.values.firstWhere(
    (c) => c.name == companyName,
    orElse: () => Company.chabely,
  );

  final branding = brandingFor(company);

  final logoBytes = payload['logoBytes'] as Uint8List;
  final logo = pw.MemoryImage(logoBytes);

  final formatWidth = payload['formatWidth'] as double?;
  final formatHeight = payload['formatHeight'] as double?;
  final format = (formatWidth != null && formatHeight != null)
      ? PdfPageFormat(formatWidth, formatHeight)
      : null;

  final data = _deserializeOrderPdfData(payload, branding);
  return _buildOrderPdfWithLogo(data, format, logo);
}

OrderPdfData _deserializeOrderPdfData(
  Map<String, dynamic> payload,
  CompanyBranding branding,
) {
  final items = <OrderItemDraft>[];
  final rawItems = payload['items'];

  if (rawItems is List) {
    for (final raw in rawItems) {
      if (raw is Map) {
        items.add(
          OrderItemDraft(
            line: (raw['line'] as num?)?.toInt() ?? 0,
            pieces: (raw['pieces'] as num?)?.toInt() ?? 0,
            partNumber: (raw['partNumber'] as String?) ?? '',
            description: (raw['description'] as String?) ?? '',
            quantity: (raw['quantity'] as num?) ?? 0,
            unit: (raw['unit'] as String?) ?? '',
            customer: raw['customer'] as String?,
            supplier: raw['supplier'] as String?,
            budget: raw['budget'] as num?,
            estimatedDate: _parseMillis(raw['estimatedDate']),
            reviewFlagged: (raw['reviewFlagged'] as bool?) ?? false,
            reviewComment: raw['reviewComment'] as String?,
          ),
        );
      }
    }
  }

  return OrderPdfData(
    branding: branding,
    requesterName: (payload['requesterName'] as String?) ?? '',
    requesterArea: (payload['requesterArea'] as String?) ?? '',
    areaName: (payload['areaName'] as String?) ?? '',
    urgency: _urgencyFromName(payload['urgency'] as String?),
    items: items,
    createdAt: _parseMillis(payload['createdAt']) ?? DateTime.now(),
    updatedAt: _parseMillis(payload['updatedAt']),
    observations: (payload['observations'] as String?) ?? '',
    folio: payload['folio'] as String?,
    supplier: payload['supplier'] as String?,
    internalOrder: payload['internalOrder'] as String?,
    budget: payload['budget'] as num?,
    supplierBudgets: _parseSupplierBudgets(payload['supplierBudgets']),
    comprasComment: payload['comprasComment'] as String?,
    comprasReviewerName: payload['comprasReviewerName'] as String?,
    comprasReviewerArea: payload['comprasReviewerArea'] as String?,
    direccionGeneralName: payload['direccionGeneralName'] as String?,
    direccionGeneralArea: payload['direccionGeneralArea'] as String?,
    requestedDeliveryDate: _parseMillis(payload['requestedDeliveryDate']),
    etaDate: _parseMillis(payload['etaDate']),
    resubmissionDates: _parseResubmissionDates(payload['resubmissionDates']),
  );
}

PurchaseOrderUrgency _urgencyFromName(String? raw) {
  if (raw == null) return PurchaseOrderUrgency.media;
  return PurchaseOrderUrgency.values.firstWhere(
    (e) => e.name == raw,
    orElse: () => PurchaseOrderUrgency.media,
  );
}

DateTime? _parseMillis(dynamic value) {
  if (value == null) return null;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return DateTime.fromMillisecondsSinceEpoch(parsed);
  }
  return null;
}

Map<String, num> _parseSupplierBudgets(dynamic value) {
  final budgets = <String, num>{};

  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString().trim();
      if (key.isEmpty) continue;

      final raw = entry.value;
      num? parsed;
      if (raw is num) {
        parsed = raw;
      } else if (raw is String) {
        parsed = num.tryParse(raw.trim());
      }

      if (parsed != null) {
        budgets[key] = parsed;
      }
    }
  }

  return budgets;
}

List<DateTime> _parseResubmissionDates(dynamic value) {
  if (value is! List) return const [];
  final dates = <DateTime>[];
  for (final entry in value) {
    final parsed = _parseMillis(entry);
    if (parsed != null) dates.add(parsed);
  }
  return dates;
}
