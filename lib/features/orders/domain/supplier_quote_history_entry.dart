import 'package:sistema_compras/features/orders/domain/supplier_quote.dart';

class SupplierQuoteHistoryItemEntry {
  const SupplierQuoteHistoryItemEntry({
    required this.line,
    required this.description,
    required this.quantity,
    required this.unit,
    this.partNumber,
    this.amount,
  });

  final int line;
  final String description;
  final num quantity;
  final String unit;
  final String? partNumber;
  final num? amount;

  factory SupplierQuoteHistoryItemEntry.fromMap(Map<String, dynamic> data) {
    return SupplierQuoteHistoryItemEntry(
      line: (data['line'] as num?)?.toInt() ?? 0,
      description: (data['description'] as String?) ?? '',
      quantity: (data['quantity'] as num?) ?? 0,
      unit: (data['unit'] as String?) ?? '',
      partNumber: data['partNumber'] as String?,
      amount: data['amount'] as num?,
    );
  }
}

class SupplierQuoteHistoryOrderEntry {
  const SupplierQuoteHistoryOrderEntry({
    required this.orderId,
    required this.items,
    this.requesterName,
    this.areaName,
    this.status,
  });

  final String orderId;
  final String? requesterName;
  final String? areaName;
  final String? status;
  final List<SupplierQuoteHistoryItemEntry> items;

  factory SupplierQuoteHistoryOrderEntry.fromMap(Map<String, dynamic> data) {
    return SupplierQuoteHistoryOrderEntry(
      orderId: (data['orderId'] as String?) ?? '',
      requesterName: data['requesterName'] as String?,
      areaName: data['areaName'] as String?,
      status: data['status'] as String?,
      items: _parseHistoryItems(data['items']),
    );
  }
}

class SupplierQuoteHistoryEntry {
  const SupplierQuoteHistoryEntry({
    required this.id,
    required this.quoteId,
    required this.folio,
    required this.eventType,
    required this.status,
    required this.supplier,
    required this.links,
    required this.facturaLinks,
    required this.paymentLinks,
    required this.orderIds,
    required this.orders,
    required this.version,
    required this.itemCount,
    required this.orderCount,
    required this.totalAmount,
    this.comprasComment,
    this.comment,
    this.createdAt,
    this.updatedAt,
    this.sentToDireccionAt,
    this.approvedAt,
    this.approvedByName,
    this.approvedByArea,
    this.rejectedAt,
    this.rejectedByName,
    this.rejectedByArea,
    this.processedByName,
    this.processedByArea,
    this.actorName,
    this.actorArea,
    this.pdfSuggestedName,
    this.timestamp,
  });

  final String id;
  final String quoteId;
  final String folio;
  final String eventType;
  final SupplierQuoteStatus status;
  final String supplier;
  final List<String> links;
  final List<String> facturaLinks;
  final List<String> paymentLinks;
  final List<String> orderIds;
  final List<SupplierQuoteHistoryOrderEntry> orders;
  final int version;
  final int itemCount;
  final int orderCount;
  final num totalAmount;
  final String? comprasComment;
  final String? comment;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? sentToDireccionAt;
  final DateTime? approvedAt;
  final String? approvedByName;
  final String? approvedByArea;
  final DateTime? rejectedAt;
  final String? rejectedByName;
  final String? rejectedByArea;
  final String? processedByName;
  final String? processedByArea;
  final String? actorName;
  final String? actorArea;
  final String? pdfSuggestedName;
  final DateTime? timestamp;

  String get eventLabel {
    switch (eventType) {
      case 'created':
        return 'Borrador creado';
      case 'draft_updated':
        return 'Borrador actualizado';
      case 'sent_to_direccion':
        return 'Enviada para autorizacion de pago';
      case 'approved':
        return 'Autorizada';
      case 'rejected':
        return 'Rechazada';
      case 'factura_links_updated':
        return 'Links contables actualizados';
      case 'items_sent_to_contabilidad':
        return 'Items enviados a Contabilidad';
      case 'deleted':
        return 'Eliminada';
      case 'returned_to_cotizaciones':
        return 'Devuelta a compras';
      case 'returned_from_contabilidad':
        return 'Regresada desde Contabilidad';
      default:
        return eventType;
    }
  }

  factory SupplierQuoteHistoryEntry.fromMap(String id, Map<String, dynamic> data) {
    final quoteId = (data['quoteId'] as String?) ?? '';
    final folio = (data['folio'] as String?) ?? '';
    return SupplierQuoteHistoryEntry(
      id: id,
      quoteId: quoteId,
      folio: folio.trim().isEmpty ? quoteId : folio,
      eventType: (data['eventType'] as String?) ?? '',
      status: _statusFromString(data['status'] as String?) ??
          SupplierQuoteStatus.draft,
      supplier: (data['supplier'] as String?) ?? '',
      links: _parseLinks(data['links']),
      facturaLinks: _parseLinks(data['facturaLinks']),
      paymentLinks: _parseLinks(data['paymentLinks']),
      orderIds: _parseStringList(data['orderIds']),
      orders: _parseHistoryOrders(data['orders']),
      version: (data['version'] as num?)?.toInt() ?? 1,
      itemCount: (data['itemCount'] as num?)?.toInt() ?? 0,
      orderCount: (data['orderCount'] as num?)?.toInt() ?? 0,
      totalAmount: (data['totalAmount'] as num?) ?? 0,
      comprasComment: data['comprasComment'] as String?,
      comment: data['comment'] as String?,
      createdAt: _parseDateTime(data['createdAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
      sentToDireccionAt: _parseDateTime(data['sentToDireccionAt']),
      approvedAt: _parseDateTime(data['approvedAt']),
      approvedByName: data['approvedByName'] as String?,
      approvedByArea: data['approvedByArea'] as String?,
      rejectedAt: _parseDateTime(data['rejectedAt']),
      rejectedByName: data['rejectedByName'] as String?,
      rejectedByArea: data['rejectedByArea'] as String?,
      processedByName: data['processedByName'] as String?,
      processedByArea: data['processedByArea'] as String?,
      actorName: data['actorName'] as String?,
      actorArea: data['actorArea'] as String?,
      pdfSuggestedName: data['pdfSuggestedName'] as String?,
      timestamp: _parseDateTime(data['timestamp']),
    );
  }
}

List<SupplierQuoteHistoryOrderEntry> _parseHistoryOrders(dynamic value) {
  final orders = <SupplierQuoteHistoryOrderEntry>[];
  if (value is List) {
    for (final entry in value) {
      if (entry is Map) {
        orders.add(
          SupplierQuoteHistoryOrderEntry.fromMap(Map<String, dynamic>.from(entry)),
        );
      }
    }
  } else if (value is Map) {
    for (final entry in value.values) {
      if (entry is Map) {
        orders.add(
          SupplierQuoteHistoryOrderEntry.fromMap(Map<String, dynamic>.from(entry)),
        );
      }
    }
  }
  return orders;
}

List<SupplierQuoteHistoryItemEntry> _parseHistoryItems(dynamic value) {
  final items = <SupplierQuoteHistoryItemEntry>[];
  if (value is List) {
    for (final entry in value) {
      if (entry is Map) {
        items.add(
          SupplierQuoteHistoryItemEntry.fromMap(Map<String, dynamic>.from(entry)),
        );
      }
    }
  } else if (value is Map) {
    for (final entry in value.values) {
      if (entry is Map) {
        items.add(
          SupplierQuoteHistoryItemEntry.fromMap(Map<String, dynamic>.from(entry)),
        );
      }
    }
  }
  return items;
}

List<String> _parseStringList(dynamic value) {
  final values = <String>[];
  if (value is List) {
    for (final entry in value) {
      final text = entry?.toString().trim() ?? '';
      if (text.isNotEmpty) values.add(text);
    }
  }
  return values;
}

List<String> _parseLinks(dynamic value) {
  final links = <String>[];
  if (value is List) {
    for (final entry in value) {
      final text = entry?.toString().trim() ?? '';
      if (text.isNotEmpty) links.add(text);
    }
  } else if (value is String) {
    final text = value.trim();
    if (text.isNotEmpty) links.add(text);
  }
  return links;
}

SupplierQuoteStatus? _statusFromString(String? raw) {
  if (raw == null) return null;
  for (final status in SupplierQuoteStatus.values) {
    if (status.name == raw) return status;
  }
  return null;
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is double) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  return null;
}
