import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/domain/order_folio.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/domain/shared_quote.dart';

class PurchaseOrderRepository {
  PurchaseOrderRepository(this._database, this._company);

  final FirebaseDatabase _database;
  final Company _company;

  DatabaseReference get _ordersRef => _database.ref('purchaseOrders');
  DatabaseReference get _sharedQuotesRef => _database.ref('sharedQuotes');

  Stream<List<PurchaseOrder>> watchOrdersForUser(String uid) {
    return _ordersRef.orderByChild('requesterId').equalTo(uid).onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <PurchaseOrder>[];

      final orders = <PurchaseOrder>[];
      value.forEach((key, raw) {
        if (raw is Map) {
          orders.add(
            PurchaseOrder.fromMap(
              key.toString(),
              Map<String, dynamic>.from(raw),
            ),
          );
        }
      });

      // Más recientes primero
      orders.sort((a, b) {
        final aTime = (a.updatedAt ?? a.createdAt)?.millisecondsSinceEpoch ?? 0;
        final bTime = (b.updatedAt ?? b.createdAt)?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });

      return orders;
    });
  }

  Stream<List<PurchaseOrder>> watchAllOrders() {
    return _ordersRef.onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <PurchaseOrder>[];

      final orders = <PurchaseOrder>[];
      value.forEach((key, raw) {
        if (raw is Map) {
          orders.add(
            PurchaseOrder.fromMap(
              key.toString(),
              Map<String, dynamic>.from(raw),
            ),
          );
        }
      });

      orders.sort((a, b) {
        final aTime = (a.updatedAt ?? a.createdAt)?.millisecondsSinceEpoch ?? 0;
        final bTime = (b.updatedAt ?? b.createdAt)?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });

      return orders;
    });
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

  Stream<List<PurchaseOrder>> watchOrdersByStatus(PurchaseOrderStatus status) {
    return _ordersRef.orderByChild('status').equalTo(status.name).onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <PurchaseOrder>[];

      final orders = <PurchaseOrder>[];
      value.forEach((key, raw) {
        if (raw is Map) {
          orders.add(
            PurchaseOrder.fromMap(
              key.toString(),
              Map<String, dynamic>.from(raw),
            ),
          );
        }
      });

      orders.sort((a, b) {
        final aTime = (a.updatedAt ?? a.createdAt)?.millisecondsSinceEpoch ?? 0;
        final bTime = (b.updatedAt ?? b.createdAt)?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });

      return orders;
    });
  }

  Stream<PurchaseOrder?> watchOrderById(String orderId) {
    return _ordersRef.child(orderId).onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return null;
      return PurchaseOrder.fromMap(orderId, Map<String, dynamic>.from(value));
    });
  }

  Future<PurchaseOrder?> fetchOrderById(String orderId) async {
    final snapshot = await _ordersRef.child(orderId).get();
    if (!snapshot.exists || snapshot.value is! Map) return null;
    return PurchaseOrder.fromMap(
      orderId,
      Map<String, dynamic>.from(snapshot.value as Map),
    );
  }

  Future<void> submitOrder({
    String? draftId,
    required AppUser requester,
    required PurchaseOrderUrgency urgency,
    required List<PurchaseOrderItem> items,
    String? clientNote,
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
          'companyId': _company.name,
          'requesterId': requester.id,
          'requesterName': requester.name,
          'areaId': requester.areaId,
          'areaName': requester.areaDisplay,
          'urgency': urgency.name,
          'clientNote': clientNote,
          'items': items.map((item) => item.toMap()).toList(),
          'resubmissions': resubmissions,
          'status': PurchaseOrderStatus.pendingCompras.name,
          'isDraft': false,
          'updatedAt': ServerValue.timestamp,
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
        return;
      }
    }

    final nextFolio = await _reserveNextFolio(_database, _company);
    final orderId = nextFolio;

    final payload = <String, dynamic>{
      'companyId': _company.name,
      'requesterId': requester.id,
      'requesterName': requester.name,
      'areaId': requester.areaId,
      'areaName': requester.areaDisplay,
      'urgency': urgency.name,
      'clientNote': clientNote,
      'items': items.map((item) => item.toMap()).toList(),
      'status': PurchaseOrderStatus.pendingCompras.name,
      'isDraft': false,
      'lastReturnReason': null,
      'returnCount': 0,
      'resubmissions': <int>[],
      'direccionReturnCount': 0,
      'updatedAt': ServerValue.timestamp,
      'statusEnteredAt': ServerValue.timestamp,
      'statusDurations': <String, int>{},
      'visibility': {
        'contabilidad': false,
      },
    };

    final orderRef = _ordersRef.child(orderId);
    await orderRef.set({
      ...payload,
      'createdAt': ServerValue.timestamp,
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
      'updatedAt': ServerValue.timestamp,
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

    await _markSharedQuotesNeedsUpdate(order);
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
  }) async {
    final trimmedSupplier = supplier?.trim();
    final trimmedComment = comprasComment?.trim();
    final trimmedReviewer = comprasReviewerName?.trim();
    final trimmedInternal = internalOrder?.trim();

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
      'updatedAt': ServerValue.timestamp,
    };

    if (items != null) {
      payload['items'] = items.map((item) => item.toMap()).toList();
    }

    await _ordersRef.child(orderId).update(payload);
  }

  Future<void> markPaymentDone({
    required PurchaseOrder order,
    required AppUser actor,
  }) async {
    final orderRef = _ordersRef.child(order.id);
    final trimmedName = actor.name.trim();
    final trimmedArea = actor.areaDisplay.trim();
    final timingUpdate = _statusTimingUpdate(order);

    await orderRef.update({
      'status': PurchaseOrderStatus.paymentDone.name,
      'direccionGeneralName': trimmedName.isEmpty ? null : trimmedName,
      'direccionGeneralArea': trimmedArea.isEmpty ? null : trimmedArea,
      'updatedAt': ServerValue.timestamp,
      ...timingUpdate,
    });

    await _appendEvent(
      orderRef,
      fromStatus: order.status,
      toStatus: PurchaseOrderStatus.paymentDone,
      byUserId: actor.id,
      byRole: _actorRoleLabel(actor),
      type: 'advance',
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
      'updatedAt': ServerValue.timestamp,
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

  Future<void> sendFacturaToAlmacen({
    required PurchaseOrder order,
    required List<String> facturaUrls,
    required AppUser actor,
  }) async {
    final cleaned = facturaUrls.map((url) => url.trim()).where((url) => url.isNotEmpty).toList();
    if (cleaned.isEmpty) throw StateError('Link de factura requerido.');

    final orderRef = _ordersRef.child(order.id);
    final trimmedName = actor.name.trim();
    final trimmedArea = actor.areaDisplay.trim();
    final timingUpdate = _statusTimingUpdate(order);

    await orderRef.update({
      'status': PurchaseOrderStatus.almacen.name,
      'facturaPdfUrls': cleaned,
      'facturaPdfUrl': cleaned.first,
      'contabilidadName': trimmedName.isEmpty ? null : trimmedName,
      'contabilidadArea': trimmedArea.isEmpty ? null : trimmedArea,
      'facturaUploadedAt': ServerValue.timestamp,
      'updatedAt': ServerValue.timestamp,
      ...timingUpdate,
    });

    await _appendEvent(
      orderRef,
      fromStatus: order.status,
      toStatus: PurchaseOrderStatus.almacen,
      byUserId: actor.id,
      byRole: _actorRoleLabel(actor),
      type: 'advance',
    );
  }

  Future<void> finalizeFromAlmacen({
    required PurchaseOrder order,
    required List<PurchaseOrderItem> items,
    required AppUser actor,
    String? comment,
  }) async {
    final orderRef = _ordersRef.child(order.id);
    final trimmedName = actor.name.trim();
    final trimmedArea = actor.areaDisplay.trim();
    final trimmedComment = comment?.trim() ?? '';
    final timingUpdate = _statusTimingUpdate(order);

    await orderRef.update({
      'status': PurchaseOrderStatus.eta.name,
      'items': items.map((item) => item.toMap()).toList(),
      'almacenName': trimmedName.isEmpty ? null : trimmedName,
      'almacenArea': trimmedArea.isEmpty ? null : trimmedArea,
      'almacenComment': trimmedComment.isEmpty ? null : trimmedComment,
      'almacenReceivedAt': ServerValue.timestamp,
      'updatedAt': ServerValue.timestamp,
      ...timingUpdate,
    });

    await _appendEvent(
      orderRef,
      fromStatus: order.status,
      toStatus: PurchaseOrderStatus.eta,
      byUserId: actor.id,
      byRole: _actorRoleLabel(actor),
      type: 'advance',
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
      'direccionGeneralName': null,
      'direccionGeneralArea': null,
      'direccionReturnCount': nextDireccionReturnCount,
      'items': items.map((item) => item.toMap()).toList(),
      'updatedAt': ServerValue.timestamp,
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

    await _markSharedQuotesNeedsUpdate(order);
  }

  Stream<List<SharedQuote>> watchSharedQuotes() {
    return _sharedQuotesRef.onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <SharedQuote>[];

      final quotes = <SharedQuote>[];
      value.forEach((key, raw) {
        if (raw is Map) {
          quotes.add(
            SharedQuote.fromMap(
              key.toString(),
              Map<String, dynamic>.from(raw),
            ),
          );
        }
      });

      quotes.sort((a, b) => a.supplier.compareTo(b.supplier));
      return quotes;
    });
  }

  Stream<SharedQuote?> watchSharedQuoteById(String quoteId) {
    return _sharedQuotesRef.child(quoteId).onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return null;
      return SharedQuote.fromMap(quoteId, Map<String, dynamic>.from(value));
    });
  }

  Future<SharedQuote?> fetchSharedQuoteById(String quoteId) async {
    final snapshot = await _sharedQuotesRef.child(quoteId).get();
    if (!snapshot.exists || snapshot.value is! Map) return null;
    return SharedQuote.fromMap(
      quoteId,
      Map<String, dynamic>.from(snapshot.value as Map),
    );
  }

  Future<SharedQuote> createSharedQuote({
    required String supplier,
    required List<String> orderIds,
    String? pdfUrl,
  }) async {
    final ref = _sharedQuotesRef.push();
    final quoteId = ref.key;
    if (quoteId == null || quoteId.isEmpty) {
      throw StateError('No se pudo crear la cotización compartida.');
    }

    final cleanedUrl = pdfUrl?.trim() ?? '';
    final hasUrl = cleanedUrl.isNotEmpty;

    await ref.set({
      'supplier': supplier.trim(),
      'orderIds': {for (final id in orderIds) id: true},
      'pdfUrl': hasUrl ? cleanedUrl : null,
      'needsUpdate': !hasUrl,
      'version': 1,
      'createdAt': ServerValue.timestamp,
      'updatedAt': ServerValue.timestamp,
    });

    return SharedQuote(
      id: quoteId,
      supplier: supplier.trim(),
      orderIds: orderIds,
      pdfUrl: cleanedUrl,
      needsUpdate: !hasUrl,
      version: 1,
    );
  }

  Future<void> linkOrdersToSharedQuote({
    required SharedQuote quote,
    required List<String> orderIds,
  }) async {
    if (orderIds.isEmpty) return;

    final updates = <String, Object?>{};
    for (final orderId in orderIds) {
      updates['sharedQuotes/${quote.id}/orderIds/$orderId'] = true;
    }
    await _database.ref().update(updates);

    for (final orderId in orderIds) {
      final order = await fetchOrderById(orderId);
      if (order == null) continue;
      await _updateOrderSharedQuote(order: order, quote: quote);
    }
  }

  Future<void> unlinkOrderFromSharedQuote({
    required PurchaseOrder order,
    required SharedQuote quote,
  }) async {
    final updatedRefs = _removeSharedQuoteRef(order.sharedQuoteRefs, quote.supplier);
    final nextLinks = _removeSupplierLinks(order.cotizacionLinks, quote.supplier);

    await _ordersRef.child(order.id).update({
      'sharedQuoteRefs': updatedRefs.isEmpty ? null : updatedRefs.map((ref) => ref.toMap()).toList(),
      'cotizacionLinks': nextLinks.isEmpty ? null : nextLinks.map((link) => link.toMap()).toList(),
      'cotizacionPdfUrls': nextLinks.map((link) => link.url).toList(),
      'cotizacionPdfUrl': nextLinks.isEmpty ? null : nextLinks.first.url,
      'updatedAt': ServerValue.timestamp,
    });

    await _sharedQuotesRef.child(quote.id).child('orderIds').child(order.id).remove();

    final refreshed = await fetchSharedQuoteById(quote.id);
    if (refreshed != null && refreshed.orderIds.isEmpty) {
      await _sharedQuotesRef.child(quote.id).remove();
    }
  }

  Future<void> updateSharedQuoteLink({
    required SharedQuote quote,
    required String pdfUrl,
  }) async {
    final cleaned = pdfUrl.trim();
    if (cleaned.isEmpty) throw StateError('Link de cotización requerido.');

    final nextVersion = quote.version + 1;

    await _sharedQuotesRef.child(quote.id).update({
      'pdfUrl': cleaned,
      'needsUpdate': false,
      'version': nextVersion,
      'updatedAt': ServerValue.timestamp,
    });

    final orderIds = quote.orderIds;
    if (orderIds.isEmpty) return;

    final updatedQuote = SharedQuote(
      id: quote.id,
      supplier: quote.supplier,
      orderIds: orderIds,
      pdfUrl: cleaned,
      needsUpdate: false,
      version: nextVersion,
    );

    for (final orderId in orderIds) {
      final order = await fetchOrderById(orderId);
      if (order == null) continue;
      await _updateOrderSharedQuote(order: order, quote: updatedQuote);
    }
  }

  Future<void> _markSharedQuotesNeedsUpdate(PurchaseOrder order) async {
    if (order.sharedQuoteRefs.isEmpty) return;

    final updates = <String, Object?>{};
    for (final ref in order.sharedQuoteRefs) {
      if (ref.quoteId.trim().isEmpty) continue;
      updates['sharedQuotes/${ref.quoteId}/needsUpdate'] = true;
      updates['sharedQuotes/${ref.quoteId}/updatedAt'] = ServerValue.timestamp;
    }

    if (updates.isEmpty) return;
    await _database.ref().update(updates);
  }

  Future<void> _updateOrderSharedQuote({
    required PurchaseOrder order,
    required SharedQuote quote,
  }) async {
    final nextRefs = _upsertSharedQuoteRef(order.sharedQuoteRefs, quote);

    final nextLinks = quote.pdfUrl.trim().isEmpty
        ? _removeSupplierLinks(order.cotizacionLinks, quote.supplier)
        : _upsertSupplierLink(order.cotizacionLinks, quote.supplier, quote.pdfUrl);

    await _ordersRef.child(order.id).update({
      'sharedQuoteRefs': nextRefs.isEmpty ? null : nextRefs.map((ref) => ref.toMap()).toList(),
      'cotizacionLinks': nextLinks.isEmpty ? null : nextLinks.map((link) => link.toMap()).toList(),
      'cotizacionPdfUrls': nextLinks.map((link) => link.url).toList(),
      'cotizacionPdfUrl': nextLinks.isEmpty ? null : nextLinks.first.url,
      'updatedAt': ServerValue.timestamp,
    });
  }

  Future<void> transitionStatus({
    required PurchaseOrder order,
    required PurchaseOrderStatus targetStatus,
    required AppUser actor,
  }) async {
    final orderRef = _ordersRef.child(order.id);
    final timingUpdate = _statusTimingUpdate(order);

    await orderRef.update({
      'status': targetStatus.name,
      'isDraft': targetStatus == PurchaseOrderStatus.draft,
      'updatedAt': ServerValue.timestamp,
      ...timingUpdate,
    });

    await _appendEvent(
      orderRef,
      fromStatus: order.status,
      toStatus: targetStatus,
      byUserId: actor.id,
      byRole: _actorRoleLabel(actor),
      type: 'advance',
    );
  }

  Future<void> sendToDireccionWithCotizacion({
    required PurchaseOrder order,
    required List<CotizacionLink> cotizacionLinks,
    required AppUser actor,
  }) async {
    final cleanedLinks = cotizacionLinks
        .map((link) => CotizacionLink(
              supplier: link.supplier.trim(),
              url: link.url.trim(),
            ))
        .where((link) => link.url.isNotEmpty)
        .toList();

    if (cleanedLinks.isEmpty) throw StateError('Link de cotización requerido.');

    final orderRef = _ordersRef.child(order.id);
    final timingUpdate = _statusTimingUpdate(order);

    await orderRef.update({
      'status': PurchaseOrderStatus.authorizedGerencia.name,
      'cotizacionLinks': cleanedLinks.map((link) => link.toMap()).toList(),
      'cotizacionPdfUrls': cleanedLinks.map((link) => link.url).toList(),
      'cotizacionPdfUrl': cleanedLinks.first.url,
      'updatedAt': ServerValue.timestamp,
      ...timingUpdate,
    });

    await _appendEvent(
      orderRef,
      fromStatus: order.status,
      toStatus: PurchaseOrderStatus.authorizedGerencia,
      byUserId: actor.id,
      byRole: _actorRoleLabel(actor),
      type: 'advance',
    );
  }

  Future<void> deleteOrder(String orderId) async {
    await _ordersRef.child(orderId).remove();
  }
}

final purchaseOrderRepositoryProvider = Provider<PurchaseOrderRepository>((ref) {
  final database = ref.watch(firebaseDatabaseProvider);
  final company = ref.watch(currentCompanyProvider);
  return PurchaseOrderRepository(database, company);
});

Future<String> _reserveNextFolio(FirebaseDatabase database, Company company) async {
  final counterRef = database.ref('counters/folios/purchaseOrderNext');
  final currentSnapshot = await counterRef.get();
  final snapshotValue = _parseCounterValue(currentSnapshot.value);
  final legacySeed = snapshotValue > 0 ? 0 : await _resolveLegacyMax(database);

  final result = await counterRef.runTransaction((current) {
    final base = _parseCounterValue(current);
    final effective = base > 0 ? base : legacySeed;
    final next = effective + 1;
    return Transaction.success(next);
  });

  if (!result.committed) throw StateError('No se pudo generar el folio.');

  final nextValue = _parseCounterValue(result.snapshot.value);
  if (nextValue <= 0) throw StateError('Folio inválido.');

  return formatFolio(company, nextValue);
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

Future<int> _resolveLegacyMax(FirebaseDatabase database) async {
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
  DatabaseReference orderRef, {
  required PurchaseOrderStatus? fromStatus,
  required PurchaseOrderStatus toStatus,
  required String byUserId,
  required String byRole,
  required String type,
  String? comment,
  List<PurchaseOrderItem>? itemsSnapshot,
}) async {
  final eventRef = orderRef.child('events').push();
  final payload = <String, dynamic>{
    'fromStatus': fromStatus?.name,
    'toStatus': toStatus.name,
    'byUserId': byUserId,
    'byRole': byRole,
    'timestamp': ServerValue.timestamp,
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

List<SharedQuoteRef> _upsertSharedQuoteRef(
  List<SharedQuoteRef> existing,
  SharedQuote quote,
) {
  final normalizedSupplier = quote.supplier.trim().toLowerCase();
  final next = <SharedQuoteRef>[];
  var inserted = false;

  for (final ref in existing) {
    final supplierKey = ref.supplier.trim().toLowerCase();
    if (supplierKey == normalizedSupplier) {
      next.add(SharedQuoteRef(supplier: ref.supplier.trim(), quoteId: quote.id));
      inserted = true;
    } else {
      next.add(ref);
    }
  }

  if (!inserted) {
    next.add(SharedQuoteRef(supplier: quote.supplier.trim(), quoteId: quote.id));
  }

  return next;
}

List<SharedQuoteRef> _removeSharedQuoteRef(
  List<SharedQuoteRef> existing,
  String supplier,
) {
  final normalizedSupplier = supplier.trim().toLowerCase();
  if (normalizedSupplier.isEmpty) return existing;
  return existing.where((ref) => ref.supplier.trim().toLowerCase() != normalizedSupplier).toList();
}

List<CotizacionLink> _upsertSupplierLink(
  List<CotizacionLink> existing,
  String supplier,
  String url,
) {
  final cleanedSupplier = supplier.trim();
  final cleanedUrl = url.trim();
  if (cleanedSupplier.isEmpty || cleanedUrl.isEmpty) return existing;

  final normalizedSupplier = cleanedSupplier.toLowerCase();
  final next = <CotizacionLink>[];
  var inserted = false;

  for (final link in existing) {
    final supplierKey = link.supplier.trim().toLowerCase();
    if (supplierKey == normalizedSupplier) {
      if (!inserted) {
        next.add(CotizacionLink(supplier: cleanedSupplier, url: cleanedUrl));
        inserted = true;
      }
    } else {
      next.add(link);
    }
  }

  if (!inserted) {
    next.add(CotizacionLink(supplier: cleanedSupplier, url: cleanedUrl));
  }

  return next;
}

List<CotizacionLink> _removeSupplierLinks(
  List<CotizacionLink> existing,
  String supplier,
) {
  final normalizedSupplier = supplier.trim().toLowerCase();
  if (normalizedSupplier.isEmpty) return existing;
  return existing.where((link) => link.supplier.trim().toLowerCase() != normalizedSupplier).toList();
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
