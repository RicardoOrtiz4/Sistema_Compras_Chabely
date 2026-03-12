import 'package:cloud_functions/cloud_functions.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod/legacy.dart';

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
    DateTime? estimatedDate,
    bool? reviewFlagged,
    String? reviewComment,
    bool removeEstimatedDate = false,
    bool clearBudget = false,
    bool clearSupplier = false,
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
    this.notes = '',
    this.isSubmitting = false,
    this.returnCount = 0,
    this.resubmissionDates = const [],
    this.previewCreatedAt,
    this.previewUpdatedAt,
    this.previewAccepted = false,
    this.scheduleChangeConfirmed = false,
    this.baselineUrgency,
    this.baselineRequestedDate,
    this.baselineSignature,
    this.baselineUpdatedAt,
    this.message,
    this.error,
  });

  final PurchaseOrderUrgency urgency;
  final List<OrderItemDraft> items;
  final String? draftId;
  final bool isLoadingDraft;
  final String notes;
  final bool isSubmitting;
  final int returnCount;
  final List<DateTime> resubmissionDates;
  final DateTime? previewCreatedAt;
  final DateTime? previewUpdatedAt;
  final bool previewAccepted;
  final bool scheduleChangeConfirmed;
  final PurchaseOrderUrgency? baselineUrgency;
  final DateTime? baselineRequestedDate;
  final String? baselineSignature;
  final DateTime? baselineUpdatedAt;
  final String? message;
  final Object? error;

  DateTime? get requestedDate {
    return items.isEmpty ? null : items.first.estimatedDate;
  }

  bool get requiresScheduleChange => returnCount > 0;

  bool get hasScheduleChange {
    if (!requiresScheduleChange) return true;
    if (scheduleChangeConfirmed) return true;
    if (baselineUrgency != null && baselineUrgency != urgency) return true;
    return !_isSameRequestedDate(baselineRequestedDate, requestedDate);
  }

  CreateOrderState copyWith({
    PurchaseOrderUrgency? urgency,
    List<OrderItemDraft>? items,
    String? draftId,
    bool? isLoadingDraft,
    String? notes,
    bool? isSubmitting,
    int? returnCount,
    List<DateTime>? resubmissionDates,
    DateTime? previewCreatedAt,
    DateTime? previewUpdatedAt,
    bool? previewAccepted,
    bool? scheduleChangeConfirmed,
    PurchaseOrderUrgency? baselineUrgency,
    DateTime? baselineRequestedDate,
    String? baselineSignature,
    DateTime? baselineUpdatedAt,
    String? message,
    bool clearPreviewUpdatedAt = false,
    bool clearBaselineUrgency = false,
    bool clearBaselineRequestedDate = false,
    bool clearBaselineSignature = false,
    bool clearBaselineUpdatedAt = false,
    bool clearMessage = false,
    Object? error,
    bool clearError = false,
  }) {
    return CreateOrderState(
      urgency: urgency ?? this.urgency,
      items: items ?? this.items,
      draftId: draftId ?? this.draftId,
      isLoadingDraft: isLoadingDraft ?? this.isLoadingDraft,
      notes: notes ?? this.notes,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      returnCount: returnCount ?? this.returnCount,
      resubmissionDates: resubmissionDates ?? this.resubmissionDates,
      previewCreatedAt: previewCreatedAt ?? this.previewCreatedAt,
      previewUpdatedAt: clearPreviewUpdatedAt
          ? null
          : (previewUpdatedAt ?? this.previewUpdatedAt),
      previewAccepted: previewAccepted ?? this.previewAccepted,
      scheduleChangeConfirmed:
          scheduleChangeConfirmed ?? this.scheduleChangeConfirmed,
      baselineUrgency: clearBaselineUrgency
          ? null
          : (baselineUrgency ?? this.baselineUrgency),
      baselineRequestedDate: clearBaselineRequestedDate
          ? null
          : (baselineRequestedDate ?? this.baselineRequestedDate),
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
      urgency: PurchaseOrderUrgency.media,
      items: [OrderItemDraft.empty(1)],
      previewCreatedAt: DateTime.now(),
      previewUpdatedAt: null,
      previewAccepted: false,
      scheduleChangeConfirmed: false,
      baselineUrgency: null,
      baselineRequestedDate: null,
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
    final date = _dateFromUrgency(urgency);
    final updated = [
      for (final item in state.items) item.copyWith(estimatedDate: date),
    ];
    state = _markPreviewEdited(
      state.copyWith(
        urgency: urgency,
        items: updated,
        scheduleChangeConfirmed: false,
      ),
    );
  }

  void setNotes(String notes) {
    if (notes == state.notes) return;
    state = _markPreviewEdited(state.copyWith(notes: notes));
  }

  void syncUrgencyFromDate(DateTime date) {
    final nextUrgency = _urgencyFromDate(date);
    if (nextUrgency == state.urgency) return;
    state = _markPreviewEdited(state.copyWith(urgency: nextUrgency));
  }

  PurchaseOrderUrgency urgencyFromDate(DateTime date) {
    return _urgencyFromDate(date);
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
      final items = order.items.isEmpty
          ? [OrderItemDraft.empty(1)]
          : [
              for (var i = 0; i < order.items.length; i++)
                OrderItemDraft.fromModel(order.items[i]).copyWith(line: i + 1),
            ];
      final baselineSignature = buildCreateOrderSignature(
        urgency: order.urgency,
        notes: order.clientNote ?? '',
        items: items,
      );
      state = state.copyWith(
        isLoadingDraft: false,
        draftId: draftId,
        urgency: order.urgency,
        items: items,
        notes: order.clientNote ?? '',
        returnCount: order.returnCount,
        resubmissionDates: order.resubmissionDates,
        previewCreatedAt: order.createdAt ?? DateTime.now(),
        previewUpdatedAt: order.updatedAt,
        previewAccepted: false,
        scheduleChangeConfirmed: false,
        baselineUrgency: order.urgency,
        baselineRequestedDate: _requestedDateForItems(items),
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
                  reviewFlagged: false,
                  clearReviewComment: true,
                  clearReceivedQuantity: true,
                  clearReceivedComment: true,
                ),
            ];
      state = state.copyWith(
        isLoadingDraft: false,
        draftId: null,
        urgency: order.urgency,
        items: items,
        notes: order.clientNote ?? '',
        returnCount: 0,
        resubmissionDates: const [],
        previewCreatedAt: DateTime.now(),
        previewAccepted: false,
        scheduleChangeConfirmed: false,
        clearPreviewUpdatedAt: true,
        clearBaselineUrgency: true,
        clearBaselineRequestedDate: true,
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
    final base = OrderItemDraft.empty(nextLine);
    final sharedDate = state.items.isEmpty ? null : state.items.first.estimatedDate;
    final next = sharedDate == null ? base : base.copyWith(estimatedDate: sharedDate);
    final updated = [next, ...state.items];
    var nextState = state.copyWith(items: updated);
    final urgency = _urgencyFromItems(updated);
    if (urgency != null) {
      nextState = nextState.copyWith(urgency: urgency);
    }
    state = _markPreviewEdited(nextState);
  }

  void replaceItems(List<OrderItemDraft> items) {
    if (items.isEmpty) {
      state = _markPreviewEdited(
        state.copyWith(items: [OrderItemDraft.empty(1)]),
      );
      return;
    }
    final normalized = [
      for (var i = 0; i < items.length; i++) items[i].copyWith(line: i + 1),
    ];
    var next = state.copyWith(items: normalized);
    final urgency = _urgencyFromItems(normalized);
    if (urgency != null) {
      next = next.copyWith(urgency: urgency);
    }
    state = _markPreviewEdited(next);
  }

  void removeItem(int index) {
    if (state.items.length == 1) return;
    final updated = [...state.items]..removeAt(index);
    final reindexed = [
      for (var i = 0; i < updated.length; i++) updated[i].copyWith(line: i + 1),
    ];
    var next = state.copyWith(items: reindexed);
    final urgency = _urgencyFromItems(reindexed);
    if (urgency != null) {
      next = next.copyWith(urgency: urgency);
    }
    state = _markPreviewEdited(next);
  }

  void updateItem(int index, OrderItemDraft item) {
    final updated = [...state.items];
    final previous = updated[index];
    updated[index] = item;
    var nextItems = updated;
    var next = state.copyWith(items: nextItems);
    if (previous.estimatedDate != item.estimatedDate) {
      if (item.estimatedDate == null) {
        nextItems = [
          for (final entry in updated) entry.copyWith(removeEstimatedDate: true),
        ];
        next = state.copyWith(items: nextItems);
      } else {
        final sharedDate = item.estimatedDate!;
        nextItems = [
          for (final entry in updated) entry.copyWith(estimatedDate: sharedDate),
        ];
        next = state.copyWith(items: nextItems, urgency: _urgencyFromDate(sharedDate));
      }
    }
    state = _markPreviewEdited(next);
  }

  void setMaxDeliveryDate(DateTime date) {
    final updated = [
      for (final item in state.items) item.copyWith(estimatedDate: date),
    ];
    state = _markPreviewEdited(
      state.copyWith(
        items: updated,
        urgency: _urgencyFromDate(date),
        scheduleChangeConfirmed: false,
      ),
    );
  }

  void refreshRequestedDateForCurrentUrgency() {
    final date = _dateFromUrgency(state.urgency);
    final updated = [
      for (final item in state.items) item.copyWith(estimatedDate: date),
    ];
    state = _markPreviewEdited(
      state.copyWith(
        items: updated,
        urgency: state.urgency,
        scheduleChangeConfirmed: true,
      ),
    );
  }

  Future<String?> submit() async {
    final user = await _requireUser();
    if (user == null) return null;
    if (state.returnCount >= _maxCorrections) {
      state = state.copyWith(
        error: 'Máximo de correcciones alcanzado. Crea otra requisición.',
      );
      return null;
    }

    final invalid = state.items.where((item) => !item.isValid()).isNotEmpty;
    if (invalid) {
      state = state.copyWith(error: 'Completa todos los campos de los artículos');
      return null;
    }

    final repo = _ref.read(purchaseOrderRepositoryProvider);
    state = state.copyWith(isSubmitting: true, clearMessage: true, clearError: true);
    try {
      final orderId = await repo.submitOrder(
        draftId: state.draftId,
        requester: user,
        urgency: state.urgency,
        clientNote: state.notes.isEmpty ? null : state.notes,
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

  Future<AppUser?> _requireUser() async {
    final userAsync = _ref.read(currentUserProfileProvider);
    final user = userAsync.value;
    if (user == null) {
      state = state.copyWith(error: 'Perfil no disponible, reintenta.');
    }
    return user;
  }

  PurchaseOrderUrgency? _urgencyFromItems(List<OrderItemDraft> items) {
    final dates = items
        .map((item) => item.estimatedDate)
        .whereType<DateTime>()
        .toList();
    if (dates.isEmpty) return null;
    dates.sort();
    return _urgencyFromDate(dates.first);
  }

  PurchaseOrderUrgency _urgencyFromDate(DateTime date) {
    final now = DateTime.now();
    final normalizedNow = DateTime(now.year, now.month, now.day);
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final days = normalizedDate.difference(normalizedNow).inDays;
    if (days <= 1) {
      return PurchaseOrderUrgency.urgente;
    }
    if (days <= 3) {
      return PurchaseOrderUrgency.alta;
    }
    if (days <= 7) {
      return PurchaseOrderUrgency.media;
    }
    return PurchaseOrderUrgency.baja;
  }

  DateTime? _requestedDateForItems(List<OrderItemDraft> items) {
    return items.isEmpty ? null : items.first.estimatedDate;
  }

  DateTime _dateFromUrgency(PurchaseOrderUrgency urgency) {
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day);
    switch (urgency) {
      case PurchaseOrderUrgency.urgente:
        return base.add(const Duration(days: 1));
      case PurchaseOrderUrgency.alta:
        return base.add(const Duration(days: 3));
      case PurchaseOrderUrgency.media:
        return base.add(const Duration(days: 7));
      case PurchaseOrderUrgency.baja:
        return base.add(const Duration(days: 14));
    }
  }

  CreateOrderState _markPreviewEdited(CreateOrderState next) {
    return next.copyWith(
      previewUpdatedAt: DateTime.now(),
      previewAccepted: false,
    );
  }
}

bool _isSameRequestedDate(DateTime? left, DateTime? right) {
  if (identical(left, right)) return true;
  if (left == null || right == null) return left == right;
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String buildCreateOrderSignature({
  required PurchaseOrderUrgency urgency,
  required String notes,
  required List<OrderItemDraft> items,
}) {
  String normalize(String? value) => (value ?? '').trim();
  String numOrEmpty(num? value) => value?.toString() ?? '';
  String dateOrEmpty(DateTime? value) =>
      value?.millisecondsSinceEpoch.toString() ?? '';

  final buffer = StringBuffer()
    ..write('urg:')
    ..write(urgency.name)
    ..write(';notes:')
    ..write(normalize(notes))
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

