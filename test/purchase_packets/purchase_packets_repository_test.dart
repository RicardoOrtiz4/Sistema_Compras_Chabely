import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/firebase_database_compat.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/purchase_packets/data/purchase_packets_repository.dart';
import 'package:sistema_compras/features/purchase_packets/domain/purchase_packet_domain.dart';

void main() {
  group('domain transitions', () {
    test('accepts valid order transitions', () {
      expect(
        () => ensureValidOrderTransition(
          RequestOrderStatus.readyForApproval,
          RequestOrderStatus.approvalQueue,
        ),
        returnsNormally,
      );
      expect(
        () => ensureValidOrderTransition(
          RequestOrderStatus.executionReady,
          RequestOrderStatus.completed,
        ),
        returnsNormally,
      );
    });

    test('rejects invalid order transitions', () {
      expect(
        () => ensureValidOrderTransition(
          RequestOrderStatus.draft,
          RequestOrderStatus.completed,
        ),
        throwsA(isA<InvalidOrderTransition>()),
      );
    });

    test('accepts valid packet transitions and rejects invalid ones', () {
      expect(
        () => ensureValidPacketTransition(
          PurchasePacketStatus.draft,
          PurchasePacketStatus.approvalQueue,
        ),
        returnsNormally,
      );
      expect(
        () => ensureValidPacketTransition(
          PurchasePacketStatus.draft,
          PurchasePacketStatus.executionReady,
        ),
        throwsA(isA<InvalidPacketTransition>()),
      );
    });
  });

  group('purchase packet repository integration', () {
    late MemoryAppDatabase database;
    late PurchasePacketsRepository repository;
    late AppUser compras;
    late AppUser direccion;

    setUp(() {
      database = MemoryAppDatabase();
      repository = PurchasePacketsRepository(database, Company.chabely);
      compras = const AppUser(
        id: 'compras_1',
        name: 'Compras Uno',
        email: 'compras@chabely.com.mx',
        role: 'usuario',
        areaId: 'compras',
        areaName: 'Compras',
        isActive: true,
      );
      direccion = const AppUser(
        id: 'dig_1',
        name: 'Direccion Uno',
        email: 'direccion@chabely.com.mx',
        role: 'usuario',
        areaId: 'direccion',
        areaName: 'Direccion General (DIG)',
        isActive: true,
      );
      _seedNewReadyOrder(database, orderId: 'ORD-1');
    });

    test('create -> submit -> approve', () async {
      final packet = await repository.createPacketFromReadyOrders(
        actor: compras,
        supplierName: 'Proveedor Norte',
        totalAmount: 1500,
        evidenceUrls: const <String>['https://evidence/1'],
        itemRefIds: const <String>['ORD-1::item_1'],
      );

      expect(packet.status, PurchasePacketStatus.draft);
      expect(packet.version, 1);

      final submitted = await repository.submitPacketForExecutiveApproval(
        actor: compras,
        packetId: packet.id,
        expectedVersion: 1,
      );
      expect(submitted.status, PurchasePacketStatus.approvalQueue);
      expect(submitted.version, 2);

      final approved = await repository.approvePacket(
        actor: direccion,
        packetId: packet.id,
        expectedVersion: 2,
      );
      expect(approved.status, PurchasePacketStatus.executionReady);
      expect(approved.version, 3);

      final mirroredOrder = await repository.fetchOrderById('ORD-1');
      expect(mirroredOrder, isNotNull);
      expect(mirroredOrder!.status, RequestOrderStatus.executionReady);
    });

    test('create -> submit -> return -> resubmit', () async {
      final packet = await repository.createPacketFromReadyOrders(
        actor: compras,
        supplierName: 'Proveedor Norte',
        totalAmount: 1500,
        evidenceUrls: const <String>['https://evidence/1'],
        itemRefIds: const <String>['ORD-1::item_1'],
      );
      final submitted = await repository.submitPacketForExecutiveApproval(
        actor: compras,
        packetId: packet.id,
        expectedVersion: packet.version,
      );
      final returned = await repository.returnPacketForRework(
        actor: direccion,
        packetId: packet.id,
        expectedVersion: submitted.version,
        reason: 'Falta cotizacion actualizada',
      );
      expect(returned.status, PurchasePacketStatus.draft);
      expect(returned.version, 3);

      final resubmitted = await repository.submitPacketForExecutiveApproval(
        actor: compras,
        packetId: packet.id,
        expectedVersion: returned.version,
      );
      expect(resubmitted.status, PurchasePacketStatus.approvalQueue);
      expect(resubmitted.version, 4);
    });

    test('partial close as unpurchasable keeps unrelated items intact', () async {
      final packet = await repository.createPacketFromReadyOrders(
        actor: compras,
        supplierName: 'Proveedor Norte',
        totalAmount: 1500,
        evidenceUrls: const <String>['https://evidence/1'],
        itemRefIds: const <String>['ORD-1::item_1', 'ORD-1::item_2'],
      );
      final submitted = await repository.submitPacketForExecutiveApproval(
        actor: compras,
        packetId: packet.id,
        expectedVersion: packet.version,
      );

      final closed = await repository.closePacketItemsAsUnpurchasable(
        actor: direccion,
        packetId: packet.id,
        expectedVersion: submitted.version,
        itemRefIds: const <String>['ORD-1::item_1'],
        reason: 'No hay disponibilidad del fabricante',
      );

      expect(closed.status, PurchasePacketStatus.approvalQueue);
      final refreshed = await repository.fetchPacketById(packet.id);
      expect(refreshed, isNotNull);
      final item1 = refreshed!.packet.itemRefs.firstWhere((item) => item.id == 'ORD-1::item_1');
      final item2 = refreshed.packet.itemRefs.firstWhere((item) => item.id == 'ORD-1::item_2');
      expect(item1.closedAsUnpurchasable, isTrue);
      expect(item2.closedAsUnpurchasable, isFalse);
    });

    test('version conflict is controlled', () async {
      final packet = await repository.createPacketFromReadyOrders(
        actor: compras,
        supplierName: 'Proveedor Norte',
        totalAmount: 1500,
        evidenceUrls: const <String>['https://evidence/1'],
        itemRefIds: const <String>['ORD-1::item_1'],
      );

      await expectLater(
        () => repository.submitPacketForExecutiveApproval(
          actor: compras,
          packetId: packet.id,
          expectedVersion: 99,
        ),
        throwsA(isA<PacketVersionConflict>()),
      );
    });

    test('legacy ready order reads without crash and new writes stay out of legacy node', () async {
      await database.ref('purchaseOrders/LEG-1').set(<String, Object?>{
        'requesterId': 'legacy_user',
        'requesterName': 'Usuario Legacy',
        'areaId': 'mantenimiento',
        'areaName': 'Mantenimiento',
        'urgency': 'normal',
        'status': 'readyForApproval',
        'items': <Object?>[
          <String, Object?>{
            'line': 1,
            'partNumber': 'LEG-1',
            'description': 'Refaccion legacy',
            'quantity': 2,
            'unit': 'PZA',
            'supplier': 'Proveedor Legacy',
            'budget': 200,
          },
        ],
      });

      final legacyOrder = await repository.fetchOrderById('LEG-1');
      expect(legacyOrder, isNotNull);
      expect(legacyOrder!.status, RequestOrderStatus.readyForApproval);

      await repository.createPacketFromReadyOrders(
        actor: compras,
        supplierName: 'Proveedor Legacy',
        totalAmount: 200,
        evidenceUrls: const <String>['https://evidence/legacy'],
        itemRefIds: const <String>['LEG-1::line_1'],
      );

      final legacySnapshot = await database.ref('purchaseOrders/LEG-1').get();
      final legacyMap = Map<String, dynamic>.from(legacySnapshot.value as Map);
      expect(legacyMap.containsKey('projection'), isFalse);
      expect(legacyMap.containsKey('packetIds'), isFalse);

      final mirroredSnapshot = await database.ref('orders/LEG-1').get();
      expect(mirroredSnapshot.exists, isTrue);
    });
  });
}

void _seedNewReadyOrder(MemoryAppDatabase database, {required String orderId}) {
  database.ref('orders/$orderId').set(<String, Object?>{
    'requesterId': 'user_1',
    'requesterName': 'Solicitante Uno',
    'areaId': 'mtto',
    'areaName': 'Mantenimiento',
    'urgency': 'normal',
    'status': 'ready_for_approval',
    'source': 'new',
  });
  database.ref('order_items/$orderId/item_1').set(<String, Object?>{
    'itemId': 'item_1',
    'lineNumber': 1,
    'partNumber': 'SKU-1',
    'description': 'Rodamiento',
    'quantity': 2,
    'unit': 'PZA',
    'supplierName': 'Proveedor Norte',
    'estimatedAmount': 750,
  });
  database.ref('order_items/$orderId/item_2').set(<String, Object?>{
    'itemId': 'item_2',
    'lineNumber': 2,
    'partNumber': 'SKU-2',
    'description': 'Aceite',
    'quantity': 3,
    'unit': 'GAL',
    'supplierName': 'Proveedor Norte',
    'estimatedAmount': 750,
  });
}

class MemoryAppDatabase implements AppDatabase {
  final Map<String, Object?> _root = <String, Object?>{};
  final List<_MemoryQueryBase> _queries = <_MemoryQueryBase>[];
  int _pushCounter = 0;

  @override
  AppDatabaseRef ref([String path = '']) {
    final ref = _MemoryRef(this, _normalize(path));
    _queries.add(ref);
    return ref;
  }

  Object? read(String path) {
    final normalized = _normalize(path);
    if (normalized.isEmpty) return _deepCopy(_root);
    Object? current = _root;
    for (final segment in normalized.split('/')) {
      if (current is! Map || !current.containsKey(segment)) return null;
      current = current[segment];
    }
    return _deepCopy(current);
  }

  void write(String path, Object? value) {
    final normalized = _normalize(path);
    if (normalized.isEmpty) {
      _root
        ..clear()
        ..addAll((value as Map?)?.cast<String, Object?>() ?? <String, Object?>{});
      _notifyAll();
      return;
    }
    final segments = normalized.split('/');
    Map<String, Object?> current = _root;
    for (var index = 0; index < segments.length - 1; index++) {
      final segment = segments[index];
      final next = current[segment];
      if (next is Map<String, Object?>) {
        current = next;
      } else if (next is Map) {
        final copied = next.cast<String, Object?>();
        current[segment] = copied;
        current = copied;
      } else {
        final created = <String, Object?>{};
        current[segment] = created;
        current = created;
      }
    }
    current[segments.last] = _deepCopy(value);
    _notifyAll();
  }

  void patch(String path, Map<String, Object?> value) {
    final current = read(path);
    final target = current is Map<String, Object?>
        ? current
        : current is Map
            ? current.cast<String, Object?>()
            : <String, Object?>{};
    for (final entry in value.entries) {
      _applyPatch(target, entry.key, entry.value);
    }
    write(path, target);
  }

  void delete(String path) {
    final normalized = _normalize(path);
    if (normalized.isEmpty) {
      _root.clear();
      _notifyAll();
      return;
    }
    final segments = normalized.split('/');
    Map<String, Object?> current = _root;
    for (var index = 0; index < segments.length - 1; index++) {
      final next = current[segments[index]];
      if (next is Map<String, Object?>) {
        current = next;
      } else if (next is Map) {
        current = next.cast<String, Object?>();
      } else {
        return;
      }
    }
    current.remove(segments.last);
    _notifyAll();
  }

  Future<AppDatabaseTransactionResult> transact(
    String path,
    Object? Function(Object? current) update,
  ) async {
    final current = read(path);
    final next = update(current);
    write(path, next);
    return AppDatabaseTransactionResult(
      committed: true,
      snapshot: AppDatabaseSnapshot(read(path)),
    );
  }

  String nextPushKey() {
    _pushCounter += 1;
    return 'push_${_pushCounter.toString().padLeft(4, '0')}';
  }

  void registerQuery(_MemoryQueryBase query) {
    if (!_queries.contains(query)) {
      _queries.add(query);
    }
  }

  void _notifyAll() {
    for (final query in _queries) {
      query.emitCurrent();
    }
  }
}

abstract class _MemoryQueryBase {
  void emitCurrent();
}

class _MemoryQuery implements AppDatabaseQuery, _MemoryQueryBase {
  _MemoryQuery(this.database, this.path) {
    database.registerQuery(this);
  }

  final MemoryAppDatabase database;
  final String path;
  final StreamController<AppDatabaseEvent> _controller = StreamController<AppDatabaseEvent>.broadcast();
  String? _orderByChildPath;
  Object? _equalToValue;
  int? _limitToLastCount;

  @override
  Stream<AppDatabaseEvent> get onValue async* {
    emitCurrent();
    yield* _controller.stream;
  }

  @override
  Future<AppDatabaseSnapshot> get() async {
    return AppDatabaseSnapshot(_applyQuery(database.read(path)));
  }

  @override
  AppDatabaseQuery orderByChild(String path) {
    _orderByChildPath = path;
    return this;
  }

  @override
  AppDatabaseQuery equalTo(Object? value) {
    _equalToValue = value;
    return this;
  }

  @override
  AppDatabaseQuery limitToLast(int limit) {
    _limitToLastCount = limit;
    return this;
  }

  @override
  void emitCurrent() {
    if (_controller.isClosed) return;
    _controller.add(AppDatabaseEvent(AppDatabaseSnapshot(_applyQuery(database.read(path)))));
  }

  Object? _applyQuery(Object? raw) {
    if (raw is! Map || _orderByChildPath == null || _orderByChildPath!.isEmpty) {
      return raw;
    }
    final entries = raw.entries.where((entry) {
      if (_equalToValue == null) return true;
      final value = _readNested(entry.value, _orderByChildPath!);
      return value == _equalToValue;
    }).toList(growable: false);
    final limited = (_limitToLastCount != null && entries.length > _limitToLastCount!)
        ? entries.sublist(entries.length - _limitToLastCount!)
        : entries;
    return <String, Object?>{
      for (final entry in limited) entry.key.toString(): _deepCopy(entry.value),
    };
  }
}

class _MemoryRef extends _MemoryQuery implements AppDatabaseRef {
  _MemoryRef(super.database, super.path);

  @override
  String? get key {
    if (path.isEmpty) return null;
    final segments = path.split('/');
    return segments.isEmpty ? null : segments.last;
  }

  @override
  AppDatabaseRef child(String path) {
    final childPath = _normalize(path);
    final next = [this.path, childPath].where((segment) => segment.isNotEmpty).join('/');
    return _MemoryRef(database, next);
  }

  @override
  AppDatabaseRef push() {
    return child(database.nextPushKey());
  }

  @override
  Future<void> remove() async {
    database.delete(path);
  }

  @override
  Future<void> set(Object? value) async {
    database.write(path, value);
  }

  @override
  Future<void> update(Map<String, Object?> value) async {
    database.patch(path, value);
  }

  @override
  Future<AppDatabaseTransactionResult> runTransaction(
    Object? Function(Object? current) update,
  ) {
    return database.transact(path, update);
  }
}

String _normalize(String path) {
  return path
      .split('/')
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .join('/');
}

Object? _deepCopy(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): _deepCopy(entry.value),
    };
  }
  if (value is List) {
    return value.map(_deepCopy).toList(growable: false);
  }
  return value;
}

void _applyPatch(Map<String, Object?> root, String path, Object? value) {
  final segments = _normalize(path).split('/').where((segment) => segment.isNotEmpty).toList(growable: false);
  if (segments.isEmpty) return;
  Map<String, Object?> current = root;
  for (var index = 0; index < segments.length - 1; index++) {
    final segment = segments[index];
    final next = current[segment];
    if (next is Map<String, Object?>) {
      current = next;
    } else if (next is Map) {
      final casted = next.cast<String, Object?>();
      current[segment] = casted;
      current = casted;
    } else {
      final created = <String, Object?>{};
      current[segment] = created;
      current = created;
    }
  }
  current[segments.last] = _deepCopy(value);
}

Object? _readNested(Object? raw, String path) {
  Object? current = raw;
  for (final segment in path.split('/')) {
    if (current is! Map || !current.containsKey(segment)) return null;
    current = current[segment];
  }
  return current;
}
