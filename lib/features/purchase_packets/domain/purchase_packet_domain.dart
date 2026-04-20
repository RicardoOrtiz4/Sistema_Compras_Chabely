import 'dart:convert';

import 'package:sistema_compras/features/auth/domain/app_user.dart';

String _normalizedStorageKey(String raw) {
  return raw.trim().toLowerCase().replaceAll('-', '_');
}

enum RequestOrderStatus {
  draft('draft'),
  intakeReview('intake_review'),
  sourcing('sourcing'),
  readyForApproval('ready_for_approval'),
  approvalQueue('approval_queue'),
  executionReady('execution_ready'),
  documentsCheck('documents_check'),
  completed('completed');

  const RequestOrderStatus(this.storageKey);

  final String storageKey;

  static RequestOrderStatus? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = _normalizedStorageKey(raw);
    for (final value in values) {
      if (value.storageKey == normalized) return value;
    }
    return null;
  }
}

enum PurchasePacketStatus {
  draft('draft'),
  approvalQueue('approval_queue'),
  executionReady('execution_ready'),
  completed('completed');

  const PurchasePacketStatus(this.storageKey);

  final String storageKey;

  static PurchasePacketStatus? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = _normalizedStorageKey(raw);
    for (final value in values) {
      if (value.storageKey == normalized) return value;
    }
    return null;
  }
}

enum PacketDecisionAction {
  approve('approve'),
  returnForRework('return_for_rework'),
  closeUnpurchasable('close_unpurchasable');

  const PacketDecisionAction(this.storageKey);

  final String storageKey;

  static PacketDecisionAction? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = _normalizedStorageKey(raw);
    for (final value in values) {
      if (value.storageKey == normalized) return value;
    }
    return null;
  }
}

class PacketDomainError implements Exception {
  const PacketDomainError(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

class MissingOrderReference extends PacketDomainError {
  MissingOrderReference(String orderId)
      : super('MissingOrderReference', 'No existe la orden $orderId.');
}

class MissingItemReference extends PacketDomainError {
  MissingItemReference(String orderId, String itemId)
      : super(
          'MissingItemReference',
          'No existe el item $itemId en la orden $orderId.',
        );
}

class PacketVersionConflict extends PacketDomainError {
  PacketVersionConflict({
    required this.packetId,
    required this.expectedVersion,
    required this.actualVersion,
  }) : super(
          'PacketVersionConflict',
          'Version esperada $expectedVersion, version actual $actualVersion para el paquete $packetId.',
        );

  final String packetId;
  final int expectedVersion;
  final int actualVersion;
}

class PacketAlreadySubmitted extends PacketDomainError {
  PacketAlreadySubmitted(String packetId)
      : super(
          'PacketAlreadySubmitted',
          'El paquete $packetId ya fue enviado a aprobacion ejecutiva.',
        );
}

class InvalidPacketTransition extends PacketDomainError {
  InvalidPacketTransition(PurchasePacketStatus from, PurchasePacketStatus to)
      : super(
          'InvalidPacketTransition',
          'Transicion invalida del paquete ${from.storageKey} -> ${to.storageKey}.',
        );
}

class InvalidOrderTransition extends PacketDomainError {
  InvalidOrderTransition(RequestOrderStatus from, RequestOrderStatus to)
      : super(
          'InvalidOrderTransition',
          'Transicion invalida de la orden ${from.storageKey} -> ${to.storageKey}.',
        );
}

class RequestOrderItem {
  const RequestOrderItem({
    required this.id,
    required this.lineNumber,
    required this.partNumber,
    required this.description,
    required this.quantity,
    required this.unit,
    this.supplierName,
    this.estimatedAmount,
    this.customer,
    this.isClosed = false,
  });

  final String id;
  final int lineNumber;
  final String partNumber;
  final String description;
  final num quantity;
  final String unit;
  final String? supplierName;
  final num? estimatedAmount;
  final String? customer;
  final bool isClosed;

  RequestOrderItem copyWith({
    bool? isClosed,
    String? supplierName,
    num? estimatedAmount,
  }) {
    return RequestOrderItem(
      id: id,
      lineNumber: lineNumber,
      partNumber: partNumber,
      description: description,
      quantity: quantity,
      unit: unit,
      supplierName: supplierName ?? this.supplierName,
      estimatedAmount: estimatedAmount ?? this.estimatedAmount,
      customer: customer,
      isClosed: isClosed ?? this.isClosed,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'itemId': id,
      'lineNumber': lineNumber,
      'partNumber': partNumber,
      'description': description,
      'quantity': quantity,
      'unit': unit,
      'supplierName': supplierName,
      'estimatedAmount': estimatedAmount,
      'customer': customer,
      'isClosed': isClosed,
    };
  }

  factory RequestOrderItem.fromMap(String itemId, Map<String, dynamic> data) {
    return RequestOrderItem(
      id: (data['itemId'] as String?)?.trim().isNotEmpty == true
          ? (data['itemId'] as String).trim()
          : itemId,
      lineNumber: (data['lineNumber'] as num?)?.toInt() ??
          (data['line'] as num?)?.toInt() ??
          0,
      partNumber: (data['partNumber'] as String?)?.trim() ?? '',
      description: (data['description'] as String?)?.trim() ?? '',
      quantity: (data['quantity'] as num?) ?? 0,
      unit: (data['unit'] as String?)?.trim() ?? '',
      supplierName: (data['supplierName'] as String?)?.trim().isNotEmpty == true
          ? (data['supplierName'] as String).trim()
          : (data['supplier'] as String?)?.trim(),
      estimatedAmount: data['estimatedAmount'] as num? ?? data['budget'] as num?,
      customer: (data['customer'] as String?)?.trim(),
      isClosed: data['isClosed'] == true,
    );
  }
}

class RequestOrder {
  const RequestOrder({
    required this.id,
    required this.requesterId,
    required this.requesterName,
    required this.areaId,
    required this.areaName,
    required this.urgency,
    required this.status,
    required this.items,
    this.createdAt,
    this.updatedAt,
    this.projection = const OrderProjectionSnapshot(),
    this.source = 'new',
  });

  final String id;
  final String requesterId;
  final String requesterName;
  final String areaId;
  final String areaName;
  final String urgency;
  final RequestOrderStatus status;
  final List<RequestOrderItem> items;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final OrderProjectionSnapshot projection;
  final String source;

  RequestOrderItem? itemById(String itemId) {
    for (final item in items) {
      if (item.id == itemId) return item;
    }
    return null;
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'requesterId': requesterId,
      'requesterName': requesterName,
      'areaId': areaId,
      'areaName': areaName,
      'urgency': urgency,
      'status': status.storageKey,
      'createdAt': createdAt?.millisecondsSinceEpoch,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
      'projection': projection.toMap(),
      'source': source,
    };
  }

  factory RequestOrder.fromMap(
    String orderId,
    Map<String, dynamic> data, {
    List<RequestOrderItem> items = const <RequestOrderItem>[],
  }) {
    return RequestOrder(
      id: orderId,
      requesterId: (data['requesterId'] as String?)?.trim() ?? '',
      requesterName: (data['requesterName'] as String?)?.trim() ?? '',
      areaId: (data['areaId'] as String?)?.trim() ?? '',
      areaName: (data['areaName'] as String?)?.trim() ?? '',
      urgency: (data['urgency'] as String?)?.trim() ?? 'normal',
      status: RequestOrderStatus.tryParse(data['status'] as String?) ??
          RequestOrderStatus.draft,
      items: items,
      createdAt: _parseDateTime(data['createdAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
      projection: OrderProjectionSnapshot.fromDynamic(data['projection']),
      source: (data['source'] as String?)?.trim().isNotEmpty == true
          ? (data['source'] as String).trim()
          : 'new',
    );
  }
}

class PacketItemRef {
  const PacketItemRef({
    required this.id,
    required this.orderId,
    required this.itemId,
    required this.lineNumber,
    required this.description,
    required this.quantity,
    required this.unit,
    this.amount,
    this.closedAsUnpurchasable = false,
  });

  final String id;
  final String orderId;
  final String itemId;
  final int lineNumber;
  final String description;
  final num quantity;
  final String unit;
  final num? amount;
  final bool closedAsUnpurchasable;

  PacketItemRef copyWith({bool? closedAsUnpurchasable}) {
    return PacketItemRef(
      id: id,
      orderId: orderId,
      itemId: itemId,
      lineNumber: lineNumber,
      description: description,
      quantity: quantity,
      unit: unit,
      amount: amount,
      closedAsUnpurchasable: closedAsUnpurchasable ?? this.closedAsUnpurchasable,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'itemRefId': id,
      'orderId': orderId,
      'itemId': itemId,
      'lineNumber': lineNumber,
      'description': description,
      'quantity': quantity,
      'unit': unit,
      'amount': amount,
      'closedAsUnpurchasable': closedAsUnpurchasable,
    };
  }

  factory PacketItemRef.fromMap(String id, Map<String, dynamic> data) {
    return PacketItemRef(
      id: (data['itemRefId'] as String?)?.trim().isNotEmpty == true
          ? (data['itemRefId'] as String).trim()
          : id,
      orderId: (data['orderId'] as String?)?.trim() ?? '',
      itemId: (data['itemId'] as String?)?.trim() ?? '',
      lineNumber: (data['lineNumber'] as num?)?.toInt() ??
          _inferLineNumber((data['itemId'] as String?)?.trim()),
      description: (data['description'] as String?)?.trim() ?? '',
      quantity: (data['quantity'] as num?) ?? 0,
      unit: (data['unit'] as String?)?.trim() ?? '',
      amount: data['amount'] as num?,
      closedAsUnpurchasable: data['closedAsUnpurchasable'] == true,
    );
  }
}

int _inferLineNumber(String? rawItemId) {
  final value = rawItemId?.trim() ?? '';
  if (value.startsWith('line_')) {
    return int.tryParse(value.substring(5)) ?? 0;
  }
  return int.tryParse(value) ?? 0;
}

class PurchasePacket {
  const PurchasePacket({
    required this.id,
    required this.supplierName,
    required this.status,
    required this.version,
    required this.totalAmount,
    required this.evidenceUrls,
    required this.itemRefs,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.submittedAt,
    this.submittedBy,
    this.folio,
  });

  final String id;
  final String supplierName;
  final PurchasePacketStatus status;
  final int version;
  final num totalAmount;
  final List<String> evidenceUrls;
  final List<PacketItemRef> itemRefs;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final DateTime? submittedAt;
  final String? submittedBy;
  final String? folio;

  bool get isSubmitted => submittedAt != null;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'supplierName': supplierName,
      'status': status.storageKey,
      'version': version,
      'totalAmount': totalAmount,
      'evidenceUrls': evidenceUrls,
      'createdAt': createdAt?.millisecondsSinceEpoch,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
      'createdBy': createdBy,
      'submittedAt': submittedAt?.millisecondsSinceEpoch,
      'submittedBy': submittedBy,
      'folio': folio,
    };
  }

  factory PurchasePacket.fromMap(
    String packetId,
    Map<String, dynamic> data, {
    List<PacketItemRef> itemRefs = const <PacketItemRef>[],
  }) {
    return PurchasePacket(
      id: packetId,
      supplierName: (data['supplierName'] as String?)?.trim() ?? '',
      status: PurchasePacketStatus.tryParse(data['status'] as String?) ??
          PurchasePacketStatus.draft,
      version: (data['version'] as num?)?.toInt() ?? 0,
      totalAmount: (data['totalAmount'] as num?) ?? 0,
      evidenceUrls: _parseStringList(data['evidenceUrls']),
      itemRefs: itemRefs,
      createdAt: _parseDateTime(data['createdAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
      createdBy: (data['createdBy'] as String?)?.trim(),
      submittedAt: _parseDateTime(data['submittedAt']),
      submittedBy: (data['submittedBy'] as String?)?.trim(),
      folio: (data['folio'] as String?)?.trim(),
    );
  }
}

class PacketDecision {
  const PacketDecision({
    required this.id,
    required this.packetId,
    required this.action,
    required this.actorId,
    required this.actorName,
    required this.actorArea,
    required this.timestamp,
    this.reason,
    this.affectedItemRefIds = const <String>[],
  });

  final String id;
  final String packetId;
  final PacketDecisionAction action;
  final String actorId;
  final String actorName;
  final String actorArea;
  final DateTime timestamp;
  final String? reason;
  final List<String> affectedItemRefIds;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'packetId': packetId,
      'action': action.storageKey,
      'actorId': actorId,
      'actorName': actorName,
      'actorArea': actorArea,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'reason': reason,
      'affectedItemRefIds': affectedItemRefIds,
    };
  }

  factory PacketDecision.fromMap(String id, Map<String, dynamic> data) {
    return PacketDecision(
      id: id,
      packetId: (data['packetId'] as String?)?.trim() ?? '',
      action: PacketDecisionAction.tryParse(data['action'] as String?) ??
          PacketDecisionAction.returnForRework,
      actorId: (data['actorId'] as String?)?.trim() ?? '',
      actorName: (data['actorName'] as String?)?.trim() ?? '',
      actorArea: (data['actorArea'] as String?)?.trim() ?? '',
      timestamp: _parseDateTime(data['timestamp']) ?? DateTime.now(),
      reason: (data['reason'] as String?)?.trim(),
      affectedItemRefIds: _parseStringList(data['affectedItemRefIds']),
    );
  }
}

class OrderProjectionSnapshot {
  const OrderProjectionSnapshot({
    this.packetIds = const <String>[],
    this.closedItemRefIds = const <String>[],
    this.lastPacketStatus,
    this.status,
  });

  final List<String> packetIds;
  final List<String> closedItemRefIds;
  final PurchasePacketStatus? lastPacketStatus;
  final RequestOrderStatus? status;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'packetIds': packetIds,
      'closedItemRefIds': closedItemRefIds,
      'lastPacketStatus': lastPacketStatus?.storageKey,
      'status': status?.storageKey,
    };
  }

  factory OrderProjectionSnapshot.fromDynamic(Object? raw) {
    if (raw is! Map) {
      return const OrderProjectionSnapshot();
    }
    final data = Map<String, dynamic>.from(raw);
    return OrderProjectionSnapshot(
      packetIds: _parseStringList(data['packetIds']),
      closedItemRefIds: _parseStringList(data['closedItemRefIds']),
      lastPacketStatus:
          PurchasePacketStatus.tryParse(data['lastPacketStatus'] as String?),
      status: RequestOrderStatus.tryParse(data['status'] as String?),
    );
  }
}

class PacketBundle {
  const PacketBundle({
    required this.packet,
    required this.decisions,
  });

  final PurchasePacket packet;
  final List<PacketDecision> decisions;
}

class PacketTelemetryRecord {
  const PacketTelemetryRecord({
    required this.operationId,
    required this.actorId,
    required this.entityId,
    required this.expectedVersion,
    required this.actualVersion,
    required this.durationMs,
    required this.result,
    this.context = const <String, Object?>{},
  });

  final String operationId;
  final String actorId;
  final String entityId;
  final int? expectedVersion;
  final int? actualVersion;
  final int durationMs;
  final String result;
  final Map<String, Object?> context;

  String toJsonLine() {
    return jsonEncode(<String, Object?>{
      'operationId': operationId,
      'actorId': actorId,
      'entityId': entityId,
      'expectedVersion': expectedVersion,
      'actualVersion': actualVersion,
      'durationMs': durationMs,
      'result': result,
      'context': context,
    });
  }
}

void ensureValidOrderTransition(
  RequestOrderStatus from,
  RequestOrderStatus to,
) {
  const allowed = <RequestOrderStatus, Set<RequestOrderStatus>>{
    RequestOrderStatus.draft: <RequestOrderStatus>{
      RequestOrderStatus.intakeReview,
    },
    RequestOrderStatus.intakeReview: <RequestOrderStatus>{
      RequestOrderStatus.sourcing,
    },
    RequestOrderStatus.sourcing: <RequestOrderStatus>{
      RequestOrderStatus.readyForApproval,
    },
    RequestOrderStatus.readyForApproval: <RequestOrderStatus>{
      RequestOrderStatus.approvalQueue,
      RequestOrderStatus.executionReady,
      RequestOrderStatus.completed,
    },
    RequestOrderStatus.approvalQueue: <RequestOrderStatus>{
      RequestOrderStatus.readyForApproval,
      RequestOrderStatus.executionReady,
      RequestOrderStatus.completed,
    },
    RequestOrderStatus.executionReady: <RequestOrderStatus>{
      RequestOrderStatus.documentsCheck,
      RequestOrderStatus.completed,
    },
    RequestOrderStatus.documentsCheck: <RequestOrderStatus>{
      RequestOrderStatus.completed,
    },
    RequestOrderStatus.completed: <RequestOrderStatus>{},
  };

  if (from == to) return;
  final next = allowed[from] ?? const <RequestOrderStatus>{};
  if (!next.contains(to)) {
    throw InvalidOrderTransition(from, to);
  }
}

void ensureValidPacketTransition(
  PurchasePacketStatus from,
  PurchasePacketStatus to,
) {
  const allowed = <PurchasePacketStatus, Set<PurchasePacketStatus>>{
    PurchasePacketStatus.draft: <PurchasePacketStatus>{
      PurchasePacketStatus.approvalQueue,
    },
    PurchasePacketStatus.approvalQueue: <PurchasePacketStatus>{
      PurchasePacketStatus.draft,
      PurchasePacketStatus.executionReady,
      PurchasePacketStatus.completed,
    },
    PurchasePacketStatus.executionReady: <PurchasePacketStatus>{
      PurchasePacketStatus.completed,
    },
    PurchasePacketStatus.completed: <PurchasePacketStatus>{},
  };

  if (from == to) return;
  final next = allowed[from] ?? const <PurchasePacketStatus>{};
  if (!next.contains(to)) {
    throw InvalidPacketTransition(from, to);
  }
}

String buildPacketItemRefId(String orderId, String itemId) => '$orderId::$itemId';

String buildOperationId() {
  final now = DateTime.now().microsecondsSinceEpoch;
  return 'op_$now';
}

PacketDecision buildDecision({
  required String id,
  required String packetId,
  required PacketDecisionAction action,
  required AppUser actor,
  String? reason,
  List<String> affectedItemRefIds = const <String>[],
  DateTime? timestamp,
}) {
  return PacketDecision(
    id: id,
    packetId: packetId,
    action: action,
    actorId: actor.id,
    actorName: actor.name,
    actorArea: actor.areaDisplay,
    timestamp: timestamp ?? DateTime.now(),
    reason: reason?.trim().isEmpty == true ? null : reason?.trim(),
    affectedItemRefIds: affectedItemRefIds,
  );
}

DateTime? _parseDateTime(Object? value) {
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is double) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  return null;
}

List<String> _parseStringList(Object? raw) {
  if (raw is List) {
    return raw
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }
  if (raw is Map) {
    return raw.values
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }
  if (raw is String) {
    final value = raw.trim();
    return value.isEmpty ? const <String>[] : <String>[value];
  }
  return const <String>[];
}

