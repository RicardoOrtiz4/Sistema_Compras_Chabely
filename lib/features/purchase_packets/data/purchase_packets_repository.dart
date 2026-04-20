import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/app_logger.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/firebase_database_compat.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/domain/order_folio.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/purchase_packets/domain/purchase_packet_domain.dart';

class PurchasePacketsRepository {
  PurchasePacketsRepository(this._database, this._company);

  final AppDatabase _database;
  final Company _company;

  AppDatabaseRef get _ordersRef => _database.ref('orders');
  AppDatabaseRef get _orderItemsRef => _database.ref('order_items');
  AppDatabaseRef get _packetsRef => _database.ref('packets');
  AppDatabaseRef get _packetItemsRef => _database.ref('packet_items');
  AppDatabaseRef get _packetDecisionsRef => _database.ref('packet_decisions');
  AppDatabaseRef get _legacyOrdersRef => _database.ref('purchaseOrders');
  AppDatabaseRef get _generalQuoteFolioCounterRef =>
      _database.ref('counters/folios/generalQuoteNext');

  Stream<List<RequestOrder>> watchReadyOrders() {
    final newOrdersStream = _combineLatest<Map<String, Map<String, dynamic>>, List<RequestOrder>>(
      _ordersRef.onValue.map((event) => _parseRawNodeMap(event.snapshot.value)),
      _orderItemsRef.onValue.map((event) => _parseRawNodeMap(event.snapshot.value)),
      (rawOrders, rawItems) => _parseNewOrders(rawOrders, rawItems),
    );
    return _distinctBySignature(
      _combineLatest<List<RequestOrder>, List<RequestOrder>>(
      newOrdersStream,
      _legacyOrdersRef.onValue.map((event) => _parseLegacyReadyOrders(event.snapshot.value)),
      _mergeReadyOrders,
      ),
      _readyOrdersSignature,
    );
  }

  Stream<List<PacketBundle>> watchPackets() {
    final packetsWithItemsStream = _combineLatest<Map<String, Map<String, dynamic>>, List<PurchasePacket>>(
      _packetsRef.onValue.map((event) => _parseRawNodeMap(event.snapshot.value)),
      _packetItemsRef.onValue.map((event) => _parseRawNodeMap(event.snapshot.value)),
      (rawPackets, rawItems) => _parsePackets(rawPackets, rawItems),
    );
    return _distinctBySignature(
      _combineLatest<List<PurchasePacket>, List<PacketBundle>>(
      packetsWithItemsStream,
      _packetDecisionsRef.onValue.map((event) => _parseDecisionsMap(event.snapshot.value)),
      (packets, decisionsByPacketId) => packets
          .map(
            (packet) => PacketBundle(
              packet: packet,
              decisions: decisionsByPacketId[packet.id] ?? const <PacketDecision>[],
            ),
          )
          .toList(growable: false),
      ),
      _packetBundlesSignature,
    );
  }

  Future<RequestOrder?> fetchOrderById(String orderId) async {
    final newSnapshot = await _ordersRef.child(orderId).get();
    if (newSnapshot.exists && newSnapshot.value is Map) {
      final itemSnapshot = await _orderItemsRef.child(orderId).get();
      return _parseNewOrder(
        orderId,
        Map<String, dynamic>.from(newSnapshot.value as Map),
        itemSnapshot.value,
      );
    }

    final legacySnapshot = await _legacyOrdersRef.child(orderId).get();
    if (!legacySnapshot.exists || legacySnapshot.value is! Map) {
      return null;
    }
    return _parseLegacyOrder(
      orderId,
      Map<String, dynamic>.from(legacySnapshot.value as Map),
    );
  }

  Future<String> _reserveNextGeneralQuoteFolio() async {
    final currentSnapshot = await _generalQuoteFolioCounterRef.get();
    final currentValue = _parseCounterValue(currentSnapshot.value);
    final legacySeed =
        currentValue > 0 ? 0 : await _resolveLegacyGeneralQuoteMax();
    final result = await _generalQuoteFolioCounterRef.runTransaction((current) {
      final base = _parseCounterValue(current);
      final effective = base > 0 ? base : legacySeed;
      return effective + 1;
    });
    if (!result.committed) {
      throw StateError('No se pudo reservar el folio de cotizacion general.');
    }
    final nextValue = _parseCounterValue(result.snapshot.value);
    if (nextValue <= 0) {
      throw StateError('Folio de cotizacion general invalido.');
    }
    return formatPacketSupplierFolio(_company, nextValue);
  }

  Future<int> _resolveLegacyGeneralQuoteMax() async {
    final snapshot = await _generalQuoteFolioCounterRef.get();
    return _parseCounterValue(snapshot.value);
  }

  Future<PacketBundle?> fetchPacketById(String packetId) async {
    final packetSnapshot = await _packetsRef.child(packetId).get();
    if (!packetSnapshot.exists || packetSnapshot.value is! Map) {
      return null;
    }
    final itemsSnapshot = await _packetItemsRef.child(packetId).get();
    final decisionsSnapshot = await _packetDecisionsRef.child(packetId).get();
    final packet = PurchasePacket.fromMap(
      packetId,
      Map<String, dynamic>.from(packetSnapshot.value as Map),
      itemRefs: _parsePacketItemRefs(itemsSnapshot.value),
    );
    final decisions = _parseDecisionListForPacket(packetId, decisionsSnapshot.value);
    return PacketBundle(packet: packet, decisions: decisions);
  }

  Future<PurchasePacket> createPacketFromReadyOrders({
    required AppUser actor,
    required String supplierName,
    required num totalAmount,
    required List<String> evidenceUrls,
    required List<String> itemRefIds,
  }) async {
    final trimmedSupplier = supplierName.trim();
    if (trimmedSupplier.isEmpty) {
      throw const PacketDomainError('InvalidSupplier', 'Proveedor requerido.');
    }
    if (itemRefIds.isEmpty) {
      throw const PacketDomainError('EmptyPacket', 'Selecciona al menos un item.');
    }

    final hydratedRefs = <PacketItemRef>[];
    final affectedOrderIds = <String>{};
    final orderCache = <String, RequestOrder>{};
    for (final refId in itemRefIds.toSet()) {
      final separator = refId.indexOf('::');
      if (separator <= 0 || separator >= refId.length - 2) {
        throw PacketDomainError('InvalidItemReference', 'Referencia invalida $refId.');
      }
      final orderId = refId.substring(0, separator);
      final itemId = refId.substring(separator + 2);
      final order = orderCache[orderId] ?? await fetchOrderById(orderId);
      if (order == null) throw MissingOrderReference(orderId);
      orderCache[orderId] = order;
      if (order.status != RequestOrderStatus.readyForApproval) {
        throw PacketDomainError(
          'InvalidOrderState',
          'La orden $orderId no esta lista para agrupacion.',
        );
      }
      final item = order.itemById(itemId);
      if (item == null) throw MissingItemReference(orderId, itemId);
      if (item.isClosed) {
        throw PacketDomainError(
          'ItemAlreadyClosed',
          'El item $itemId de la orden $orderId ya esta cerrado.',
        );
      }
      hydratedRefs.add(
        PacketItemRef(
          id: buildPacketItemRefId(orderId, itemId),
          orderId: orderId,
          itemId: itemId,
          lineNumber: item.lineNumber,
          description: item.description,
          quantity: item.quantity,
          unit: item.unit,
          amount: item.estimatedAmount,
        ),
      );
      affectedOrderIds.add(orderId);
    }

    await Future.wait(
      affectedOrderIds.map((orderId) => _ensureNewOrderMirror(orderCache[orderId]!)),
    );

    final packetRef = _packetsRef.push();
    final packetId = packetRef.key ?? buildOperationId();
    final now = DateTime.now();
    final packet = PurchasePacket(
      id: packetId,
      supplierName: trimmedSupplier,
      status: PurchasePacketStatus.draft,
      version: 1,
      totalAmount: totalAmount,
      evidenceUrls: evidenceUrls
          .map((url) => url.trim())
          .where((url) => url.isNotEmpty)
          .toList(growable: false),
      itemRefs: hydratedRefs,
      createdAt: now,
      updatedAt: now,
      createdBy: actor.id,
    );

    await packetRef.set(packet.toMap());
    await Future.wait(
      hydratedRefs.map(
        (itemRef) => _packetItemsRef.child(packetId).child(itemRef.id).set(itemRef.toMap()),
      ),
    );
    await Future.wait(affectedOrderIds.map(rebuildOrderProjectionFromPackets));
    return packet;
  }

  Future<PurchasePacket> submitPacketForExecutiveApproval({
    required AppUser actor,
    required String packetId,
    required int expectedVersion,
  }) async {
    final operationId = buildOperationId();
    final startedAt = DateTime.now();
    PurchasePacket? updatedPacket;
    try {
      final bundle = await _requirePacket(packetId);
      final packet = bundle.packet;
      if (packet.status == PurchasePacketStatus.approvalQueue) {
        throw PacketAlreadySubmitted(packetId);
      }
      if (packet.version != expectedVersion) {
        throw PacketVersionConflict(
          packetId: packetId,
          expectedVersion: expectedVersion,
          actualVersion: packet.version,
        );
      }
      ensureValidPacketTransition(packet.status, PurchasePacketStatus.approvalQueue);
      await _validatePacketReferences(packet);
      final reservedFolio = await _reserveNextGeneralQuoteFolio();

      final packetRef = _packetsRef.child(packetId);
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final nextPacket = PurchasePacket(
        id: packet.id,
        supplierName: packet.supplierName,
        status: PurchasePacketStatus.approvalQueue,
        version: packet.version + 1,
        totalAmount: packet.totalAmount,
        evidenceUrls: packet.evidenceUrls,
        itemRefs: packet.itemRefs,
        createdAt: packet.createdAt,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(nowMs),
        createdBy: packet.createdBy,
        submittedAt: DateTime.fromMillisecondsSinceEpoch(nowMs),
        submittedBy: actor.id,
        folio: (packet.folio?.trim().isNotEmpty ?? false)
            ? packet.folio!.trim()
            : reservedFolio,
      );
      await packetRef.set(nextPacket.toMap());
      final refreshed = await _requirePacket(packetId);
      updatedPacket = refreshed.packet;
      if (updatedPacket.status != PurchasePacketStatus.approvalQueue) {
        throw StateError(
          'El paquete $packetId no quedo en aprobacion. Estado leido: ${updatedPacket.status.storageKey}.',
        );
      }
      unawaited(_rebuildAffectedOrders(refreshed.packet.itemRefs));
      _logTelemetry(
        PacketTelemetryRecord(
          operationId: operationId,
          actorId: actor.id,
          entityId: packetId,
          expectedVersion: expectedVersion,
          actualVersion: updatedPacket.version,
          durationMs: DateTime.now().difference(startedAt).inMilliseconds,
          result: 'ok',
          context: <String, Object?>{
            'step': 'submitPacketForExecutiveApproval',
            'itemRefIds': updatedPacket.itemRefs.map((item) => item.id).toList(growable: false),
          },
        ),
      );
      return updatedPacket;
    } catch (error) {
      final actualVersion = updatedPacket?.version;
      _logTelemetry(
        PacketTelemetryRecord(
          operationId: operationId,
          actorId: actor.id,
          entityId: packetId,
          expectedVersion: expectedVersion,
          actualVersion: actualVersion,
          durationMs: DateTime.now().difference(startedAt).inMilliseconds,
          result: error is PacketDomainError ? error.code : error.runtimeType.toString(),
          context: <String, Object?>{
            'step': 'submitPacketForExecutiveApproval',
          },
        ),
      );
      rethrow;
    }
  }

  Future<PurchasePacket> approvePacket({
    required AppUser actor,
    required String packetId,
    required int expectedVersion,
    String? reason,
  }) async {
    return _mutatePacketWithDecision(
      actor: actor,
      packetId: packetId,
      expectedVersion: expectedVersion,
      decisionAction: PacketDecisionAction.approve,
      nextStatus: PurchasePacketStatus.executionReady,
      reason: reason,
      affectedItemRefIds: const <String>[],
      telemetryStep: 'approvePacket',
    );
  }

  Future<PurchasePacket> returnPacketForRework({
    required AppUser actor,
    required String packetId,
    required int expectedVersion,
    required String reason,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      throw const PacketDomainError('MissingReason', 'Motivo requerido para regresar el paquete.');
    }
    return _mutatePacketWithDecision(
      actor: actor,
      packetId: packetId,
      expectedVersion: expectedVersion,
      decisionAction: PacketDecisionAction.returnForRework,
      nextStatus: PurchasePacketStatus.draft,
      reason: trimmed,
      affectedItemRefIds: const <String>[],
      telemetryStep: 'returnPacketForRework',
    );
  }

  Future<PurchasePacket> closePacketItemsAsUnpurchasable({
    required AppUser actor,
    required String packetId,
    required int expectedVersion,
    required List<String> itemRefIds,
    required String reason,
  }) async {
    final trimmedReason = reason.trim();
    if (itemRefIds.isEmpty) {
      throw const PacketDomainError('EmptyItemSelection', 'Selecciona items para cerrar.');
    }
    if (trimmedReason.isEmpty) {
      throw const PacketDomainError('MissingReason', 'Motivo requerido para cierre sin compra.');
    }

    final bundle = await _requirePacket(packetId);
    final packet = bundle.packet;
    if (packet.version != expectedVersion) {
      throw PacketVersionConflict(
        packetId: packetId,
        expectedVersion: expectedVersion,
        actualVersion: packet.version,
      );
    }
    ensureValidPacketTransition(packet.status, PurchasePacketStatus.completed);

    final targetIds = itemRefIds.toSet();
    final existingIds = packet.itemRefs.map((item) => item.id).toSet();
    for (final itemRefId in targetIds) {
      if (!existingIds.contains(itemRefId)) {
        throw PacketDomainError('MissingPacketItem', 'El paquete no contiene la referencia $itemRefId.');
      }
    }

    for (final item in packet.itemRefs) {
      if (!targetIds.contains(item.id)) continue;
      await _packetItemsRef.child(packetId).child(item.id).update(<String, Object?>{
        'closedAsUnpurchasable': true,
      });
    }

    await _appendDecision(
      packetId: packetId,
      decision: buildDecision(
        id: _packetDecisionsRef.child(packetId).push().key ?? buildOperationId(),
        packetId: packetId,
        action: PacketDecisionAction.closeUnpurchasable,
        actor: actor,
        reason: trimmedReason,
        affectedItemRefIds: targetIds.toList(growable: false),
      ),
    );

    final refreshedPacket = await _requirePacket(packetId);
    final allClosed = refreshedPacket.packet.itemRefs.every((item) => item.closedAsUnpurchasable);
    await _packetsRef.child(packetId).update(<String, Object?>{
      'status': allClosed
          ? PurchasePacketStatus.completed.storageKey
          : refreshedPacket.packet.status.storageKey,
      'version': packet.version + 1,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });

    final finalBundle = await _requirePacket(packetId);
    await _rebuildAffectedOrders(finalBundle.packet.itemRefs);
    return finalBundle.packet;
  }

  Future<RequestOrder> rebuildOrderProjectionFromPackets(String orderId) async {
    final order = await fetchOrderById(orderId);
    if (order == null) throw MissingOrderReference(orderId);
    await _ensureNewOrderMirror(order);

    final packets = await _fetchAllPackets();
    final related = packets.where((packet) {
      for (final item in packet.itemRefs) {
        if (item.orderId == orderId) return true;
      }
      return false;
    }).toList(growable: false);

    final packetIds = related.map((packet) => packet.id).toList(growable: false);
    final closedItemRefIds = <String>[];
    final submittedItemRefIds = <String>{};
    final draftItemRefIds = <String>{};
    var hasApprovalQueue = false;
    var hasExecutionReady = false;

    for (final packet in related) {
      if (packet.status == PurchasePacketStatus.approvalQueue) {
        hasApprovalQueue = true;
      }
      if (packet.status == PurchasePacketStatus.executionReady) {
        hasExecutionReady = true;
      }
      for (final item in packet.itemRefs) {
        if (item.orderId == orderId && item.closedAsUnpurchasable) {
          closedItemRefIds.add(item.id);
        }
        if (item.orderId != orderId) continue;
        if (packet.status == PurchasePacketStatus.draft) {
          draftItemRefIds.add(item.id);
        } else {
          submittedItemRefIds.add(item.id);
        }
      }
    }

    final openItemRefIds = order.items
        .where((item) => !item.isClosed)
        .map((item) => buildPacketItemRefId(orderId, item.id))
        .toList(growable: false);
    final allOpenItemsSubmitted = openItemRefIds.isNotEmpty &&
        openItemRefIds.every(submittedItemRefIds.contains);
    final hasActiveDraftItems = draftItemRefIds.any(
      (itemRefId) => !submittedItemRefIds.contains(itemRefId),
    );

    RequestOrderStatus nextStatus = order.status;
    if (related.isEmpty) {
      nextStatus = RequestOrderStatus.readyForApproval;
    } else if (hasExecutionReady && allOpenItemsSubmitted) {
      nextStatus = RequestOrderStatus.executionReady;
    } else if (hasApprovalQueue && allOpenItemsSubmitted) {
      nextStatus = RequestOrderStatus.approvalQueue;
    } else if (hasActiveDraftItems) {
      nextStatus = RequestOrderStatus.readyForApproval;
    } else if (!allOpenItemsSubmitted) {
      nextStatus = RequestOrderStatus.readyForApproval;
    }

    final allItemsClosed = order.items.every(
      (item) => closedItemRefIds.contains(buildPacketItemRefId(orderId, item.id)),
    );
    if (allItemsClosed && order.items.isNotEmpty) {
      nextStatus = RequestOrderStatus.completed;
    }

    ensureValidOrderTransition(order.status, nextStatus);
    final projection = OrderProjectionSnapshot(
      packetIds: packetIds,
      closedItemRefIds: closedItemRefIds,
      lastPacketStatus: related.isEmpty ? null : related.last.status,
      status: nextStatus,
    );

    await _ordersRef.child(orderId).update(<String, Object?>{
      'status': nextStatus.storageKey,
      'projection': projection.toMap(),
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });

    final snapshot = await _ordersRef.child(orderId).get();
    final itemSnapshot = await _orderItemsRef.child(orderId).get();
    return _parseNewOrder(
      orderId,
      Map<String, dynamic>.from(snapshot.value as Map),
      itemSnapshot.value,
    );
  }

  Future<void> _validatePacketReferences(PurchasePacket packet) async {
    final orderCache = <String, RequestOrder>{};
    for (final itemRef in packet.itemRefs) {
      final order =
          orderCache[itemRef.orderId] ?? await fetchOrderById(itemRef.orderId);
      if (order == null) throw MissingOrderReference(itemRef.orderId);
      orderCache[itemRef.orderId] = order;
      final item = order.itemById(itemRef.itemId);
      if (item == null) {
        throw MissingItemReference(itemRef.orderId, itemRef.itemId);
      }
      if (item.isClosed) {
        throw PacketDomainError(
          'ClosedItemReference',
          'El item ${itemRef.itemId} de la orden ${itemRef.orderId} ya esta cerrado.',
        );
      }
    }
  }

  Future<PurchasePacket> _mutatePacketWithDecision({
    required AppUser actor,
    required String packetId,
    required int expectedVersion,
    required PacketDecisionAction decisionAction,
    required PurchasePacketStatus nextStatus,
    required String? reason,
    required List<String> affectedItemRefIds,
    required String telemetryStep,
  }) async {
    final operationId = buildOperationId();
    final startedAt = DateTime.now();
    try {
      final bundle = await _requirePacket(packetId);
      final packet = bundle.packet;
      if (packet.version != expectedVersion) {
        throw PacketVersionConflict(
          packetId: packetId,
          expectedVersion: expectedVersion,
          actualVersion: packet.version,
        );
      }
      ensureValidPacketTransition(packet.status, nextStatus);
      if (packet.status != PurchasePacketStatus.approvalQueue) {
        throw InvalidPacketTransition(packet.status, nextStatus);
      }

      await _packetsRef.child(packetId).update(<String, Object?>{
        'status': nextStatus.storageKey,
        'version': packet.version + 1,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
      await _appendDecision(
        packetId: packetId,
        decision: buildDecision(
          id: _packetDecisionsRef.child(packetId).push().key ?? buildOperationId(),
          packetId: packetId,
          action: decisionAction,
          actor: actor,
          reason: reason,
          affectedItemRefIds: affectedItemRefIds,
        ),
      );

      final refreshed = await _requirePacket(packetId);
      await _rebuildAffectedOrders(refreshed.packet.itemRefs);
      _logTelemetry(
        PacketTelemetryRecord(
          operationId: operationId,
          actorId: actor.id,
          entityId: packetId,
          expectedVersion: expectedVersion,
          actualVersion: refreshed.packet.version,
          durationMs: DateTime.now().difference(startedAt).inMilliseconds,
          result: 'ok',
          context: <String, Object?>{
            'step': telemetryStep,
            'reason': reason,
            'affectedItemRefIds': affectedItemRefIds,
          },
        ),
      );
      return refreshed.packet;
    } catch (error) {
      _logTelemetry(
        PacketTelemetryRecord(
          operationId: operationId,
          actorId: actor.id,
          entityId: packetId,
          expectedVersion: expectedVersion,
          actualVersion: null,
          durationMs: DateTime.now().difference(startedAt).inMilliseconds,
          result: error is PacketDomainError ? error.code : error.runtimeType.toString(),
          context: <String, Object?>{
            'step': telemetryStep,
            'reason': reason,
            'affectedItemRefIds': affectedItemRefIds,
          },
        ),
      );
      rethrow;
    }
  }

  Future<void> _appendDecision({
    required String packetId,
    required PacketDecision decision,
  }) {
    return _packetDecisionsRef.child(packetId).child(decision.id).set(decision.toMap());
  }

  Future<PacketBundle> _requirePacket(String packetId) async {
    final bundle = await fetchPacketById(packetId);
    if (bundle == null) {
      throw PacketDomainError('MissingPacket', 'No existe el paquete $packetId.');
    }
    return bundle;
  }

  Future<void> _rebuildAffectedOrders(List<PacketItemRef> itemRefs) async {
    final orderIds = itemRefs.map((item) => item.orderId).toSet();
    await Future.wait(
      orderIds.map(rebuildOrderProjectionFromPackets),
    );
  }

  Future<List<PurchasePacket>> _fetchAllPackets() async {
    final snapshot = await _packetsRef.get();
    final itemsSnapshot = await _packetItemsRef.get();
    return _parsePackets(
      _parseRawNodeMap(snapshot.value),
      _parseRawNodeMap(itemsSnapshot.value),
    );
  }

  Future<void> _ensureNewOrderMirror(RequestOrder order) async {
    final snapshot = await _ordersRef.child(order.id).get();
    if (!snapshot.exists) {
      await _ordersRef.child(order.id).set(order.toMap());
    }
    for (final item in order.items) {
      await _orderItemsRef.child(order.id).child(item.id).set(item.toMap());
    }
  }

  List<RequestOrder> _parseNewOrders(
    Map<String, Map<String, dynamic>> rawOrders,
    Map<String, Map<String, dynamic>> rawItems,
  ) {
    final orders = <RequestOrder>[];
    rawOrders.forEach((key, value) {
      orders.add(
        _parseNewOrder(
          key,
          value,
          rawItems[key],
        ),
      );
    });
    return orders;
  }

  RequestOrder _parseNewOrder(
    String orderId,
    Map<String, dynamic> data,
    Object? rawItems,
  ) {
    final items = <RequestOrderItem>[];
    if (rawItems is Map) {
      rawItems.forEach((itemKey, itemValue) {
        if (itemValue is! Map) return;
        items.add(
          RequestOrderItem.fromMap(
            itemKey.toString(),
            Map<String, dynamic>.from(itemValue),
          ),
        );
      });
    }
    if (items.isEmpty) {
      final embedded = data['items'];
      if (embedded is Map) {
        embedded.forEach((itemKey, itemValue) {
          if (itemValue is! Map) return;
          items.add(
            RequestOrderItem.fromMap(
              itemKey.toString(),
              Map<String, dynamic>.from(itemValue),
            ),
          );
        });
      }
    }
    return RequestOrder.fromMap(orderId, data, items: items);
  }

  List<RequestOrder> _parseLegacyReadyOrders(Object? raw) {
    if (raw is! Map) return const <RequestOrder>[];
    final orders = <RequestOrder>[];
    raw.forEach((key, value) {
      if (value is! Map) return;
      final order = _parseLegacyOrder(key.toString(), Map<String, dynamic>.from(value));
      if (order.status == RequestOrderStatus.readyForApproval) {
        orders.add(order);
      }
    });
    return orders;
  }

  RequestOrder _parseLegacyOrder(String orderId, Map<String, dynamic> data) {
    final legacy = PurchaseOrder.fromMap(orderId, data);
    final items = legacy.items.map((item) {
      final itemId = 'line_${item.line}';
      return RequestOrderItem(
        id: itemId,
        lineNumber: item.line,
        partNumber: item.partNumber,
        description: item.description,
        quantity: item.quantity,
        unit: item.unit,
        supplierName: item.supplier,
        estimatedAmount: item.budget,
        customer: item.customer,
        isClosed: item.isNotPurchased,
      );
    }).toList(growable: false);
    return RequestOrder(
      id: orderId,
      requesterId: legacy.requesterId,
      requesterName: legacy.requesterName,
      areaId: legacy.areaId,
      areaName: legacy.areaName,
      urgency: legacy.urgency.name,
      status: _legacyOrderStatusToNew(legacy.status),
      items: items,
      createdAt: legacy.createdAt,
      updatedAt: legacy.updatedAt,
      source: 'legacy',
    );
  }

  RequestOrderStatus _legacyOrderStatusToNew(PurchaseOrderStatus status) {
    switch (status) {
      case PurchaseOrderStatus.draft:
        return RequestOrderStatus.draft;
      case PurchaseOrderStatus.intakeReview:
        return RequestOrderStatus.intakeReview;
      case PurchaseOrderStatus.sourcing:
        return RequestOrderStatus.sourcing;
      case PurchaseOrderStatus.readyForApproval:
        return RequestOrderStatus.readyForApproval;
      case PurchaseOrderStatus.approvalQueue:
        return RequestOrderStatus.approvalQueue;
      case PurchaseOrderStatus.paymentDone:
      case PurchaseOrderStatus.orderPlaced:
        return RequestOrderStatus.executionReady;
      case PurchaseOrderStatus.contabilidad:
        return RequestOrderStatus.documentsCheck;
      case PurchaseOrderStatus.eta:
        return RequestOrderStatus.completed;
    }
  }

  List<PurchasePacket> _parsePackets(
    Map<String, Map<String, dynamic>> rawPackets,
    Map<String, Map<String, dynamic>> rawItems,
  ) {
    final packets = <PurchasePacket>[];
    rawPackets.forEach((key, value) {
      packets.add(
        PurchasePacket.fromMap(
          key,
          value,
          itemRefs: _parsePacketItemRefs(rawItems[key]),
        ),
      );
    });
    packets.sort((left, right) {
      final leftTime = left.updatedAt?.millisecondsSinceEpoch ?? 0;
      final rightTime = right.updatedAt?.millisecondsSinceEpoch ?? 0;
      return rightTime.compareTo(leftTime);
    });
    return packets;
  }

  Map<String, List<PacketDecision>> _parseDecisionsMap(Object? raw) {
    final decisionsByPacket = <String, List<PacketDecision>>{};
    if (raw is! Map) return decisionsByPacket;
    raw.forEach((packetKey, packetValue) {
      decisionsByPacket[packetKey.toString()] =
          _parseDecisionListForPacket(packetKey.toString(), packetValue);
    });
    return decisionsByPacket;
  }

  List<PacketDecision> _parseDecisionListForPacket(String packetId, Object? raw) {
    if (raw is! Map) return const <PacketDecision>[];
    final decisions = <PacketDecision>[];
    raw.forEach((key, value) {
      if (value is! Map) return;
      decisions.add(
        PacketDecision.fromMap(key.toString(), Map<String, dynamic>.from(value)),
      );
    });
    decisions.sort((left, right) => right.timestamp.compareTo(left.timestamp));
    return decisions;
  }

  List<PacketItemRef> _parsePacketItemRefs(Object? raw) {
    if (raw is! Map) return const <PacketItemRef>[];
    final items = <PacketItemRef>[];
    raw.forEach((key, value) {
      if (value is! Map) return;
      items.add(
        PacketItemRef.fromMap(key.toString(), Map<String, dynamic>.from(value)),
      );
    });
    items.sort((left, right) => left.id.compareTo(right.id));
    return items;
  }

  void _logTelemetry(PacketTelemetryRecord record) {
    AppLogger.log(record.toJsonLine(), tag: 'PACKETS');
  }

  List<RequestOrder> _mergeReadyOrders(
    List<RequestOrder> newOrders,
    dynamic legacyOrdersRaw,
  ) {
    final legacyOrders = legacyOrdersRaw is List<RequestOrder>
        ? legacyOrdersRaw
        : const <RequestOrder>[];
    final merged = <String, RequestOrder>{
      for (final order in legacyOrders) order.id: order,
      for (final order in newOrders) order.id: order,
    };
    final values = merged.values
        .where((order) => order.status == RequestOrderStatus.readyForApproval)
        .toList(growable: false)
      ..sort((left, right) {
        final leftTime = left.updatedAt?.millisecondsSinceEpoch ?? 0;
        final rightTime = right.updatedAt?.millisecondsSinceEpoch ?? 0;
        return rightTime.compareTo(leftTime);
      });
    return values;
  }

  Map<String, Map<String, dynamic>> _parseRawNodeMap(Object? raw) {
    if (raw is! Map) return const <String, Map<String, dynamic>>{};
    final result = <String, Map<String, dynamic>>{};
    raw.forEach((key, value) {
      if (value is! Map) return;
      result[key.toString()] = Map<String, dynamic>.from(value);
    });
    return result;
  }
}

Stream<R> _combineLatest<A, R>(
  Stream<A> first,
  Stream<dynamic> second,
  R Function(A firstValue, dynamic secondValue) combine,
) {
  late StreamController<R> controller;
  StreamSubscription<A>? firstSubscription;
  StreamSubscription<dynamic>? secondSubscription;
  A? firstValue;
  dynamic secondValue;
  var hasFirst = false;
  var hasSecond = false;

  void emitIfReady() {
    if (!hasFirst || !hasSecond) return;
    controller.add(combine(firstValue as A, secondValue));
  }

  controller = StreamController<R>(
    onListen: () {
      firstSubscription = first.listen(
        (value) {
          firstValue = value;
          hasFirst = true;
          emitIfReady();
        },
        onError: controller.addError,
      );
      secondSubscription = second.listen(
        (value) {
          secondValue = value;
          hasSecond = true;
          emitIfReady();
        },
        onError: controller.addError,
      );
    },
    onCancel: () async {
      await firstSubscription?.cancel();
      await secondSubscription?.cancel();
    },
  );

  return controller.stream;
}

Stream<T> _distinctBySignature<T>(
  Stream<T> source,
  String Function(T value) signatureOf,
) {
  late StreamController<T> controller;
  StreamSubscription<T>? subscription;
  String? lastSignature;

  controller = StreamController<T>(
    onListen: () {
      subscription = source.listen(
        (value) {
          final signature = signatureOf(value);
          if (lastSignature == signature) return;
          lastSignature = signature;
          controller.add(value);
        },
        onError: controller.addError,
      );
    },
    onCancel: () async {
      await subscription?.cancel();
    },
  );

  return controller.stream;
}

String _readyOrdersSignature(List<RequestOrder> orders) {
  return orders
      .map(
        (order) => [
          order.id,
          order.status.storageKey,
          order.updatedAt?.millisecondsSinceEpoch ?? 0,
          order.items.length,
          order.items
              .map(
                (item) => [
                  item.id,
                  item.supplierName ?? '',
                  item.estimatedAmount?.toString() ?? '',
                  item.isClosed ? '1' : '0',
                ].join(':'),
              )
              .join(','),
        ].join('|'),
      )
      .join('||');
}

String _packetBundlesSignature(List<PacketBundle> bundles) {
  return bundles
      .map(
        (bundle) => [
          bundle.packet.id,
          bundle.packet.folio ?? '',
          bundle.packet.status.storageKey,
          bundle.packet.version,
          bundle.packet.updatedAt?.millisecondsSinceEpoch ?? 0,
          bundle.packet.itemRefs
              .map(
                (item) => [
                  item.id,
                  item.closedAsUnpurchasable ? '1' : '0',
                ].join(':'),
              )
              .join(','),
          bundle.decisions
              .map(
                (decision) => [
                  decision.id,
                  decision.action.storageKey,
                  decision.timestamp.millisecondsSinceEpoch,
                ].join(':'),
              )
              .join(','),
        ].join('|'),
      )
      .join('||');
}

int _parseCounterValue(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) {
    return int.tryParse(raw.trim()) ?? 0;
  }
  return 0;
}

final purchasePacketsRepositoryProvider = Provider<PurchasePacketsRepository>((ref) {
  final database = ref.watch(firebaseDatabaseProvider);
  final company = ref.watch(currentCompanyProvider);
  return PurchasePacketsRepository(database, company);
});
