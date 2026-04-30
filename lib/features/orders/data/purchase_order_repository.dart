import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/firebase_database_compat.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/domain/order_dashboard_counts.dart';
import 'package:sistema_compras/features/orders/domain/order_folio.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';

class PurchaseOrderRepository {
  PurchaseOrderRepository(this._database, this._storage, this._company);

  final AppDatabase _database;
  final FirebaseStorage _storage;
  final Company _company;

  AppDatabaseRef get _ordersRef => _database.ref('purchaseOrders');
  AppDatabaseRef get _orderCountersRef => _database.ref('purchaseOrderCounters');


  PurchaseOrder? _parseOrderEntry(String id, Object? raw) {
    if (raw is! Map) return null;
    return PurchaseOrder.fromMap(
      id,
      Map<String, dynamic>.from(raw),
    );
  }

  List<PurchaseOrder> _parseOrdersMap(Object? value) {
    if (value is! Map) return const <PurchaseOrder>[];

    final orders = <PurchaseOrder>[];
    value.forEach((key, raw) {
      final order = _parseOrderEntry(key.toString(), raw);
      if (order != null) {
        orders.add(order);
      }
    });

    orders.sort((a, b) {
      final aTime = (a.updatedAt ?? a.createdAt)?.millisecondsSinceEpoch ?? 0;
      final bTime = (b.updatedAt ?? b.createdAt)?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });

    return orders;
  }

  Stream<List<PurchaseOrder>> watchOrdersForUser(String uid, {int? limit}) {
    AppDatabaseQuery query = _ordersRef.orderByChild('requesterId').equalTo(uid);
    if (limit != null && limit > 0) {
      query = query.limitToLast(limit);
    }
    return query.onValue
        .map((event) => _parseOrdersMap(event.snapshot.value))
        .distinct(_sameOrderList);
  }

  Stream<List<PurchaseOrder>> watchAllOrders({int? limit}) {
    AppDatabaseQuery query = _ordersRef;
    if (limit != null && limit > 0) {
      query = query.limitToLast(limit);
    }
    return query.onValue
        .map((event) => _parseOrdersMap(event.snapshot.value))
        .distinct(_sameOrderList);
  }

  Stream<List<PurchaseOrderEvent>> watchEvents(String orderId) {
    return _ordersRef.child('$orderId/events').onValue
        .map((event) {
          final value = event.snapshot.value;
          if (value is! Map) return <PurchaseOrderEvent>[];

          final events = <PurchaseOrderEvent>[];
          value.forEach((key, raw) {
            if (raw is Map) {
              events.add(
                PurchaseOrderEvent.fromMap(
                  key.toString(),
                  Map<String, dynamic>.from(raw),
                ),
              );
            }
          });

          // Mas antiguos primero (historial)
          events.sort((a, b) {
            final aTime = a.timestamp?.millisecondsSinceEpoch ?? 0;
            final bTime = b.timestamp?.millisecondsSinceEpoch ?? 0;
            return aTime.compareTo(bTime);
          });

          return events;
        })
        .distinct(_sameEventList);
  }

  Stream<List<PurchaseOrder>> watchOrdersByStatus(
    PurchaseOrderStatus status, {
    int? limit,
  }) {
    AppDatabaseQuery query = _ordersRef.orderByChild('status').equalTo(status.name);
    if (limit != null && limit > 0) {
      query = query.limitToLast(limit);
    }
    return query.onValue
        .map((event) => _parseOrdersMap(event.snapshot.value))
        .distinct(_sameOrderList);
  }

  Stream<PurchaseOrder?> watchOrderById(String orderId) {
    return _ordersRef.child(orderId).onValue
        .map((event) => _parseOrderEntry(orderId, event.snapshot.value))
        .distinct(_sameOrder);
  }

  Stream<OrderDashboardCounts?> watchDashboardCounts({required String? userId}) {
    return _orderCountersRef.onValue
        .map((event) {
          final value = event.snapshot.value;
          if (value is! Map) return null;
          return OrderDashboardCounts.fromMap(
            Map<String, dynamic>.from(value),
            userId: userId,
          );
        })
        .distinct(_sameDashboardCounts);
  }

  Future<PurchaseOrder?> fetchOrderById(String orderId) async {
    final snapshot = await _ordersRef.child(orderId).get();
    if (!snapshot.exists) return null;
    return _parseOrderEntry(orderId, snapshot.value);
  }

  Future<List<PurchaseOrder>> fetchOrdersByIds(Iterable<String> orderIds) async {
    final ordersById = await _fetchOrdersByIds(_database, orderIds);
    final orders = ordersById.values.toList(growable: false)
      ..sort((a, b) => a.id.compareTo(b.id));
    return orders;
  }

  Future<List<PurchaseOrder>> fetchAllOrders({int? limit}) async {
    AppDatabaseQuery query = _ordersRef;
    if (limit != null && limit > 0) {
      query = query.limitToLast(limit);
    }
    final snapshot = await query.get();
    return _parseOrdersMap(snapshot.value);
  }

  Future<void> saveOrder(
    PurchaseOrder order, {
    AppUser? actor,
  }) async {
    final payload = order.toMap()
      ..['updatedAt'] = appServerTimestamp;
    await _ordersRef.child(order.id).update(payload);

    if (actor != null) {
      unawaited(
        _appendEvent(
          _ordersRef.child(order.id),
          fromStatus: order.status,
          toStatus: order.status,
          byUserId: actor.id,
          byRole: _actorRoleLabel(actor),
          type: 'save',
          comment: 'Orden actualizada.',
          itemsSnapshot: order.items,
        ),
      );
    }
  }

  Future<List<PurchaseOrder>> fetchOrdersByStatus(
    PurchaseOrderStatus status, {
    int? limit,
  }) async {
    AppDatabaseQuery query = _ordersRef.orderByChild('status').equalTo(status.name);
    if (limit != null && limit > 0) {
      query = query.limitToLast(limit);
    }
    final snapshot = await query.get();
    return _parseOrdersMap(snapshot.value);
  }

  Future<String> submitOrder({
    String? draftId,
    required AppUser requester,
    required PurchaseOrderUrgency urgency,
    required List<PurchaseOrderItem> items,
    DateTime? requestedDeliveryDate,
    String? clientNote,
    String? urgentJustification,
  }) async {
    final trimmedDraftId = draftId?.trim();
    if (_isFolioId(trimmedDraftId)) {
      final orderRef = _ordersRef.child(trimmedDraftId!);
      final snapshot = await orderRef.get();
      if (snapshot.exists) {
        final resubmissions = _mergeResubmissions(snapshot.value);
        final existing = snapshot.value is Map
            ? PurchaseOrder.fromMap(
                trimmedDraftId,
                Map<String, dynamic>.from(snapshot.value as Map),
              )
            : null;

        final timingUpdate = existing == null ? const <String, Object?>{} : _statusTimingUpdate(existing);

        await orderRef.update({
          'companyId': sharedCompanyDataId,
          'requesterId': requester.id,
          'requesterName': requester.name,
          'areaId': requester.areaId,
          'areaName': requester.areaDisplay,
          'urgency': urgency.name,
          'clientNote': clientNote,
          'urgentJustification': urgentJustification,
          'requestedDeliveryDate': requestedDeliveryDate?.millisecondsSinceEpoch,
          'items': items.map((item) => item.toMap()).toList(),
          'resubmissions': resubmissions,
          'status': PurchaseOrderStatus.intakeReview.name,
          'isDraft': false,
          'pdfUrl': null,
          'authorizedByName': null,
          'authorizedByArea': null,
          'authorizedAt': null,
          'processByName': null,
          'processByArea': null,
          'processAt': null,
          'updatedAt': appServerTimestamp,
          'visibility': {
            'contabilidad': false,
          },
          ...timingUpdate,
        });

        unawaited(
          _appendEvent(
            orderRef,
            fromStatus: PurchaseOrderStatus.draft,
            toStatus: PurchaseOrderStatus.intakeReview,
            byUserId: requester.id,
            byRole: _actorRoleLabel(requester),
            type: 'advance',
            itemsSnapshot: items,
          ),
        );
        return trimmedDraftId;
      }
    }

    final nextFolio = await _reserveNextFolio(_database, _company);
    final orderId = nextFolio;

    final payload = <String, dynamic>{
      'companyId': sharedCompanyDataId,
      'requesterId': requester.id,
      'requesterName': requester.name,
      'areaId': requester.areaId,
      'areaName': requester.areaDisplay,
      'urgency': urgency.name,
      'clientNote': clientNote,
      'urgentJustification': urgentJustification,
      'requestedDeliveryDate': requestedDeliveryDate?.millisecondsSinceEpoch,
      'items': items.map((item) => item.toMap()).toList(),
      'status': PurchaseOrderStatus.intakeReview.name,
      'isDraft': false,
      'pdfUrl': null,
      'authorizedByName': null,
      'authorizedByArea': null,
      'authorizedAt': null,
      'processByName': null,
      'processByArea': null,
      'processAt': null,
      'updatedAt': appServerTimestamp,
      'statusEnteredAt': appServerTimestamp,
      'statusDurations': <String, int>{},
      'visibility': {
        'contabilidad': false,
      },
    };

    final orderRef = _ordersRef.child(orderId);
    await orderRef.set({
      ...payload,
      'createdAt': appServerTimestamp,
    });

    unawaited(
      _appendEvent(
        orderRef,
        fromStatus: PurchaseOrderStatus.draft,
        toStatus: PurchaseOrderStatus.intakeReview,
        byUserId: requester.id,
        byRole: _actorRoleLabel(requester),
        type: 'advance',
        itemsSnapshot: items,
      ),
    );
    return orderId;
  }

  Future<void> requestEdit({
    required PurchaseOrder order,
    required String comment,
    required List<PurchaseOrderItem> items,
    required AppUser actor,
  }) async {
    final trimmed = comment.trim();
    final orderRef = _ordersRef.child(order.id);
    final timingUpdate = _statusTimingUpdate(order);
    final enteredAt =
        order.statusEnteredAt ?? order.updatedAt ?? order.createdAt ?? DateTime.now();
    final reviewDurationMs = DateTime.now().difference(enteredAt).inMilliseconds;
    final safeReviewDurationMs = reviewDurationMs < 0 ? 0 : reviewDurationMs;

    await orderRef.update({
      'status': PurchaseOrderStatus.draft.name,
      'isDraft': true,
      'lastReturnReason': trimmed.isEmpty ? null : trimmed,
      'lastReturnFromStatus': order.status.name,
      'rejectionAcknowledgedAt': null,
      'lastReviewDurationMs': safeReviewDurationMs,
      'returnCount': order.returnCount + 1,
      'items': items.map((item) => item.toMap()).toList(),
      'pdfUrl': null,
      'authorizedByName': null,
      'authorizedByArea': null,
      'authorizedAt': null,
      'processByName': null,
      'processByArea': null,
      'processAt': null,
      'updatedAt': appServerTimestamp,
      ...timingUpdate,
    });

    unawaited(
      _appendEvent(
        orderRef,
        fromStatus: order.status,
        toStatus: PurchaseOrderStatus.draft,
        byUserId: actor.id,
        byRole: _actorRoleLabel(actor),
        type: 'return',
        itemsSnapshot: items,
        comment: trimmed.isEmpty ? null : trimmed,
      ),
    );
  }

  Future<void> acknowledgeRejectedOrder(String orderId) async {
    final orderRef = _ordersRef.child(orderId);
    await orderRef.update({
      'rejectionAcknowledgedAt': appServerTimestamp,
      'updatedAt': appServerTimestamp,
    });
  }

  Future<void> advanceOrderStage({
    required PurchaseOrder order,
    required PurchaseOrderStatus nextStatus,
    required AppUser actor,
    String? comment,
    List<PurchaseOrderItem>? items,
  }) async {
    if (order.status == nextStatus) return;

    final orderRef = _ordersRef.child(order.id);
    final timingUpdate = _statusTimingUpdate(order);
    final payload = <String, Object?>{
      'status': nextStatus.name,
      'updatedAt': appServerTimestamp,
      ...timingUpdate,
    };
    if (items != null) {
      payload['items'] = items.map((item) => item.toMap()).toList();
    }

    await orderRef.update(payload);
    unawaited(
      _appendEvent(
        orderRef,
        fromStatus: order.status,
        toStatus: nextStatus,
        byUserId: actor.id,
        byRole: _actorRoleLabel(actor),
        type: 'advance',
        comment: comment,
        itemsSnapshot: items,
      ),
    );
  }

  Future<void> markOrderAuthorized({
    required PurchaseOrder order,
    required AppUser actor,
  }) async {
    final normalizedName = actor.name.trim().isEmpty ? actor.id : actor.name.trim();
    final normalizedArea = actor.areaDisplay.trim();
    await _ordersRef.child(order.id).update({
      'authorizedByName': normalizedName,
      'authorizedByArea': normalizedArea.isEmpty ? null : normalizedArea,
      'authorizedAt': appServerTimestamp,
      'updatedAt': appServerTimestamp,
    });
  }

  Future<void> authorizeAndAdvanceToCompras({
    required PurchaseOrder order,
    required AppUser actor,
    String? comment,
    List<PurchaseOrderItem>? items,
  }) async {
    final normalizedName = actor.name.trim().isEmpty ? actor.id : actor.name.trim();
    final normalizedArea = actor.areaDisplay.trim();
    final orderRef = _ordersRef.child(order.id);
    final timingUpdate = _statusTimingUpdate(order);
    final payload = <String, Object?>{
      'status': PurchaseOrderStatus.sourcing.name,
      'authorizedByName': normalizedName,
      'authorizedByArea': normalizedArea.isEmpty ? null : normalizedArea,
      'authorizedAt': appServerTimestamp,
      'updatedAt': appServerTimestamp,
      ...timingUpdate,
    };
    if (items != null) {
      payload['items'] = items.map((item) => item.toMap()).toList();
    }

    await orderRef.update(payload);
    unawaited(
      _appendEvent(
        orderRef,
        fromStatus: order.status,
        toStatus: PurchaseOrderStatus.sourcing,
        byUserId: actor.id,
        byRole: _actorRoleLabel(actor),
        type: 'advance',
        comment: comment,
        itemsSnapshot: items,
      ),
    );
  }

  Future<void> processAndAdvanceToDashboard({
    required PurchaseOrder order,
    required AppUser actor,
    required List<PurchaseOrderItem> items,
    required num totalBudget,
    required MoneyCurrency amountCurrency,
    required Map<String, num> supplierBudgets,
    required String? primarySupplier,
    required String? primaryInternalOrder,
    String? comment,
  }) async {
    final normalizedName = actor.name.trim().isEmpty ? actor.id : actor.name.trim();
    final normalizedArea = actor.areaDisplay.trim();
    final orderRef = _ordersRef.child(order.id);
    final timingUpdate = _statusTimingUpdate(order);
    await orderRef.update({
      'status': PurchaseOrderStatus.readyForApproval.name,
      'items': items.map((item) => item.toMap()).toList(),
      'supplier': primarySupplier,
      'internalOrder': primaryInternalOrder,
      'budget': totalBudget,
      'amountCurrency': amountCurrency.code,
      'supplierBudgets': supplierBudgets,
      'processByName': normalizedName,
      'processByArea': normalizedArea.isEmpty ? null : normalizedArea,
      'processAt': appServerTimestamp,
      'updatedAt': appServerTimestamp,
      ...timingUpdate,
    });
    unawaited(
      _appendEvent(
        orderRef,
        fromStatus: order.status,
        toStatus: PurchaseOrderStatus.readyForApproval,
        byUserId: actor.id,
        byRole: _actorRoleLabel(actor),
        type: 'advance',
        comment: comment,
        itemsSnapshot: items,
      ),
    );
  }

  Future<void> persistAuthorizedOrderPdf({
    required PurchaseOrder order,
    required Uint8List pdfBytes,
    required AppUser actor,
  }) async {
    final normalizedName = actor.name.trim().isEmpty ? actor.id : actor.name.trim();
    final normalizedArea = actor.areaDisplay.trim();
    final storageRef = _storage
        .ref()
        .child('purchase_orders')
        .child(order.id)
        .child('authorized_${DateTime.now().millisecondsSinceEpoch}.pdf');

    await storageRef.putData(
      pdfBytes,
      SettableMetadata(
        contentType: 'application/pdf',
        customMetadata: <String, String>{
          'orderId': order.id,
          'authorizedByName': normalizedName,
          'authorizedByArea': normalizedArea,
        },
      ),
    );

    final downloadUrl = await storageRef.getDownloadURL();
    final orderRef = _ordersRef.child(order.id);
    await orderRef.update({
      'pdfUrl': downloadUrl,
      'authorizedByName': normalizedName,
      'authorizedByArea': normalizedArea.isEmpty ? null : normalizedArea,
      'authorizedAt': appServerTimestamp,
      'updatedAt': appServerTimestamp,
    });
  }

  Future<void> sendOrderBackToCompras({
    required PurchaseOrder order,
    required AppUser actor,
    required String comment,
  }) async {
    final trimmed = comment.trim();
    final orderRef = _ordersRef.child(order.id);
    final timingUpdate = _statusTimingUpdate(order);
    await orderRef.update({
      'status': PurchaseOrderStatus.sourcing.name,
      'updatedAt': appServerTimestamp,
      'lastReturnReason': trimmed.isEmpty ? null : trimmed,
      'lastReturnFromStatus': order.status.name,
      ...timingUpdate,
    });
    unawaited(
      _appendEvent(
        orderRef,
        fromStatus: order.status,
        toStatus: PurchaseOrderStatus.sourcing,
        byUserId: actor.id,
        byRole: _actorRoleLabel(actor),
        type: 'return',
        comment: trimmed.isEmpty ? null : trimmed,
      ),
    );
  }

  Future<void> setEstimatedDeliveryDate({
    required PurchaseOrder order,
    required DateTime etaDate,
    required AppUser actor,
  }) async {
    final orderRef = _ordersRef.child(order.id);
    final timingUpdate = _statusTimingUpdate(order);

    await orderRef.update({
      'status': PurchaseOrderStatus.contabilidad.name,
      'etaDate': etaDate.millisecondsSinceEpoch,
      'updatedAt': appServerTimestamp,
      ...timingUpdate,
    });

    unawaited(
      _appendEvent(
        orderRef,
        fromStatus: order.status,
        toStatus: PurchaseOrderStatus.contabilidad,
        byUserId: actor.id,
        byRole: _actorRoleLabel(actor),
        type: 'advance',
      ),
    );
  }

  Future<void> completeFromContabilidad({
    required PurchaseOrder order,
    required List<String> facturaUrls,
    required AppUser actor,
    List<PurchaseOrderItem>? items,
  }) async {
    final cleaned = facturaUrls.map((url) => url.trim()).where((url) => url.isNotEmpty).toList();
    if (cleaned.isEmpty) throw StateError('Link de factura requerido.');

    final orderRef = _ordersRef.child(order.id);
    final trimmedName = actor.name.trim();
    final trimmedArea = actor.areaDisplay.trim();
    final timingUpdate = _statusTimingUpdate(order);

    final payload = <String, dynamic>{
      'status': PurchaseOrderStatus.eta.name,
      'facturaPdfUrls': cleaned,
      'facturaPdfUrl': cleaned.first,
      'contabilidadName': trimmedName.isEmpty ? null : trimmedName,
      'contabilidadArea': trimmedArea.isEmpty ? null : trimmedArea,
      'facturaUploadedAt': appServerTimestamp,
      'materialArrivedAt': appServerTimestamp,
      'materialArrivedName': trimmedName.isEmpty ? null : trimmedName,
      'materialArrivedArea': trimmedArea.isEmpty ? null : trimmedArea,
      'completedAt': appServerTimestamp,
      'updatedAt': appServerTimestamp,
      ...timingUpdate,
    };
    if (items != null) {
      payload['items'] = items.map((item) => item.toMap()).toList();
      payload['internalOrder'] = null;
    }

    await orderRef.update(payload);

    unawaited(
      _appendEvent(
        orderRef,
        fromStatus: order.status,
        toStatus: PurchaseOrderStatus.eta,
        byUserId: actor.id,
        byRole: _actorRoleLabel(actor),
        type: 'material_arrived',
        comment: 'Material recibido en sitio y listo para confirmacion del solicitante.',
      ),
    );
  }

  Future<void> registerArrivedItems({
    required PurchaseOrder order,
    required Set<int> itemLines,
    required AppUser actor,
    DateTime? registeredAt,
  }) async {
    if (itemLines.isEmpty) {
      throw StateError('Selecciona al menos un item para registrar llegada.');
    }

    final orderRef = _ordersRef.child(order.id);
    final arrivalMoment = registeredAt ?? DateTime.now();
    final trimmedName = actor.name.trim();
    final trimmedArea = actor.areaDisplay.trim();
    var changedCount = 0;

    final updatedItems = <PurchaseOrderItem>[];
    for (final item in order.items) {
      final matchesTarget =
          itemLines.contains(item.line) &&
          item.deliveryEtaDate != null &&
          !item.isArrivalRegistered;
      if (!matchesTarget) {
        updatedItems.add(item);
        continue;
      }
      changedCount += 1;
      updatedItems.add(
        item.copyWith(
          arrivedAt: arrivalMoment,
          arrivedByName: trimmedName.isEmpty ? null : trimmedName,
          arrivedByArea: trimmedArea.isEmpty ? null : trimmedArea,
        ),
      );
    }

    if (changedCount == 0) {
      throw StateError('No hubo items validos para registrar como llegados.');
    }

    final updatedOrder = PurchaseOrder.fromMap(
      order.id,
      <String, dynamic>{
        ...order.toMap(),
        'items': updatedItems.map((item) => item.toMap()).toList(),
      },
    );
    final allResolved = areAllItemsResolved(updatedOrder);
    final nextStatus = allResolved ? PurchaseOrderStatus.eta : order.status;
    final payload = <String, Object?>{
      'items': updatedItems.map((item) => item.toMap()).toList(),
      'materialArrivedAt': appServerTimestamp,
      'materialArrivedName': trimmedName.isEmpty ? null : trimmedName,
      'materialArrivedArea': trimmedArea.isEmpty ? null : trimmedArea,
      'updatedAt': appServerTimestamp,
    };
    if (allResolved) {
      payload['status'] = nextStatus.name;
      payload['completedAt'] = appServerTimestamp;
      if (order.status != nextStatus) {
        payload.addAll(_statusTimingUpdate(order));
      }
    }

    await orderRef.update(payload);

    unawaited(
      _appendEvent(
        orderRef,
        fromStatus: order.status,
        toStatus: nextStatus == order.status ? order.status : nextStatus,
        byUserId: actor.id,
        byRole: _actorRoleLabel(actor),
        type: 'items_arrived',
        itemsSnapshot: updatedItems,
        comment: allResolved
            ? '$changedCount item(s) marcados como llegados. La orden quedo lista para confirmacion de recibido.'
            : '$changedCount item(s) marcados como llegados por Compras.',
      ),
    );
  }

  Future<void> setEstimatedDeliveryDateForItems({
    required PurchaseOrder order,
    required Set<int> itemLines,
    required DateTime etaDate,
    required AppUser actor,
  }) async {
    if (itemLines.isEmpty) {
      throw StateError('Selecciona al menos un item para registrar ETA.');
    }

    final orderRef = _ordersRef.child(order.id);
    var changedCount = 0;
    final updatedItems = <PurchaseOrderItem>[];
    for (final item in order.items) {
      final matchesTarget =
          itemLines.contains(item.line) && item.requiresFulfillment;
      if (!matchesTarget) {
        updatedItems.add(item);
        continue;
      }
      changedCount += 1;
      updatedItems.add(
        item.copyWith(
          deliveryEtaDate: etaDate,
        ),
      );
    }

    if (changedCount == 0) {
      throw StateError('No hubo items validos para registrar ETA.');
    }

    await orderRef.update({
      'items': updatedItems.map((item) => item.toMap()).toList(),
      'etaDate': etaDate.millisecondsSinceEpoch,
      'updatedAt': appServerTimestamp,
    });

    unawaited(
      _appendEvent(
        orderRef,
        fromStatus: order.status,
        toStatus: order.status,
        byUserId: actor.id,
        byRole: _actorRoleLabel(actor),
        type: 'items_eta',
        itemsSnapshot: updatedItems,
        comment: '$changedCount item(s) con fecha estimada registrada.',
      ),
    );
  }

  Future<void> sendItemsToFacturas({
    required PurchaseOrder order,
    required Set<int> itemLines,
    required AppUser actor,
    DateTime? sentAt,
  }) async {
    if (itemLines.isEmpty) {
      throw StateError('Selecciona al menos un item para enviar a facturas y evidencias.');
    }

    final orderRef = _ordersRef.child(order.id);
    final sentMoment = sentAt ?? DateTime.now();
    var changedCount = 0;
    final updatedItems = <PurchaseOrderItem>[];
    for (final item in order.items) {
      final matchesTarget =
          itemLines.contains(item.line) &&
          item.requiresFulfillment &&
          item.deliveryEtaDate != null;
      if (!matchesTarget) {
        updatedItems.add(item);
        continue;
      }
      changedCount += 1;
      updatedItems.add(item.copyWith(sentToContabilidadAt: sentMoment));
    }

    if (changedCount == 0) {
      throw StateError('No hubo items validos para enviar a facturas y evidencias.');
    }

    await orderRef.update({
      'status': PurchaseOrderStatus.contabilidad.name,
      'items': updatedItems.map((item) => item.toMap()).toList(),
      'updatedAt': appServerTimestamp,
      ..._statusTimingUpdate(order),
    });

    unawaited(
      _appendEvent(
        orderRef,
        fromStatus: order.status,
        toStatus: PurchaseOrderStatus.contabilidad,
        byUserId: actor.id,
        byRole: _actorRoleLabel(actor),
        type: 'items_to_facturas',
        itemsSnapshot: updatedItems,
        comment: '$changedCount item(s) enviados a facturas y evidencias.',
      ),
    );
  }

  Future<void> attachAccountingEvidence({
    required PurchaseOrder order,
    required List<String> facturaUrls,
    required List<String> paymentReceiptUrls,
    required AppUser actor,
  }) async {
    final cleanedFacturas = facturaUrls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    final cleanedReceipts = paymentReceiptUrls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    if (cleanedFacturas.isEmpty || cleanedReceipts.isEmpty) {
      throw StateError('Agrega al menos un link de factura y un link de recibo de pago.');
    }

    final mergedFacturas = <String>{
      ...order.facturaPdfUrls.map((url) => url.trim()).where((url) => url.isNotEmpty),
      ...cleanedFacturas,
    }.toList(growable: false);
    final mergedReceipts = <String>{
      ...order.paymentReceiptUrls.map((url) => url.trim()).where((url) => url.isNotEmpty),
      ...cleanedReceipts,
    }.toList(growable: false);

    final orderRef = _ordersRef.child(order.id);
    await orderRef.update({
      'facturaPdfUrls': mergedFacturas,
      'facturaPdfUrl': mergedFacturas.first,
      'paymentReceiptUrls': mergedReceipts,
      'facturaUploadedAt': appServerTimestamp,
      'updatedAt': appServerTimestamp,
    });

    unawaited(
      _appendEvent(
        orderRef,
        fromStatus: order.status,
        toStatus: order.status,
        byUserId: actor.id,
        byRole: _actorRoleLabel(actor),
        type: 'accounting_evidence',
        comment:
            '${cleanedFacturas.length} link(s) de factura y ${cleanedReceipts.length} link(s) de recibo agregados.',
      ),
    );
  }

  Future<void> finalizeResolvedOrder({
    required PurchaseOrder order,
    required AppUser actor,
  }) async {
    if (!areAllItemsResolved(order)) {
      throw StateError('La orden aun tiene items pendientes por resolver.');
    }
    if (order.isRequesterReceiptConfirmed) {
      return;
    }

    final orderRef = _ordersRef.child(order.id);
    await orderRef.update({
      'status': PurchaseOrderStatus.eta.name,
      'completedAt': appServerTimestamp,
      'updatedAt': appServerTimestamp,
      ..._statusTimingUpdate(order),
    });

    unawaited(
      _appendEvent(
        orderRef,
        fromStatus: order.status,
        toStatus: PurchaseOrderStatus.eta,
        byUserId: actor.id,
        byRole: _actorRoleLabel(actor),
        type: 'finalize_resolved',
        comment: 'Orden lista para confirmacion de recibido del solicitante.',
      ),
    );
  }

  Future<void> confirmRequesterReceived({
    required PurchaseOrder order,
    required AppUser actor,
  }) async {
    if (order.status != PurchaseOrderStatus.eta) {
      throw StateError('La orden aun no esta lista para confirmar recibido.');
    }
    if (order.isRequesterReceiptConfirmed) {
      return;
    }

    final trimmedName = actor.name.trim();
    final trimmedArea = actor.areaDisplay.trim();
    final orderRef = _ordersRef.child(order.id);
    await orderRef.update({
      'requesterReceivedAt': appServerTimestamp,
      'requesterReceivedName': trimmedName.isEmpty ? null : trimmedName,
      'requesterReceivedArea': trimmedArea.isEmpty ? null : trimmedArea,
      'requesterReceiptAutoConfirmed': null,
      'completedAt': appServerTimestamp,
      'updatedAt': appServerTimestamp,
    });

    unawaited(
      _appendEvent(
        orderRef,
        fromStatus: order.status,
        toStatus: null,
        byUserId: actor.id,
        byRole: _actorRoleLabel(actor),
        type: 'received',
        comment: 'Orden confirmada como recibida por el solicitante.',
      ),
    );
  }

  Future<void> submitServiceRating({
    required PurchaseOrder order,
    required int rating,
    String? comment,
  }) async {
    if (rating < 1 || rating > 5) {
      throw StateError('La calificacion debe estar entre 1 y 5.');
    }
    final trimmedComment = comment?.trim();
    final orderRef = _ordersRef.child(order.id);
    await orderRef.update({
      'serviceRating': rating,
      'serviceRatingComment':
          trimmedComment == null || trimmedComment.isEmpty ? null : trimmedComment,
      'serviceRatedAt': appServerTimestamp,
      'updatedAt': appServerTimestamp,
    });

    unawaited(
      _appendEvent(
        orderRef,
        fromStatus: order.status,
        toStatus: null,
        byUserId: order.requesterId,
        byRole: order.areaName,
        type: 'service_rating',
        comment: 'Calificacion registrada: $rating/5',
      ),
    );
  }

  Future<void> autoConfirmRequesterReceived({
    required PurchaseOrder order,
  }) async {
    if (order.isRequesterReceiptConfirmed) return;
    if (!isOrderAutoReceiptDue(order)) {
      throw StateError('La orden aun no cumple el plazo de autocierre.');
    }

    final orderRef = _ordersRef.child(order.id);
    final nextStatus = PurchaseOrderStatus.eta;
    final payload = <String, Object?>{
      'status': nextStatus.name,
      'requesterReceivedAt': appServerTimestamp,
      'requesterReceivedName': 'Sistema',
      'requesterReceivedArea': 'Autocierre 5 dias habiles',
      'requesterReceiptAutoConfirmed': true,
      'completedAt': appServerTimestamp,
      'updatedAt': appServerTimestamp,
    };
    if (order.status != nextStatus) {
      payload.addAll(_statusTimingUpdate(order));
    }

    await orderRef.update(payload);

    unawaited(
      _appendEvent(
        orderRef,
        fromStatus: order.status,
        toStatus: nextStatus,
        byUserId: 'system',
        byRole: 'Sistema',
        type: 'received_timeout',
        comment:
            'Autocierre por 5 dias habiles sin reaccion del solicitante. El sistema marco el item como enterado por falta de reaccion humana.',
      ),
    );
  }

  Future<void> deleteOrder(String orderId) async {
    await _ordersRef.child(orderId).remove();
  }
}

final purchaseOrderRepositoryProvider = Provider<PurchaseOrderRepository>((ref) {
  final database = ref.watch(firebaseDatabaseProvider);
  final storage = ref.watch(firebaseStorageProvider);
  return PurchaseOrderRepository(database, storage, Company.chabely);
});

Future<Map<String, PurchaseOrder>> _fetchOrdersByIds(
  AppDatabase database,
  Iterable<String> orderIds,
) async {
  final ordersById = <String, PurchaseOrder>{};
  for (final rawOrderId in orderIds) {
    final orderId = rawOrderId.trim();
    if (orderId.isEmpty) continue;
    _logWindowsReleaseRepoStep('_fetchOrdersByIds:getStart orderId=$orderId');
    final snapshot = await database.ref('purchaseOrders/$orderId').get();
    _logWindowsReleaseRepoStep(
      '_fetchOrdersByIds:getDone orderId=$orderId exists=${snapshot.exists}',
    );
    if (!snapshot.exists || snapshot.value is! Map) continue;
    ordersById[orderId] = PurchaseOrder.fromMap(
      orderId,
      Map<String, dynamic>.from(snapshot.value as Map),
    );
  }
  return ordersById;
}

Future<String> _reserveNextFolio(AppDatabase database, Company company) async {
  final counterRef = database.ref('counters/folios/purchaseOrderNext');
  final currentSnapshot = await counterRef.get();
  final currentValue = _parseCounterValue(currentSnapshot.value);
  final legacySeed = currentValue > 0 ? 0 : await _resolveLegacyMax(database);
  final result = await counterRef.runTransaction((current) {
    final base = _parseCounterValue(current);
    final effective = base > 0 ? base : legacySeed;
    return effective + 1;
  });
  if (!result.committed) {
    throw StateError('No se pudo reservar el folio.');
  }
  final nextValue = _parseCounterValue(result.snapshot.value);
  if (nextValue <= 0) {
    throw StateError('Folio invalido.');
  }
  return formatFolio(company, nextValue);
}

Future<int> _resolveLegacyMax(AppDatabase database) async {
  var maxValue = 0;
  for (final company in Company.values) {
    final snapshot = await database
        .ref('counters/folios/${company.name}/purchaseOrderNext')
        .get();
    final value = _parseCounterValue(snapshot.value);
    if (value > maxValue) {
      maxValue = value;
    }
  }
  return maxValue;
}

int _parseCounterValue(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) {
    return int.tryParse(raw.trim()) ?? 0;
  }
  return 0;
}

void _logWindowsReleaseRepoStep(String message) {
  // Instrumentacion deshabilitada.
}

String _orderSignature(PurchaseOrder order) {
  final updatedAt = order.updatedAt?.millisecondsSinceEpoch ?? 0;
  final createdAt = order.createdAt?.millisecondsSinceEpoch ?? 0;
  final itemsSignature = ([...order.items]
        ..sort((left, right) => left.line.compareTo(right.line)))
      .map((item) {
        final estimatedDate = item.estimatedDate?.millisecondsSinceEpoch ?? 0;
        final deliveryEtaDate = item.deliveryEtaDate?.millisecondsSinceEpoch ?? 0;
        final sentToContabilidadAt =
            item.sentToContabilidadAt?.millisecondsSinceEpoch ?? 0;
        final arrivedAt = item.arrivedAt?.millisecondsSinceEpoch ?? 0;
        final notPurchasedAt = item.notPurchasedAt?.millisecondsSinceEpoch ?? 0;
        return [
          item.line.toString(),
          item.pieces.toString(),
          item.partNumber,
          item.description,
          item.quantity.toString(),
          item.unit,
          item.customer ?? '',
          item.supplier ?? '',
          item.budget?.toString() ?? '',
          item.amountCurrency.code,
          item.internalOrder ?? '',
          estimatedDate.toString(),
          deliveryEtaDate.toString(),
          sentToContabilidadAt.toString(),
          arrivedAt.toString(),
          item.arrivedByName ?? '',
          item.arrivedByArea ?? '',
          item.reviewFlagged ? '1' : '0',
          item.reviewComment ?? '',
          item.notPurchasedReason ?? '',
          notPurchasedAt.toString(),
          item.notPurchasedByName ?? '',
          item.notPurchasedByArea ?? '',
          item.receivedQuantity?.toString() ?? '',
          item.receivedComment ?? '',
        ].join('^');
      }).join('~');
  return [
    order.id,
    order.companyId ?? '',
    order.status.name,
    updatedAt.toString(),
    createdAt.toString(),
    order.lastReturnReason ?? '',
    order.lastReturnFromStatus?.name ?? '',
    order.rejectionAcknowledgedAt?.millisecondsSinceEpoch.toString() ?? '',
    order.lastReviewDurationMs?.toString() ?? '',
    order.returnCount.toString(),
    order.requesterId,
    order.requesterName,
    order.areaId,
    order.areaName,
    order.urgency.name,
    order.clientNote ?? '',
    order.urgentJustification ?? '',
    order.supplier ?? '',
    order.internalOrder ?? '',
    order.budget?.toString() ?? '',
    order.amountCurrency.code,
    (order.supplierBudgets.entries.toList()
          ..sort((left, right) => left.key.compareTo(right.key)))
        .map((entry) => '${entry.key}=${entry.value}')
        .join(','),
    order.requestedDeliveryDate?.millisecondsSinceEpoch.toString() ?? '',
    order.etaDate?.millisecondsSinceEpoch.toString() ?? '',
    order.facturaPdfUrl ?? '',
    order.facturaPdfUrls.join(','),
    order.paymentReceiptUrls.join(','),
    order.pdfUrl ?? '',
    order.authorizedByName ?? '',
    order.authorizedByArea ?? '',
    order.authorizedAt?.millisecondsSinceEpoch.toString() ?? '',
    order.processByName ?? '',
    order.processByArea ?? '',
    order.processAt?.millisecondsSinceEpoch.toString() ?? '',
    order.resubmissionDates
        .map((date) => date.millisecondsSinceEpoch.toString())
        .join(','),
    (order.statusDurations.entries.toList()
          ..sort((left, right) => left.key.compareTo(right.key)))
        .map((entry) => '${entry.key}=${entry.value}')
        .join(','),
    order.statusEnteredAt?.millisecondsSinceEpoch.toString() ?? '',
    order.contabilidadName ?? '',
    order.contabilidadArea ?? '',
    order.facturaUploadedAt?.millisecondsSinceEpoch.toString() ?? '',
    order.materialArrivedAt?.millisecondsSinceEpoch.toString() ?? '',
    order.materialArrivedName ?? '',
    order.materialArrivedArea ?? '',
    order.completedAt?.millisecondsSinceEpoch.toString() ?? '',
    order.requesterReceivedAt?.millisecondsSinceEpoch.toString() ?? '',
    order.requesterReceivedName ?? '',
    order.requesterReceivedArea ?? '',
    order.serviceRating?.toString() ?? '',
    order.serviceRatingComment ?? '',
    order.serviceRatedAt?.millisecondsSinceEpoch.toString() ?? '',
    order.requesterReceiptAutoConfirmed ? '1' : '0',
    order.isDraft ? '1' : '0',
    order.items.length.toString(),
    itemsSignature,
  ].join('|');
}

bool _sameOrderList(List<PurchaseOrder> a, List<PurchaseOrder> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (_orderSignature(a[index]) != _orderSignature(b[index])) {
      return false;
    }
  }
  return true;
}

bool _sameOrder(PurchaseOrder? a, PurchaseOrder? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  return _orderSignature(a) == _orderSignature(b);
}

String _eventSignature(PurchaseOrderEvent event) {
  final timestamp = event.timestamp?.millisecondsSinceEpoch ?? 0;
  return [
    event.id,
    event.type ?? '',
    event.fromStatus?.name ?? '',
    event.toStatus?.name ?? '',
    timestamp.toString(),
    event.byUser,
    event.byRole,
    event.comment ?? '',
    event.itemsSnapshot.length.toString(),
  ].join('|');
}

bool _sameEventList(List<PurchaseOrderEvent> a, List<PurchaseOrderEvent> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (_eventSignature(a[index]) != _eventSignature(b[index])) {
      return false;
    }
  }
  return true;
}

bool _sameDashboardCounts(OrderDashboardCounts? a, OrderDashboardCounts? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  return a.intakeReview == b.intakeReview &&
      a.sourcing == b.sourcing &&
      a.sourcingReadyToSend == b.sourcingReadyToSend &&
      a.pendingDireccion == b.pendingDireccion &&
      a.pendingEta == b.pendingEta &&
      a.contabilidad == b.contabilidad &&
      a.hasRemoteCounters == b.hasRemoteCounters;
}


bool _isFolioId(String? value) => isFolioId(value);


String _actorRoleLabel(AppUser actor) {
  final area = actor.areaDisplay.trim();
  if (area.isNotEmpty) return area;
  final role = actor.role.trim();
  return role.isNotEmpty ? role : actor.id;
}

Future<void> _appendEvent(
  AppDatabaseRef orderRef, {
  required PurchaseOrderStatus? fromStatus,
  required PurchaseOrderStatus? toStatus,
  required String byUserId,
  required String byRole,
  required String type,
  String? comment,
  List<PurchaseOrderItem>? itemsSnapshot,
}) async {
  final eventRef = orderRef.child('events').push();
  final payload = <String, dynamic>{
    'fromStatus': fromStatus?.name,
    'toStatus': toStatus?.name,
    'byUserId': byUserId,
    'byRole': byRole,
    'timestamp': appServerTimestamp,
    'type': type,
  };

  final trimmedComment = comment?.trim();
  if (trimmedComment != null && trimmedComment.isNotEmpty) {
    payload['comment'] = trimmedComment;
  }
  if (itemsSnapshot != null) {
    payload['itemsSnapshot'] = itemsSnapshot.map((item) => item.toMap()).toList();
  }

  await eventRef.set(payload);
}

Map<String, Object?> _statusTimingUpdate(PurchaseOrder order) {
  final now = DateTime.now();

  final enteredAt = order.statusEnteredAt ?? order.updatedAt ?? order.createdAt ?? now;
  final elapsed = now.difference(enteredAt).inMilliseconds;
  final safeElapsed = elapsed < 0 ? 0 : elapsed;

  final durations = Map<String, int>.from(order.statusDurations);
  final key = order.status.name;
  durations[key] = (durations[key] ?? 0) + safeElapsed;

  return {
    'statusDurations': durations,
    'statusEnteredAt': now.millisecondsSinceEpoch,
  };
}




List<int> _mergeResubmissions(Object? snapshotValue) {
  final next = DateTime.now().millisecondsSinceEpoch;

  // Busca un "resubmissions" existente donde sea que venga.
  dynamic raw = snapshotValue;
  dynamic resubmissions;

  if (raw is Map && raw['resubmissions'] != null) {
    resubmissions = raw['resubmissions'];
  } else {
    resubmissions = null;
  }

  final values = <int>[];

  void addParsed(dynamic v) {
    final parsed = _parseResubmissionValue(v);
    if (parsed != null) values.add(parsed);
  }

  if (resubmissions is List) {
    for (final entry in resubmissions) {
      addParsed(entry);
    }
  } else if (resubmissions is Map) {
    for (final entry in resubmissions.values) {
      addParsed(entry);
    }
  }

  values.add(next);
  return values;
}

int? _parseResubmissionValue(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) return parsed;
  }
  return null;
}
