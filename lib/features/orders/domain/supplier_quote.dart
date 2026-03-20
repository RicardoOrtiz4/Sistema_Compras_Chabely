enum SupplierQuoteStatus { draft, pendingDireccion, approved, rejected }

extension SupplierQuoteStatusX on SupplierQuoteStatus {
  String get label {
    switch (this) {
      case SupplierQuoteStatus.draft:
        return 'Borrador';
      case SupplierQuoteStatus.pendingDireccion:
        return 'Por autorizar';
      case SupplierQuoteStatus.approved:
        return 'Aprobada';
      case SupplierQuoteStatus.rejected:
        return 'Rechazada';
    }
  }
}

class SupplierQuoteItemRef {
  const SupplierQuoteItemRef({
    required this.orderId,
    required this.line,
    required this.description,
    required this.quantity,
    required this.unit,
    this.orderFolio,
    this.partNumber,
    this.amount,
  });

  final String orderId;
  final String? orderFolio;
  final int line;
  final String description;
  final num quantity;
  final String unit;
  final String? partNumber;
  final num? amount;

  factory SupplierQuoteItemRef.fromMap(Map<String, dynamic> data) {
    return SupplierQuoteItemRef(
      orderId: (data['orderId'] as String?) ?? '',
      orderFolio: data['orderFolio'] as String?,
      line: (data['line'] as num?)?.toInt() ?? 0,
      description: (data['description'] as String?) ?? '',
      quantity: (data['quantity'] as num?) ?? 0,
      unit: (data['unit'] as String?) ?? '',
      partNumber: data['partNumber'] as String?,
      amount: data['amount'] as num?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'orderId': orderId,
      'orderFolio': orderFolio,
      'line': line,
      'description': description,
      'quantity': quantity,
      'unit': unit,
      'partNumber': partNumber,
      'amount': amount,
    };
  }
}

class SupplierQuote {
  SupplierQuote({
    required this.id,
    required this.supplier,
    this.folio,
    List<SupplierQuoteItemRef>? items,
    this.status = SupplierQuoteStatus.draft,
    List<String> links = const [],
    this.facturaLinks = const [],
    List<String>? orderIds,
    String? pdfUrl,
    this.createdAt,
    this.updatedAt,
    this.comprasComment,
    this.processedByName,
    this.processedByArea,
    this.sentToDireccionAt,
    this.approvedAt,
    this.approvedByName,
    this.approvedByArea,
    this.rejectionComment,
    this.rejectedAt,
    this.rejectedByName,
    this.rejectedByArea,
    List<String> approvedOrderIds = const [],
    List<String> rejectedOrderIds = const [],
    bool needsUpdate = false,
    this.version = 1,
  }) : items = items ??
            [
              for (final orderId in orderIds ?? const <String>[])
                SupplierQuoteItemRef(
                  orderId: orderId,
                  orderFolio: orderId,
                  line: 0,
                  description: '',
                  quantity: 0,
                  unit: '',
                ),
            ],
       links = links.isNotEmpty
           ? links
           : ((pdfUrl?.trim().isNotEmpty ?? false)
               ? <String>[pdfUrl!.trim()]
               : const <String>[]);

  final String id;
  final String? folio;
  final String supplier;
  final List<SupplierQuoteItemRef> items;
  final SupplierQuoteStatus status;
  final List<String> links;
  final List<String> facturaLinks;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? comprasComment;
  final String? processedByName;
  final String? processedByArea;
  final DateTime? sentToDireccionAt;
  final DateTime? approvedAt;
  final String? approvedByName;
  final String? approvedByArea;
  final String? rejectionComment;
  final DateTime? rejectedAt;
  final String? rejectedByName;
  final String? rejectedByArea;
  final int version;

  bool get needsAttentionByCompras =>
      status == SupplierQuoteStatus.draft ||
      status == SupplierQuoteStatus.rejected;

  String get displayId {
    final trimmed = folio?.trim() ?? '';
    return trimmed.isEmpty ? id : trimmed;
  }

  List<String> get orderIds {
    final ids = <String>{};
    for (final item in items) {
      final orderId = item.orderId.trim();
      if (orderId.isNotEmpty) ids.add(orderId);
    }
    return ids.toList(growable: false);
  }

  String get primaryLink => links.isEmpty ? '' : links.first;
  String get pdfUrl => primaryLink;

  num get totalAmount {
    var total = 0.0;
    for (final item in items) {
      final amount = item.amount;
      if (amount != null) total += amount.toDouble();
    }
    return total;
  }

  factory SupplierQuote.fromMap(String id, Map<String, dynamic> data) {
    return SupplierQuote(
      id: id,
      folio: data['folio'] as String?,
      supplier: (data['supplier'] as String?) ?? '',
      items: _parseItems(data['items']),
      status: _statusFromString(data['status'] as String?) ??
          SupplierQuoteStatus.draft,
      links: _parseLinks(data['links'] ?? data['pdfUrls'] ?? data['pdfUrl']),
      facturaLinks: _parseLinks(data['facturaLinks']),
      createdAt: _parseDateTime(data['createdAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
      comprasComment: data['comprasComment'] as String?,
      processedByName: data['processedByName'] as String?,
      processedByArea: data['processedByArea'] as String?,
      sentToDireccionAt: _parseDateTime(data['sentToDireccionAt']),
      approvedAt: _parseDateTime(data['approvedAt']),
      approvedByName: data['approvedByName'] as String?,
      approvedByArea: data['approvedByArea'] as String?,
      rejectionComment: data['rejectionComment'] as String?,
      rejectedAt: _parseDateTime(data['rejectedAt']),
      rejectedByName: data['rejectedByName'] as String?,
      rejectedByArea: data['rejectedByArea'] as String?,
      version: (data['version'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    final cleanedLinks = links
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    final cleanedFacturaLinks = facturaLinks
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    return {
      'folio': (folio?.trim().isEmpty ?? true) ? null : folio!.trim(),
      'supplier': supplier.trim(),
      'items': items.map((item) => item.toMap()).toList(),
      'status': status.name,
      'links': cleanedLinks.isEmpty ? null : cleanedLinks,
      'facturaLinks': cleanedFacturaLinks.isEmpty ? null : cleanedFacturaLinks,
      'pdfUrl': cleanedLinks.isEmpty ? null : cleanedLinks.first,
      'pdfUrls': cleanedLinks.isEmpty ? null : cleanedLinks,
      'createdAt': createdAt?.millisecondsSinceEpoch,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
      'comprasComment': (comprasComment?.trim().isEmpty ?? true)
          ? null
          : comprasComment!.trim(),
      'processedByName': processedByName,
      'processedByArea': processedByArea,
      'sentToDireccionAt': sentToDireccionAt?.millisecondsSinceEpoch,
      'approvedAt': approvedAt?.millisecondsSinceEpoch,
      'approvedByName': approvedByName,
      'approvedByArea': approvedByArea,
      'rejectionComment': rejectionComment,
      'rejectedAt': rejectedAt?.millisecondsSinceEpoch,
      'rejectedByName': rejectedByName,
      'rejectedByArea': rejectedByArea,
      'version': version,
    };
  }
}

List<SupplierQuoteItemRef> _parseItems(dynamic value) {
  final items = <SupplierQuoteItemRef>[];
  if (value is List) {
    for (final entry in value) {
      if (entry is Map) {
        items.add(SupplierQuoteItemRef.fromMap(Map<String, dynamic>.from(entry)));
      }
    }
  } else if (value is Map) {
    for (final entry in value.values) {
      if (entry is Map) {
        items.add(SupplierQuoteItemRef.fromMap(Map<String, dynamic>.from(entry)));
      }
    }
  }
  return items;
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
