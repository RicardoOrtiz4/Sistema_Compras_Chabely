import 'package:sistema_compras/core/company_branding.dart';
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
  String? direccionGeneralName,
  String? direccionGeneralArea,
  List<OrderItemDraft>? items,
  DateTime? createdAt,
  DateTime? updatedAt,
  List<DateTime>? resubmissionDates,
  bool hideBudget = false,
}) {
  final effectiveBranding = _brandingForOrder(order, branding);

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

  final requestedDate = mappedItems
      .map((item) => item.estimatedDate)
      .whereType<DateTime>()
      .fold<DateTime?>(null, (current, next) {
    if (current == null) return next;
    return next.isBefore(current) ? next : current;
  });

  return OrderPdfData(
    branding: effectiveBranding,
    requesterName: order.requesterName,
    requesterArea: order.areaName,
    areaName: order.areaName,
    urgency: order.urgency,
    items: mappedItems,
    createdAt: createdAt ?? order.createdAt ?? DateTime.now(),
    updatedAt: updatedAt ?? order.updatedAt,
    observations: order.clientNote ?? '',
    folio: order.id,
    supplier: supplier ?? order.supplier ?? '',
    internalOrder: internalOrder ?? order.internalOrder ?? '',
    budget: effectiveBudget,
    supplierBudgets: effectiveSupplierBudgets,
    comprasComment: comprasComment ?? order.comprasComment ?? '',
    comprasReviewerName: comprasReviewerName ?? order.comprasReviewerName ?? '',
    comprasReviewerArea: comprasReviewerArea ?? order.comprasReviewerArea ?? '',
    direccionGeneralName: direccionGeneralName ?? order.direccionGeneralName ?? '',
    direccionGeneralArea: direccionGeneralArea ?? order.direccionGeneralArea ?? '',
    requestedDeliveryDate: requestedDate,
    etaDate: order.etaDate,
    resubmissionDates: resubmissionDates ?? order.resubmissionDates,
  );
}

void prefetchOrderPdfsForOrders(
  List<PurchaseOrder> orders, {
  required CompanyBranding branding,
  int limit = defaultPdfPrefetchLimit,
}) {
  if (orders.isEmpty || limit <= 0) return;

  final dataList = orders
      .take(limit)
      .map((order) => buildPdfDataFromOrder(order, branding: branding))
      .toList(growable: false);

  prefetchOrderPdfs(dataList, limit: dataList.length);
}

CompanyBranding _brandingForOrder(
  PurchaseOrder order,
  CompanyBranding fallback,
) {
  final company = _companyFromOrder(order);
  if (company == null) return fallback;
  return brandingFor(company);
}

Company? _companyFromOrder(PurchaseOrder order) {
  final rawId = order.companyId?.trim();
  if (rawId != null && rawId.isNotEmpty) {
    for (final company in Company.values) {
      if (company.name.toLowerCase() == rawId.toLowerCase()) {
        return company;
      }
    }
  }

  final trimmedId = order.id.trim().toUpperCase();
  if (trimmedId.contains('-')) {
    final prefix = trimmedId.split('-').first;
    if (prefix == 'CHA') return Company.chabely;
    if (prefix == 'ACE') return Company.acerpro;
  }

  return null;
}

num _sumBudgets(Map<String, num> budgets) {
  var total = 0.0;
  for (final value in budgets.values) {
    total += value.toDouble();
  }
  return total;
}
