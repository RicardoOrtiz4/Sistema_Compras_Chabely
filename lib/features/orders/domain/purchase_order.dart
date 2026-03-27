import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/constants.dart';

enum PurchaseOrderItemQuoteStatus {
  pending,
  draft,
  pendingDireccion,
  approved,
  rejected,
}

extension PurchaseOrderItemQuoteStatusX on PurchaseOrderItemQuoteStatus {
  String get label {
    switch (this) {
      case PurchaseOrderItemQuoteStatus.pending:
        return 'Pendiente de compra';
      case PurchaseOrderItemQuoteStatus.draft:
        return 'En compra';
      case PurchaseOrderItemQuoteStatus.pendingDireccion:
        return paymentAuthorizationLabel;
      case PurchaseOrderItemQuoteStatus.approved:
        return 'Aprobado';
      case PurchaseOrderItemQuoteStatus.rejected:
        return 'Rechazado';
    }
  }
}

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
    this.internalOrder,
    this.quoteId,
    this.quoteStatus = PurchaseOrderItemQuoteStatus.pending,
    this.estimatedDate,
    this.deliveryEtaDate,
    this.sentToContabilidadAt,
    this.reviewFlagged = false,
    this.reviewComment,
    this.receivedQuantity,
    this.receivedComment,
    this.arrivedAt,
    this.arrivedByName,
    this.arrivedByArea,
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
  final String? internalOrder;
  final String? quoteId;
  final PurchaseOrderItemQuoteStatus quoteStatus;
  final DateTime? estimatedDate;
  final DateTime? deliveryEtaDate;
  final DateTime? sentToContabilidadAt;
  final bool reviewFlagged;
  final String? reviewComment;
  final num? receivedQuantity;
  final String? receivedComment;
  final DateTime? arrivedAt;
  final String? arrivedByName;
  final String? arrivedByArea;

  bool get isArrivalRegistered => arrivedAt != null;

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
    String? internalOrder,
    String? quoteId,
    PurchaseOrderItemQuoteStatus? quoteStatus,
    DateTime? estimatedDate,
    DateTime? deliveryEtaDate,
    DateTime? sentToContabilidadAt,
    bool? reviewFlagged,
    String? reviewComment,
    bool clearReviewComment = false,
    bool clearInternalOrder = false,
    bool clearQuoteId = false,
    bool clearDeliveryEtaDate = false,
    bool clearSentToContabilidadAt = false,
    num? receivedQuantity,
    String? receivedComment,
    bool clearReceivedQuantity = false,
    bool clearReceivedComment = false,
    DateTime? arrivedAt,
    String? arrivedByName,
    String? arrivedByArea,
    bool clearArrivedAt = false,
    bool clearArrivedByName = false,
    bool clearArrivedByArea = false,
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
      internalOrder: clearInternalOrder ? null : (internalOrder ?? this.internalOrder),
      quoteId: clearQuoteId ? null : (quoteId ?? this.quoteId),
      quoteStatus: quoteStatus ?? this.quoteStatus,
      estimatedDate: estimatedDate ?? this.estimatedDate,
      deliveryEtaDate: clearDeliveryEtaDate
          ? null
          : (deliveryEtaDate ?? this.deliveryEtaDate),
      sentToContabilidadAt: clearSentToContabilidadAt
          ? null
          : (sentToContabilidadAt ?? this.sentToContabilidadAt),
      reviewFlagged: reviewFlagged ?? this.reviewFlagged,
      reviewComment: clearReviewComment ? null : (reviewComment ?? this.reviewComment),
      receivedQuantity: clearReceivedQuantity ? null : (receivedQuantity ?? this.receivedQuantity),
      receivedComment: clearReceivedComment ? null : (receivedComment ?? this.receivedComment),
      arrivedAt: clearArrivedAt ? null : (arrivedAt ?? this.arrivedAt),
      arrivedByName: clearArrivedByName ? null : (arrivedByName ?? this.arrivedByName),
      arrivedByArea: clearArrivedByArea ? null : (arrivedByArea ?? this.arrivedByArea),
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
      'internalOrder': internalOrder,
      'quoteId': quoteId,
      'quoteStatus': quoteStatus.name,
      'estimatedDate': estimatedDate?.millisecondsSinceEpoch,
      'deliveryEtaDate': deliveryEtaDate?.millisecondsSinceEpoch,
      'sentToContabilidadAt': sentToContabilidadAt?.millisecondsSinceEpoch,
      'reviewFlagged': reviewFlagged,
      'reviewComment': reviewComment,
      'receivedQuantity': receivedQuantity,
      'receivedComment': receivedComment,
      'arrivedAt': arrivedAt?.millisecondsSinceEpoch,
      'arrivedByName': arrivedByName,
      'arrivedByArea': arrivedByArea,
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
      internalOrder: data['internalOrder'] as String?,
      quoteId: data['quoteId'] as String?,
      quoteStatus: _itemQuoteStatusFromString(data['quoteStatus'] as String?) ??
          PurchaseOrderItemQuoteStatus.pending,
      estimatedDate: _parseDateTime(data['estimatedDate']),
      deliveryEtaDate: _parseDateTime(data['deliveryEtaDate']),
      sentToContabilidadAt: _parseDateTime(data['sentToContabilidadAt']),
      reviewFlagged: _parseBool(data['reviewFlagged']),
      reviewComment: data['reviewComment'] as String?,
      receivedQuantity: data['receivedQuantity'] as num?,
      receivedComment: data['receivedComment'] as String?,
      arrivedAt: _parseDateTime(data['arrivedAt']),
      arrivedByName: data['arrivedByName'] as String?,
      arrivedByArea: data['arrivedByArea'] as String?,
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
    this.urgentJustification,
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
    this.requestedDeliveryDate,
    this.etaDate,
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
    this.materialArrivedAt,
    this.materialArrivedName,
    this.materialArrivedArea,
    this.completedAt,
    this.requesterReceivedAt,
    this.requesterReceivedName,
    this.requesterReceivedArea,
    this.requesterReceiptAutoConfirmed = false,
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
  final String? urgentJustification;
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
  final DateTime? requestedDeliveryDate;
  final DateTime? etaDate;
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
  final DateTime? materialArrivedAt;
  final String? materialArrivedName;
  final String? materialArrivedArea;
  final DateTime? completedAt;
  final DateTime? requesterReceivedAt;
  final String? requesterReceivedName;
  final String? requesterReceivedArea;
  final bool requesterReceiptAutoConfirmed;
  final bool isDraft;

  bool get canEdit => isDraft || status == PurchaseOrderStatus.draft;
  bool get isMaterialArrivalRegistered => materialArrivedAt != null;
  bool get isRequesterReceiptConfirmed => requesterReceivedAt != null;
  bool get isRequesterReceiptAutoConfirmed =>
      isRequesterReceiptConfirmed && requesterReceiptAutoConfirmed;
  bool get isAwaitingRequesterReceipt =>
      status == PurchaseOrderStatus.eta && !isRequesterReceiptConfirmed;
  bool get isArrivalPendingConfirmation =>
      !isRequesterReceiptConfirmed && hasAllItemsArrived(this);

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
      'urgentJustification': urgentJustification,
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
      'requestedDeliveryDate': requestedDeliveryDate?.millisecondsSinceEpoch,
      'etaDate': etaDate?.millisecondsSinceEpoch,
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
      'materialArrivedAt': materialArrivedAt?.millisecondsSinceEpoch,
      'materialArrivedName': materialArrivedName,
      'materialArrivedArea': materialArrivedArea,
      'completedAt': completedAt?.millisecondsSinceEpoch,
      'requesterReceivedAt': requesterReceivedAt?.millisecondsSinceEpoch,
      'requesterReceivedName': requesterReceivedName,
      'requesterReceivedArea': requesterReceivedArea,
      'requesterReceiptAutoConfirmed':
          requesterReceiptAutoConfirmed ? true : null,
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

    final facturaUrls = _parseStringList(data['facturaPdfUrls']);
    final singleFactura = data['facturaPdfUrl'] as String?;
    if (singleFactura != null &&
        singleFactura.trim().isNotEmpty &&
        !facturaUrls.contains(singleFactura)) {
      facturaUrls.insert(0, singleFactura);
    }

    final requesterId = _firstNonEmptyString(
      data,
      const ['requesterId', 'requestedById', 'userId', 'createdBy'],
    );
    final requesterName = _firstNonEmptyString(
      data,
      const [
        'requesterName',
        'requestedByName',
        'requesterDisplayName',
        'requester',
        'userName',
        'displayName',
        'name',
      ],
    );
    final areaId = _firstNonEmptyString(
      data,
      const ['areaId', 'requesterAreaId', 'departmentId', 'area'],
    );
    final areaName = _firstNonEmptyString(
      data,
      const ['areaName', 'requesterArea', 'departmentName', 'areaLabel'],
    );

    return PurchaseOrder(
      id: id,
      requesterId: requesterId,
      requesterName: requesterName,
      areaId: areaId,
      areaName: normalizeAreaLabel(areaName),
      companyId: data['companyId'] as String?,
      urgency: _urgencyFromString(data['urgency'] as String?) ?? PurchaseOrderUrgency.normal,
      status: _statusFromString(data['status'] as String?) ?? PurchaseOrderStatus.draft,
      items: items,
      clientNote: data['clientNote'] as String?,
      urgentJustification: data['urgentJustification'] as String?,
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
      requestedDeliveryDate: _parseDateTime(data['requestedDeliveryDate']),
      etaDate: _parseDateTime(data['etaDate']),
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
      materialArrivedAt: _parseDateTime(data['materialArrivedAt']),
      materialArrivedName: data['materialArrivedName'] as String?,
      materialArrivedArea: data['materialArrivedArea'] as String?,
      completedAt: _parseDateTime(data['completedAt']),
      requesterReceivedAt: _parseDateTime(data['requesterReceivedAt']),
      requesterReceivedName: data['requesterReceivedName'] as String?,
      requesterReceivedArea: data['requesterReceivedArea'] as String?,
      requesterReceiptAutoConfirmed:
          (data['requesterReceiptAutoConfirmed'] as bool?) ?? false,
      isDraft: (data['isDraft'] as bool?) ?? false,
    );
  }
}

String _firstNonEmptyString(
  Map<String, dynamic> data,
  List<String> keys,
) {
  for (final key in keys) {
    final raw = data[key];
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    if (raw is Map) {
      final nested = Map<String, dynamic>.from(raw);
      final nestedValue = _firstNonEmptyString(
        nested,
        const [
          'name',
          'displayName',
          'fullName',
          'nombre',
          'requesterName',
          'requestedByName',
          'label',
          'value',
        ],
      );
      if (nestedValue.isNotEmpty) return nestedValue;
    }
  }
  return '';
}

DateTime? resolveRequestedDeliveryDate(PurchaseOrder order) {
  final explicit = order.requestedDeliveryDate;
  if (explicit != null) {
    return DateTime(explicit.year, explicit.month, explicit.day);
  }

  DateTime? selected;
  for (final item in order.items) {
    final date = item.estimatedDate;
    if (date == null) continue;
    final normalized = DateTime(date.year, date.month, date.day);
    if (selected == null || normalized.isBefore(selected)) {
      selected = normalized;
    }
  }
  return selected;
}

DateTime? resolveCommittedDeliveryDate(PurchaseOrder order) {
  DateTime? selected;
  for (final item in order.items) {
    final date = item.deliveryEtaDate;
    if (date == null) continue;
    final normalized = DateTime(date.year, date.month, date.day);
    if (selected == null || normalized.isAfter(selected)) {
      selected = normalized;
    }
  }
  return selected;
}

int countItemsWithCommittedDeliveryDate(PurchaseOrder order) {
  return order.items.where((item) => item.deliveryEtaDate != null).length;
}

int countArrivedItems(PurchaseOrder order) {
  return order.items.where((item) => item.isArrivalRegistered).length;
}

int countPendingArrivalItems(PurchaseOrder order) {
  return order.items
      .where((item) => item.deliveryEtaDate != null && !item.isArrivalRegistered)
      .length;
}

bool hasAnyArrivedItems(PurchaseOrder order) {
  return order.items.any((item) => item.isArrivalRegistered);
}

bool hasAllItemsArrived(PurchaseOrder order) {
  if (order.items.isEmpty) return false;
  return order.items.every((item) => item.isArrivalRegistered);
}

DateTime? resolveLatestArrivalDate(PurchaseOrder order) {
  DateTime? latest = order.materialArrivedAt;
  for (final item in order.items) {
    final arrivedAt = item.arrivedAt;
    if (arrivedAt == null) continue;
    if (latest == null || arrivedAt.isAfter(latest)) {
      latest = arrivedAt;
    }
  }
  return latest;
}

DateTime? orderAutoReceiptDueDate(PurchaseOrder order) {
  if (order.isRequesterReceiptConfirmed) return null;
  if (!hasAllItemsArrived(order)) return null;
  final latestArrival = resolveLatestArrivalDate(order);
  if (latestArrival == null) return null;
  return latestArrival.add(const Duration(days: 10));
}

bool isOrderAutoReceiptDue(PurchaseOrder order, {DateTime? now}) {
  final dueDate = orderAutoReceiptDueDate(order);
  if (dueDate == null) return false;
  final reference = now ?? DateTime.now();
  return !reference.isBefore(dueDate);
}

String requesterReceiptStatusLabel(PurchaseOrder order) {
  if (order.isRequesterReceiptAutoConfirmed) {
    return 'Llegado pero no confirmado';
  }
  if (order.isRequesterReceiptConfirmed) {
    return 'Recibida por solicitante';
  }
  if (order.isArrivalPendingConfirmation) {
    return 'Llegado pendiente de confirmacion';
  }
  return order.status.label;
}

int? itemArrivalDeltaDays(PurchaseOrderItem item) {
  final eta = _dateOnly(item.deliveryEtaDate);
  final arrived = _dateOnly(item.arrivedAt);
  if (eta == null || arrived == null) return null;
  return arrived.difference(eta).inDays;
}

String itemArrivalComplianceLabel(PurchaseOrderItem item) {
  if (!item.isArrivalRegistered) {
    return itemPendingArrivalLabel(item);
  }
  final delta = itemArrivalDeltaDays(item);
  if (delta == null) return 'Entregado sin fecha estimada';
  if (delta == 0) return 'Entregado en la fecha exacta';
  if (delta < 0) {
    final days = delta.abs();
    return 'Entregado antes de la fecha estimada ($days dia${days == 1 ? '' : 's'} antes)';
  }
  return 'Te excediste con $delta dia${delta == 1 ? '' : 's'} de entrega';
}

String itemPendingArrivalLabel(
  PurchaseOrderItem item, {
  DateTime? referenceDate,
}) {
  final eta = _dateOnly(item.deliveryEtaDate);
  if (eta == null) return 'Sin fecha estimada de entrega';
  final today = _dateOnly(referenceDate ?? DateTime.now())!;
  final delta = today.difference(eta).inDays;
  if (delta == 0) return 'Se espera hoy';
  if (delta < 0) {
    final days = delta.abs();
    return 'Faltan $days dia${days == 1 ? '' : 's'} para la fecha estimada';
  }
  return 'Atraso actual de $delta dia${delta == 1 ? '' : 's'} frente a la fecha estimada';
}

bool hasAllItemsCommittedDeliveryDate(PurchaseOrder order) {
  if (order.items.isEmpty) return false;
  for (final item in order.items) {
    if (item.deliveryEtaDate == null) {
      return false;
    }
  }
  return true;
}

DateTime? _dateOnly(DateTime? value) {
  if (value == null) return null;
  return DateTime(value.year, value.month, value.day);
}

PurchaseOrderStatus? _statusFromString(String? raw) {
  if (raw == null) return null;
  final normalized = raw.trim();
  for (final status in PurchaseOrderStatus.values) {
    if (status.name == normalized) return status;
  }
  return null;
}

PurchaseOrderUrgency? _urgencyFromString(String? raw) {
  if (raw == null) return null;
  final normalized = raw.trim().toLowerCase();
  if (normalized == 'alta' || normalized == 'media' || normalized == 'baja') {
    return PurchaseOrderUrgency.normal;
  }
  for (final urgency in PurchaseOrderUrgency.values) {
    if (urgency.name == normalized) return urgency;
  }
  return null;
}

PurchaseOrderItemQuoteStatus? _itemQuoteStatusFromString(String? raw) {
  if (raw == null) return null;
  for (final status in PurchaseOrderItemQuoteStatus.values) {
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

