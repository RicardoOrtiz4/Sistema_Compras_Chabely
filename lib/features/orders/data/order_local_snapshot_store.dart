import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:sistema_compras/features/orders/domain/order_dashboard_counts.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';

class OrderLocalSnapshotStore {
  static const _ordersPrefix = 'orders.snapshot.';
  static const _countsPrefix = 'counts.snapshot.';
  static const _schemaVersion = 2;
  static const _envelopeVersionKey = 'version';
  static const _envelopeSavedAtKey = 'savedAt';
  static const _envelopeDataKey = 'data';
  static const _maxCachedOrders = 40;
  static const _countsTtl = Duration(minutes: 3);
  static const _operationalOrdersTtl = Duration(minutes: 8);
  static const _historyOrdersTtl = Duration(minutes: 20);
  static SharedPreferences? _prefs;

  static Future<void> ensureInitialized() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static Future<List<PurchaseOrder>?> readOrders(String key) async {
    final raw = await _readJson('$_ordersPrefix$key', ttl: _ttlForOrders(key));
    if (raw is! List) return null;

    final orders = <PurchaseOrder>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);
      final id = (map['id'] as String?)?.trim() ?? '';
      final data = map['data'];
      if (id.isEmpty || data is! Map) continue;
      orders.add(PurchaseOrder.fromMap(id, Map<String, dynamic>.from(data)));
    }
    return orders;
  }

  static Future<void> writeOrders(
    String key,
    List<PurchaseOrder> orders,
  ) async {
    await _writeJson('$_ordersPrefix$key', [
      for (final order in orders.take(_maxCachedOrders))
        {'id': order.id, 'data': order.toMap()},
    ]);
  }

  static Future<OrderDashboardCounts?> readDashboardCounts(String key) async {
    final raw = await _readJson('$_countsPrefix$key', ttl: _countsTtl);
    if (raw is! Map) return null;
    return OrderDashboardCounts.fromLocalMap(Map<String, dynamic>.from(raw));
  }

  static Future<void> writeDashboardCounts(
    String key,
    OrderDashboardCounts counts,
  ) async {
    await _writeJson('$_countsPrefix$key', counts.toLocalMap());
  }

  static Future<Object?> _readJson(String key, {required Duration ttl}) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    final encoded = prefs.getString(key);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return decoded;
      final version = decoded[_envelopeVersionKey];
      if (version != _schemaVersion) {
        return decoded;
      }
      final savedAt = decoded[_envelopeSavedAtKey];
      final savedAtMs = savedAt is int ? savedAt : int.tryParse('$savedAt');
      if (savedAtMs == null) {
        await prefs.remove(key);
        return null;
      }
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(savedAtMs),
      );
      if (age > ttl) {
        await prefs.remove(key);
        return null;
      }
      return decoded[_envelopeDataKey];
    } catch (_) {
      await prefs.remove(key);
      return null;
    }
  }

  static Future<void> _writeJson(String key, Object value) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    final payload = <String, Object?>{
      _envelopeVersionKey: _schemaVersion,
      _envelopeSavedAtKey: DateTime.now().millisecondsSinceEpoch,
      _envelopeDataKey: value,
    };
    await prefs.setString(key, jsonEncode(payload));
  }

  static Duration _ttlForOrders(String key) {
    if (key.contains(':userOrders') || key.contains(':allOrders')) {
      return _historyOrdersTtl;
    }
    return _operationalOrdersTtl;
  }
}
