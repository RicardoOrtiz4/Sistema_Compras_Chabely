import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/domain/supplier_quote.dart';
import 'package:sistema_compras/features/orders/presentation/preview/supplier_quote_pdf_builder.dart';

class ContabilidadGroup {
  const ContabilidadGroup({
    required this.quote,
    required this.orders,
    required this.items,
    required this.sentLinesByOrder,
  });

  final SupplierQuote quote;
  final List<PurchaseOrder> orders;
  final List<ContabilidadGroupItem> items;
  final Map<String, Set<int>> sentLinesByOrder;
}

class ContabilidadGroupItem {
  const ContabilidadGroupItem({required this.order, required this.item});

  final PurchaseOrder order;
  final PurchaseOrderItem item;
}

ContabilidadGroup? buildContabilidadGroup(
  SupplierQuote quote,
  List<PurchaseOrder> allOrders,
) {
  if (quote.status != SupplierQuoteStatus.approved) return null;

  final ordersById = {for (final order in allOrders) order.id: order};
  final relatedOrders = <PurchaseOrder>[];
  final relatedItems = <ContabilidadGroupItem>[];
  final sentLinesByOrder = <String, Set<int>>{};

  for (final orderId in quote.orderIds) {
    final order = ordersById[orderId];
    if (order == null || order.status == PurchaseOrderStatus.eta) continue;
    final sentItems = order.items
        .where(
          (item) =>
              (item.quoteId?.trim() ?? '') == quote.id &&
              item.quoteStatus == PurchaseOrderItemQuoteStatus.approved &&
              isItemVisibleInContabilidad(item),
        )
        .toList(growable: false);
    if (sentItems.isEmpty) continue;
    relatedOrders.add(order);
    final lines = <int>{};
    for (final item in sentItems) {
      relatedItems.add(ContabilidadGroupItem(order: order, item: item));
      lines.add(item.line);
    }
    sentLinesByOrder[order.id] = lines;
  }

  if (relatedOrders.isEmpty || relatedItems.isEmpty) return null;
  relatedOrders.sort((a, b) => a.id.compareTo(b.id));
  return ContabilidadGroup(
    quote: quote,
    orders: relatedOrders,
    items: relatedItems,
    sentLinesByOrder: sentLinesByOrder,
  );
}

bool isItemVisibleInContabilidad(PurchaseOrderItem item) {
  return item.sentToContabilidadAt != null || item.deliveryEtaDate != null;
}

SupplierQuotePdfData buildContabilidadQuotePdfData({
  required SupplierQuote quote,
  required List<PurchaseOrder> allOrders,
  required CompanyBranding branding,
  required AppUser? actor,
}) {
  final refsByOrder = <String, Map<int, SupplierQuoteItemRef>>{};
  for (final ref in quote.items) {
    refsByOrder.putIfAbsent(
      ref.orderId,
      () => <int, SupplierQuoteItemRef>{},
    )[ref.line] = ref;
  }

  final orders = <SupplierQuotePdfOrderData>[];
  for (final order in allOrders) {
    final orderRefs = refsByOrder[order.id];
    if (orderRefs == null || orderRefs.isEmpty) continue;

    final items = <SupplierQuotePdfItemData>[];
    for (final item in order.items) {
      final selectedRef = orderRefs[item.line];
      items.add(
        SupplierQuotePdfItemData(
          line: item.line,
          description: item.description,
          quantity: item.quantity,
          unit: item.unit,
          selected: selectedRef != null,
          partNumber: item.partNumber,
          customer: item.customer,
          amount: selectedRef?.amount ?? item.budget,
          etaDate: item.deliveryEtaDate,
        ),
      );
    }

    orders.add(
      SupplierQuotePdfOrderData(
        orderId: order.id,
        requesterName: order.requesterName,
        areaName: order.areaName,
        items: items,
      ),
    );
  }

  orders.sort((a, b) => a.orderId.compareTo(b.orderId));
  return SupplierQuotePdfData(
    branding: branding,
    quoteId: quote.displayId,
    supplier: quote.supplier,
    links: quote.links,
    orders: orders,
    comprasComment: quote.comprasComment,
    createdAt: quote.createdAt,
    processedByName: quote.processedByName ?? actor?.name,
    processedByArea: quote.processedByArea ?? actor?.areaDisplay,
    authorizedByName: quote.approvedByName,
    authorizedByArea: quote.approvedByArea,
  );
}

bool canFinalizeOrder(PurchaseOrder order) {
  if (order.items.isEmpty) return false;
  for (final item in order.items) {
    if (item.sentToContabilidadAt == null) {
      return false;
    }
  }
  return true;
}

bool hasAllInternalOrders(PurchaseOrder order) {
  if (order.items.isEmpty) return false;
  for (final item in order.items) {
    if ((item.internalOrder ?? '').trim().isEmpty) {
      return false;
    }
  }
  return true;
}

List<String> collectOrderFacturaLinks(String orderId, List<SupplierQuote> quotes) {
  final links = <String>{};
  for (final quote in quotes) {
    if (!quote.orderIds.contains(orderId)) continue;
    for (final link in quote.facturaLinks) {
      final trimmed = link.trim();
      if (trimmed.isNotEmpty) links.add(trimmed);
    }
  }
  return links.toList(growable: false);
}
