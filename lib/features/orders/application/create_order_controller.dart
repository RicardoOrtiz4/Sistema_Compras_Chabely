import 'package:riverpod/riverpod.dart';
import 'package:riverpod/legacy.dart';

import 'package:sistema_compras/core/constants.dart';
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

  OrderItemDraft copyWith({
    int? line,
    int? pieces,
    String? partNumber,
    String? description,
    num? quantity,
    String? unit,
    String? customer,
    DateTime? estimatedDate,
    bool removeEstimatedDate = false,
  }) {
    return OrderItemDraft(
      line: line ?? this.line,
      pieces: pieces ?? this.pieces,
      partNumber: partNumber ?? this.partNumber,
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      customer: customer ?? this.customer,
      estimatedDate: removeEstimatedDate ? null : (estimatedDate ?? this.estimatedDate),
    );
  }

  PurchaseOrderItem toModel() {
    return PurchaseOrderItem(
      line: line,
      pieces: pieces,
      partNumber: partNumber,
      description: description,
      quantity: quantity,
      unit: unit,
      customer: customer,
      estimatedDate: estimatedDate,
    );
  }

  bool isValid() {
    return pieces > 0 && quantity > 0 && partNumber.isNotEmpty && description.isNotEmpty && unit.isNotEmpty;
  }

  static OrderItemDraft empty(int line) {
    return OrderItemDraft(
      line: line,
      pieces: 1,
      partNumber: '',
      description: '',
      quantity: 1,
      unit: 'PZA',
    );
  }
}

class CreateOrderState {
  const CreateOrderState({
    required this.urgency,
    required this.items,
    this.draftId,
    this.isSaving = false,
    this.isSubmitting = false,
    this.message,
    this.error,
  });

  final PurchaseOrderUrgency urgency;
  final List<OrderItemDraft> items;
  final String? draftId;
  final bool isSaving;
  final bool isSubmitting;
  final String? message;
  final String? error;

  CreateOrderState copyWith({
    PurchaseOrderUrgency? urgency,
    List<OrderItemDraft>? items,
    String? draftId,
    bool? isSaving,
    bool? isSubmitting,
    String? message,
    bool clearMessage = false,
    String? error,
    bool clearError = false,
  }) {
    return CreateOrderState(
      urgency: urgency ?? this.urgency,
      items: items ?? this.items,
      draftId: draftId ?? this.draftId,
      isSaving: isSaving ?? this.isSaving,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      message: clearMessage ? null : (message ?? this.message),
      error: clearError ? null : (error ?? this.error),
    );
  }

  factory CreateOrderState.initial() {
    return CreateOrderState(
      urgency: PurchaseOrderUrgency.media,
      items: [OrderItemDraft.empty(1)],
    );
  }
}

class CreateOrderController extends StateNotifier<CreateOrderState> {
  CreateOrderController(this._ref) : super(CreateOrderState.initial());

  final Ref _ref;

  void setUrgency(PurchaseOrderUrgency urgency) {
    state = state.copyWith(urgency: urgency);
  }

  void addItem() {
    final items = [...state.items, OrderItemDraft.empty(state.items.length + 1)];
    state = state.copyWith(items: items);
  }

  void removeItem(int index) {
    if (state.items.length == 1) return;
    final updated = [...state.items]..removeAt(index);
    state = state.copyWith(items: updated);
  }

  void updateItem(int index, OrderItemDraft item) {
    final updated = [...state.items];
    updated[index] = item;
    state = state.copyWith(items: updated);
  }

  Future<void> saveDraft() async {
    final user = await _requireUser();
    if (user == null) return;
    final repo = _ref.read(purchaseOrderRepositoryProvider);
    state = state.copyWith(isSaving: true, clearMessage: true, clearError: true);
    try {
      final items = state.items.map((item) => item.toModel()).toList();
      final draftId = await repo.saveDraft(
        draftId: state.draftId,
        requester: user,
        urgency: state.urgency,
        items: items,
        enableEditing: true,
      );
      state = state.copyWith(
        isSaving: false,
        draftId: draftId,
        message: 'Borrador guardado',
      );
    } catch (error) {
      state = state.copyWith(isSaving: false, error: error.toString());
    }
  }

  Future<void> submit() async {
    final user = await _requireUser();
    if (user == null) return;

    final invalid = state.items.where((item) => !item.isValid()).isNotEmpty;
    if (invalid) {
      state = state.copyWith(error: 'Completa todos los campos de los items');
      return;
    }

    final repo = _ref.read(purchaseOrderRepositoryProvider);
    state = state.copyWith(isSubmitting: true, clearMessage: true, clearError: true);
    try {
      await repo.submitOrder(
        draftId: state.draftId,
        requester: user,
        urgency: state.urgency,
        items: state.items.map((item) => item.toModel()).toList(),
      );
      state = CreateOrderState.initial().copyWith(
        message: 'Orden enviada a Compras',
      );
    } catch (error) {
      state = state.copyWith(isSubmitting: false, error: error.toString());
    }
  }

  Future<AppUser?> _requireUser() async {
    final userAsync = _ref.read(currentUserProfileProvider);
    final user = userAsync.value;
    if (user == null) {
      state = state.copyWith(error: 'Perfil no disponible, reintenta.');
    }
    return user;
  }
}

final createOrderControllerProvider =
    StateNotifierProvider<CreateOrderController, CreateOrderState>((ref) {
  return CreateOrderController(ref);
});






