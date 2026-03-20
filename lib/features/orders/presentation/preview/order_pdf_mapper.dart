import 'dart:collection';

import 'package:intl/intl.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/features/orders/application/create_order_controller.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';

OrderPdfData buildPdfDataFromOrder(
  PurchaseOrder order, {
  required CompanyBranding branding,
  String? supplier,
  String? internalOrder,
  num? budget,
  Map<String, num>? supplierBudgets,
  String? comprasComment,
  String? comprasReviewerName,
  String? comprasReviewerArea,
  String? processedByName,
  String? processedByArea,
  String? direccionGeneralName,
  String? direccionGeneralArea,
  String? pendingResubmissionLabel,
  List<OrderItemDraft>? items,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? etaDate,
  List<DateTime>? resubmissionDates,
  bool hideBudget = false,
  bool suppressUpdatedAt = false,
  String? cacheSalt,
}) {
  if (_canUseDefaultPdfDataCache(
    supplier: supplier,
    internalOrder: internalOrder,
    budget: budget,
    supplierBudgets: supplierBudgets,
    comprasComment: comprasComment,
    comprasReviewerName: comprasReviewerName,
    comprasReviewerArea: comprasReviewerArea,
    processedByName: processedByName,
    processedByArea: processedByArea,
    direccionGeneralName: direccionGeneralName,
    direccionGeneralArea: direccionGeneralArea,
    pendingResubmissionLabel: pendingResubmissionLabel,
    items: items,
    createdAt: createdAt,
    updatedAt: updatedAt,
    etaDate: etaDate,
    resubmissionDates: resubmissionDates,
    hideBudget: hideBudget,
    suppressUpdatedAt: suppressUpdatedAt,
    cacheSalt: cacheSalt,
  )) {
    final cacheKey = _defaultPdfDataCacheKey(order, branding);
    final cached = _defaultPdfDataCache[cacheKey];
    if (cached != null) {
      return cached;
    }
    final built = _buildPdfDataFromOrderImpl(
      order,
      branding: branding,
      supplier: supplier,
      internalOrder: internalOrder,
      budget: budget,
      supplierBudgets: supplierBudgets,
      comprasComment: comprasComment,
      comprasReviewerName: comprasReviewerName,
      comprasReviewerArea: comprasReviewerArea,
      processedByName: processedByName,
      processedByArea: processedByArea,
      direccionGeneralName: direccionGeneralName,
      direccionGeneralArea: direccionGeneralArea,
      pendingResubmissionLabel: pendingResubmissionLabel,
      items: items,
      createdAt: createdAt,
      updatedAt: updatedAt,
      etaDate: etaDate,
      resubmissionDates: resubmissionDates,
      hideBudget: hideBudget,
      suppressUpdatedAt: suppressUpdatedAt,
      cacheSalt: cacheSalt,
    );
    _defaultPdfDataCache.remove(cacheKey);
    _defaultPdfDataCache[cacheKey] = built;
    if (_defaultPdfDataCache.length > _maxDefaultPdfDataCacheEntries) {
      _defaultPdfDataCache.remove(_defaultPdfDataCache.keys.first);
    }
    return built;
  }

  return _buildPdfDataFromOrderImpl(
    order,
    branding: branding,
    supplier: supplier,
    internalOrder: internalOrder,
    budget: budget,
    supplierBudgets: supplierBudgets,
    comprasComment: comprasComment,
    comprasReviewerName: comprasReviewerName,
    comprasReviewerArea: comprasReviewerArea,
    processedByName: processedByName,
    processedByArea: processedByArea,
    direccionGeneralName: direccionGeneralName,
    direccionGeneralArea: direccionGeneralArea,
    pendingResubmissionLabel: pendingResubmissionLabel,
    items: items,
    createdAt: createdAt,
    updatedAt: updatedAt,
    etaDate: etaDate,
    resubmissionDates: resubmissionDates,
    hideBudget: hideBudget,
    suppressUpdatedAt: suppressUpdatedAt,
    cacheSalt: cacheSalt,
  );
}

OrderPdfData _buildPdfDataFromOrderImpl(
  PurchaseOrder order, {
  required CompanyBranding branding,
  String? supplier,
  String? internalOrder,
  num? budget,
  Map<String, num>? supplierBudgets,
  String? comprasComment,
  String? comprasReviewerName,
  String? comprasReviewerArea,
  String? processedByName,
  String? processedByArea,
  String? direccionGeneralName,
  String? direccionGeneralArea,
  String? pendingResubmissionLabel,
  List<OrderItemDraft>? items,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? etaDate,
  List<DateTime>? resubmissionDates,
  bool hideBudget = false,
  bool suppressUpdatedAt = false,
  String? cacheSalt,
}) {
  final effectiveBranding = _brandingForOrder(order, branding);
  final effectiveCreatedAt = createdAt ?? order.createdAt ?? DateTime.now();
  final effectiveUpdatedAt = suppressUpdatedAt ? null : (updatedAt ?? order.updatedAt);
  final effectiveResubmissionDates = resubmissionDates ?? order.resubmissionDates;
  final effectivePendingResubmissionLabel =
      pendingResubmissionLabel ??
      _fallbackResubmissionLabel(
        order,
        createdAt: effectiveCreatedAt,
        updatedAt: effectiveUpdatedAt,
        resubmissionDates: effectiveResubmissionDates,
      );

  final effectiveSupplierBudgets = hideBudget
      ? const <String, num>{}
      : (supplierBudgets ?? order.supplierBudgets);

  final effectiveBudget = hideBudget
      ? null
      : (budget ??
          (effectiveSupplierBudgets.isNotEmpty
              ? _sumBudgets(effectiveSupplierBudgets)
              : order.budget));

  final mappedItems = (items ?? order.items.map(OrderItemDraft.fromModel).toList());
  final effectiveItems = hideBudget
      ? mappedItems.map((item) => item.copyWith(clearBudget: true)).toList()
      : mappedItems;

  return OrderPdfData(
    branding: effectiveBranding,
    requesterName: order.requesterName,
    requesterArea: order.areaName,
    areaName: order.areaName,
    urgency: order.urgency,
    items: effectiveItems,
    createdAt: effectiveCreatedAt,
    updatedAt: effectiveUpdatedAt,
    observations: order.clientNote ?? '',
    urgentJustification: order.urgentJustification ?? '',
    folio: order.id,
    supplier: supplier ?? order.supplier ?? '',
    internalOrder: internalOrder ?? order.internalOrder ?? '',
    budget: effectiveBudget,
    supplierBudgets: effectiveSupplierBudgets,
    comprasComment: comprasComment ?? '',
    comprasReviewerName: comprasReviewerName ?? order.comprasReviewerName ?? '',
    comprasReviewerArea: comprasReviewerArea ?? order.comprasReviewerArea ?? '',
    processedByName: processedByName ?? order.processedByName ?? '',
    processedByArea: processedByArea ?? order.processedByArea ?? '',
    direccionGeneralName: direccionGeneralName ?? order.direccionGeneralName ?? '',
    direccionGeneralArea: direccionGeneralArea ?? order.direccionGeneralArea ?? '',
    pendingResubmissionLabel: effectivePendingResubmissionLabel,
    requestedDeliveryDate: resolveRequestedDeliveryDate(order),
    etaDate: etaDate ?? order.etaDate,
    resubmissionDates: effectiveResubmissionDates,
    cacheSalt: cacheSalt,
  );
}

bool _canUseDefaultPdfDataCache({
  required String? supplier,
  required String? internalOrder,
  required num? budget,
  required Map<String, num>? supplierBudgets,
  required String? comprasComment,
  required String? comprasReviewerName,
  required String? comprasReviewerArea,
  required String? processedByName,
  required String? processedByArea,
  required String? direccionGeneralName,
  required String? direccionGeneralArea,
  required String? pendingResubmissionLabel,
  required List<OrderItemDraft>? items,
  required DateTime? createdAt,
  required DateTime? updatedAt,
  required DateTime? etaDate,
  required List<DateTime>? resubmissionDates,
  required bool hideBudget,
  required bool suppressUpdatedAt,
  required String? cacheSalt,
}) {
  return supplier == null &&
      internalOrder == null &&
      budget == null &&
      supplierBudgets == null &&
      comprasComment == null &&
      comprasReviewerName == null &&
      comprasReviewerArea == null &&
      processedByName == null &&
      processedByArea == null &&
      direccionGeneralName == null &&
      direccionGeneralArea == null &&
      pendingResubmissionLabel == null &&
      items == null &&
      createdAt == null &&
      updatedAt == null &&
      etaDate == null &&
      resubmissionDates == null &&
      !hideBudget &&
      !suppressUpdatedAt &&
      cacheSalt == null;
}

String _defaultPdfDataCacheKey(PurchaseOrder order, CompanyBranding branding) {
  final resubmissions = order.resubmissionDates;
  final lastResubmission = resubmissions.isEmpty
      ? 0
      : resubmissions.last.millisecondsSinceEpoch;
  return [
    branding.id,
    order.id,
    order.companyId ?? '',
    order.status.name,
    (order.updatedAt ?? order.createdAt)?.millisecondsSinceEpoch ?? 0,
    order.returnCount,
    order.direccionReturnCount,
    resubmissions.length,
    lastResubmission,
    order.items.length,
    order.facturaPdfUrls.length,
  ].join('|');
}

const int _maxDefaultPdfDataCacheEntries = 96;
final LinkedHashMap<String, OrderPdfData> _defaultPdfDataCache =
    LinkedHashMap<String, OrderPdfData>();

void resetMappedOrderPdfDataCache() {
  _defaultPdfDataCache.clear();
}

void prefetchOrderPdfsForOrders(
  List<PurchaseOrder> orders, {
  required CompanyBranding branding,
  int limit = defaultPdfPrefetchLimit,
  String? groupKey,
  int? generation,
}) {
  if (orders.isEmpty || limit <= 0) return;

  final dataList = orders
      .take(limit)
      .map((order) => buildPdfDataFromOrder(order, branding: branding))
      .toList(growable: false);

  prefetchOrderPdfs(
    dataList,
    limit: dataList.length,
    groupKey: groupKey,
    generation: generation,
  );
}

Future<void> cacheOrderPdfsForOrders(
  List<PurchaseOrder> orders, {
  required CompanyBranding branding,
  int limit = defaultPdfPrefetchLimit,
  bool useIsolate = false,
}) async {
  if (orders.isEmpty || limit <= 0) return;

  final dataList = orders
      .take(limit)
      .map((order) => buildPdfDataFromOrder(order, branding: branding))
      .toList(growable: false);

  if (dataList.isEmpty) return;

  await cacheOrderPdfs(
    dataList,
    limit: dataList.length,
    useIsolate: useIsolate,
  );
}

CompanyBranding _brandingForOrder(
  PurchaseOrder order,
  CompanyBranding fallback,
) {
  return fallback;
}

final DateFormat _pdfMapperResubmissionDateFormat = DateFormat('dd/MM/yyyy');
final DateFormat _pdfMapperResubmissionTimeFormat = DateFormat('HH:mm');

String? _fallbackResubmissionLabel(
  PurchaseOrder order, {
  required DateTime createdAt,
  required DateTime? updatedAt,
  required List<DateTime> resubmissionDates,
}) {
  if (order.status == PurchaseOrderStatus.draft) return null;
  if (order.returnCount <= 0) return null;
  if (resubmissionDates.isNotEmpty) return null;
  if (updatedAt == null) return null;

  return 'REENVIO ${order.returnCount}: ${_formatFallbackResubmissionStamp(updatedAt, createdAt)}';
}

String _formatFallbackResubmissionStamp(DateTime stamp, DateTime createdAt) {
  if (_isSameDate(stamp, createdAt)) {
    return _pdfMapperResubmissionTimeFormat.format(stamp);
  }
  return '${_pdfMapperResubmissionDateFormat.format(stamp)} ${_pdfMapperResubmissionTimeFormat.format(stamp)}';
}

bool _isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

num _sumBudgets(Map<String, num> budgets) {
  var total = 0.0;
  for (final value in budgets.values) {
    total += value.toDouble();
  }
  return total;
}

