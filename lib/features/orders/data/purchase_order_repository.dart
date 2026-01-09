import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';

class PurchaseOrderRepository {
  PurchaseOrderRepository(this._firestore, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _ordersCollection =>
      _firestore.collection('purchaseOrders');

  Stream<List<PurchaseOrder>> watchOrdersForUser(String uid) {
    return _ordersCollection
        .where('requesterId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => PurchaseOrder.fromMap(doc.id, doc.data()))
            .toList());
  }

  Stream<List<PurchaseOrderEvent>> watchEvents(String orderId) {
    return _ordersCollection
        .doc(orderId)
        .collection('events')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => PurchaseOrderEvent.fromMap(doc.id, doc.data()))
            .toList());
  }

  Future<String> saveDraft({
    String? draftId,
    required AppUser requester,
    required PurchaseOrderUrgency urgency,
    required List<PurchaseOrderItem> items,
    required bool enableEditing,
  }) async {
    final data = {
      'requesterId': requester.id,
      'requesterName': requester.name,
      'areaId': requester.areaId,
      'areaName': requester.areaDisplay,
      'urgency': urgency.name,
      'status': PurchaseOrderStatus.draft.name,
      'items': items.map((item) => item.toMap()).toList(),
      'isDraft': true,
      'editable': enableEditing,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (draftId != null) {
      await _ordersCollection.doc(draftId).update(data);
      return draftId;
    }

    final docRef = await _ordersCollection.add({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<void> submitOrder({
    String? draftId,
    required AppUser requester,
    required PurchaseOrderUrgency urgency,
    required List<PurchaseOrderItem> items,
    String? clientNote,
  }) async {
    final payload = {
      'requesterId': requester.id,
      'requesterName': requester.name,
      'areaId': requester.areaId,
      'areaName': requester.areaDisplay,
      'urgency': urgency.name,
      'clientNote': clientNote,
      'items': items.map((item) => item.toMap()).toList(),
    };

    final callable = _functions.httpsCallable('assignFolioAndCreateOrder');
    await callable.call({
      'draftId': draftId,
      'order': payload,
    });
  }

  Future<void> requestEdit(String orderId, String comment) async {
    final callable = _functions.httpsCallable('returnToUser');
    await callable.call({
      'orderId': orderId,
      'comment': comment,
    });
  }
}

final purchaseOrderRepositoryProvider = Provider<PurchaseOrderRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final functions = ref.watch(firebaseFunctionsProvider);
  return PurchaseOrderRepository(firestore, functions);
});



