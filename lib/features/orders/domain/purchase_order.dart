import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/business_calendar.dart';
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
    this.amountCurrency = MoneyCurrency.mxn,
    this.internalOrder,
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
    this.notPurchasedAt,
    this.notPurchasedByName,
    this.notPurchasedByArea,
    this.notPurchasedReason,
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
  final MoneyCurrency amountCurrency;
  final String? internalOrder;
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
  final DateTime? notPurchasedAt;
  final String? notPurchasedByName;
  final String? notPurchasedByArea;
  final String? notPurchasedReason;

  bool get isArrivalRegistered => arrivedAt != null;
  bool get isNotPurchased => notPurchasedAt != null;
  bool get requiresFulfillment => !isNotPurchased;
  bool get isResolved => isNotPurchased || isArrivalRegistered;

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
    MoneyCurrency? amountCurrency,
    String? internalOrder,
    DateTime? estimatedDate,
    DateTime? deliveryEtaDate,
    DateTime? sentToContabilidadAt,
    bool? reviewFlagged,
    String? reviewComment,
    bool clearReviewComment = false,
    bool clearInternalOrder = false,
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
    DateTime? notPurchasedAt,
    String? notPurchasedByName,
    String? notPurchasedByArea,
    String? notPurchasedReason,
    bool clearNotPurchasedAt = false,
    bool clearNotPurchasedByName = false,
    bool clearNotPurchasedByArea = false,
    bool clearNotPurchasedReason = false,
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
      amountCurrency: amountCurrency ?? this.amountCurrency,
      internalOrder: clearInternalOrder ? null : (internalOrder ?? this.internalOrder),
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
      notPurchasedAt: clearNotPurchasedAt
          ? null
          : (notPurchasedAt ?? this.notPurchasedAt),
      notPurchasedByName: clearNotPurchasedByName
          ? null
          : (notPurchasedByName ?? this.notPurchasedByName),
      notPurchasedByArea: clearNotPurchasedByArea
          ? null
          : (notPurchasedByArea ?? this.notPurchasedByArea),
      notPurchasedReason: clearNotPurchasedReason
          ? null
          : (notPurchasedReason ?? this.notPurchasedReason),
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
      'amountCurrency': amountCurrency.code,
      'internalOrder': internalOrder,
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
      'notPurchasedAt': notPurchasedAt?.millisecondsSinceEpoch,
      'notPurchasedByName': notPurchasedByName,
      'notPurchasedByArea': notPurchasedByArea,
      'notPurchasedReason': notPurchasedReason,
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
      amountCurrency:
          moneyCurrencyFromString(data['amountCurrency'] as String?) ??
          MoneyCurrency.mxn,
      internalOrder: data['internalOrder'] as String?,
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
      notPurchasedAt: _parseDateTime(data['notPurchasedAt']),
      notPurchasedByName: data['notPurchasedByName'] as String?,
      notPurchasedByArea: data['notPurchasedByArea'] as String?,
      notPurchasedReason: data['notPurchasedReason'] as String?,
    );
  }
}

enum PurchaseOrderResolutionState {
  inProgress,
  awaitingRequesterConfirmation,
  closedComplete,
  closedPartial,
  closedWithoutPurchase,
}

extension PurchaseOrderResolutionStateX on PurchaseOrderResolutionState {
  String get label {
    switch (this) {
      case PurchaseOrderResolutionState.inProgress:
        return 'En proceso';
      case PurchaseOrderResolutionState.awaitingRequesterConfirmation:
        return 'Pendiente de confirmacion';
      case PurchaseOrderResolutionState.closedComplete:
        return 'Cerrada completa';
      case PurchaseOrderResolutionState.closedPartial:
        return 'Cerrada parcial';
      case PurchaseOrderResolutionState.closedWithoutPurchase:
        return 'Cerrada sin compra';
    }
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
    this.lastReturnFromStatus,
    this.rejectionAcknowledgedAt,
    this.lastReviewDurationMs,
    this.supplier,
    this.internalOrder,
    this.budget,
    this.amountCurrency = MoneyCurrency.mxn,
    this.supplierBudgets = const {},
    this.requestedDeliveryDate,
    this.etaDate,
    this.facturaPdfUrl,
    this.facturaPdfUrls = const [],
    this.paymentReceiptUrls = const [],
    this.pdfUrl,
    this.authorizedByName,
    this.authorizedByArea,
    this.authorizedAt,
    this.processByName,
    this.processByArea,
    this.processAt,
    this.resubmissionDates = const [],
    this.returnCount = 0,
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
    this.serviceRating,
    this.serviceRatingComment,
    this.serviceRatedAt,
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
  final PurchaseOrderStatus? lastReturnFromStatus;
  final DateTime? rejectionAcknowledgedAt;
  final int? lastReviewDurationMs;
  final String? supplier;
  final String? internalOrder;
  final num? budget;
  final MoneyCurrency amountCurrency;
  final Map<String, num> supplierBudgets;
  final DateTime? requestedDeliveryDate;
  final DateTime? etaDate;
  final String? facturaPdfUrl;
  final List<String> facturaPdfUrls;
  final List<String> paymentReceiptUrls;
  final String? pdfUrl;
  final String? authorizedByName;
  final String? authorizedByArea;
  final DateTime? authorizedAt;
  final String? processByName;
  final String? processByArea;
  final DateTime? processAt;
  final List<DateTime> resubmissionDates;
  final int returnCount;
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
  final int? serviceRating;
  final String? serviceRatingComment;
  final DateTime? serviceRatedAt;
  final bool requesterReceiptAutoConfirmed;
  final bool isDraft;

  bool get canEdit => isDraft || status == PurchaseOrderStatus.draft;
  bool get isRejectedDraft {
    final reason = lastReturnReason?.trim() ?? '';
    return status == PurchaseOrderStatus.draft &&
        (reason.isNotEmpty || returnCount > 0);
  }

  bool get isRejectionAcknowledged => rejectionAcknowledgedAt != null;
  bool get isRejectedPendingAcknowledgment =>
      isRejectedDraft && !isRejectionAcknowledged;
  bool get isMaterialArrivalRegistered => materialArrivedAt != null;
  bool get isRequesterReceiptConfirmed => requesterReceivedAt != null;
  bool get isRequesterReceiptAutoConfirmed =>
      isRequesterReceiptConfirmed && requesterReceiptAutoConfirmed;
  bool get isAwaitingRequesterReceipt =>
      status == PurchaseOrderStatus.eta &&
      !isRequesterReceiptConfirmed &&
      requiresRequesterReceiptConfirmation(this);
  bool get isArrivalPendingConfirmation =>
      !isRequesterReceiptConfirmed && hasAllItemsArrived(this);
  bool get hasItemsMarkedAsNotPurchased => hasAnyItemsMarkedAsNotPurchased(this);
  PurchaseOrderResolutionState get resolutionState =>
      resolveOrderResolutionState(this);
  bool get isWorkflowFinished => isOrderWorkflowFinished(this);
  bool get isClosedPartially => resolutionState == PurchaseOrderResolutionState.closedPartial;
  bool get isClosedWithoutPurchase =>
      resolutionState == PurchaseOrderResolutionState.closedWithoutPurchase;

  PurchaseOrder copyWith({
    String? id,
    String? requesterId,
    String? requesterName,
    String? areaId,
    String? areaName,
    PurchaseOrderUrgency? urgency,
    PurchaseOrderStatus? status,
    List<PurchaseOrderItem>? items,
    String? companyId,
    String? clientNote,
    String? urgentJustification,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? lastReturnReason,
    PurchaseOrderStatus? lastReturnFromStatus,
    DateTime? rejectionAcknowledgedAt,
    int? lastReviewDurationMs,
    String? supplier,
    String? internalOrder,
    num? budget,
    MoneyCurrency? amountCurrency,
    Map<String, num>? supplierBudgets,
    DateTime? requestedDeliveryDate,
    DateTime? etaDate,
    String? facturaPdfUrl,
    List<String>? facturaPdfUrls,
    List<String>? paymentReceiptUrls,
    String? pdfUrl,
    String? authorizedByName,
    String? authorizedByArea,
    DateTime? authorizedAt,
    String? processByName,
    String? processByArea,
    DateTime? processAt,
    List<DateTime>? resubmissionDates,
    int? returnCount,
    Map<String, int>? statusDurations,
    DateTime? statusEnteredAt,
    String? contabilidadName,
    String? contabilidadArea,
    DateTime? facturaUploadedAt,
    DateTime? materialArrivedAt,
    String? materialArrivedName,
    String? materialArrivedArea,
    DateTime? completedAt,
    DateTime? requesterReceivedAt,
    String? requesterReceivedName,
    String? requesterReceivedArea,
    int? serviceRating,
    String? serviceRatingComment,
    DateTime? serviceRatedAt,
    bool? requesterReceiptAutoConfirmed,
    bool? isDraft,
  }) {
    return PurchaseOrder(
      id: id ?? this.id,
      requesterId: requesterId ?? this.requesterId,
      requesterName: requesterName ?? this.requesterName,
      areaId: areaId ?? this.areaId,
      areaName: areaName ?? this.areaName,
      urgency: urgency ?? this.urgency,
      status: status ?? this.status,
      items: items ?? this.items,
      companyId: companyId ?? this.companyId,
      clientNote: clientNote ?? this.clientNote,
      urgentJustification: urgentJustification ?? this.urgentJustification,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastReturnReason: lastReturnReason ?? this.lastReturnReason,
      lastReturnFromStatus: lastReturnFromStatus ?? this.lastReturnFromStatus,
      rejectionAcknowledgedAt:
          rejectionAcknowledgedAt ?? this.rejectionAcknowledgedAt,
      lastReviewDurationMs: lastReviewDurationMs ?? this.lastReviewDurationMs,
      supplier: supplier ?? this.supplier,
      internalOrder: internalOrder ?? this.internalOrder,
      budget: budget ?? this.budget,
      amountCurrency: amountCurrency ?? this.amountCurrency,
      supplierBudgets: supplierBudgets ?? this.supplierBudgets,
      requestedDeliveryDate: requestedDeliveryDate ?? this.requestedDeliveryDate,
      etaDate: etaDate ?? this.etaDate,
      facturaPdfUrl: facturaPdfUrl ?? this.facturaPdfUrl,
      facturaPdfUrls: facturaPdfUrls ?? this.facturaPdfUrls,
      paymentReceiptUrls: paymentReceiptUrls ?? this.paymentReceiptUrls,
      pdfUrl: pdfUrl ?? this.pdfUrl,
      authorizedByName: authorizedByName ?? this.authorizedByName,
      authorizedByArea: authorizedByArea ?? this.authorizedByArea,
      authorizedAt: authorizedAt ?? this.authorizedAt,
      processByName: processByName ?? this.processByName,
      processByArea: processByArea ?? this.processByArea,
      processAt: processAt ?? this.processAt,
      resubmissionDates: resubmissionDates ?? this.resubmissionDates,
      returnCount: returnCount ?? this.returnCount,
      statusDurations: statusDurations ?? this.statusDurations,
      statusEnteredAt: statusEnteredAt ?? this.statusEnteredAt,
      contabilidadName: contabilidadName ?? this.contabilidadName,
      contabilidadArea: contabilidadArea ?? this.contabilidadArea,
      facturaUploadedAt: facturaUploadedAt ?? this.facturaUploadedAt,
      materialArrivedAt: materialArrivedAt ?? this.materialArrivedAt,
      materialArrivedName: materialArrivedName ?? this.materialArrivedName,
      materialArrivedArea: materialArrivedArea ?? this.materialArrivedArea,
      completedAt: completedAt ?? this.completedAt,
      requesterReceivedAt: requesterReceivedAt ?? this.requesterReceivedAt,
      requesterReceivedName:
          requesterReceivedName ?? this.requesterReceivedName,
      requesterReceivedArea:
          requesterReceivedArea ?? this.requesterReceivedArea,
      serviceRating: serviceRating ?? this.serviceRating,
      serviceRatingComment:
          serviceRatingComment ?? this.serviceRatingComment,
      serviceRatedAt: serviceRatedAt ?? this.serviceRatedAt,
      requesterReceiptAutoConfirmed:
          requesterReceiptAutoConfirmed ?? this.requesterReceiptAutoConfirmed,
      isDraft: isDraft ?? this.isDraft,
    );
  }

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
      'lastReturnFromStatus': lastReturnFromStatus?.name,
      'rejectionAcknowledgedAt': rejectionAcknowledgedAt?.millisecondsSinceEpoch,
      'lastReviewDurationMs': lastReviewDurationMs,
      'supplier': supplier,
      'internalOrder': internalOrder,
      'budget': budget,
      'amountCurrency': amountCurrency.code,
      'supplierBudgets': supplierBudgets.isEmpty ? null : supplierBudgets,
      'requestedDeliveryDate': requestedDeliveryDate?.millisecondsSinceEpoch,
      'etaDate': etaDate?.millisecondsSinceEpoch,
      'facturaPdfUrl': facturaPdfUrl,
      'facturaPdfUrls': facturaPdfUrls,
      'paymentReceiptUrls': paymentReceiptUrls,
      'pdfUrl': pdfUrl,
      'authorizedByName': authorizedByName,
      'authorizedByArea': authorizedByArea,
      'authorizedAt': authorizedAt?.millisecondsSinceEpoch,
      'processByName': processByName,
      'processByArea': processByArea,
      'processAt': processAt?.millisecondsSinceEpoch,
      'resubmissions': resubmissionDates
          .map((date) => date.millisecondsSinceEpoch)
          .toList(),
      'returnCount': returnCount,
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
      'serviceRating': serviceRating,
      'serviceRatingComment': serviceRatingComment,
      'serviceRatedAt': serviceRatedAt?.millisecondsSinceEpoch,
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
    final paymentReceiptUrls = _parseStringList(data['paymentReceiptUrls']);
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
      lastReturnFromStatus: _statusFromString(
        data['lastReturnFromStatus'] as String?,
      ),
      rejectionAcknowledgedAt: _parseDateTime(data['rejectionAcknowledgedAt']),
      lastReviewDurationMs: (data['lastReviewDurationMs'] as num?)?.toInt(),
      supplier: data['supplier'] as String?,
      internalOrder: data['internalOrder'] as String?,
      budget: data['budget'] as num?,
      amountCurrency:
          moneyCurrencyFromString(data['amountCurrency'] as String?) ??
          MoneyCurrency.mxn,
      supplierBudgets: _parseSupplierBudgets(data['supplierBudgets']),
      requestedDeliveryDate: _parseDateTime(data['requestedDeliveryDate']),
      etaDate: _parseDateTime(data['etaDate']),
      facturaPdfUrl: singleFactura,
      facturaPdfUrls: facturaUrls,
      paymentReceiptUrls: paymentReceiptUrls,
      pdfUrl: data['pdfUrl'] as String?,
      authorizedByName: data['authorizedByName'] as String?,
      authorizedByArea: data['authorizedByArea'] as String?,
      authorizedAt: _parseDateTime(data['authorizedAt']),
      processByName: data['processByName'] as String?,
      processByArea: data['processByArea'] as String?,
      processAt: _parseDateTime(data['processAt']),
      resubmissionDates: _parseResubmissions(data['resubmissions']),
      returnCount: (data['returnCount'] as num?)?.toInt() ?? 0,
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
      serviceRating: (data['serviceRating'] as num?)?.toInt(),
      serviceRatingComment: data['serviceRatingComment'] as String?,
      serviceRatedAt: _parseDateTime(data['serviceRatedAt']),
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

Iterable<PurchaseOrderItem> fulfillmentItems(PurchaseOrder order) sync* {
  for (final item in order.items) {
    if (!item.requiresFulfillment) continue;
    yield item;
  }
}

int countItemsMarkedAsNotPurchased(PurchaseOrder order) {
  return order.items.where((item) => item.isNotPurchased).length;
}

bool hasAnyItemsMarkedAsNotPurchased(PurchaseOrder order) {
  return order.items.any((item) => item.isNotPurchased);
}

int countItemsReturnedFromDireccion(PurchaseOrder order) {
  return 0;
}

bool hasItemsReturnedFromDireccion(PurchaseOrder order) {
  return false;
}

int countFulfillmentItems(PurchaseOrder order) {
  return fulfillmentItems(order).length;
}

DateTime? resolveCommittedDeliveryDate(PurchaseOrder order) {
  DateTime? selected;
  for (final item in fulfillmentItems(order)) {
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
  return fulfillmentItems(order)
      .where((item) => item.deliveryEtaDate != null)
      .length;
}

int countArrivedItems(PurchaseOrder order) {
  return fulfillmentItems(order)
      .where((item) => item.isArrivalRegistered)
      .length;
}

int countPendingArrivalItems(PurchaseOrder order) {
  return fulfillmentItems(order)
      .where((item) => item.deliveryEtaDate != null && !item.isArrivalRegistered)
      .length;
}

bool hasAnyArrivedItems(PurchaseOrder order) {
  return fulfillmentItems(order).any((item) => item.isArrivalRegistered);
}

bool hasAllItemsArrived(PurchaseOrder order) {
  final items = fulfillmentItems(order).toList(growable: false);
  if (items.isEmpty) return false;
  return items.every((item) => item.isArrivalRegistered);
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
  if (!requiresRequesterReceiptConfirmation(order)) return null;
  if (!hasAllItemsArrived(order)) return null;
  final latestArrival = resolveLatestArrivalDate(order);
  if (latestArrival == null) return null;
  return addBusinessDays(latestArrival, 5);
}

bool isOrderAutoReceiptDue(PurchaseOrder order, {DateTime? now}) {
  final dueDate = orderAutoReceiptDueDate(order);
  if (dueDate == null) return false;
  final reference = now ?? DateTime.now();
  return !reference.isBefore(dueDate);
}

String requesterReceiptStatusLabel(PurchaseOrder order) {
  final hasNotPurchasedItems = hasAnyItemsMarkedAsNotPurchased(order);
  final fulfillmentCount = countFulfillmentItems(order);
  if (fulfillmentCount == 0 && hasNotPurchasedItems) {
    return 'Cerrada sin compra';
  }
  if (order.isRequesterReceiptAutoConfirmed) {
    return hasNotPurchasedItems
        ? 'Cerrada parcial sin confirmacion'
        : 'Llegado pero no confirmado';
  }
  if (order.isRequesterReceiptConfirmed) {
    return hasNotPurchasedItems
        ? 'Recibida parcial por solicitante'
        : 'Recibida por solicitante';
  }
  if (order.isArrivalPendingConfirmation) {
    return hasNotPurchasedItems
        ? 'Llegada parcial pendiente de confirmacion'
        : 'Llegado pendiente de confirmacion';
  }
  return order.status.label;
}

int? itemArrivalDeltaDays(PurchaseOrderItem item) {
  if (item.isNotPurchased) return null;
  final eta = _dateOnly(item.deliveryEtaDate);
  final arrived = _dateOnly(item.arrivedAt);
  if (eta == null || arrived == null) return null;
  return arrived.difference(eta).inDays;
}

String itemArrivalComplianceLabel(PurchaseOrderItem item) {
  if (item.isNotPurchased) {
    return 'Item cerrado sin compra';
  }
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
  if (item.isNotPurchased) {
    return 'Item cerrado sin compra';
  }
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
  final items = fulfillmentItems(order).toList(growable: false);
  if (items.isEmpty) return false;
  for (final item in items) {
    if (item.deliveryEtaDate == null) {
      return false;
    }
  }
  return true;
}

bool requiresRequesterReceiptConfirmation(PurchaseOrder order) {
  return countFulfillmentItems(order) > 0;
}

bool areAllItemsResolved(PurchaseOrder order) {
  if (order.items.isEmpty) return false;
  return order.items.every((item) => item.isResolved);
}

PurchaseOrderResolutionState resolveOrderResolutionState(PurchaseOrder order) {
  if (order.items.isEmpty) return PurchaseOrderResolutionState.inProgress;

  final notPurchasedCount = countItemsMarkedAsNotPurchased(order);
  final fulfillmentCount = countFulfillmentItems(order);

  if (fulfillmentCount == 0 && notPurchasedCount == order.items.length) {
    return PurchaseOrderResolutionState.closedWithoutPurchase;
  }

  if (order.isRequesterReceiptConfirmed) {
    return notPurchasedCount > 0
        ? PurchaseOrderResolutionState.closedPartial
        : PurchaseOrderResolutionState.closedComplete;
  }

  if (hasAllItemsArrived(order)) {
    return PurchaseOrderResolutionState.awaitingRequesterConfirmation;
  }

  return PurchaseOrderResolutionState.inProgress;
}

bool isOrderWorkflowFinished(PurchaseOrder order) {
  switch (resolveOrderResolutionState(order)) {
    case PurchaseOrderResolutionState.closedComplete:
    case PurchaseOrderResolutionState.closedPartial:
    case PurchaseOrderResolutionState.closedWithoutPurchase:
      return true;
    case PurchaseOrderResolutionState.inProgress:
    case PurchaseOrderResolutionState.awaitingRequesterConfirmation:
      return false;
  }
}

DateTime? _dateOnly(DateTime? value) {
  if (value == null) return null;
  return DateTime(value.year, value.month, value.day);
}

PurchaseOrderStatus? _statusFromString(String? raw) {
  if (raw == null) return null;
  final normalized = raw.trim();
  const legacyAliases = <String, PurchaseOrderStatus>{
    'pendingCompras': PurchaseOrderStatus.intakeReview,
    'cotizaciones': PurchaseOrderStatus.sourcing,
    'dataComplete': PurchaseOrderStatus.readyForApproval,
    'authorizedGerencia': PurchaseOrderStatus.approvalQueue,
  };
  final legacyMatch = legacyAliases[normalized];
  if (legacyMatch != null) return legacyMatch;
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
