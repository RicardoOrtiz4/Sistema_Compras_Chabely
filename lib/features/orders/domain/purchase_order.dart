import 'package:cloud_firestore/cloud_firestore.dart';

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
    this.estimatedDate,
  });

  final int line;
  final int pieces;
  final String partNumber;
  final String description;
  final num quantity;
  final String unit;
  final String? customer;
  final DateTime? estimatedDate;

  Map<String, dynamic> toMap() {
    return {
      'line': line,
      'pieces': pieces,
      'partNumber': partNumber,
      'description': description,
      'quantity': quantity,
      'unit': unit,
      'customer': customer,
      'estimatedDate': estimatedDate,
    };
  }

  factory PurchaseOrderItem.fromMap(Map<String, dynamic> data) {
    return PurchaseOrderItem(
      line: (data['line'] as num?)?.toInt() ?? 0,
      pieces: (data['pieces'] as num?)?.toInt() ?? 0,
      partNumber: (data['partNumber'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      quantity: data['quantity'] as num? ?? 0,
      unit: (data['unit'] as String?) ?? '',
      customer: data['customer'] as String?,
      estimatedDate: (data['estimatedDate'] as Timestamp?)?.toDate(),
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
  });

  final String id;
  final PurchaseOrderStatus? fromStatus;
  final PurchaseOrderStatus? toStatus;
  final DateTime? timestamp;
  final String byUser;
  final String byRole;
  final String? comment;
  final String? type;

  factory PurchaseOrderEvent.fromMap(String id, Map<String, dynamic> data) {
    return PurchaseOrderEvent(
      id: id,
      fromStatus: _statusFromString(data['fromStatus'] as String?),
      toStatus: _statusFromString(data['toStatus'] as String?),
      timestamp: (data['timestamp'] as Timestamp?)?.toDate(),
      byUser: (data['byUserId'] as String?) ?? 'Sistema',
      byRole: (data['byRole'] as String?) ?? '',
      comment: data['comment'] as String?,
      type: data['type'] as String?,
    );
  }
}

class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    this.folio,
    required this.requesterId,
    required this.requesterName,
    required this.areaId,
    required this.areaName,
    required this.urgency,
    required this.status,
    required this.items,
    this.createdAt,
    this.updatedAt,
    this.lastReturnReason,
    this.pdfUrl,
    this.isDraft = false,
  });

  final String id;
  final String? folio;
  final String requesterId;
  final String requesterName;
  final String areaId;
  final String areaName;
  final PurchaseOrderUrgency urgency;
  final PurchaseOrderStatus status;
  final List<PurchaseOrderItem> items;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? lastReturnReason;
  final String? pdfUrl;
  final bool isDraft;

  bool get canEdit => isDraft || status == PurchaseOrderStatus.draft;

  Map<String, dynamic> toMap() {
    return {
      'folio': folio,
      'requesterId': requesterId,
      'requesterName': requesterName,
      'areaId': areaId,
      'areaName': areaName,
      'urgency': urgency.name,
      'status': status.name,
      'items': items.map((item) => item.toMap()).toList(),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'lastReturnReason': lastReturnReason,
      'pdfUrl': pdfUrl,
      'isDraft': isDraft,
    };
  }

  factory PurchaseOrder.fromMap(String id, Map<String, dynamic> data) {
    final items = (data['items'] as List<dynamic>? ?? [])
        .map((raw) => PurchaseOrderItem.fromMap(raw as Map<String, dynamic>))
        .toList();
    return PurchaseOrder(
      id: id,
      folio: data['folio'] as String?,
      requesterId: (data['requesterId'] as String?) ?? '',
      requesterName: (data['requesterName'] as String?) ?? '',
      areaId: (data['areaId'] as String?) ?? '',
      areaName: (data['areaName'] as String?) ?? '',
      urgency: _urgencyFromString(data['urgency'] as String?) ??
          PurchaseOrderUrgency.media,
      status:
          _statusFromString(data['status'] as String?) ?? PurchaseOrderStatus.draft,
      items: items,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      lastReturnReason: data['lastReturnReason'] as String?,
      pdfUrl: data['pdfUrl'] as String?,
      isDraft: (data['isDraft'] as bool?) ?? false,
    );
  }
}

PurchaseOrderStatus? _statusFromString(String? raw) {
  if (raw == null) return null;
  return PurchaseOrderStatus.values.firstWhere(
    (element) => element.name == raw,
    orElse: () => PurchaseOrderStatus.draft,
  );
}

PurchaseOrderUrgency? _urgencyFromString(String? raw) {
  if (raw == null) return null;
  return PurchaseOrderUrgency.values.firstWhere(
    (element) => element.name == raw,
    orElse: () => PurchaseOrderUrgency.media,
  );
}
