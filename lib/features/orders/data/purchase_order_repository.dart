import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/firebase_database_compat.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/domain/order_dashboard_counts.dart';
import 'package:sistema_compras/features/orders/domain/order_folio.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/domain/supplier_quote.dart';
import 'package:sistema_compras/features/orders/domain/supplier_quote_history_entry.dart';

class PurchaseOrderRepository {
  PurchaseOrderRepository(this._database, this._company);

  final AppDatabase _database;
  final Company _company;

  AppDatabaseRef get _ordersRef => _database.ref('purchaseOrders');
  AppDatabaseRef get _supplierQuotesRef => _database.ref('supplierQuotes');
  AppDatabaseRef get _supplierQuoteHistoryRef =>
      _database.ref('supplierQuoteHistory');
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
    return query.onValue.map((event) => _parseOrdersMap(event.snapshot.value));
  }

  Stream<List<PurchaseOrder>> watchAllOrders({int? limit}) {
    AppDatabaseQuery query = _ordersRef;
    if (limit != null && limit > 0) {
      query = query.limitToLast(limit);
    }
    return query.onValue.map((event) => _parseOrdersMap(event.snapshot.value));
  }

  Stream<List<PurchaseOrderEvent>> watchEvents(String orderId) {
    return _ordersRef.child('$orderId/events').onValue.map((event) {
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

      // Más antiguos primero (historial)
      events.sort((a, b) {
        final aTime = a.timestamp?.millisecondsSinceEpoch ?? 0;
        final bTime = b.timestamp?.millisecondsSinceEpoch ?? 0;
        return aTime.compareTo(bTime);
      });

      return events;
    });
  }

  Stream<List<PurchaseOrder>> watchOrdersByStatus(
    PurchaseOrderStatus status, {
    int? limit,
  }) {
    AppDatabaseQuery query = _ordersRef.orderByChild('status').equalTo(status.name);
    if (limit != null && limit > 0) {
      query = query.limitToLast(limit);
    }
    return query.onValue.map((event) => _parseOrdersMap(event.snapshot.value));
  }

  Stream<PurchaseOrder?> watchOrderById(String orderId) {
    return _ordersRef.child(orderId).onValue.map((event) {
      return _parseOrderEntry(orderId, event.snapshot.value);
    });
  }

  Stream<OrderDashboardCounts?> watchDashboardCounts({required String? userId}) {
    return _orderCountersRef.onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return null;
      return OrderDashboardCounts.fromMap(
        Map<String, dynamic>.from(value),
        userId: userId,
      );
    });
  }

  Future<PurchaseOrder?> fetchOrderById(String orderId) async {
    final snapshot = await _ordersRef.child(orderId).get();
    if (!snapshot.exists) return null;
    return _parseOrderEntry(orderId, snapshot.value);
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
          'status': PurchaseOrderStatus.pendingCompras.name,
          'isDraft': false,
          'updatedAt': appServerTimestamp,
          'visibility': {
            'contabilidad': false,
          },
          ...timingUpdate,
        });

        await _appendEvent(
          orderRef,
          fromStatus: PurchaseOrderStatus.draft,
          toStatus: PurchaseOrderStatus.pendingCompras,
          byUserId: requester.id,
          byRole: _actorRoleLabel(requester),
          type: 'advance',
          itemsSnapshot: items,
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
      'status': PurchaseOrderStatus.pendingCompras.name,
      'isDraft': false,
      'lastReturnReason': null,
      'returnCount': 0,
      'resubmissions': <int>[],
      'direccionReturnCount': 0,
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

    await _appendEvent(
      orderRef,
      fromStatus: PurchaseOrderStatus.draft,
      toStatus: PurchaseOrderStatus.pendingCompras,
      byUserId: requester.id,
      byRole: _actorRoleLabel(requester),
      type: 'advance',
      itemsSnapshot: items,
    );
    return orderId;
  }

  Future<void> requestEdit({
    required PurchaseOrder order,
    required String comment,
    required List<PurchaseOrderItem> items,
    required AppUser actor,
  }) async {
    if (order.returnCount >= _maxCorrections) {
      throw StateError('Máximo de correcciones alcanzado.');
    }

    final nextReturnCount = order.returnCount + 1;
    final orderRef = _ordersRef.child(order.id);
    final timingUpdate = _statusTimingUpdate(order);

    await orderRef.update({
      'status': PurchaseOrderStatus.draft.name,
      'isDraft': true,
      'lastReturnReason': comment.trim().isEmpty ? null : comment.trim(),
      'returnCount': nextReturnCount,
      'items': items.map((item) => item.toMap()).toList(),
      'updatedAt': appServerTimestamp,
      ...timingUpdate,
    });

    await _appendEvent(
      orderRef,
      fromStatus: order.status,
      toStatus: PurchaseOrderStatus.draft,
      byUserId: actor.id,
      byRole: _actorRoleLabel(actor),
      type: 'return',
      itemsSnapshot: items,
      comment: comment.trim().isEmpty ? null : comment.trim(),
    );

  }

  Future<void> updateApprovalData({
    required String orderId,
    required String? supplier,
    required num? budget,
    Map<String, num>? supplierBudgets,
    required String? comprasComment,
    required String? comprasReviewerName,
    String? comprasReviewerArea,
    String? internalOrder,
    List<PurchaseOrderItem>? items,
    bool markReady = false,
  }) async {
    final trimmedSupplier = supplier?.trim();
    final trimmedComment = comprasComment?.trim();
    final trimmedReviewer = comprasReviewerName?.trim();
    final trimmedInternal = internalOrder?.trim();
    final currentOrder = markReady ? await fetchOrderById(orderId) : null;

    final normalizedBudgets = _normalizeSupplierBudgets(supplierBudgets);
    final effectiveBudget = normalizedBudgets.isNotEmpty ? _sumBudgets(normalizedBudgets) : budget;

    final payload = <String, dynamic>{
      'supplier': (trimmedSupplier == null || trimmedSupplier.isEmpty) ? null : trimmedSupplier,
      'internalOrder': (trimmedInternal == null || trimmedInternal.isEmpty) ? null : trimmedInternal,
      'budget': effectiveBudget,
      'supplierBudgets': normalizedBudgets.isEmpty ? null : normalizedBudgets,
      'comprasComment': (trimmedComment == null || trimmedComment.isEmpty) ? null : trimmedComment,
      'comprasReviewerName': (trimmedReviewer == null || trimmedReviewer.isEmpty) ? null : trimmedReviewer,
      'comprasReviewerArea': (comprasReviewerArea == null || comprasReviewerArea.trim().isEmpty)
          ? null
          : comprasReviewerArea.trim(),
      'updatedAt': appServerTimestamp,
    };

    if (items != null) {
      payload['items'] = items.map((item) => item.toMap()).toList();
    }
    if (markReady) {
      payload['status'] = PurchaseOrderStatus.dataComplete.name;
      if (currentOrder != null && currentOrder.status != PurchaseOrderStatus.dataComplete) {
        payload.addAll(_statusTimingUpdate(currentOrder));
      }
    }

    await _ordersRef.child(orderId).update(payload);
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

    await _appendEvent(
      orderRef,
      fromStatus: order.status,
      toStatus: PurchaseOrderStatus.contabilidad,
      byUserId: actor.id,
      byRole: _actorRoleLabel(actor),
      type: 'advance',
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
      'completedAt': appServerTimestamp,
      'updatedAt': appServerTimestamp,
      ...timingUpdate,
    };
    if (items != null) {
      payload['items'] = items.map((item) => item.toMap()).toList();
      payload['internalOrder'] = null;
    }

    await orderRef.update(payload);

    await _appendEvent(
      orderRef,
      fromStatus: order.status,
      toStatus: PurchaseOrderStatus.eta,
      byUserId: actor.id,
      byRole: _actorRoleLabel(actor),
      type: 'advance',
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
      'completedAt': appServerTimestamp,
      'updatedAt': appServerTimestamp,
    });

    await _appendEvent(
      orderRef,
      fromStatus: order.status,
      toStatus: null,
      byUserId: actor.id,
      byRole: _actorRoleLabel(actor),
      type: 'received',
      comment: 'Orden confirmada como recibida por el solicitante.',
    );
  }

  Future<void> returnToCompras({
    required PurchaseOrder order,
    required String comment,
    required List<PurchaseOrderItem> items,
    required AppUser actor,
  }) async {
    if (order.returnCount >= _maxCorrections) {
      throw StateError('Máximo de correcciones alcanzado.');
    }

    final trimmed = comment.trim();
    final orderRef = _ordersRef.child(order.id);
    final nextDireccionReturnCount = order.direccionReturnCount + 1;
    final timingUpdate = _statusTimingUpdate(order);

    await orderRef.update({
      'status': PurchaseOrderStatus.pendingCompras.name,
      'direccionComment': trimmed.isEmpty ? null : trimmed,
      'processedByName': null,
      'processedByArea': null,
      'direccionGeneralName': null,
      'direccionGeneralArea': null,
      'direccionReturnCount': nextDireccionReturnCount,
      'items': items.map((item) => item.toMap()).toList(),
      'updatedAt': appServerTimestamp,
      ...timingUpdate,
    });

    await _appendEvent(
      orderRef,
      fromStatus: order.status,
      toStatus: PurchaseOrderStatus.pendingCompras,
      byUserId: actor.id,
      byRole: _actorRoleLabel(actor),
      type: 'return',
      itemsSnapshot: items,
      comment: trimmed.isEmpty ? null : trimmed,
    );

  }

  Future<void> returnToCotizaciones({
    required PurchaseOrder order,
    required String comment,
    required List<PurchaseOrderItem> items,
    required AppUser actor,
  }) async {
    final trimmed = comment.trim();
    final orderRef = _ordersRef.child(order.id);
    final nextDireccionReturnCount = order.direccionReturnCount + 1;
    final timingUpdate = _statusTimingUpdate(order);

    await orderRef.update({
      'status': PurchaseOrderStatus.cotizaciones.name,
      'direccionComment': trimmed.isEmpty ? null : trimmed,
      'processedByName': null,
      'processedByArea': null,
      'direccionGeneralName': null,
      'direccionGeneralArea': null,
      'direccionReturnCount': nextDireccionReturnCount,
      'items': items.map((item) => item.toMap()).toList(),
      'updatedAt': appServerTimestamp,
      ...timingUpdate,
    });

    await _appendEvent(
      orderRef,
      fromStatus: order.status,
      toStatus: PurchaseOrderStatus.cotizaciones,
      byUserId: actor.id,
      byRole: _actorRoleLabel(actor),
      type: 'return',
      itemsSnapshot: items,
      comment: trimmed.isEmpty ? null : trimmed,
    );

  }

  Stream<List<SupplierQuote>> watchSupplierQuotes() {
    return _supplierQuotesRef.onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <SupplierQuote>[];

      final quotes = <SupplierQuote>[];
      value.forEach((key, raw) {
        if (raw is Map) {
          quotes.add(
            SupplierQuote.fromMap(
              key.toString(),
              Map<String, dynamic>.from(raw),
            ),
          );
        }
      });

      quotes.sort((a, b) {
        final aTime = (a.updatedAt ?? a.createdAt)?.millisecondsSinceEpoch ?? 0;
        final bTime = (b.updatedAt ?? b.createdAt)?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });
      return quotes;
    });
  }

  Stream<SupplierQuote?> watchSupplierQuoteById(String quoteId) {
    return _supplierQuotesRef.child(quoteId).onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return null;
      return SupplierQuote.fromMap(quoteId, Map<String, dynamic>.from(value));
    });
  }

  Stream<List<SupplierQuoteHistoryEntry>> watchSupplierQuoteHistory(
    String quoteId,
  ) {
    return _supplierQuoteHistoryRef.child(quoteId).onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <SupplierQuoteHistoryEntry>[];

      final entries = <SupplierQuoteHistoryEntry>[];
      value.forEach((key, raw) {
        if (raw is Map) {
          entries.add(
            SupplierQuoteHistoryEntry.fromMap(
              key.toString(),
              Map<String, dynamic>.from(raw),
            ),
          );
        }
      });

      entries.sort((a, b) {
        final left = a.timestamp?.millisecondsSinceEpoch ??
            a.updatedAt?.millisecondsSinceEpoch ??
            a.createdAt?.millisecondsSinceEpoch ??
            0;
        final right = b.timestamp?.millisecondsSinceEpoch ??
            b.updatedAt?.millisecondsSinceEpoch ??
            b.createdAt?.millisecondsSinceEpoch ??
            0;
        return right.compareTo(left);
      });
      return entries;
    });
  }

  Future<SupplierQuote> createSupplierQuote({
    required String supplier,
    required List<SupplierQuoteItemRef> items,
    required List<String> links,
    String? comprasComment,
    AppUser? actor,
  }) async {
    final ref = _supplierQuotesRef.push();
    final quoteId = ref.key;
    if (quoteId == null || quoteId.isEmpty) {
      throw StateError('No se pudo crear la cotizacion del proveedor.');
    }
    final folio = await _reserveNextSupplierQuoteFolio(_database);

    final quote = SupplierQuote(
      id: quoteId,
      folio: folio,
      supplier: supplier.trim(),
      items: items,
      links: _sanitizeQuoteLinks(links),
      comprasComment: comprasComment,
      status: SupplierQuoteStatus.draft,
      version: 1,
    );
    await ref.set({
      ...quote.toMap(),
      'createdAt': appServerTimestamp,
      'updatedAt': appServerTimestamp,
    });
    await _appendSupplierQuoteHistorySnapshot(
      quote: quote,
      eventType: 'created',
      actor: actor,
    );
    await _syncQuoteItemsOnOrders(
      quote: quote,
      itemStatus: PurchaseOrderItemQuoteStatus.draft,
      clearRemovedItems: false,
    );
    return quote;
  }

  Future<void> updateSupplierQuoteDraft({
    required SupplierQuote quote,
    required List<SupplierQuoteItemRef> items,
    required List<String> links,
    String? comprasComment,
    AppUser? actor,
  }) async {
    final next = SupplierQuote(
      id: quote.id,
      folio: quote.folio,
      supplier: quote.supplier.trim(),
      items: items,
      links: _sanitizeQuoteLinks(links),
      comprasComment: comprasComment,
      status: SupplierQuoteStatus.draft,
      createdAt: quote.createdAt,
      updatedAt: quote.updatedAt,
      version: quote.version + 1,
    );
    await _supplierQuotesRef.child(quote.id).update({
      ...next.toMap(),
      'updatedAt': appServerTimestamp,
      'approvedAt': null,
      'approvedByName': null,
      'approvedByArea': null,
      'rejectionComment': null,
      'rejectedAt': null,
      'rejectedByName': null,
      'rejectedByArea': null,
      'processedByName': null,
      'processedByArea': null,
      'sentToDireccionAt': null,
    });
    await _appendSupplierQuoteHistorySnapshot(
      quote: next,
      eventType: 'draft_updated',
      actor: actor,
    );
    await _syncQuoteItemsOnOrders(
      quote: next,
      itemStatus: PurchaseOrderItemQuoteStatus.draft,
      clearRemovedItems: true,
    );
  }

  Future<void> sendSupplierQuoteToDireccion({
    required SupplierQuote quote,
    required AppUser actor,
  }) async {
    final links = _sanitizeQuoteLinks(quote.links);
    if (links.isEmpty) {
      throw StateError('Agrega al menos un link de cotizacion.');
    }
    final refsByOrder = <String, Set<int>>{};
    for (final ref in quote.items) {
      final orderId = ref.orderId.trim();
      if (orderId.isEmpty) continue;
      refsByOrder.putIfAbsent(orderId, () => <int>{}).add(ref.line);
    }

    final relatedOrders = await _fetchOrdersByIds(_database, refsByOrder.keys);
    for (final entry in refsByOrder.entries) {
      final orderId = entry.key;
      final order = relatedOrders[orderId];
      if (order == null) {
        throw StateError(
          'No se encontro la orden $orderId para enviar a Direccion General.',
        );
      }

      for (final line in entry.value) {
        PurchaseOrderItem? item;
        for (final candidate in order.items) {
          if (candidate.line == line) {
            item = candidate;
            break;
          }
        }
        if (item == null) {
          throw StateError(
            'No se encontro el item $line de la orden $orderId en esta cotizacion.',
          );
        }
        if (!_hasQuoteAssignmentData(item)) {
          throw StateError(
            'La orden $orderId aun tiene items seleccionados sin proveedor o presupuesto.',
          );
        }
        final quoteId = item.quoteId?.trim() ?? '';
        if (quoteId != quote.id ||
            item.quoteStatus == PurchaseOrderItemQuoteStatus.rejected) {
          throw StateError(
            'La orden $orderId aun tiene items seleccionados sin una cotizacion valida para enviar a Direccion General.',
          );
        }
      }
    }
    await _supplierQuotesRef.child(quote.id).update({
      'status': SupplierQuoteStatus.pendingDireccion.name,
      'links': links,
      'pdfUrls': links,
      'pdfUrl': links.first,
      'comprasComment': (quote.comprasComment?.trim().isEmpty ?? true)
          ? null
          : quote.comprasComment!.trim(),
      'processedByName': actor.name.trim().isEmpty ? null : actor.name.trim(),
      'processedByArea': actor.areaDisplay.trim().isEmpty
          ? null
          : actor.areaDisplay.trim(),
      'sentToDireccionAt': appServerTimestamp,
      'updatedAt': appServerTimestamp,
    });
    await _syncQuoteItemsOnOrders(
      quote: SupplierQuote(
        id: quote.id,
        folio: quote.folio,
        supplier: quote.supplier,
        items: quote.items,
        links: links,
        facturaLinks: quote.facturaLinks,
        comprasComment: quote.comprasComment,
        status: SupplierQuoteStatus.pendingDireccion,
        createdAt: quote.createdAt,
        updatedAt: quote.updatedAt,
        processedByName: actor.name,
        processedByArea: actor.areaDisplay,
        version: quote.version + 1,
      ),
      itemStatus: PurchaseOrderItemQuoteStatus.pendingDireccion,
      clearRemovedItems: false,
    );
    await _appendSupplierQuoteHistorySnapshot(
      quote: SupplierQuote(
        id: quote.id,
        folio: quote.folio,
        supplier: quote.supplier,
        items: quote.items,
        links: links,
        facturaLinks: quote.facturaLinks,
        comprasComment: quote.comprasComment,
        status: SupplierQuoteStatus.pendingDireccion,
        createdAt: quote.createdAt,
        updatedAt: quote.updatedAt,
        processedByName: actor.name,
        processedByArea: actor.areaDisplay,
        sentToDireccionAt: DateTime.now(),
        version: quote.version + 1,
      ),
      eventType: 'sent_to_direccion',
      actor: actor,
    );
  }

  Future<void> approveSupplierQuote({
    required SupplierQuote quote,
    required AppUser actor,
  }) async {
    await _supplierQuotesRef.child(quote.id).update({
      'status': SupplierQuoteStatus.approved.name,
      'approvedAt': appServerTimestamp,
      'approvedByName': actor.name.trim().isEmpty ? null : actor.name.trim(),
      'approvedByArea': actor.areaDisplay.trim().isEmpty
          ? null
          : actor.areaDisplay.trim(),
      'updatedAt': appServerTimestamp,
    });
    final approvedQuote = SupplierQuote(
      id: quote.id,
      folio: quote.folio,
      supplier: quote.supplier,
      items: quote.items,
      links: quote.links,
      facturaLinks: quote.facturaLinks,
      comprasComment: quote.comprasComment,
      status: SupplierQuoteStatus.approved,
      createdAt: quote.createdAt,
      updatedAt: quote.updatedAt,
      approvedAt: DateTime.now(),
      approvedByName: actor.name,
      approvedByArea: actor.areaDisplay,
      processedByName: quote.processedByName,
      processedByArea: quote.processedByArea,
      sentToDireccionAt: quote.sentToDireccionAt,
      version: quote.version + 1,
    );
    await _syncQuoteItemsOnOrders(
      quote: approvedQuote,
      itemStatus: PurchaseOrderItemQuoteStatus.approved,
      clearRemovedItems: false,
      approver: actor,
    );
    await _appendSupplierQuoteHistorySnapshot(
      quote: approvedQuote,
      eventType: 'approved',
      actor: actor,
    );
  }

  Future<void> setSupplierQuoteDeliveryEta({
    required SupplierQuote quote,
    required DateTime etaDate,
    required AppUser actor,
  }) async {
    final normalizedEta = DateTime(etaDate.year, etaDate.month, etaDate.day);
    final refsByOrder = <String, Set<int>>{};
    for (final ref in quote.items) {
      final orderId = ref.orderId.trim();
      if (orderId.isEmpty) continue;
      refsByOrder.putIfAbsent(orderId, () => <int>{}).add(ref.line);
    }

    for (final entry in refsByOrder.entries) {
      final order = await fetchOrderById(entry.key);
      if (order == null) continue;

      final targetLines = entry.value;
      var changed = false;
      final updatedItems = <PurchaseOrderItem>[];
      for (final item in order.items) {
        if (targetLines.contains(item.line) &&
            (item.quoteId?.trim() ?? '') == quote.id &&
            item.quoteStatus == PurchaseOrderItemQuoteStatus.approved) {
          changed = true;
          updatedItems.add(
            item.copyWith(
              deliveryEtaDate: normalizedEta,
              clearSentToContabilidadAt: true,
            ),
          );
          continue;
        }
        updatedItems.add(item);
      }
      if (!changed) continue;

      final nextStatus = _statusForDeliveryEtaProgress(updatedItems);
      final committedEta = _resolveCommittedDeliveryDate(updatedItems);
      final updates = <String, Object?>{
        'items': updatedItems.map((item) => item.toMap()).toList(),
        'etaDate': committedEta?.millisecondsSinceEpoch,
        'status': nextStatus.name,
        'updatedAt': appServerTimestamp,
      };
      if (nextStatus != order.status) {
        updates.addAll(_statusTimingUpdate(order));
      }

      final orderRef = _ordersRef.child(order.id);
      await orderRef.update(updates);

      if (nextStatus != order.status) {
        await _appendEvent(
          orderRef,
          fromStatus: order.status,
          toStatus: nextStatus,
          byUserId: actor.id,
          byRole: _actorRoleLabel(actor),
          type: 'advance',
          itemsSnapshot: updatedItems,
          comment: nextStatus == PurchaseOrderStatus.contabilidad
              ? 'Todos los items ya tienen fecha estimada de entrega.'
              : 'Fecha estimada de entrega actualizada por proveedor.',
        );
      }
    }
  }

  Future<void> sendSupplierQuoteItemsToContabilidad({
    required SupplierQuote quote,
    required DateTime etaDate,
    required AppUser actor,
    required Map<String, Set<int>> selectedLinesByOrder,
  }) async {
    final normalizedEta = DateTime(etaDate.year, etaDate.month, etaDate.day);
    final sentAt = DateTime.now();
    var sentItemsCount = 0;

    for (final entry in selectedLinesByOrder.entries) {
      final order = await fetchOrderById(entry.key);
      if (order == null) continue;

      final targetLines = entry.value;
      if (targetLines.isEmpty) continue;

      var changed = false;
      final updatedItems = <PurchaseOrderItem>[];
      for (final item in order.items) {
        final matchesTarget = targetLines.contains(item.line) &&
            (item.quoteId?.trim() ?? '') == quote.id &&
            item.quoteStatus == PurchaseOrderItemQuoteStatus.approved;
        if (matchesTarget) {
          changed = true;
          sentItemsCount += 1;
          updatedItems.add(
            item.copyWith(
              deliveryEtaDate: normalizedEta,
              sentToContabilidadAt: sentAt,
            ),
          );
          continue;
        }
        updatedItems.add(item);
      }
      if (!changed) continue;

      final nextStatus = _statusForDeliveryEtaProgress(updatedItems);
      final committedEta = _resolveCommittedDeliveryDate(updatedItems);
      final orderRef = _ordersRef.child(order.id);
      await orderRef.update({
        'items': updatedItems.map((item) => item.toMap()).toList(),
        'etaDate': committedEta?.millisecondsSinceEpoch,
        'status': nextStatus.name,
        'updatedAt': appServerTimestamp,
        if (nextStatus != order.status) ..._statusTimingUpdate(order),
      });

      await _appendEvent(
        orderRef,
        fromStatus: order.status,
        toStatus: nextStatus,
        byUserId: actor.id,
        byRole: _actorRoleLabel(actor),
        type: 'advance',
        itemsSnapshot: updatedItems,
        comment:
            '${targetLines.length} item(s) enviados a Contabilidad con fecha estimada.',
      );
    }

    if (sentItemsCount > 0) {
      await _appendSupplierQuoteHistorySnapshot(
        quote: SupplierQuote(
          id: quote.id,
          folio: quote.folio,
          supplier: quote.supplier,
          items: quote.items,
          links: quote.links,
          facturaLinks: quote.facturaLinks,
          comprasComment: quote.comprasComment,
          status: quote.status,
          createdAt: quote.createdAt,
          updatedAt: sentAt,
          processedByName: quote.processedByName,
          processedByArea: quote.processedByArea,
          sentToDireccionAt: quote.sentToDireccionAt,
          approvedAt: quote.approvedAt,
          approvedByName: quote.approvedByName,
          approvedByArea: quote.approvedByArea,
          rejectionComment: quote.rejectionComment,
          rejectedAt: quote.rejectedAt,
          rejectedByName: quote.rejectedByName,
          rejectedByArea: quote.rejectedByArea,
          version: quote.version,
        ),
        eventType: 'items_sent_to_contabilidad',
        actor: actor,
        comment:
            '$sentItemsCount item(s) enviados a Contabilidad con fecha estimada registrada.',
      );
    }
  }

  Future<void> saveSupplierQuoteFacturaLinks({
    required SupplierQuote quote,
    required List<String> links,
    AppUser? actor,
  }) async {
    final cleaned = _sanitizeQuoteLinks(links);
    await _supplierQuotesRef.child(quote.id).update({
      'facturaLinks': cleaned.isEmpty ? null : cleaned,
      'updatedAt': appServerTimestamp,
    });
    await _appendSupplierQuoteHistorySnapshot(
      quote: SupplierQuote(
        id: quote.id,
        folio: quote.folio,
        supplier: quote.supplier,
        items: quote.items,
        links: quote.links,
        facturaLinks: cleaned,
        comprasComment: quote.comprasComment,
        status: quote.status,
        createdAt: quote.createdAt,
        updatedAt: DateTime.now(),
        processedByName: quote.processedByName,
        processedByArea: quote.processedByArea,
        sentToDireccionAt: quote.sentToDireccionAt,
        approvedAt: quote.approvedAt,
        approvedByName: quote.approvedByName,
        approvedByArea: quote.approvedByArea,
        rejectionComment: quote.rejectionComment,
        rejectedAt: quote.rejectedAt,
        rejectedByName: quote.rejectedByName,
        rejectedByArea: quote.rejectedByArea,
        version: quote.version,
      ),
      eventType: 'factura_links_updated',
      actor: actor,
    );
  }

  Future<void> returnSupplierQuoteItemsFromContabilidad({
    required SupplierQuote quote,
    required AppUser actor,
    required String comment,
  }) async {
    final trimmedComment = comment.trim();
    final relatedOrders = await _fetchOrdersByIds(_database, quote.orderIds);
    var returnedItemsCount = 0;

    for (final order in relatedOrders.values) {
      var changed = false;
      final updatedItems = <PurchaseOrderItem>[];
      for (final item in order.items) {
        final matchesQuote = (item.quoteId?.trim() ?? '') == quote.id &&
            item.quoteStatus == PurchaseOrderItemQuoteStatus.approved &&
            item.sentToContabilidadAt != null;
        if (matchesQuote) {
          changed = true;
          returnedItemsCount += 1;
          updatedItems.add(
            item.copyWith(
              clearSentToContabilidadAt: true,
            ),
          );
          continue;
        }
        updatedItems.add(item);
      }
      if (!changed) continue;

      final nextStatus = _statusForDeliveryEtaProgress(updatedItems);
      final orderRef = _ordersRef.child(order.id);
      final baseComment = trimmedComment.isEmpty
          ? 'Agrupacion regresada desde Contabilidad.'
          : trimmedComment;
      final eventComment = nextStatus == order.status
          ? '$baseComment La orden permanece en Contabilidad por items de otros proveedores.'
          : baseComment;

      await orderRef.update({
        'items': updatedItems.map((item) => item.toMap()).toList(),
        'etaDate': _resolveCommittedDeliveryDate(updatedItems)?.millisecondsSinceEpoch,
        'status': nextStatus.name,
        'updatedAt': appServerTimestamp,
        if (nextStatus != order.status) ..._statusTimingUpdate(order),
      });

      await _appendEvent(
        orderRef,
        fromStatus: order.status,
        toStatus: nextStatus,
        byUserId: actor.id,
        byRole: _actorRoleLabel(actor),
        type: 'return',
        itemsSnapshot: updatedItems,
        comment: eventComment,
      );
    }

    if (returnedItemsCount <= 0) return;

    await _supplierQuotesRef.child(quote.id).update({
      'facturaLinks': null,
      'updatedAt': appServerTimestamp,
    });

    await _appendSupplierQuoteHistorySnapshot(
      quote: SupplierQuote(
        id: quote.id,
        folio: quote.folio,
        supplier: quote.supplier,
        items: quote.items,
        links: quote.links,
        facturaLinks: const <String>[],
        comprasComment: quote.comprasComment,
        status: quote.status,
        createdAt: quote.createdAt,
        updatedAt: DateTime.now(),
        processedByName: quote.processedByName,
        processedByArea: quote.processedByArea,
        sentToDireccionAt: quote.sentToDireccionAt,
        approvedAt: quote.approvedAt,
        approvedByName: quote.approvedByName,
        approvedByArea: quote.approvedByArea,
        rejectionComment: quote.rejectionComment,
        rejectedAt: quote.rejectedAt,
        rejectedByName: quote.rejectedByName,
        rejectedByArea: quote.rejectedByArea,
        version: quote.version,
      ),
      eventType: 'returned_from_contabilidad',
      actor: actor,
      comment: trimmedComment,
    );
  }

  Future<void> saveInternalOrderForItems({
    required PurchaseOrder order,
    required Set<int> lines,
    required String? internalOrder,
  }) async {
    if (lines.isEmpty) return;
    final trimmed = internalOrder?.trim() ?? '';
    var changed = false;
    final updatedItems = <PurchaseOrderItem>[];
    for (final item in order.items) {
      if (!lines.contains(item.line)) {
        updatedItems.add(item);
        continue;
      }
      changed = true;
      updatedItems.add(
        trimmed.isEmpty
            ? item.copyWith(clearInternalOrder: true)
            : item.copyWith(internalOrder: trimmed),
      );
    }
    if (!changed) return;

    await _ordersRef.child(order.id).update({
      'items': updatedItems.map((item) => item.toMap()).toList(),
      'updatedAt': appServerTimestamp,
    });
  }

  Future<void> rejectSupplierQuote({
    required SupplierQuote quote,
    required String comment,
    required AppUser actor,
  }) async {
    final trimmedComment = comment.trim();
    final rejectedQuote = SupplierQuote(
      id: quote.id,
      folio: quote.folio,
      supplier: quote.supplier,
      items: quote.items,
      links: quote.links,
      facturaLinks: quote.facturaLinks,
      comprasComment: quote.comprasComment,
      status: SupplierQuoteStatus.rejected,
      createdAt: quote.createdAt,
      updatedAt: quote.updatedAt,
      rejectionComment: trimmedComment,
      rejectedAt: DateTime.now(),
      rejectedByName: actor.name,
      rejectedByArea: actor.areaDisplay,
      processedByName: quote.processedByName,
      processedByArea: quote.processedByArea,
      sentToDireccionAt: quote.sentToDireccionAt,
      version: quote.version + 1,
    );
    await _supplierQuotesRef.child(quote.id).update({
      'status': SupplierQuoteStatus.rejected.name,
      'rejectionComment': trimmedComment.isEmpty ? null : trimmedComment,
      'rejectedAt': appServerTimestamp,
      'rejectedByName': actor.name.trim().isEmpty ? null : actor.name.trim(),
      'rejectedByArea': actor.areaDisplay.trim().isEmpty
          ? null
          : actor.areaDisplay.trim(),
      'updatedAt': appServerTimestamp,
    });
    await _syncQuoteItemsOnOrders(
      quote: rejectedQuote,
      itemStatus: PurchaseOrderItemQuoteStatus.rejected,
      clearRemovedItems: false,
      eventActor: actor,
      eventType: 'return',
      eventComment: trimmedComment,
    );
    await _appendSupplierQuoteHistorySnapshot(
      quote: rejectedQuote,
      eventType: 'rejected',
      actor: actor,
      comment: trimmedComment,
    );
  }

  Future<void> deleteSupplierQuote({
    required SupplierQuote quote,
  }) async {
    await _appendSupplierQuoteHistorySnapshot(
      quote: quote,
      eventType: 'deleted',
    );
    await _clearQuoteItemsOnOrders(quote.id);
    await _supplierQuotesRef.child(quote.id).remove();
  }

  Future<void> cancelSupplierQuoteToCotizaciones({
    required SupplierQuote quote,
    required AppUser actor,
  }) async {
    await _appendSupplierQuoteHistorySnapshot(
      quote: quote,
      eventType: 'returned_to_cotizaciones',
      actor: actor,
      comment: 'Cotizacion cancelada desde dashboard de compras.',
    );
    final relatedOrders = await _fetchOrdersByIds(_database, quote.orderIds);
    for (final order in relatedOrders.values) {
      final updatedItems = <PurchaseOrderItem>[];
      var changed = false;
      for (final item in order.items) {
        if (item.quoteId == quote.id) {
          changed = true;
          updatedItems.add(
            item.copyWith(
              quoteId: null,
              clearQuoteId: true,
              quoteStatus: PurchaseOrderItemQuoteStatus.pending,
              clearDeliveryEtaDate: true,
              clearSentToContabilidadAt: true,
            ),
          );
        } else {
          updatedItems.add(item);
        }
      }
      if (!changed) continue;

      final orderRef = _ordersRef.child(order.id);
      final timingUpdate = _statusTimingUpdate(order);
      await orderRef.update({
        'status': PurchaseOrderStatus.cotizaciones.name,
        'processedByName': null,
        'processedByArea': null,
        'direccionGeneralName': null,
        'direccionGeneralArea': null,
        'items': updatedItems.map((item) => item.toMap()).toList(),
        'updatedAt': appServerTimestamp,
        ...timingUpdate,
      });

      await _appendEvent(
        orderRef,
        fromStatus: order.status,
        toStatus: PurchaseOrderStatus.cotizaciones,
        byUserId: actor.id,
        byRole: _actorRoleLabel(actor),
        type: 'return',
        itemsSnapshot: updatedItems,
        comment: 'Cotizacion cancelada desde dashboard de compras.',
      );
    }

    await _supplierQuotesRef.child(quote.id).remove();
  }


  Future<void> transitionStatus({
    required PurchaseOrder order,
    required PurchaseOrderStatus targetStatus,
    required AppUser actor,
    String? comprasReviewerName,
    String? comprasReviewerArea,
  }) async {
    final orderRef = _ordersRef.child(order.id);
    final timingUpdate = _statusTimingUpdate(order);
    final trimmedReviewer = comprasReviewerName?.trim();
    final trimmedArea = comprasReviewerArea?.trim();

    final payload = <String, Object?>{
      'status': targetStatus.name,
      'isDraft': targetStatus == PurchaseOrderStatus.draft,
      'updatedAt': appServerTimestamp,
      ...timingUpdate,
    };
    if (trimmedReviewer != null && trimmedReviewer.isNotEmpty) {
      payload['comprasReviewerName'] = trimmedReviewer;
    }
    if (trimmedArea != null && trimmedArea.isNotEmpty) {
      payload['comprasReviewerArea'] = trimmedArea;
    }

    final eventRef = orderRef.child('events').push();
    final eventKey = eventRef.key;
    if (eventKey == null) {
      await orderRef.update(payload);
      await _appendEvent(
        orderRef,
        fromStatus: order.status,
        toStatus: targetStatus,
        byUserId: actor.id,
        byRole: _actorRoleLabel(actor),
        type: 'advance',
      );
      return;
    }

    final eventPayload = <String, dynamic>{
      'fromStatus': order.status.name,
      'toStatus': targetStatus.name,
      'byUserId': actor.id,
      'byRole': _actorRoleLabel(actor),
      'timestamp': appServerTimestamp,
      'type': 'advance',
    };

    final updates = <String, Object?>{};
    for (final entry in payload.entries) {
      updates['purchaseOrders/${order.id}/${entry.key}'] = entry.value;
    }
    updates['purchaseOrders/${order.id}/events/$eventKey'] = eventPayload;

    await _database.ref().update(updates);
  }


  List<String> _sanitizeQuoteLinks(List<String> links) {
    return links
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  Future<void> _appendSupplierQuoteHistorySnapshot({
    required SupplierQuote quote,
    required String eventType,
    AppUser? actor,
    String? comment,
  }) async {
    final relatedOrders = await _fetchOrdersByIds(_database, quote.orderIds);
    final ref = _supplierQuoteHistoryRef.child(quote.id).push();
    final snapshotKey = ref.key;
    if (snapshotKey == null || snapshotKey.isEmpty) return;

    final ordersPayload = _buildSupplierQuoteHistoryOrders(
      quote: quote,
      relatedOrders: relatedOrders,
    );
    final actorName = actor?.name.trim() ?? '';
    final actorArea = actor?.areaDisplay.trim() ?? '';

    await ref.set({
      'quoteId': quote.id,
      'folio': quote.displayId,
      'eventType': eventType,
      'status': quote.status.name,
      'supplier': quote.supplier.trim(),
      'links': quote.links.isEmpty ? null : quote.links,
      'facturaLinks': quote.facturaLinks.isEmpty ? null : quote.facturaLinks,
      'orderIds': quote.orderIds,
      'orderCount': ordersPayload.length,
      'itemCount': quote.items.length,
      'totalAmount': quote.totalAmount,
      'version': quote.version,
      'comprasComment': (quote.comprasComment?.trim().isEmpty ?? true)
          ? null
          : quote.comprasComment!.trim(),
      'comment': comment?.trim().isEmpty ?? true ? null : comment!.trim(),
      'createdAt': quote.createdAt?.millisecondsSinceEpoch,
      'updatedAt': quote.updatedAt?.millisecondsSinceEpoch,
      'sentToDireccionAt': quote.sentToDireccionAt?.millisecondsSinceEpoch,
      'approvedAt': quote.approvedAt?.millisecondsSinceEpoch,
      'approvedByName': quote.approvedByName,
      'approvedByArea': quote.approvedByArea,
      'rejectedAt': quote.rejectedAt?.millisecondsSinceEpoch,
      'rejectedByName': quote.rejectedByName,
      'rejectedByArea': quote.rejectedByArea,
      'processedByName': quote.processedByName,
      'processedByArea': quote.processedByArea,
      'actorName': actorName.isEmpty ? null : actorName,
      'actorArea': actorArea.isEmpty ? null : actorArea,
      'pdfSuggestedName': 'cotizacion_${quote.displayId}.pdf',
      'orders': ordersPayload,
      'timestamp': appServerTimestamp,
    });
  }

  List<Map<String, Object?>> _buildSupplierQuoteHistoryOrders({
    required SupplierQuote quote,
    required Map<String, PurchaseOrder> relatedOrders,
  }) {
    final refsByOrder = <String, List<SupplierQuoteItemRef>>{};
    for (final ref in quote.items) {
      final orderId = ref.orderId.trim();
      if (orderId.isEmpty) continue;
      refsByOrder.putIfAbsent(orderId, () => <SupplierQuoteItemRef>[]).add(ref);
    }

    final ordersPayload = <Map<String, Object?>>[];
    for (final entry in refsByOrder.entries) {
      final order = relatedOrders[entry.key];
      final refs = entry.value;
      refs.sort((a, b) => a.line.compareTo(b.line));
      ordersPayload.add({
        'orderId': entry.key,
        'requesterName': order?.requesterName,
        'areaName': order?.areaName,
        'status': order?.status.name,
        'items': [
          for (final ref in refs)
            {
              'line': ref.line,
              'description': ref.description,
              'quantity': ref.quantity,
              'unit': ref.unit,
              'partNumber': ref.partNumber,
              'amount': ref.amount,
            },
        ],
      });
    }
    ordersPayload.sort((a, b) {
      final left = (a['orderId'] as String? ?? '');
      final right = (b['orderId'] as String? ?? '');
      return left.compareTo(right);
    });
    return ordersPayload;
  }

  Future<void> _syncQuoteItemsOnOrders({
    required SupplierQuote quote,
    required PurchaseOrderItemQuoteStatus itemStatus,
    required bool clearRemovedItems,
    AppUser? approver,
    AppUser? eventActor,
    String? eventType,
    String? eventComment,
  }) async {
    final refsByOrder = <String, Map<int, SupplierQuoteItemRef>>{};
    for (final ref in quote.items) {
      final orderId = ref.orderId.trim();
      if (orderId.isEmpty) continue;
      refsByOrder.putIfAbsent(orderId, () => <int, SupplierQuoteItemRef>{})[ref.line] = ref;
    }

    for (final entry in refsByOrder.entries) {
      final order = await fetchOrderById(entry.key);
      if (order == null) continue;

      final refsByLine = entry.value;
      final updatedItems = <PurchaseOrderItem>[];
      for (final item in order.items) {
        final ref = refsByLine[item.line];
        if (ref != null) {
          updatedItems.add(
            item.copyWith(
              supplier: quote.supplier.trim().isEmpty ? item.supplier : quote.supplier.trim(),
              budget: ref.amount ?? item.budget,
              quoteId: quote.id,
              quoteStatus: itemStatus,
              clearDeliveryEtaDate:
                  itemStatus != PurchaseOrderItemQuoteStatus.approved,
              clearSentToContabilidadAt:
                  itemStatus != PurchaseOrderItemQuoteStatus.approved,
            ),
          );
          continue;
        }

        if (clearRemovedItems && item.quoteId == quote.id) {
          updatedItems.add(
            item.copyWith(
              quoteId: null,
              clearQuoteId: true,
              quoteStatus: PurchaseOrderItemQuoteStatus.pending,
              clearDeliveryEtaDate: true,
              clearSentToContabilidadAt: true,
            ),
          );
          continue;
        }

        updatedItems.add(item);
      }

      final updates = <String, Object?>{
        'items': updatedItems.map((item) => item.toMap()).toList(),
        'etaDate': _resolveCommittedDeliveryDate(updatedItems)?.millisecondsSinceEpoch,
        'updatedAt': appServerTimestamp,
      };
      final nextStatus = _statusForQuoteProgress(updatedItems);

      if (itemStatus == PurchaseOrderItemQuoteStatus.pendingDireccion) {
        updates['processedByName'] = quote.processedByName?.trim().isEmpty ?? true
            ? null
            : quote.processedByName!.trim();
        updates['processedByArea'] = quote.processedByArea?.trim().isEmpty ?? true
            ? null
            : quote.processedByArea!.trim();
      }

      updates['status'] = nextStatus.name;
      if (nextStatus != order.status) {
        updates.addAll(_statusTimingUpdate(order));
      }
      if (nextStatus == PurchaseOrderStatus.paymentDone) {
        updates['direccionGeneralName'] = approver?.name.trim().isEmpty ?? true
            ? null
            : approver!.name.trim();
        updates['direccionGeneralArea'] =
            approver?.areaDisplay.trim().isEmpty ?? true
                ? null
                : approver!.areaDisplay.trim();
      }

      await _ordersRef.child(order.id).update(updates);

      final trimmedEventType = eventType?.trim() ?? '';
      if (trimmedEventType.isNotEmpty && eventActor != null) {
        await _appendEvent(
          _ordersRef.child(order.id),
          fromStatus: order.status,
          toStatus: nextStatus,
          byUserId: eventActor.id,
          byRole: _actorRoleLabel(eventActor),
          type: trimmedEventType,
          itemsSnapshot: updatedItems,
          comment: eventComment,
        );
      }
    }
  }

  Future<void> _clearQuoteItemsOnOrders(String quoteId) async {
    final orders = await watchAllOrders().first;
    for (final order in orders) {
      var changed = false;
      final updatedItems = <PurchaseOrderItem>[];
      for (final item in order.items) {
        if (item.quoteId == quoteId) {
          changed = true;
          updatedItems.add(
            item.copyWith(
              quoteId: null,
              clearQuoteId: true,
              quoteStatus: PurchaseOrderItemQuoteStatus.pending,
              clearDeliveryEtaDate: true,
              clearSentToContabilidadAt: true,
            ),
          );
        } else {
          updatedItems.add(item);
        }
      }
      if (!changed) continue;
      final nextStatus = _statusForQuoteProgress(updatedItems);
      await _ordersRef.child(order.id).update({
        'items': updatedItems.map((item) => item.toMap()).toList(),
        'etaDate': _resolveCommittedDeliveryDate(updatedItems)?.millisecondsSinceEpoch,
        'status': nextStatus.name,
        'updatedAt': appServerTimestamp,
        if (nextStatus != order.status) ..._statusTimingUpdate(order),
      });
    }
  }

  Future<void> deleteOrder(String orderId) async {
    await _ordersRef.child(orderId).remove();
  }
}

final purchaseOrderRepositoryProvider = Provider<PurchaseOrderRepository>((ref) {
  final database = ref.watch(firebaseDatabaseProvider);
  return PurchaseOrderRepository(database, Company.chabely);
});

Future<String> _reserveNextFolio(AppDatabase database, Company company) async {
  final counterRef = database.ref('counters/folios/purchaseOrderNext');
  final currentSnapshot = await counterRef.get();
  final snapshotValue = _parseCounterValue(currentSnapshot.value);
  final legacySeed = snapshotValue > 0 ? 0 : await _resolveLegacyMax(database);

  final result = await counterRef.runTransaction((current) {
    final base = _parseCounterValue(current);
    final effective = base > 0 ? base : legacySeed;
    final next = effective + 1;
    return next;
  });

  if (!result.committed) throw StateError('No se pudo generar el folio.');

  final nextValue = _parseCounterValue(result.snapshot.value);
  if (nextValue <= 0) throw StateError('Folio inválido.');

  return formatFolio(company, nextValue);
}

Future<String> _reserveNextSupplierQuoteFolio(AppDatabase database) async {
  final counterRef = database.ref('counters/folios/supplierQuoteNext');
  final result = await counterRef.runTransaction((current) {
    final base = _parseCounterValue(current);
    final next = base + 1;
    return next;
  });

  if (!result.committed) {
    throw StateError('No se pudo generar el folio de cotizacion.');
  }

  final nextValue = _parseCounterValue(result.snapshot.value);
  if (nextValue <= 0) {
    throw StateError('Folio de cotizacion invalido.');
  }

  return 'CP-${nextValue.toString().padLeft(6, '0')}';
}

int _parseCounterValue(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) {
    final parsed = int.tryParse(raw);
    if (parsed != null) return parsed;
  }
  return 0;
}

Map<String, num> _normalizeSupplierBudgets(Map<String, num>? raw) {
  if (raw == null || raw.isEmpty) return const {};
  final normalized = <String, num>{};
  for (final entry in raw.entries) {
    final key = entry.key.trim();
    if (key.isEmpty) continue;
    normalized[key] = entry.value;
  }
  return normalized;
}

num _sumBudgets(Map<String, num> budgets) {
  var total = 0.0;
  for (final value in budgets.values) {
    total += value.toDouble();
  }
  return total;
}

bool _hasQuoteAssignmentData(PurchaseOrderItem item) {
  final supplier = (item.supplier ?? '').trim();
  final budget = item.budget ?? 0;
  return supplier.isNotEmpty && budget > 0;
}


bool _hasSentToContabilidad(PurchaseOrderItem item) {
  return item.sentToContabilidadAt != null;
}

PurchaseOrderStatus _statusForQuoteProgress(List<PurchaseOrderItem> items) {
  if (items.isEmpty) return PurchaseOrderStatus.cotizaciones;
  if (items.any((item) => !_hasQuoteAssignmentData(item))) {
    return PurchaseOrderStatus.cotizaciones;
  }

  final allApproved = items.every(
    (item) =>
        (item.quoteId?.trim().isNotEmpty ?? false) &&
        item.quoteStatus == PurchaseOrderItemQuoteStatus.approved,
  );
  if (allApproved) {
    return PurchaseOrderStatus.paymentDone;
  }

  final allSentToDireccion = items.every(
    (item) =>
        (item.quoteId?.trim().isNotEmpty ?? false) &&
        (item.quoteStatus == PurchaseOrderItemQuoteStatus.pendingDireccion ||
            item.quoteStatus == PurchaseOrderItemQuoteStatus.approved),
  );
  if (allSentToDireccion) {
    return PurchaseOrderStatus.authorizedGerencia;
  }

  return PurchaseOrderStatus.dataComplete;
}

PurchaseOrderStatus _statusForDeliveryEtaProgress(List<PurchaseOrderItem> items) {
  if (items.isEmpty) return PurchaseOrderStatus.paymentDone;
  final allApproved = items.every(
    (item) =>
        (item.quoteId?.trim().isNotEmpty ?? false) &&
        item.quoteStatus == PurchaseOrderItemQuoteStatus.approved,
  );
  if (!allApproved) {
    return _statusForQuoteProgress(items);
  }

  final anySentToContabilidad = items.any(_hasSentToContabilidad);
  return anySentToContabilidad
      ? PurchaseOrderStatus.contabilidad
      : PurchaseOrderStatus.paymentDone;
}

DateTime? _resolveCommittedDeliveryDate(List<PurchaseOrderItem> items) {
  DateTime? selected;
  for (final item in items) {
    final date = item.deliveryEtaDate;
    if (date == null) continue;
    final normalized = DateTime(date.year, date.month, date.day);
    if (selected == null || normalized.isAfter(selected)) {
      selected = normalized;
    }
  }
  return selected;
}

Future<Map<String, PurchaseOrder>> _fetchOrdersByIds(
  AppDatabase database,
  Iterable<String> orderIds,
) async {
  final ordersById = <String, PurchaseOrder>{};
  for (final rawOrderId in orderIds) {
    final orderId = rawOrderId.trim();
    if (orderId.isEmpty) continue;
    final snapshot = await database.ref('purchaseOrders/$orderId').get();
    if (!snapshot.exists || snapshot.value is! Map) continue;
    ordersById[orderId] = PurchaseOrder.fromMap(
      orderId,
      Map<String, dynamic>.from(snapshot.value as Map),
    );
  }
  return ordersById;
}

Future<int> _resolveLegacyMax(AppDatabase database) async {
  var maxValue = 0;
  for (final company in Company.values) {
    final snapshot = await database.ref('counters/folios/${company.name}/purchaseOrderNext').get();
    final value = _parseCounterValue(snapshot.value);
    if (value > maxValue) maxValue = value;
  }
  return maxValue;
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


const _maxCorrections = 3;


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
