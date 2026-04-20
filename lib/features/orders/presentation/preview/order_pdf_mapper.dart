import 'dart:collection';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/features/orders/application/create_order_controller.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';

OrderPdfData buildPdfDataFromOrder(
  PurchaseOrder order, {
  required CompanyBranding branding,
  String? requesterName,
  String? requesterArea,
  String? supplier,
  String? internalOrder,
  num? budget,
  Map<String, num>? supplierBudgets,
  String? pendingResubmissionLabel,
  String? authorizedByName,
  String? authorizedByArea,
  String? processByName,
  String? processByArea,
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
    pendingResubmissionLabel: pendingResubmissionLabel,
    authorizedByName: authorizedByName,
    authorizedByArea: authorizedByArea,
    processByName: processByName,
    processByArea: processByArea,
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
      requesterName: requesterName,
      requesterArea: requesterArea,
      supplier: supplier,
      internalOrder: internalOrder,
      budget: budget,
      supplierBudgets: supplierBudgets,
      pendingResubmissionLabel: pendingResubmissionLabel,
      authorizedByName: authorizedByName,
      authorizedByArea: authorizedByArea,
      processByName: processByName,
      processByArea: processByArea,
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
    requesterName: requesterName,
    requesterArea: requesterArea,
    supplier: supplier,
    internalOrder: internalOrder,
    budget: budget,
    supplierBudgets: supplierBudgets,
    pendingResubmissionLabel: pendingResubmissionLabel,
    authorizedByName: authorizedByName,
    authorizedByArea: authorizedByArea,
    processByName: processByName,
    processByArea: processByArea,
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
  String? requesterName,
  String? requesterArea,
  String? supplier,
  String? internalOrder,
  num? budget,
  Map<String, num>? supplierBudgets,
  String? pendingResubmissionLabel,
  String? authorizedByName,
  String? authorizedByArea,
  String? processByName,
  String? processByArea,
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
  const effectiveResubmissionDates = <DateTime>[];
  const String? effectivePendingResubmissionLabel = null;

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
    requesterName: requesterName ?? order.requesterName,
    requesterArea: requesterArea ?? order.areaName,
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
    pendingResubmissionLabel: effectivePendingResubmissionLabel,
    authorizedByName: authorizedByName ?? order.authorizedByName,
    authorizedByArea: authorizedByArea ?? order.authorizedByArea,
    processByName: processByName ?? order.processByName,
    processByArea: processByArea ?? order.processByArea,
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
  required String? pendingResubmissionLabel,
  required String? authorizedByName,
  required String? authorizedByArea,
  required String? processByName,
  required String? processByArea,
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
      pendingResubmissionLabel == null &&
      authorizedByName == null &&
      authorizedByArea == null &&
      processByName == null &&
      processByArea == null &&
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
  return [
    branding.id,
    order.id,
    order.companyId ?? '',
    order.status.name,
    (order.updatedAt ?? order.createdAt)?.millisecondsSinceEpoch ?? 0,
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

num _sumBudgets(Map<String, num> budgets) {
  var total = 0.0;
  for (final value in budgets.values) {
    total += value.toDouble();
  }
  return total;
}
