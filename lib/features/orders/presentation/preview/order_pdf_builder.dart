import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/extensions.dart';
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
    this.cacheSalt,
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

  // Used to bust PDF caches without affecting visual content.
  final String? cacheSalt;
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
  _orderPdfStickyCache.clear();
  _logoImageFutures.clear();
  _logoBytesFutures.clear();
  _pdfFontFutures.clear();
  _pdfFontBytesFutures.clear();
  _pdfFontsFuture = null;
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
    _storeOrderPdfForFolio(data, cached, format: format);
    return kIsWeb ? Uint8List.fromList(cached) : cached;
  }

  final bytes = useIsolate
      ? await _buildOrderPdfIsolated(data, format)
      : await _buildOrderPdfLocal(data, format);

  _pdfCache[cacheKey] = kIsWeb ? Uint8List.fromList(bytes) : bytes;
  if (_pdfCache.length > _maxPdfCacheEntries) {
    _pdfCache.remove(_pdfCache.keys.first);
  }
  _storeOrderPdfForFolio(data, bytes, format: format);

  return bytes;
}

Future<Uint8List> buildOrderPdfUncached(
  OrderPdfData data, {
  PdfPageFormat? format,
  bool useIsolate = false,
}) async {
  final bytes = useIsolate
      ? await _buildOrderPdfIsolated(data, format)
      : await _buildOrderPdfLocal(data, format);
  _storeOrderPdfForFolio(data, bytes, format: format);
  return bytes;
}

Future<Uint8List> buildCotizacionPdf(
  OrderPdfData data, {
  PdfPageFormat? format,
  bool useIsolate = false,
}) async {
  return useIsolate
      ? await _buildCotizacionPdfIsolated(data, format)
      : await _buildCotizacionPdfLocal(data, format);
}

void prefetchOrderPdfs(
  List<OrderPdfData> dataList, {
  int limit = defaultPdfPrefetchLimit,
}) {
  if (dataList.isEmpty || limit <= 0) return;

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
  final fonts = await _loadPdfFonts();
  final sanitized = _sanitizePdfData(data);
  return _buildOrderPdfWithAssets(
    sanitized,
    format,
    logo,
    fonts.base,
    fonts.bold,
  );
}

Future<Uint8List> _buildOrderPdfIsolated(
  OrderPdfData data,
  PdfPageFormat? format,
) async {
  final logoBytes = await _loadLogoBytes(data.branding);
  final baseFontBytes = await _loadPdfFontBytes(_pdfBaseFontAsset);
  final boldFontBytes = await _loadPdfFontBytes(_pdfBoldFontAsset);
  final sanitized = _sanitizePdfData(data);
  final payload = _serializePdfPayload(
    sanitized,
    format,
    logoBytes,
    baseFontBytes,
    boldFontBytes,
  );
  return compute(_buildOrderPdfInIsolate, payload);
}

Future<Uint8List> _buildCotizacionPdfLocal(
  OrderPdfData data,
  PdfPageFormat? format,
) async {
  final logo = await _loadLogo(data.branding);
  final fonts = await _loadPdfFonts();
  final sanitized = _sanitizePdfData(data);
  return _buildCotizacionPdfWithAssets(
    sanitized,
    format,
    logo,
    fonts.base,
    fonts.bold,
  );
}

Future<Uint8List> _buildCotizacionPdfIsolated(
  OrderPdfData data,
  PdfPageFormat? format,
) async {
  final logoBytes = await _loadLogoBytes(data.branding);
  final baseFontBytes = await _loadPdfFontBytes(_pdfBaseFontAsset);
  final boldFontBytes = await _loadPdfFontBytes(_pdfBoldFontAsset);
  final sanitized = _sanitizePdfData(data);
  final payload = _serializePdfPayload(
    sanitized,
    format,
    logoBytes,
    baseFontBytes,
    boldFontBytes,
  );
  return compute(_buildCotizacionPdfInIsolate, payload);
}

Future<Uint8List> _buildOrderPdfWithAssets(
  OrderPdfData data,
  PdfPageFormat? format,
  pw.MemoryImage logo,
  pw.Font baseFont,
  pw.Font boldFont,
) async {
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
  );

  final pageFormat = (format ?? PdfPageFormat.a4).landscape;
  final dateFormat = _dateFormat;
  final timeFormat = _timeFormat;

  doc.addPage(
    pw.MultiPage(
      pageFormat: pageFormat,
      margin: const pw.EdgeInsets.all(20),
      maxPages: _estimateMaxPages(data),
      header: (context) {
        final pageNumber = _safePageNumber(context);
        final pageCount = _safePageCount(context);
        if (pageNumber != null && pageNumber != 1) {
          return pw.SizedBox.shrink();
        }
        return _buildHeader(
          logo,
          data.branding,
          pageNumber: pageNumber,
          pageCount: pageCount,
        );
      },
      footer: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _buildSignatureRow(data),
          ],
        );
      },
      build: (context) => [
        pw.SizedBox(height: 8),
        _buildMetaSection(data, dateFormat, timeFormat),
        pw.SizedBox(height: 8),
        ..._buildItemsTables(data, dateFormat),
        pw.SizedBox(height: 8),
        ..._buildFooterSections(data),
      ],
    ),
  );

  return doc.save();
}

Future<Uint8List> _buildCotizacionPdfWithAssets(
  OrderPdfData data,
  PdfPageFormat? format,
  pw.MemoryImage logo,
  pw.Font baseFont,
  pw.Font boldFont,
) async {
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
  );

  final pageFormat = (format ?? PdfPageFormat.a4).landscape;
  final dateFormat = _dateFormat;
  final timeFormat = _timeFormat;

  doc.addPage(
    pw.MultiPage(
      pageFormat: pageFormat,
      margin: const pw.EdgeInsets.all(20),
      maxPages: _estimateMaxPages(data),
      header: (context) {
        final pageNumber = _safePageNumber(context);
        final pageCount = _safePageCount(context);
        if (pageNumber != null && pageNumber != 1) {
          return pw.SizedBox.shrink();
        }
        return _buildHeader(
          logo,
          data.branding,
          pageNumber: pageNumber,
          pageCount: pageCount,
        );
      },
      build: (context) {
        _buildNotesSectionWidgets(data);
        return [
          pw.SizedBox(height: 8),
          _sectionTitle('DATOS DE REQUISICION'),
          _buildMetaSection(data, dateFormat, timeFormat),
          pw.SizedBox(height: 8),
          _sectionTitle('ARTICULOS'),
          ..._buildItemsTables(data, dateFormat),

          pw.SizedBox(height: 12),
          _sectionTitle('FIRMAS'),
          _buildSignatureRow(data),
        ];
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

const String _pdfBaseFontAsset = 'assets/fonts/arial.ttf';
const String _pdfBoldFontAsset = 'assets/fonts/arialbd.ttf';

final Map<String, Future<pw.Font>> _pdfFontFutures =
    <String, Future<pw.Font>>{};
final Map<String, Future<Uint8List>> _pdfFontBytesFutures =
    <String, Future<Uint8List>>{};
Future<_PdfFonts>? _pdfFontsFuture;

Future<_PdfFonts> _loadPdfFonts() {
  final cached = _pdfFontsFuture;
  if (cached != null) return cached;
  final future = Future<_PdfFonts>(() async {
    final base = await _loadPdfFont(_pdfBaseFontAsset);
    final bold = await _loadPdfFont(_pdfBoldFontAsset);
    return _PdfFonts(base, bold);
  });
  _pdfFontsFuture = future;
  return future;
}

Future<pw.Font> _loadPdfFont(String asset) {
  return _pdfFontFutures.putIfAbsent(
    asset,
    () => rootBundle.load(asset).then((bytes) => pw.Font.ttf(bytes)),
  );
}

Future<Uint8List> _loadPdfFontBytes(String asset) {
  return _pdfFontBytesFutures.putIfAbsent(
    asset,
    () => rootBundle.load(asset).then((bytes) => bytes.buffer.asUint8List()),
  );
}

class _PdfFonts {
  const _PdfFonts(this.base, this.bold);

  final pw.Font base;
  final pw.Font bold;
}

pw.Widget _buildHeader(
  pw.MemoryImage logo,
  CompanyBranding branding, {
  int? pageNumber,
  int? pageCount,
}) {
  final border = pw.Border.all(width: 0.8, color: PdfColors.grey700);
  final titleBarColor = _pdfColor(branding.pdfTitleBarColor);
  final accentColor = _pdfColor(branding.pdfAccentColor);
  final titleTextColor = branding.pdfTitleBarColor.computeLuminance() < 0.45
      ? PdfColors.white
      : PdfColors.black;
  final pageLabel = (pageNumber != null && pageCount != null && pageCount > 0)
      ? 'HOJA $pageNumber DE $pageCount'
      : 'HOJA 1 DE 1';

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
              pw.Text(pageLabel, style: const pw.TextStyle(fontSize: 8)),
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

pw.Widget _sectionTitle(String text) {
  return pw.Container(
    width: double.infinity,
    color: PdfColors.grey300,
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
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
  final showRequestedDate = requestedDate != null;
  final hasFolio = _hasText(data.folio);
  final hasInternalOrder = _hasText(data.internalOrder);

  final resubmissionLabel = _resubmissionLabel(data.resubmissionDates);
  final modification = _modificationDate(data);
  final showModificationTime =
      modification != null && data.resubmissionDates.isEmpty;

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
              pw.SizedBox(height: 6),
              pw.Text('URGENCIA:', style: labelStyle),
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  _checkBox(
                    'BAJA',
                    data.urgency == PurchaseOrderUrgency.baja,
                  ),
                  pw.SizedBox(width: 8),
                  _checkBox(
                    'MEDIA',
                    data.urgency == PurchaseOrderUrgency.media,
                  ),
                  pw.SizedBox(width: 8),
                  _checkBox(
                    'ALTA',
                    data.urgency == PurchaseOrderUrgency.alta,
                  ),
                  pw.SizedBox(width: 8),
                  _checkBox(
                    'URGENTE',
                    data.urgency == PurchaseOrderUrgency.urgente,
                  ),
                  if (showRequestedDate) ...[
                    pw.SizedBox(width: 12),
                    pw.Text('FECHA MÁXIMA SOLICITADA: ', style: labelStyle),
                    pw.Text(requestedDate.toShortDate(), style: valueStyle),
                  ],
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
                    pw.Text(
                      'HORA: ${timeFormat.format(data.createdAt)}',
                      style: valueStyle,
                    ),
                    if (modification != null) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'FECHA DE MODIFICACIÓN: ${dateFormat.format(modification)}',
                        style: valueStyle,
                      ),
                      if (showModificationTime)
                        pw.Text(
                          'HORA DE MODIFICACIÓN: ${timeFormat.format(modification)}',
                          style: valueStyle,
                        ),
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
                    if (data.resubmissionDates.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      for (var i = 0; i < data.resubmissionDates.length; i++)
                        pw.Text(
                          'REENVÍO ${i + 1}: ${_formatResubmissionStampPdf(data.resubmissionDates[i], data.createdAt, dateFormat, timeFormat)}',
                          style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
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

pw.Widget _buildItemsTable(
  OrderPdfData data,
  DateFormat dateFormat, {
  List<OrderItemDraft>? itemsOverride,
  required bool showCost,
  bool isLastTable = false,
  num? totalCost,
}) {
  final headerStyle = pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold);
  final bodyStyle = const pw.TextStyle(fontSize: 7);

  final etaLabel = data.etaDate == null ? '' : dateFormat.format(data.etaDate!);
  final items = _sortItemsForPdf(itemsOverride ?? data.items);

  final hasPartNumber = items.any((item) => _hasText(item.partNumber));
  final hasCustomer = items.any((item) => _hasText(item.customer));
  final hasSupplier =
      _hasText(data.supplier) || items.any((item) => _hasText(item.supplier));
  final hasEta = data.etaDate != null;
  final showCostColumn = showCost;

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
    if (showCostColumn)
      _PdfColumn(
        label: 'COSTO',
        width: 0.9,
        alignment: pw.Alignment.centerRight,
        value: (item) => _formatCost(item.budget),
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
  final table = pw.Table(
    border: pw.TableBorder.all(width: 0.8, color: PdfColors.grey700),
    columnWidths: columnWidths,
    children: rows,
  );
  if (!showCostColumn || !isLastTable || totalCost == null) {
    return table;
  }

  final totalFlex = columns.fold<int>(
    0,
    (sum, column) => sum + (column.width * 100).round(),
  );
  final costFlex = (columns.last.width * 100).round();
  final spacerFlex = (totalFlex - costFlex).clamp(0, totalFlex);

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      table,
      pw.SizedBox(height: 2),
      pw.Row(
        children: [
          if (spacerFlex > 0)
            pw.Expanded(flex: spacerFlex, child: pw.SizedBox.shrink()),
          pw.Expanded(
            flex: costFlex > 0 ? costFlex : 1,
            child: _totalCostCell(totalCost, bodyStyle),
          ),
        ],
      ),
    ],
  );
}

List<pw.Widget> _buildItemsTables(OrderPdfData data, DateFormat dateFormat) {
  final sorted = _sortItemsForPdf(data.items);
  final showCost = _shouldShowCostColumn(data);
  final totalCost = showCost ? _totalCostForPdf(data) : null;
  if (sorted.isEmpty) {
    return [
      _buildItemsTable(
        data,
        dateFormat,
        itemsOverride: sorted,
        showCost: showCost,
        isLastTable: true,
        totalCost: totalCost,
      ),
    ];
  }

  final tables = <pw.Widget>[];
  for (var i = 0; i < sorted.length; i += _itemsPerPageEstimate) {
    var end = i + _itemsPerPageEstimate;
    if (end > sorted.length) end = sorted.length;
    final chunk = sorted.sublist(i, end);
    final isLastTable = end >= sorted.length;
    tables.add(
      _buildItemsTable(
        data,
        dateFormat,
        itemsOverride: chunk,
        showCost: showCost,
        isLastTable: isLastTable,
        totalCost: isLastTable ? totalCost : null,
      ),
    );
    if (end < sorted.length) {
      tables.add(pw.SizedBox(height: 8));
    }
  }
  return tables;
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

String _formatResubmissionStampPdf(
  DateTime stamp,
  DateTime createdAt,
  DateFormat dateFormat,
  DateFormat timeFormat,
) {
  if (_isSameDate(stamp, createdAt)) {
    return timeFormat.format(stamp);
  }
  return '${dateFormat.format(stamp)} ${timeFormat.format(stamp)}';
}

String _autorizaName(OrderPdfData data) {
  final direccion = (data.direccionGeneralName ?? '').trim();
  if (direccion.isNotEmpty) return direccion;
  return (data.comprasReviewerName ?? '').trim();
}

String? _autorizaArea(OrderPdfData data) {
  final direccionArea = (data.direccionGeneralArea ?? '').trim();
  if (direccionArea.isNotEmpty) return direccionArea;
  final comprasArea = (data.comprasReviewerArea ?? '').trim();
  return comprasArea.isEmpty ? null : comprasArea;
}


DateTime? _modificationDate(OrderPdfData data) {
  final updatedAt = data.updatedAt;
  if (updatedAt == null) return null;
  if (_isSameDate(updatedAt, data.createdAt)) {
    return null;
  }
  return updatedAt;
}

bool _isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}


List<pw.Widget> _buildNotesSectionWidgets(OrderPdfData data) {
  final notes = <pw.Widget>[];
  final hasObservations = data.observations.trim().isNotEmpty;
  final comprasText = _composeComprasText(data);

  if (hasObservations) {
    notes.addAll(
      _buildTextSection(
        'OBSERVACIONES',
        data.observations,
        labelStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        valueStyle: const pw.TextStyle(fontSize: 8),
      ),
    );
  }

  if (comprasText.trim().isNotEmpty) {
    if (notes.isNotEmpty) {
      notes.add(pw.SizedBox(height: 6));
    }
    notes.addAll(
      _buildTextSection(
        'REVISIÓN DEL ÁREA DE COMPRAS',
        comprasText,
        labelStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        valueStyle: const pw.TextStyle(fontSize: 8),
      ),
    );
  }

  return notes;
}


String _composeComprasText(OrderPdfData data) {
  final comment = (data.comprasComment ?? '').trim();
  if (comment.isEmpty) return '';
  return comment;
}

List<pw.Widget> _buildTextSection(
  String title,
  String text, {
  required pw.TextStyle labelStyle,
  required pw.TextStyle valueStyle,
}) {
  final chunks = _splitText(text, _textChunkSize);
  if (chunks.isEmpty) return const [];

  final widgets = <pw.Widget>[
    pw.Container(
      width: double.infinity,
      color: PdfColors.grey300,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: pw.Text(title, style: labelStyle),
    ),
  ];

  for (final chunk in chunks) {
    widgets.add(
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Text(chunk, style: valueStyle),
      ),
    );
  }

  return widgets;
}

List<String> _splitText(String text, int maxChars) {
  final cleaned = text.replaceAll('\r\n', '\n').trim();
  if (cleaned.isEmpty) return const [];
  if (cleaned.length <= maxChars) return [cleaned];

  final chunks = <String>[];
  var remaining = cleaned;
  while (remaining.length > maxChars) {
    var splitAt = remaining.lastIndexOf(' ', maxChars);
    if (splitAt <= 0) splitAt = maxChars;
    chunks.add(remaining.substring(0, splitAt).trim());
    remaining = remaining.substring(splitAt).trim();
  }
  if (remaining.isNotEmpty) {
    chunks.add(remaining);
  }
  return chunks;
}

pw.Widget _buildSignatureRow(OrderPdfData data) {
  final signatures = <pw.Widget>[
    _signatureBox(
      label: 'SOLICITÓ',
      name: data.requesterName,
    ),
    _signatureBox(
      label: 'PROCESÓ',
      name: '',
      area: null,
      areaInTitle: true,
    ),
    _signatureBox(
      label: 'AUTORIZÓ',
      name: _autorizaName(data),
      area: _autorizaArea(data),
      areaInTitle: true,
    ),
  ];

  return pw.Row(
    children: [
      for (var i = 0; i < signatures.length; i++) ...[
        if (i > 0) pw.SizedBox(width: 8),
        signatures[i],
      ],
    ],
  );
}


List<pw.Widget> _buildFooterSections(OrderPdfData data) {
  final sections = <pw.Widget>[];

  final hasObservations = data.observations.trim().isNotEmpty;
  final comprasText = _composeComprasText(data);

  if (hasObservations) {
    sections.addAll(
      _buildTextSection(
        'OBSERVACIONES',
        data.observations,
        labelStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        valueStyle: const pw.TextStyle(fontSize: 8),
      ),
    );
  }

  if (comprasText.trim().isNotEmpty) {
    if (sections.isNotEmpty) {
      sections.add(pw.SizedBox(height: 6));
    }
    sections.addAll(
      _buildTextSection(
        'REVISIÓN DEL ÁREA DE COMPRAS',
        comprasText,
        labelStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        valueStyle: const pw.TextStyle(fontSize: 8),
      ),
    );
  }

  return sections;
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

bool _shouldShowCostColumn(OrderPdfData data) {
  if (data.items.any((item) => item.budget != null)) return true;
  if (_normalizedBudgets(data.supplierBudgets).isNotEmpty) return true;
  return data.budget != null;
}

num? _totalCostForPdf(OrderPdfData data) {
  final itemBudgets = data.items
      .map((item) => item.budget)
      .whereType<num>()
      .toList(growable: false);
  if (itemBudgets.isNotEmpty) {
    var total = 0.0;
    for (final value in itemBudgets) {
      total += value.toDouble();
    }
    return total;
  }

  final budgets = _normalizedBudgets(data.supplierBudgets);
  if (budgets.isNotEmpty) return _sumBudgets(budgets);

  return data.budget;
}

String _formatBudget(num? value) {
  if (value == null) return '';
  final formatter = NumberFormat('#,##0.##');
  return formatter.format(value);
}

String _formatCost(num? value) {
  if (value == null) return '';
  return '\$${_formatBudget(value)}';
}

pw.Widget _totalCostCell(
  num totalCost,
  pw.TextStyle baseStyle,
) {
  final totalStyle = pw.TextStyle(
    fontSize: baseStyle.fontSize,
    fontWeight: pw.FontWeight.bold,
  );
  final label = 'TOTAL A PAGAR: \$${_formatBudget(totalCost)}';
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    decoration: pw.BoxDecoration(
      color: PdfColors.grey200,
      border: pw.Border.all(width: 0.8, color: PdfColors.grey700),
    ),
    alignment: pw.Alignment.centerRight,
    child: pw.Text(label, style: totalStyle, textAlign: pw.TextAlign.right),
  );
}

pw.Widget _signatureBox({
  required String label,
  required String name,
  String? area,
  bool areaInTitle = false,
}) {
  final border = pw.Border.all(width: 0.8, color: PdfColors.grey700);
  final areaLabel = (area == null || area.trim().isEmpty) ? '' : area.trim();

  return pw.Expanded(
    child: pw.Container(
      decoration: pw.BoxDecoration(border: border),
      padding: const pw.EdgeInsets.all(6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (areaInTitle && areaLabel.isNotEmpty)
            pw.Row(
              children: [
                pw.Text(
                  label,
                  style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
                ),
                pw.Spacer(),
                pw.Text(
                  areaLabel,
                  style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
                ),
              ],
            )
          else
            pw.Text(
              label,
              style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
            ),
          pw.SizedBox(height: 12),
          pw.Text(name, style: const pw.TextStyle(fontSize: 8)),
          if (!areaInTitle && areaLabel.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text('Area: $areaLabel', style: const pw.TextStyle(fontSize: 7)),
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
    ..write('salt:')
    ..write(data.cacheSalt ?? '')
    ..write(';')
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
final LinkedHashMap<String, _StickyPdfEntry> _orderPdfStickyCache =
    LinkedHashMap<String, _StickyPdfEntry>();
final Set<String> _pdfInFlight = <String>{};
final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
final DateFormat _timeFormat = DateFormat('HH:mm');
final Set<String> _warmedBrandings = <String>{};

PdfColor _pdfColor(Color color) => PdfColor.fromInt(color.toARGB32());

class _StickyPdfEntry {
  const _StickyPdfEntry({
    required this.cacheKey,
    required this.bytes,
  });

  final String cacheKey;
  final Uint8List bytes;
}

ByteData _byteDataFromList(Uint8List bytes) {
  return ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
}

int? _safePageNumber(pw.Context context) {
  try {
    return context.pageNumber;
  } catch (_) {
    return null;
  }
}

int? _safePageCount(pw.Context context) {
  try {
    return context.pagesCount;
  } catch (_) {
    return null;
  }
}

int _estimateMaxPages(OrderPdfData data) {
  final items = data.items.length;
  if (items <= 0) return 20;
  final estimated = (items / _itemsPerPageEstimate).ceil() + 10;
  final minimal = items + 10;
  var desired = estimated > minimal ? estimated : minimal;
  if (desired < 20) desired = 20;
  if (desired > _maxPdfPagesCap) return _maxPdfPagesCap;
  return desired;
}

OrderPdfData _sanitizePdfData(OrderPdfData data) {
  return OrderPdfData(
    branding: data.branding,
    requesterName: _sanitizePdfString(data.requesterName),
    requesterArea: _sanitizePdfString(data.requesterArea),
    areaName: _sanitizePdfString(data.areaName),
    urgency: data.urgency,
    items: data.items.map(_sanitizePdfItem).toList(growable: false),
    createdAt: data.createdAt,
    updatedAt: data.updatedAt,
    observations: _sanitizePdfString(data.observations),
    folio: _sanitizePdfOptional(data.folio),
    supplier: _sanitizePdfOptional(data.supplier),
    internalOrder: _sanitizePdfOptional(data.internalOrder),
    budget: data.budget,
    supplierBudgets: _sanitizeBudgets(data.supplierBudgets),
    comprasComment: _sanitizePdfOptional(data.comprasComment),
    comprasReviewerName: _sanitizePdfOptional(data.comprasReviewerName),
    comprasReviewerArea: _sanitizePdfOptional(data.comprasReviewerArea),
    direccionGeneralName: _sanitizePdfOptional(data.direccionGeneralName),
    direccionGeneralArea: _sanitizePdfOptional(data.direccionGeneralArea),
    requestedDeliveryDate: data.requestedDeliveryDate,
    etaDate: data.etaDate,
    resubmissionDates: data.resubmissionDates,
    cacheSalt: data.cacheSalt,
  );
}

OrderItemDraft _sanitizePdfItem(OrderItemDraft item) {
  return OrderItemDraft(
    line: item.line,
    pieces: item.pieces,
    partNumber: _sanitizePdfTableText(item.partNumber),
    description: _sanitizePdfTableText(item.description),
    quantity: item.quantity,
    unit: _sanitizePdfTableText(item.unit),
    customer: _sanitizePdfOptionalTable(item.customer),
    supplier: _sanitizePdfOptionalTable(item.supplier),
    budget: item.budget,
    estimatedDate: item.estimatedDate,
    reviewFlagged: item.reviewFlagged,
    reviewComment: _sanitizePdfOptional(item.reviewComment),
  );
}

Map<String, num> _sanitizeBudgets(Map<String, num> budgets) {
  if (budgets.isEmpty) return const {};
  final sanitized = <String, num>{};
  for (final entry in budgets.entries) {
    final key = _sanitizePdfString(entry.key).trim();
    if (key.isEmpty) continue;
    sanitized[key] = entry.value;
  }
  return sanitized;
}

String? _sanitizePdfOptional(String? value) {
  if (value == null) return null;
  return _sanitizePdfString(value);
}

String? _sanitizePdfOptionalTable(String? value) {
  if (value == null) return null;
  return _sanitizePdfTableText(value);
}

String _sanitizePdfString(String value) {
  if (value.isEmpty) return value;
  final buffer = StringBuffer();
  for (final code in value.runes) {
    if (code == 0x0A || code == 0x0D || code == 0x09) {
      buffer.writeCharCode(code);
      continue;
    }
    if (code >= 0x20 && code <= 0x7E) {
      buffer.writeCharCode(code);
      continue;
    }
    if (code >= 0xA0 && code <= 0xFF) {
      buffer.writeCharCode(code);
      continue;
    }
    buffer.write('?');
  }
  return buffer.toString();
}

String _sanitizePdfTableText(String value) {
  final cleaned = _sanitizePdfString(value);
  final noBreaks = cleaned.replaceAll(RegExp(r'[\r\n]+'), ' ');
  return noBreaks.replaceAll(RegExp(r'\s+'), ' ').trim();
}

const int _itemsPerPageEstimate = 10;
const int _maxPdfPagesCap = 1000;
const int _textChunkSize = 450;

Uint8List? getCachedOrderPdf(
  OrderPdfData data, {
  PdfPageFormat? format,
}) {
  final cacheKey = _pdfCacheKey(data, format);
  final cached = _pdfCache[cacheKey];
  if (cached == null) return null;
  return kIsWeb ? Uint8List.fromList(cached) : cached;
}

Uint8List? getCachedOrderPdfForFolio(
  OrderPdfData data, {
  PdfPageFormat? format,
}) {
  final folio = data.folio?.trim();
  if (folio == null || folio.isEmpty) return null;
  final cached = _orderPdfStickyCache[folio];
  if (cached == null) return null;
  final expectedKey = _pdfCacheKey(data, format);
  if (cached.cacheKey != expectedKey) return null;
  return kIsWeb ? Uint8List.fromList(cached.bytes) : cached.bytes;
}

void _storeOrderPdfForFolio(
  OrderPdfData data,
  Uint8List bytes, {
  PdfPageFormat? format,
}) {
  final folio = data.folio?.trim();
  if (folio == null || folio.isEmpty) return;
  final cacheKey = _pdfCacheKey(data, format);
  _orderPdfStickyCache.remove(folio);
  _orderPdfStickyCache[folio] = _StickyPdfEntry(
    cacheKey: cacheKey,
    bytes: kIsWeb ? Uint8List.fromList(bytes) : bytes,
  );
  if (_orderPdfStickyCache.length > _maxPdfCacheEntries) {
    _orderPdfStickyCache.remove(_orderPdfStickyCache.keys.first);
  }
}

Map<String, dynamic> _serializePdfPayload(
  OrderPdfData data,
  PdfPageFormat? format,
  Uint8List logoBytes,
  Uint8List baseFontBytes,
  Uint8List boldFontBytes,
) {
  return {
    // OJO: para reconstruir branding en isolate, guardamos el company name
    'company': data.branding.company.name,
    'brandingId': data.branding.id,
    'logoBytes': logoBytes,
    'baseFontBytes': baseFontBytes,
    'boldFontBytes': boldFontBytes,
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
    'cacheSalt': data.cacheSalt,
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
  final baseFontBytes = payload['baseFontBytes'] as Uint8List;
  final boldFontBytes = payload['boldFontBytes'] as Uint8List;
  final baseFont = pw.Font.ttf(_byteDataFromList(baseFontBytes));
  final boldFont = pw.Font.ttf(_byteDataFromList(boldFontBytes));

  final formatWidth = payload['formatWidth'] as double?;
  final formatHeight = payload['formatHeight'] as double?;
  final format = (formatWidth != null && formatHeight != null)
      ? PdfPageFormat(formatWidth, formatHeight)
      : null;

  final data = _deserializeOrderPdfData(payload, branding);
  return _buildOrderPdfWithAssets(data, format, logo, baseFont, boldFont);
}

Future<Uint8List> _buildCotizacionPdfInIsolate(
    Map<String, dynamic> payload) async {
  final companyName = payload['company'] as String?;
  final company = Company.values.firstWhere(
    (c) => c.name == companyName,
    orElse: () => Company.chabely,
  );

  final branding = brandingFor(company);

  final logoBytes = payload['logoBytes'] as Uint8List;
  final logo = pw.MemoryImage(logoBytes);
  final baseFontBytes = payload['baseFontBytes'] as Uint8List;
  final boldFontBytes = payload['boldFontBytes'] as Uint8List;
  final baseFont = pw.Font.ttf(_byteDataFromList(baseFontBytes));
  final boldFont = pw.Font.ttf(_byteDataFromList(boldFontBytes));

  final formatWidth = payload['formatWidth'] as double?;
  final formatHeight = payload['formatHeight'] as double?;
  final format = (formatWidth != null && formatHeight != null)
      ? PdfPageFormat(formatWidth, formatHeight)
      : null;

  final data = _deserializeOrderPdfData(payload, branding);
  return _buildCotizacionPdfWithAssets(data, format, logo, baseFont, boldFont);
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
    cacheSalt: payload['cacheSalt'] as String?,
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
