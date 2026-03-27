import 'package:cloud_functions/cloud_functions.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod/legacy.dart';

import 'package:sistema_compras/core/business_calendar.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';

class OrderItemDraft {
  const OrderItemDraft({
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
  final String? internalOrder;
  final String? quoteId;
  final PurchaseOrderItemQuoteStatus quoteStatus;
  final DateTime? estimatedDate;
  final bool reviewFlagged;
  final String? reviewComment;
  final num? receivedQuantity;
  final String? receivedComment;

  OrderItemDraft copyWith({
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
    bool? reviewFlagged,
    String? reviewComment,
    bool removeEstimatedDate = false,
    bool clearBudget = false,
    bool clearSupplier = false,
    bool clearInternalOrder = false,
    bool clearReviewComment = false,
    bool clearReceivedQuantity = false,
    bool clearReceivedComment = false,
    num? receivedQuantity,
    String? receivedComment,
  }) {
    final nextPieces = pieces ?? this.pieces;
    final nextQuantity = quantity ?? nextPieces;
    return OrderItemDraft(
      line: line ?? this.line,
      pieces: nextPieces,
      partNumber: partNumber ?? this.partNumber,
      description: description ?? this.description,
      quantity: nextQuantity,
      unit: unit ?? this.unit,
      customer: customer ?? this.customer,
      supplier: clearSupplier ? null : (supplier ?? this.supplier),
      budget: clearBudget ? null : (budget ?? this.budget),
      internalOrder: clearInternalOrder ? null : (internalOrder ?? this.internalOrder),
      quoteId: quoteId ?? this.quoteId,
      quoteStatus: quoteStatus ?? this.quoteStatus,
      estimatedDate: removeEstimatedDate ? null : (estimatedDate ?? this.estimatedDate),
      reviewFlagged: reviewFlagged ?? this.reviewFlagged,
      reviewComment: clearReviewComment ? null : (reviewComment ?? this.reviewComment),
      receivedQuantity: clearReceivedQuantity ? null : (receivedQuantity ?? this.receivedQuantity),
      receivedComment: clearReceivedComment ? null : (receivedComment ?? this.receivedComment),
    );
  }

  PurchaseOrderItem toModel() {
    return PurchaseOrderItem(
      line: line,
      pieces: pieces,
      partNumber: partNumber,
      description: description,
      quantity: pieces,
      unit: unit,
      customer: customer,
      supplier: supplier,
      budget: budget,
      internalOrder: internalOrder,
      quoteId: quoteId,
      quoteStatus: quoteStatus,
      estimatedDate: estimatedDate,
      reviewFlagged: reviewFlagged,
      reviewComment: reviewComment,
      receivedQuantity: receivedQuantity,
      receivedComment: receivedComment,
    );
  }

  bool isValid() {
    return pieces > 0 && description.isNotEmpty && unit.isNotEmpty;
  }

  static OrderItemDraft empty(int line) {
    return OrderItemDraft(
      line: line,
      pieces: 1,
      partNumber: '',
      description: '',
      quantity: 1,
      unit: 'PZA',
      reviewFlagged: false,
    );
  }

  static OrderItemDraft fromModel(PurchaseOrderItem item) {
    return OrderItemDraft(
      line: item.line,
      pieces: item.pieces,
      partNumber: item.partNumber,
      description: item.description,
      quantity: item.quantity,
      unit: item.unit,
      customer: item.customer,
      supplier: item.supplier,
      budget: item.budget,
      internalOrder: item.internalOrder,
      quoteId: item.quoteId,
      quoteStatus: item.quoteStatus,
      estimatedDate: item.estimatedDate,
      reviewFlagged: item.reviewFlagged,
      reviewComment: item.reviewComment,
      receivedQuantity: item.receivedQuantity,
      receivedComment: item.receivedComment,
    );
  }
}

class CreateOrderState {
  const CreateOrderState({
    required this.urgency,
    required this.items,
    this.draftId,
    this.isLoadingDraft = false,
    this.requestedDeliveryDate,
    this.notes = '',
    this.urgentJustification = '',
    this.isSubmitting = false,
    this.returnCount = 0,
    this.resubmissionDates = const [],
    this.previewCreatedAt,
    this.previewUpdatedAt,
    this.previewAccepted = false,
    this.baselineSignature,
    this.baselineUpdatedAt,
    this.message,
    this.error,
  });

  final PurchaseOrderUrgency urgency;
  final List<OrderItemDraft> items;
  final String? draftId;
  final bool isLoadingDraft;
  final DateTime? requestedDeliveryDate;
  final String notes;
  final String urgentJustification;
  final bool isSubmitting;
  final int returnCount;
  final List<DateTime> resubmissionDates;
  final DateTime? previewCreatedAt;
  final DateTime? previewUpdatedAt;
  final bool previewAccepted;
  final String? baselineSignature;
  final DateTime? baselineUpdatedAt;
  final String? message;
  final Object? error;

  bool get requiresScheduleChange => false;
  bool get hasScheduleChange => true;

  CreateOrderState copyWith({
    PurchaseOrderUrgency? urgency,
    List<OrderItemDraft>? items,
    String? draftId,
    bool? isLoadingDraft,
    DateTime? requestedDeliveryDate,
    String? notes,
    String? urgentJustification,
    bool? isSubmitting,
    int? returnCount,
    List<DateTime>? resubmissionDates,
    DateTime? previewCreatedAt,
    DateTime? previewUpdatedAt,
    bool? previewAccepted,
    String? baselineSignature,
    DateTime? baselineUpdatedAt,
    String? message,
    bool clearPreviewUpdatedAt = false,
    bool clearBaselineSignature = false,
    bool clearBaselineUpdatedAt = false,
    bool clearRequestedDeliveryDate = false,
    bool clearMessage = false,
    Object? error,
    bool clearError = false,
  }) {
    return CreateOrderState(
      urgency: urgency ?? this.urgency,
      items: items ?? this.items,
      draftId: draftId ?? this.draftId,
      isLoadingDraft: isLoadingDraft ?? this.isLoadingDraft,
      requestedDeliveryDate: clearRequestedDeliveryDate
          ? null
          : (requestedDeliveryDate ?? this.requestedDeliveryDate),
      notes: notes ?? this.notes,
      urgentJustification: urgentJustification ?? this.urgentJustification,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      returnCount: returnCount ?? this.returnCount,
      resubmissionDates: resubmissionDates ?? this.resubmissionDates,
      previewCreatedAt: previewCreatedAt ?? this.previewCreatedAt,
      previewUpdatedAt: clearPreviewUpdatedAt
          ? null
          : (previewUpdatedAt ?? this.previewUpdatedAt),
      previewAccepted: previewAccepted ?? this.previewAccepted,
      baselineSignature: clearBaselineSignature
          ? null
          : (baselineSignature ?? this.baselineSignature),
      baselineUpdatedAt: clearBaselineUpdatedAt
          ? null
          : (baselineUpdatedAt ?? this.baselineUpdatedAt),
      message: clearMessage ? null : (message ?? this.message),
      error: clearError ? null : (error ?? this.error),
    );
  }

  factory CreateOrderState.initial() {
    return CreateOrderState(
      urgency: PurchaseOrderUrgency.normal,
      items: [OrderItemDraft.empty(1)],
      previewCreatedAt: DateTime.now(),
      previewUpdatedAt: null,
      previewAccepted: false,
      baselineSignature: null,
      baselineUpdatedAt: null,
    );
  }
}

class CreateOrderController extends StateNotifier<CreateOrderState> {
  CreateOrderController(this._ref) : super(CreateOrderState.initial());

  final Ref _ref;

  void setUrgency(PurchaseOrderUrgency urgency) {
    if (urgency == state.urgency) return;
    final requestedDeliveryDate = _requestedDeliveryDateForUrgency(
      state.requestedDeliveryDate,
      urgency,
    );
    state = _markPreviewEdited(
      state.copyWith(
        urgency: urgency,
        requestedDeliveryDate: requestedDeliveryDate,
        clearRequestedDeliveryDate: requestedDeliveryDate == null,
        clearError: true,
        urgentJustification:
            urgency == PurchaseOrderUrgency.urgente ? state.urgentJustification : '',
      ),
    );
  }

  void setNotes(String notes) {
    if (notes == state.notes) return;
    state = _markPreviewEdited(state.copyWith(notes: notes));
  }

  void setRequestedDeliveryDate(DateTime? requestedDeliveryDate) {
    final normalized = requestedDeliveryDate == null
        ? null
        : DateTime(
            requestedDeliveryDate.year,
            requestedDeliveryDate.month,
           requestedDeliveryDate.day,
          );
    if (normalized != null &&
        normalizeCalendarDate(normalized)
            .isBefore(normalizeCalendarDate(DateTime.now()))) {
      state = state.copyWith(
        error: 'La fecha maxima solicitada no puede ser anterior a hoy.',
      );
      return;
    }
    if (normalized != null &&
        state.urgency != PurchaseOrderUrgency.urgente &&
        !isBusinessDay(normalized)) {
      state = state.copyWith(
        error: 'La fecha maxima solicitada debe ser un dia habil.',
      );
      return;
    }
    if (normalized != null &&
        state.urgency == PurchaseOrderUrgency.urgente &&
        !isAllowedUrgentRequestedDeliveryDate(normalized)) {
      state = state.copyWith(
        error: _urgentRequestedDeliveryDateErrorMessage(),
      );
      return;
    }
    final current = state.requestedDeliveryDate;
    final sameDate = current != null &&
        normalized != null &&
        current.year == normalized.year &&
        current.month == normalized.month &&
        current.day == normalized.day;
    if (current == null && normalized == null) return;
    if (sameDate) return;
    state = _markPreviewEdited(
      state.copyWith(
        requestedDeliveryDate: normalized,
        clearRequestedDeliveryDate: normalized == null,
        clearError: true,
      ),
    );
  }

  void setUrgentJustification(String justification) {
    if (justification == state.urgentJustification) return;
    state = _markPreviewEdited(
      state.copyWith(urgentJustification: justification),
    );
  }

  Future<void> loadDraft(String draftId) async {
    state = state.copyWith(isLoadingDraft: true, clearMessage: true, clearError: true);
    try {
      final repo = _ref.read(purchaseOrderRepositoryProvider);
      final order = await repo.fetchOrderById(draftId);
      if (order == null) {
        state = state.copyWith(
          isLoadingDraft: false,
          error: 'Orden no encontrada.',
        );
        return;
      }
      final isRejectedDraft = order.status == PurchaseOrderStatus.draft &&
          ((order.lastReturnReason?.trim().isNotEmpty ?? false) ||
              order.returnCount > 0);
      if (isRejectedDraft) {
        final items = order.items.isEmpty
            ? [OrderItemDraft.empty(1)]
            : [
                for (var i = 0; i < order.items.length; i++)
                  OrderItemDraft.fromModel(order.items[i]).copyWith(
                    line: i + 1,
                    removeEstimatedDate: true,
                    reviewFlagged: false,
                    clearReviewComment: true,
                    clearReceivedQuantity: true,
                    clearReceivedComment: true,
                  ),
              ];
        final requestedDeliveryDate = _requestedDeliveryDateForUrgency(
          resolveRequestedDeliveryDate(order),
          order.urgency,
        );
        state = state.copyWith(
          isLoadingDraft: false,
          draftId: null,
          urgency: order.urgency,
          items: items,
          requestedDeliveryDate: requestedDeliveryDate,
          clearRequestedDeliveryDate: requestedDeliveryDate == null,
          notes: order.clientNote ?? '',
          urgentJustification: order.urgentJustification ?? '',
          returnCount: 0,
          resubmissionDates: const [],
          previewCreatedAt: DateTime.now(),
          previewAccepted: false,
          clearPreviewUpdatedAt: true,
          clearBaselineSignature: true,
          clearBaselineUpdatedAt: true,
          message:
              'La orden fue rechazada. Se cargo como copia para crear una nueva requisicion.',
        );
        return;
      }
      final items = order.items.isEmpty
          ? [OrderItemDraft.empty(1)]
          : [
              for (var i = 0; i < order.items.length; i++)
                OrderItemDraft.fromModel(order.items[i]).copyWith(
                  line: i + 1,
                  removeEstimatedDate: true,
                ),
            ];
      final requestedDeliveryDate = _requestedDeliveryDateForUrgency(
        resolveRequestedDeliveryDate(order),
        order.urgency,
      );
      final baselineSignature = buildCreateOrderSignature(
        urgency: order.urgency,
        requestedDeliveryDate: requestedDeliveryDate,
        notes: order.clientNote ?? '',
        urgentJustification: order.urgentJustification ?? '',
        items: items,
      );
      state = state.copyWith(
        isLoadingDraft: false,
        draftId: draftId,
        urgency: order.urgency,
        items: items,
        requestedDeliveryDate: requestedDeliveryDate,
        clearRequestedDeliveryDate: requestedDeliveryDate == null,
        notes: order.clientNote ?? '',
        urgentJustification: order.urgentJustification ?? '',
        returnCount: order.returnCount,
        resubmissionDates: order.resubmissionDates,
        previewCreatedAt: order.createdAt ?? DateTime.now(),
        previewUpdatedAt: order.updatedAt,
        previewAccepted: false,
        clearPreviewUpdatedAt: order.updatedAt == null,
        baselineSignature: baselineSignature,
        baselineUpdatedAt: order.updatedAt,
        clearBaselineUpdatedAt: order.updatedAt == null,
      );
    } catch (error, stack) {
      logError(error, stack, context: 'CreateOrderController.loadDraft');
      state = state.copyWith(
        isLoadingDraft: false,
        error: AppError(
          'No se pudo cargar la orden. Reintenta.',
          cause: error,
          stack: stack,
        ),
      );
    }
  }

  Future<void> loadFromOrder(String orderId) async {
    state = state.copyWith(isLoadingDraft: true, clearMessage: true, clearError: true);
    try {
      final repo = _ref.read(purchaseOrderRepositoryProvider);
      final order = await repo.fetchOrderById(orderId);
      if (order == null) {
        state = state.copyWith(
          isLoadingDraft: false,
          error: 'Orden no encontrada.',
        );
        return;
      }
      final items = order.items.isEmpty
          ? [OrderItemDraft.empty(1)]
          : [
              for (var i = 0; i < order.items.length; i++)
                OrderItemDraft.fromModel(order.items[i]).copyWith(
                  line: i + 1,
                  removeEstimatedDate: true,
                  reviewFlagged: false,
                  clearReviewComment: true,
                  clearReceivedQuantity: true,
                  clearReceivedComment: true,
                ),
            ];
      final requestedDeliveryDate = _requestedDeliveryDateForUrgency(
        resolveRequestedDeliveryDate(order),
        order.urgency,
      );
      state = state.copyWith(
        isLoadingDraft: false,
        draftId: null,
        urgency: order.urgency,
        items: items,
        requestedDeliveryDate: requestedDeliveryDate,
        clearRequestedDeliveryDate: requestedDeliveryDate == null,
        notes: order.clientNote ?? '',
        urgentJustification: order.urgentJustification ?? '',
        returnCount: 0,
        resubmissionDates: const [],
        previewCreatedAt: DateTime.now(),
        previewAccepted: false,
        clearPreviewUpdatedAt: true,
        clearBaselineSignature: true,
        clearBaselineUpdatedAt: true,
      );
    } catch (error, stack) {
      logError(error, stack, context: 'CreateOrderController.loadFromOrder');
      state = state.copyWith(
        isLoadingDraft: false,
        error: AppError(
          'No se pudo cargar la orden. Reintenta.',
          cause: error,
          stack: stack,
        ),
      );
    }
  }

  void addItem() {
    final nextLine = state.items.isEmpty
        ? 1
        : state.items.map((item) => item.line).reduce((a, b) => a > b ? a : b) + 1;
    final updated = [OrderItemDraft.empty(nextLine), ...state.items];
    state = _markPreviewEdited(state.copyWith(items: updated));
  }

  void replaceItems(List<OrderItemDraft> items) {
    if (items.isEmpty) {
      state = _markPreviewEdited(
        state.copyWith(items: [OrderItemDraft.empty(1)]),
      );
      return;
    }
    final normalized = [
      for (var i = 0; i < items.length; i++)
        items[i].copyWith(line: i + 1, removeEstimatedDate: true),
    ];
    state = _markPreviewEdited(
      state.copyWith(
        items: normalized,
        requestedDeliveryDate:
            _requestedDeliveryDateFromItems(items) ?? state.requestedDeliveryDate,
      ),
    );
  }

  void removeItem(int index) {
    if (state.items.length == 1) return;
    final updated = [...state.items]..removeAt(index);
    final reindexed = [
      for (var i = 0; i < updated.length; i++) updated[i].copyWith(line: i + 1),
    ];
    state = _markPreviewEdited(state.copyWith(items: reindexed));
  }

  void updateItem(int index, OrderItemDraft item) {
    final updated = [...state.items];
    updated[index] = item.copyWith(removeEstimatedDate: true);
    state = _markPreviewEdited(state.copyWith(items: updated));
  }

  Future<String?> submit() async {
    final user = await _requireUser();
    if (user == null) return null;
    if (state.returnCount >= _maxCorrections) {
      state = state.copyWith(
        error: 'Esta orden ya no puede seguir corrigiendose. Crea una nueva requisicion.',
      );
      return null;
    }

    final invalid = state.items.where((item) => !item.isValid()).isNotEmpty;
    if (invalid) {
      state = state.copyWith(error: 'Completa todos los campos de los artículos');
      return null;
    }

    if (state.urgency == PurchaseOrderUrgency.urgente &&
        state.urgentJustification.trim().isEmpty) {
      state = state.copyWith(
        error: 'Debes justificar por que la requisicion esta marcada como urgente.',
      );
      return null;
    }

    final requestedDeliveryDateError = this.requestedDeliveryDateError();
    if (requestedDeliveryDateError != null) {
      state = state.copyWith(error: requestedDeliveryDateError);
      return null;
    }

    final repo = _ref.read(purchaseOrderRepositoryProvider);
    state = state.copyWith(isSubmitting: true, clearMessage: true, clearError: true);
    try {
      final orderId = await repo.submitOrder(
        draftId: state.draftId,
        requester: user,
        urgency: state.urgency,
        requestedDeliveryDate: state.requestedDeliveryDate,
        clientNote: state.notes.isEmpty ? null : state.notes,
        urgentJustification: state.urgentJustification.trim().isEmpty
            ? null
            : state.urgentJustification.trim(),
        items: state.items
            .map((item) => item
                .toModel()
                .copyWith(reviewFlagged: false, reviewComment: null, clearReviewComment: true))
            .toList(),
      );
      state = CreateOrderState.initial().copyWith(
        message: 'Orden enviada y en proceso de confirmarción',
      );
      return orderId;
    } catch (error, stack) {
      logError(error, stack, context: 'CreateOrderController.submit');
      state = state.copyWith(
        isSubmitting: false,
        error: AppError(
          _submitErrorMessage(error),
          cause: error,
          stack: stack,
        ),
      );
      return null;
    }
  }

  void reset() {
    state = CreateOrderState.initial();
  }

  void acceptPreview() {
    state = state.copyWith(previewAccepted: true);
  }

  bool get requiresUrgentJustification =>
      state.urgency == PurchaseOrderUrgency.urgente;

  bool get hasValidUrgentJustification =>
      !requiresUrgentJustification ||
      state.urgentJustification.trim().isNotEmpty;

  String? urgentJustificationError() {
    if (hasValidUrgentJustification) return null;
    return 'Explica por que esta requisicion es urgente.';
  }

  String? requestedDeliveryDateError() {
    final requestedDeliveryDate = state.requestedDeliveryDate;
    if (requestedDeliveryDate == null) {
      return 'La fecha maxima solicitada es obligatoria.';
    }
    if (normalizeCalendarDate(requestedDeliveryDate)
        .isBefore(normalizeCalendarDate(DateTime.now()))) {
      return 'La fecha maxima solicitada no puede ser anterior a hoy.';
    }
    if (state.urgency != PurchaseOrderUrgency.urgente) {
      if (!isBusinessDay(requestedDeliveryDate)) {
        return 'La fecha maxima solicitada debe ser un dia habil.';
      }
      return null;
    }
    if (isAllowedUrgentRequestedDeliveryDate(requestedDeliveryDate)) return null;
    return _urgentRequestedDeliveryDateErrorMessage();
  }

  Future<AppUser?> _requireUser() async {
    final userAsync = _ref.read(currentUserProfileProvider);
    final user = userAsync.value;
    if (user == null) {
      state = state.copyWith(error: 'Perfil no disponible, reintenta.');
    }
    return user;
  }

  CreateOrderState _markPreviewEdited(CreateOrderState next) {
    return next.copyWith(
      previewUpdatedAt: DateTime.now(),
      previewAccepted: false,
    );
  }
}

DateTime? _requestedDeliveryDateForUrgency(
  DateTime? requestedDeliveryDate,
  PurchaseOrderUrgency urgency,
) {
  if (requestedDeliveryDate == null) return null;
  final normalized = normalizeCalendarDate(requestedDeliveryDate);
  if (urgency != PurchaseOrderUrgency.urgente) {
    return normalized;
  }
  if (!isAllowedUrgentRequestedDeliveryDate(normalized)) {
    return null;
  }
  return normalized;
}

String _urgentRequestedDeliveryDateErrorMessage() {
  return 'Para urgencia, la fecha requerida debe estar dentro de los próximos '
      '$urgentRequestedDeliveryBusinessDays días hábiles después de hoy.';
}

String buildCreateOrderSignature({
  required PurchaseOrderUrgency urgency,
  required DateTime? requestedDeliveryDate,
  required String notes,
  required String urgentJustification,
  required List<OrderItemDraft> items,
}) {
  String normalize(String? value) => (value ?? '').trim();
  String numOrEmpty(num? value) => value?.toString() ?? '';
  String dateOrEmpty(DateTime? value) =>
      value?.millisecondsSinceEpoch.toString() ?? '';

  final buffer = StringBuffer()
    ..write('urg:')
    ..write(urgency.name)
    ..write(';requestedDeliveryDate:')
    ..write(dateOrEmpty(requestedDeliveryDate))
    ..write(';notes:')
    ..write(normalize(notes))
    ..write(';urgentJustification:')
    ..write(normalize(urgentJustification))
    ..write(';items:')
    ..write(items.length)
    ..write(';');

  for (final item in items) {
    buffer
      ..write(item.line)
      ..write('|')
      ..write(item.pieces)
      ..write('|')
      ..write(normalize(item.partNumber))
      ..write('|')
      ..write(normalize(item.description))
      ..write('|')
      ..write(numOrEmpty(item.quantity))
      ..write('|')
      ..write(normalize(item.unit))
      ..write('|')
      ..write(normalize(item.customer))
      ..write('|')
      ..write(normalize(item.supplier))
      ..write('|')
      ..write(numOrEmpty(item.budget))
      ..write('|')
      ..write(dateOrEmpty(item.estimatedDate))
      ..write('|')
      ..write(item.reviewFlagged ? '1' : '0')
      ..write('|')
      ..write(normalize(item.reviewComment))
      ..write('|')
      ..write(numOrEmpty(item.receivedQuantity))
      ..write('|')
      ..write(normalize(item.receivedComment))
      ..write(';');
  }

  return buffer.toString();
}

DateTime? _requestedDeliveryDateFromItems(List<OrderItemDraft> items) {
  DateTime? selected;
  for (final item in items) {
    final date = item.estimatedDate;
    if (date == null) continue;
    final normalized = DateTime(date.year, date.month, date.day);
    if (selected == null || normalized.isBefore(selected)) {
      selected = normalized;
    }
  }
  return selected;
}

String _submitErrorMessage(Object error) {
  if (error is FirebaseFunctionsException) {
    final message = error.message;
    if (message != null && message.isNotEmpty) {
      return message;
    }
  }
  if (error is StateError) {
    return error.message;
  }
  if (error is String && error.isNotEmpty) {
    return error;
  }
  return 'No se pudo enviar la requisición. Reintenta.';
}

final createOrderControllerProvider =
    StateNotifierProvider<CreateOrderController, CreateOrderState>((ref) {
  return CreateOrderController(ref);
});

const _maxCorrections = 3;

