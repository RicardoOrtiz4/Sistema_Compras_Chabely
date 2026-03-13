import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/constants.dart';

class PurchaseOrderItem {
  const PurchaseOrderItem({
    required this.line,
    required this.pieces,
    required this.partNumber,
    required this.description,
    required this.quantity,
    required this.unit,
    this.customer,
    this.supplier,
    this.budget,
    this.estimatedDate,
    this.reviewFlagged = false,
    this.reviewComment,
    this.receivedQuantity,
    this.receivedComment,
  });

  final int line;
  final int pieces;
  final String partNumber;
  final String description;
  final num quantity;
  final String unit;
  final String? customer;
  final String? supplier;
  final num? budget;
  final DateTime? estimatedDate;
  final bool reviewFlagged;
  final String? reviewComment;
  final num? receivedQuantity;
  final String? receivedComment;

  PurchaseOrderItem copyWith({
    int? line,
    int? pieces,
    String? partNumber,
    String? description,
    num? quantity,
    String? unit,
    String? customer,
    String? supplier,
    num? budget,
    DateTime? estimatedDate,
    bool? reviewFlagged,
    String? reviewComment,
    bool clearReviewComment = false,
    num? receivedQuantity,
    String? receivedComment,
    bool clearReceivedQuantity = false,
    bool clearReceivedComment = false,
  }) {
    return PurchaseOrderItem(
      line: line ?? this.line,
      pieces: pieces ?? this.pieces,
      partNumber: partNumber ?? this.partNumber,
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      customer: customer ?? this.customer,
      supplier: supplier ?? this.supplier,
      budget: budget ?? this.budget,
      estimatedDate: estimatedDate ?? this.estimatedDate,
      reviewFlagged: reviewFlagged ?? this.reviewFlagged,
      reviewComment: clearReviewComment ? null : (reviewComment ?? this.reviewComment),
      receivedQuantity: clearReceivedQuantity ? null : (receivedQuantity ?? this.receivedQuantity),
      receivedComment: clearReceivedComment ? null : (receivedComment ?? this.receivedComment),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'line': line,
      'pieces': pieces,
      'partNumber': partNumber,
      'description': description,
      'quantity': quantity,
      'unit': unit,
      'customer': customer,
      'supplier': supplier,
      'budget': budget,
      'estimatedDate': estimatedDate?.millisecondsSinceEpoch,
      'reviewFlagged': reviewFlagged,
      'reviewComment': reviewComment,
      'receivedQuantity': receivedQuantity,
      'receivedComment': receivedComment,
    };
  }

  factory PurchaseOrderItem.fromMap(Map<String, dynamic> data) {
    num? budget;
    final rawBudget = data['budget'];
    if (rawBudget is num) {
      budget = rawBudget;
    } else if (rawBudget is String) {
      budget = num.tryParse(rawBudget.trim());
    }
    return PurchaseOrderItem(
      line: (data['line'] as num?)?.toInt() ?? 0,
      pieces: (data['pieces'] as num?)?.toInt() ?? 0,
      partNumber: (data['partNumber'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      quantity: (data['quantity'] as num?) ?? 0,
      unit: (data['unit'] as String?) ?? '',
      customer: data['customer'] as String?,
      supplier: data['supplier'] as String?,
      budget: budget,
      estimatedDate: _parseDateTime(data['estimatedDate']),
      reviewFlagged: _parseBool(data['reviewFlagged']),
      reviewComment: data['reviewComment'] as String?,
      receivedQuantity: data['receivedQuantity'] as num?,
      receivedComment: data['receivedComment'] as String?,
    );
  }
}

class CotizacionLink {
  const CotizacionLink({
    required this.supplier,
    required this.url,
    this.quoteId,
  });

  final String supplier;
  final String url;
  final String? quoteId;

  Map<String, dynamic> toMap() {
    return {
      'supplier': supplier,
      'url': url,
      'quoteId': quoteId,
    };
  }

  factory CotizacionLink.fromMap(Map<String, dynamic> data) {
    return CotizacionLink(
      supplier: (data['supplier'] as String?) ?? '',
      url: (data['url'] as String?) ?? '',
      quoteId: data['quoteId'] as String?,
    );
  }
}

class SharedQuoteRef {
  const SharedQuoteRef({
    required this.supplier,
    required this.quoteId,
  });

  final String supplier;
  final String quoteId;

  Map<String, dynamic> toMap() {
    return {
      'supplier': supplier,
      'quoteId': quoteId,
    };
  }

  factory SharedQuoteRef.fromMap(Map<String, dynamic> data) {
    return SharedQuoteRef(
      supplier: (data['supplier'] as String?) ?? '',
      quoteId: (data['quoteId'] as String?) ?? '',
    );
  }
}

class PurchaseOrderEvent {
  const PurchaseOrderEvent({
    required this.id,
    required this.fromStatus,
    required this.toStatus,
    required this.timestamp,
    required this.byUser,
    required this.byRole,
    this.comment,
    this.type,
    this.itemsSnapshot = const [],
  });

  final String id;
  final PurchaseOrderStatus? fromStatus;
  final PurchaseOrderStatus? toStatus;
  final DateTime? timestamp;
  final String byUser;
  final String byRole;
  final String? comment;
  final String? type;
  final List<PurchaseOrderItem> itemsSnapshot;

  factory PurchaseOrderEvent.fromMap(String id, Map<String, dynamic> data) {
    return PurchaseOrderEvent(
      id: id,
      fromStatus: _statusFromString(data['fromStatus'] as String?),
      toStatus: _statusFromString(data['toStatus'] as String?),
      timestamp: _parseDateTime(data['timestamp']),
      byUser: (data['byUserId'] as String?) ?? 'Sistema',
      byRole: normalizeAreaLabel((data['byRole'] as String?) ?? ''),
      comment: data['comment'] as String?,
      type: data['type'] as String?,
      itemsSnapshot: _parseItemsSnapshot(data['itemsSnapshot']),
    );
  }
}

class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.requesterId,
    required this.requesterName,
    required this.areaId,
    required this.areaName,
    required this.urgency,
    required this.status,
    required this.items,
    this.companyId,
    this.clientNote,
    this.createdAt,
    this.updatedAt,
    this.lastReturnReason,
    this.supplier,
    this.internalOrder,
    this.budget,
    this.supplierBudgets = const {},
    this.comprasComment,
    this.comprasReviewerName,
    this.comprasReviewerArea,
    this.processedByName,
    this.processedByArea,
    this.direccionGeneralName,
    this.direccionGeneralArea,
    this.direccionComment,
    this.etaDate,
    this.cotizacionPdfUrl,
    this.cotizacionPdfUrls = const [],
    this.cotizacionLinks = const [],
    this.sharedQuoteRefs = const [],
    this.primaryQuoteId,
    this.cotizacionReady,
    this.restoredToCotizacionesOrders = false,
    this.facturaPdfUrl,
    this.facturaPdfUrls = const [],
    this.pdfUrl,
    this.resubmissionDates = const [],
    this.returnCount = 0,
    this.direccionReturnCount = 0,
    this.statusDurations = const {},
    this.statusEnteredAt,
    this.contabilidadName,
    this.contabilidadArea,
    this.facturaUploadedAt,
    this.almacenName,
    this.almacenArea,
    this.almacenComment,
    this.almacenHasDifferences = false,
    this.almacenDifferenceSummary,
    this.almacenReceivedAt,
    this.completedAt,
    this.isDraft = false,
  });

  final String id;
  final String requesterId;
  final String requesterName;
  final String areaId;
  final String areaName;
  final PurchaseOrderUrgency urgency;
  final PurchaseOrderStatus status;
  final List<PurchaseOrderItem> items;
  final String? companyId;
  final String? clientNote;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? lastReturnReason;
  final String? supplier;
  final String? internalOrder;
  final num? budget;
  final Map<String, num> supplierBudgets;
  final String? comprasComment;
  final String? comprasReviewerName;
  final String? comprasReviewerArea;
  final String? processedByName;
  final String? processedByArea;
  final String? direccionGeneralName;
  final String? direccionGeneralArea;
  final String? direccionComment;
  final DateTime? etaDate;
  final String? cotizacionPdfUrl;
  final List<String> cotizacionPdfUrls;
  final List<CotizacionLink> cotizacionLinks;
  final List<SharedQuoteRef> sharedQuoteRefs;
  final String? primaryQuoteId;
  final bool? cotizacionReady;
  final bool restoredToCotizacionesOrders;
  final String? facturaPdfUrl;
  final List<String> facturaPdfUrls;
  final String? pdfUrl;
  final List<DateTime> resubmissionDates;
  final int returnCount;
  final int direccionReturnCount;
  final Map<String, int> statusDurations;
  final DateTime? statusEnteredAt;
  final String? contabilidadName;
  final String? contabilidadArea;
  final DateTime? facturaUploadedAt;
  final String? almacenName;
  final String? almacenArea;
  final String? almacenComment;
  final bool almacenHasDifferences;
  final String? almacenDifferenceSummary;
  final DateTime? almacenReceivedAt;
  final DateTime? completedAt;
  final bool isDraft;

  bool get canEdit => isDraft || status == PurchaseOrderStatus.draft;

  Map<String, dynamic> toMap() {
    return {
      'companyId': companyId,
      'requesterId': requesterId,
      'requesterName': requesterName,
      'areaId': areaId,
      'areaName': areaName,
      'urgency': urgency.name,
      'status': status.name,
      'items': items.map((item) => item.toMap()).toList(),
      'clientNote': clientNote,
      'createdAt': createdAt?.millisecondsSinceEpoch,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
      'lastReturnReason': lastReturnReason,
      'supplier': supplier,
      'internalOrder': internalOrder,
      'budget': budget,
      'supplierBudgets': supplierBudgets.isEmpty ? null : supplierBudgets,
      'comprasComment': comprasComment,
      'comprasReviewerName': comprasReviewerName,
      'comprasReviewerArea': comprasReviewerArea,
      'processedByName': processedByName,
      'processedByArea': processedByArea,
      'direccionGeneralName': direccionGeneralName,
      'direccionGeneralArea': direccionGeneralArea,
      'direccionComment': direccionComment,
      'etaDate': etaDate?.millisecondsSinceEpoch,
      'cotizacionPdfUrl':
          cotizacionLinks.isNotEmpty ? cotizacionLinks.first.url : cotizacionPdfUrl,
      'cotizacionPdfUrls': _urlsFromLinks(cotizacionLinks),
      'cotizacionLinks': cotizacionLinks.isEmpty
          ? null
          : cotizacionLinks.map((link) => link.toMap()).toList(),
      'sharedQuoteRefs': sharedQuoteRefs.isEmpty
          ? null
          : sharedQuoteRefs.map((ref) => ref.toMap()).toList(),
      'primaryQuoteId': primaryQuoteId?.trim().isEmpty ?? true ? null : primaryQuoteId?.trim(),
      'cotizacionReady': cotizacionReady,
      'restoredToCotizacionesOrders': restoredToCotizacionesOrders,
      'facturaPdfUrl': facturaPdfUrl,
      'facturaPdfUrls': facturaPdfUrls,
      'pdfUrl': pdfUrl,
      'resubmissions': resubmissionDates
          .map((date) => date.millisecondsSinceEpoch)
          .toList(),
      'returnCount': returnCount,
      'direccionReturnCount': direccionReturnCount,
      'statusDurations': statusDurations.isEmpty ? null : statusDurations,
      'statusEnteredAt': statusEnteredAt?.millisecondsSinceEpoch,
      'contabilidadName': contabilidadName,
      'contabilidadArea': contabilidadArea,
      'facturaUploadedAt': facturaUploadedAt?.millisecondsSinceEpoch,
      'almacenName': almacenName,
      'almacenArea': almacenArea,
      'almacenComment': almacenComment,
      'almacenHasDifferences': almacenHasDifferences,
      'almacenDifferenceSummary': almacenDifferenceSummary,
      'almacenReceivedAt': almacenReceivedAt?.millisecondsSinceEpoch,
      'completedAt': completedAt?.millisecondsSinceEpoch,
      'isDraft': isDraft,
    };
  }

  factory PurchaseOrder.fromMap(String id, Map<String, dynamic> data) {
    final items = <PurchaseOrderItem>[];
    final rawItems = data['items'];

    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is Map) {
          items.add(PurchaseOrderItem.fromMap(Map<String, dynamic>.from(raw)));
        }
      }
    } else if (rawItems is Map) {
      for (final raw in rawItems.values) {
        if (raw is Map) {
          items.add(PurchaseOrderItem.fromMap(Map<String, dynamic>.from(raw)));
        }
      }
    }

    final urls = _parseStringList(data['cotizacionPdfUrls']);
    final singleUrl = data['cotizacionPdfUrl'] as String?;
    if (singleUrl != null && singleUrl.trim().isNotEmpty && !urls.contains(singleUrl)) {
      urls.insert(0, singleUrl);
    }

    final linkEntries = _parseCotizacionLinks(data['cotizacionLinks']);
    final mergedLinks = _mergeCotizacionLinks(linkEntries, urls);

    final facturaUrls = _parseStringList(data['facturaPdfUrls']);
    final singleFactura = data['facturaPdfUrl'] as String?;
    if (singleFactura != null &&
        singleFactura.trim().isNotEmpty &&
        !facturaUrls.contains(singleFactura)) {
      facturaUrls.insert(0, singleFactura);
    }

    return PurchaseOrder(
      id: id,
      requesterId: (data['requesterId'] as String?) ?? '',
      requesterName: (data['requesterName'] as String?) ?? '',
      areaId: (data['areaId'] as String?) ?? '',
      areaName: normalizeAreaLabel((data['areaName'] as String?) ?? ''),
      companyId: data['companyId'] as String?,
      urgency: _urgencyFromString(data['urgency'] as String?) ?? PurchaseOrderUrgency.media,
      status: _statusFromString(data['status'] as String?) ?? PurchaseOrderStatus.draft,
      items: items,
      clientNote: data['clientNote'] as String?,
      createdAt: _parseDateTime(data['createdAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
      lastReturnReason: data['lastReturnReason'] as String?,
      supplier: data['supplier'] as String?,
      internalOrder: data['internalOrder'] as String?,
      budget: data['budget'] as num?,
      supplierBudgets: _parseSupplierBudgets(data['supplierBudgets']),
      comprasComment: data['comprasComment'] as String?,
      comprasReviewerName: data['comprasReviewerName'] as String?,
      comprasReviewerArea: data['comprasReviewerArea'] as String?,
      processedByName: data['processedByName'] as String?,
      processedByArea: data['processedByArea'] as String?,
      direccionGeneralName: data['direccionGeneralName'] as String?,
      direccionGeneralArea: data['direccionGeneralArea'] as String?,
      direccionComment: data['direccionComment'] as String?,
      etaDate: _parseDateTime(data['etaDate']),
      cotizacionPdfUrl: singleUrl,
      cotizacionPdfUrls: _urlsFromLinks(mergedLinks),
      cotizacionLinks: mergedLinks,
      sharedQuoteRefs: _parseSharedQuoteRefs(data['sharedQuoteRefs']),
      primaryQuoteId: (data['primaryQuoteId'] as String?)?.trim(),
      cotizacionReady: data['cotizacionReady'] == null
          ? null
          : _parseBool(data['cotizacionReady']),
      restoredToCotizacionesOrders: _parseBool(
        data['restoredToCotizacionesOrders'],
      ),
      facturaPdfUrl: singleFactura,
      facturaPdfUrls: facturaUrls,
      pdfUrl: data['pdfUrl'] as String?,
      resubmissionDates: _parseResubmissions(data['resubmissions']),
      returnCount: (data['returnCount'] as num?)?.toInt() ?? 0,
      direccionReturnCount: (data['direccionReturnCount'] as num?)?.toInt() ?? 0,
      statusDurations: _parseStatusDurations(data['statusDurations']),
      statusEnteredAt: _parseDateTime(data['statusEnteredAt']),
      contabilidadName: data['contabilidadName'] as String?,
      contabilidadArea: data['contabilidadArea'] as String?,
      facturaUploadedAt: _parseDateTime(data['facturaUploadedAt']),
      almacenName: data['almacenName'] as String?,
      almacenArea: data['almacenArea'] as String?,
      almacenComment: data['almacenComment'] as String?,
      almacenHasDifferences: _parseBool(data['almacenHasDifferences']),
      almacenDifferenceSummary: data['almacenDifferenceSummary'] as String?,
      almacenReceivedAt: _parseDateTime(data['almacenReceivedAt']),
      completedAt: _parseDateTime(data['completedAt']),
      isDraft: (data['isDraft'] as bool?) ?? false,
    );
  }
}

PurchaseOrderStatus? _statusFromString(String? raw) {
  if (raw == null) return null;
  for (final status in PurchaseOrderStatus.values) {
    if (status.name == raw) return status;
  }
  return null;
}

PurchaseOrderUrgency? _urgencyFromString(String? raw) {
  if (raw == null) return null;
  for (final urgency in PurchaseOrderUrgency.values) {
    if (urgency.name == raw) return urgency;
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

List<DateTime> _parseResubmissions(dynamic value) {
  final dates = <DateTime>[];
  if (value is List) {
    for (final entry in value) {
      final parsed = _parseDateTime(entry);
      if (parsed != null) dates.add(parsed);
    }
  } else if (value is Map) {
    for (final entry in value.values) {
      final parsed = _parseDateTime(entry);
      if (parsed != null) dates.add(parsed);
    }
  }
  dates.sort();
  return dates;
}

bool _parseBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'si' || normalized == 'sí';
  }
  return false;
}

List<String> _parseStringList(dynamic value) {
  final items = <String>[];
  if (value is List) {
    for (final entry in value) {
      final text = entry?.toString().trim() ?? '';
      if (text.isNotEmpty) items.add(text);
    }
  } else if (value is Map) {
    for (final entry in value.values) {
      final text = entry?.toString().trim() ?? '';
      if (text.isNotEmpty) items.add(text);
    }
  } else if (value is String) {
    final text = value.trim();
    if (text.isNotEmpty) items.add(text);
  }
  return items;
}

List<CotizacionLink> _parseCotizacionLinks(dynamic value) {
  final items = <CotizacionLink>[];
  if (value is List) {
    for (final entry in value) {
      if (entry is Map) {
        items.add(CotizacionLink.fromMap(Map<String, dynamic>.from(entry)));
      }
    }
  } else if (value is Map) {
    for (final entry in value.values) {
      if (entry is Map) {
        items.add(CotizacionLink.fromMap(Map<String, dynamic>.from(entry)));
      }
    }
  }
  return items;
}

List<CotizacionLink> _mergeCotizacionLinks(
  List<CotizacionLink> links,
  List<String> urls,
) {
  final merged = <CotizacionLink>[...links];

  for (final url in urls) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) continue;

    final exists = merged.any((entry) => entry.url.trim() == trimmed);
    if (!exists) {
      merged.add(CotizacionLink(supplier: '', url: trimmed));
    }
  }

  return merged;
}

List<String> _urlsFromLinks(List<CotizacionLink> links) {
  final urls = <String>[];
  for (final link in links) {
    final url = link.url.trim();
    if (url.isEmpty) continue;
    if (!urls.contains(url)) urls.add(url);
  }
  return urls;
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
      if (parsed != null) budgets[key] = parsed;
    }
  }
  return budgets;
}

Map<String, int> _parseStatusDurations(dynamic value) {
  final durations = <String, int>{};
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString().trim();
      if (key.isEmpty) continue;

      final raw = entry.value;
      int? parsed;
      if (raw is int) {
        parsed = raw;
      } else if (raw is num) {
        parsed = raw.toInt();
      } else if (raw is String) {
        parsed = int.tryParse(raw.trim());
      }
      if (parsed != null) durations[key] = parsed;
    }
  }
  return durations;
}

List<PurchaseOrderItem> _parseItemsSnapshot(dynamic value) {
  final items = <PurchaseOrderItem>[];
  if (value is List) {
    for (final entry in value) {
      if (entry is Map) {
        items.add(PurchaseOrderItem.fromMap(Map<String, dynamic>.from(entry)));
      }
    }
  } else if (value is Map) {
    for (final entry in value.values) {
      if (entry is Map) {
        items.add(PurchaseOrderItem.fromMap(Map<String, dynamic>.from(entry)));
      }
    }
  }
  return items;
}

List<SharedQuoteRef> _parseSharedQuoteRefs(dynamic value) {
  final refs = <SharedQuoteRef>[];

  if (value is List) {
    for (final entry in value) {
      if (entry is Map) {
        refs.add(SharedQuoteRef.fromMap(Map<String, dynamic>.from(entry)));
      }
    }
    return refs;
  }

  if (value is Map) {
    // Soporta:
    // 1) [{supplier, quoteId}, ...] (ya cubierto arriba)
    // 2) { "proveedor": {supplier, quoteId}, ... }
    // 3) { "proveedor": "quoteId", ... }
    for (final entry in value.entries) {
      final keySupplier = entry.key.toString().trim();

      final v = entry.value;
      if (v is Map) {
        refs.add(SharedQuoteRef.fromMap(Map<String, dynamic>.from(v)));
        continue;
      }
      if (v is String) {
        final quoteId = v.trim();
        if (keySupplier.isNotEmpty && quoteId.isNotEmpty) {
          refs.add(SharedQuoteRef(supplier: keySupplier, quoteId: quoteId));
        }
      }
    }
  }

  return refs;
}
