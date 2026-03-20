import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:sistema_compras/core/app_auth.dart';

const Map<String, String> appServerTimestamp = <String, String>{
  '.sv': 'timestamp',
};

abstract class AppDatabase {
  AppDatabaseRef ref([String path = '']);
}

abstract class AppDatabaseQuery {
  Stream<AppDatabaseEvent> get onValue;

  Future<AppDatabaseSnapshot> get();

  AppDatabaseQuery orderByChild(String path);

  AppDatabaseQuery equalTo(Object? value);

  AppDatabaseQuery limitToLast(int limit);
}

abstract class AppDatabaseRef implements AppDatabaseQuery {
  String? get key;

  AppDatabaseRef child(String path);

  AppDatabaseRef push();

  Future<void> set(Object? value);

  Future<void> update(Map<String, Object?> value);

  Future<void> remove();

  Future<AppDatabaseTransactionResult> runTransaction(
    Object? Function(Object? current) update,
  );
}

class AppDatabaseSnapshot {
  const AppDatabaseSnapshot(this.value);

  final Object? value;

  bool get exists => value != null;
}

class AppDatabaseEvent {
  const AppDatabaseEvent(this.snapshot);

  final AppDatabaseSnapshot snapshot;
}

class AppDatabaseTransactionResult {
  const AppDatabaseTransactionResult({
    required this.committed,
    required this.snapshot,
  });

  final bool committed;
  final AppDatabaseSnapshot snapshot;
}

AppDatabase createAppDatabase(AppAuthClient auth) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    final databaseUrl = Firebase.app().options.databaseURL;
    if (databaseUrl == null || databaseUrl.isEmpty) {
      throw StateError('Firebase Realtime Database URL no configurada.');
    }
    return RestAppDatabase(
      auth: auth,
      databaseUrl: databaseUrl,
    );
  }
  return PluginAppDatabase(FirebaseDatabase.instance);
}

class PluginAppDatabase implements AppDatabase {
  PluginAppDatabase(this._database);

  final FirebaseDatabase _database;

  @override
  AppDatabaseRef ref([String path = '']) {
    return PluginAppDatabaseRef(
      path.isEmpty ? _database.ref() : _database.ref(path),
    );
  }
}

class PluginAppDatabaseQuery implements AppDatabaseQuery {
  PluginAppDatabaseQuery(this._query);

  final Query _query;

  @override
  Future<AppDatabaseSnapshot> get() async {
    final snapshot = await _query.get();
    return AppDatabaseSnapshot(snapshot.value);
  }

  @override
  Stream<AppDatabaseEvent> get onValue {
    return _query.onValue.map(
      (event) => AppDatabaseEvent(AppDatabaseSnapshot(event.snapshot.value)),
    );
  }

  @override
  AppDatabaseQuery orderByChild(String path) {
    return PluginAppDatabaseQuery(_query.orderByChild(path));
  }

  @override
  AppDatabaseQuery equalTo(Object? value) {
    return PluginAppDatabaseQuery(_query.equalTo(value));
  }

  @override
  AppDatabaseQuery limitToLast(int limit) {
    return PluginAppDatabaseQuery(_query.limitToLast(limit));
  }
}

class PluginAppDatabaseRef extends PluginAppDatabaseQuery implements AppDatabaseRef {
  PluginAppDatabaseRef(this._ref) : super(_ref);

  final DatabaseReference _ref;

  @override
  String? get key => _ref.key;

  @override
  AppDatabaseRef child(String path) => PluginAppDatabaseRef(_ref.child(path));

  @override
  AppDatabaseRef push() => PluginAppDatabaseRef(_ref.push());

  @override
  Future<void> remove() => _ref.remove();

  @override
  Future<void> set(Object? value) => _ref.set(value);

  @override
  Future<void> update(Map<String, Object?> value) => _ref.update(value);

  @override
  Future<AppDatabaseTransactionResult> runTransaction(
    Object? Function(Object? current) update,
  ) async {
    final result = await _ref.runTransaction((current) {
      return Transaction.success(update(current));
    });
    return AppDatabaseTransactionResult(
      committed: result.committed,
      snapshot: AppDatabaseSnapshot(result.snapshot.value),
    );
  }
}

class RestAppDatabase implements AppDatabase {
  RestAppDatabase({
    required AppAuthClient auth,
    required String databaseUrl,
    http.Client? client,
    Duration pollInterval = const Duration(seconds: 2),
  })  : _auth = auth,
        _databaseUrl = databaseUrl,
        _client = client ?? http.Client(),
        _pollInterval = pollInterval;

  final AppAuthClient _auth;
  final String _databaseUrl;
  final http.Client _client;
  final Duration _pollInterval;

  @override
  AppDatabaseRef ref([String path = '']) {
    return RestAppDatabaseRef._(
      backend: this,
      path: _normalizePath(path),
    );
  }

  Future<AppDatabaseSnapshot> get({
    required String path,
    String? orderByChild,
    Object? equalTo,
    int? limitToLast,
  }) async {
    try {
      final response = await _request(
        'GET',
        path,
        queryParameters: _queryParameters(
          orderByChild: orderByChild,
          equalTo: equalTo,
          limitToLast: limitToLast,
        ),
      );
      return AppDatabaseSnapshot(_decodeResponseBody(response));
    } on StateError catch (error) {
      if (!_shouldFallbackToClientSideQuery(
        error,
        orderByChild: orderByChild,
      )) {
        rethrow;
      }

      final response = await _request('GET', path);
      final value = _applyClientSideQuery(
        _decodeResponseBody(response),
        orderByChild: orderByChild,
        equalTo: equalTo,
        limitToLast: limitToLast,
      );
      return AppDatabaseSnapshot(value);
    }
  }

  Stream<AppDatabaseEvent> watch({
    required String path,
    String? orderByChild,
    Object? equalTo,
    int? limitToLast,
  }) {
    return Stream.multi((controller) {
      Timer? timer;
      var fetching = false;
      var disposed = false;
      var hasEmitted = false;
      String? lastFingerprint;

      Future<void> poll() async {
        if (fetching || disposed) return;
        fetching = true;
        try {
          final snapshot = await get(
            path: path,
            orderByChild: orderByChild,
            equalTo: equalTo,
            limitToLast: limitToLast,
          );
          final fingerprint = _fingerprint(snapshot.value);
          if (!hasEmitted || fingerprint != lastFingerprint) {
            hasEmitted = true;
            lastFingerprint = fingerprint;
            controller.add(AppDatabaseEvent(snapshot));
          }
        } catch (error, stackTrace) {
          controller.addError(error, stackTrace);
        } finally {
          fetching = false;
        }
      }

      unawaited(poll());
      timer = Timer.periodic(_pollInterval, (_) {
        unawaited(poll());
      });

      controller.onCancel = () {
        disposed = true;
        timer?.cancel();
      };
    });
  }

  Future<void> set(String path, Object? value) async {
    await _request('PUT', path, body: value);
  }

  Future<void> update(String path, Map<String, Object?> value) async {
    await _request('PATCH', path, body: _normalizeUpdateKeys(value));
  }

  Future<void> remove(String path) async {
    await _request('DELETE', path);
  }

  Future<AppDatabaseTransactionResult> runTransaction({
    required String path,
    required Object? Function(Object? current) update,
    int maxAttempts = 8,
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final current = await _request(
        'GET',
        path,
        headers: const <String, String>{'X-Firebase-ETag': 'true'},
      );
      final currentValue = _decodeResponseBody(current);
      final etag = current.headers['etag'];
      if (etag == null || etag.isEmpty) {
        throw StateError('No se pudo obtener ETag para la transaccion.');
      }

      final nextValue = update(currentValue);
      final response = await _request(
        'PUT',
        path,
        body: nextValue,
        headers: <String, String>{'if-match': etag},
        allowConflict: true,
      );
      if (response.statusCode == 412) {
        continue;
      }

      return AppDatabaseTransactionResult(
        committed: true,
        snapshot: AppDatabaseSnapshot(_decodeResponseBody(response)),
      );
    }

    return const AppDatabaseTransactionResult(
      committed: false,
      snapshot: AppDatabaseSnapshot(null),
    );
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
    Object? body,
    bool allowConflict = false,
  }) async {
    final token = await _auth.currentUser?.getIdToken();
    final mergedQuery = <String, String>{
      ...?queryParameters,
      if (token != null && token.isNotEmpty) 'auth': token,
    };

    final uri = _buildUri(path, mergedQuery);
    final requestHeaders = <String, String>{
      if (body != null) 'Content-Type': 'application/json',
      ...?headers,
    };

    late http.Response response;
    switch (method) {
      case 'GET':
        response = await _client.get(uri, headers: requestHeaders);
        break;
      case 'PUT':
        response = await _client.put(
          uri,
          headers: requestHeaders,
          body: jsonEncode(body),
        );
        break;
      case 'PATCH':
        response = await _client.patch(
          uri,
          headers: requestHeaders,
          body: jsonEncode(body),
        );
        break;
      case 'DELETE':
        response = await _client.delete(uri, headers: requestHeaders);
        break;
      default:
        throw UnsupportedError('Metodo HTTP no soportado: $method');
    }

    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (ok || (allowConflict && response.statusCode == 412)) {
      return response;
    }

    throw StateError(
      'Realtime Database REST error ${response.statusCode} en "$path": ${response.body}',
    );
  }

  Uri _buildUri(String path, Map<String, String> queryParameters) {
    final baseUri = Uri.parse(_databaseUrl);
    final basePath = _trimSlashes(baseUri.path);
    final normalizedPath = _normalizePath(path);
    final fullPath = <String>[
      if (basePath.isNotEmpty) basePath,
      if (normalizedPath.isNotEmpty) normalizedPath,
    ].join('/');

    return baseUri.replace(
      path: fullPath.isEmpty ? '/.json' : '/$fullPath.json',
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
  }

  Map<String, String> _queryParameters({
    String? orderByChild,
    Object? equalTo,
    int? limitToLast,
  }) {
    final parameters = <String, String>{};
    if (orderByChild != null) {
      parameters['orderBy'] = jsonEncode(orderByChild);
    }
    if (equalTo != null) {
      parameters['equalTo'] = jsonEncode(equalTo);
    }
    if (limitToLast != null && limitToLast > 0) {
      parameters['limitToLast'] = '$limitToLast';
    }
    return parameters;
  }
}

bool _shouldFallbackToClientSideQuery(
  StateError error, {
  required String? orderByChild,
}) {
  if (orderByChild == null || orderByChild.isEmpty) return false;
  return error.message.toString().contains('Index not defined');
}

Object? _applyClientSideQuery(
  Object? rawValue, {
  required String? orderByChild,
  required Object? equalTo,
  required int? limitToLast,
}) {
  if (rawValue is! Map || orderByChild == null || orderByChild.isEmpty) {
    return rawValue;
  }

  final entries = rawValue.entries
      .map(
        (entry) => MapEntry<String, Object?>(
          entry.key.toString(),
          entry.value,
        ),
      )
      .where((entry) {
        if (equalTo == null) return true;
        return _queryValueEquals(
          _readNestedValue(entry.value, orderByChild),
          equalTo,
        );
      })
      .toList(growable: false)
    ..sort((a, b) => a.key.compareTo(b.key));

  final limited = (limitToLast != null && limitToLast > 0 && entries.length > limitToLast)
      ? entries.sublist(entries.length - limitToLast)
      : entries;

  return <String, Object?>{
    for (final entry in limited) entry.key: entry.value,
  };
}

Object? _readNestedValue(Object? value, String path) {
  Object? current = value;
  for (final segment in path.split('/')) {
    if (current is! Map) return null;
    if (!current.containsKey(segment)) return null;
    current = current[segment];
  }
  return current;
}

bool _queryValueEquals(Object? left, Object? right) {
  if (left == right) return true;
  if (left is num && right is num) return left == right;
  return left?.toString() == right?.toString();
}

class RestAppDatabaseQuery implements AppDatabaseQuery {
  const RestAppDatabaseQuery._({
    required RestAppDatabase backend,
    required String path,
    this.orderByChildPath,
    this.equalToValue,
    this.limitToLastCount,
  })  : _backend = backend,
        _path = path;

  final RestAppDatabase _backend;
  final String _path;
  final String? orderByChildPath;
  final Object? equalToValue;
  final int? limitToLastCount;

  @override
  Future<AppDatabaseSnapshot> get() {
    return _backend.get(
      path: _path,
      orderByChild: orderByChildPath,
      equalTo: equalToValue,
      limitToLast: limitToLastCount,
    );
  }

  @override
  Stream<AppDatabaseEvent> get onValue {
    return _backend.watch(
      path: _path,
      orderByChild: orderByChildPath,
      equalTo: equalToValue,
      limitToLast: limitToLastCount,
    );
  }

  @override
  AppDatabaseQuery orderByChild(String path) {
    return RestAppDatabaseQuery._(
      backend: _backend,
      path: _path,
      orderByChildPath: path,
      equalToValue: equalToValue,
      limitToLastCount: limitToLastCount,
    );
  }

  @override
  AppDatabaseQuery equalTo(Object? value) {
    return RestAppDatabaseQuery._(
      backend: _backend,
      path: _path,
      orderByChildPath: orderByChildPath,
      equalToValue: value,
      limitToLastCount: limitToLastCount,
    );
  }

  @override
  AppDatabaseQuery limitToLast(int limit) {
    return RestAppDatabaseQuery._(
      backend: _backend,
      path: _path,
      orderByChildPath: orderByChildPath,
      equalToValue: equalToValue,
      limitToLastCount: limit,
    );
  }
}

class RestAppDatabaseRef extends RestAppDatabaseQuery implements AppDatabaseRef {
  RestAppDatabaseRef._({
    required super.backend,
    required super.path,
    String? key,
  })  : _key = key ?? _lastPathSegment(path),
        super._();

  final String? _key;

  @override
  String? get key => _key;

  @override
  AppDatabaseRef child(String path) {
    final childPath = _normalizePath(path);
    final nextPath = [_path, childPath].where((segment) => segment.isNotEmpty).join('/');
    return RestAppDatabaseRef._(
      backend: _backend,
      path: nextPath,
      key: _lastPathSegment(childPath),
    );
  }

  @override
  AppDatabaseRef push() {
    final generatedKey = _PushIdGenerator.instance.next();
    return child(generatedKey);
  }

  @override
  Future<void> remove() => _backend.remove(_path);

  @override
  Future<void> set(Object? value) => _backend.set(_path, value);

  @override
  Future<void> update(Map<String, Object?> value) => _backend.update(_path, value);

  @override
  Future<AppDatabaseTransactionResult> runTransaction(
    Object? Function(Object? current) update,
  ) {
    return _backend.runTransaction(path: _path, update: update);
  }
}

String _normalizePath(String path) {
  return path
      .split('/')
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .join('/');
}

String _trimSlashes(String path) {
  var next = path.trim();
  while (next.startsWith('/')) {
    next = next.substring(1);
  }
  while (next.endsWith('/')) {
    next = next.substring(0, next.length - 1);
  }
  return next;
}

String? _lastPathSegment(String path) {
  final normalized = _normalizePath(path);
  if (normalized.isEmpty) return null;
  final segments = normalized.split('/');
  return segments.isEmpty ? null : segments.last;
}

Object? _decodeResponseBody(http.Response response) {
  if (response.body.isEmpty || response.body == 'null') {
    return null;
  }
  return jsonDecode(response.body);
}

String _fingerprint(Object? value) {
  return jsonEncode(_canonicalize(value));
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final sorted = SplayTreeMap<String, Object?>();
    value.forEach((key, raw) {
      sorted[key.toString()] = _canonicalize(raw);
    });
    return sorted;
  }
  if (value is List) {
    return value.map(_canonicalize).toList(growable: false);
  }
  return value;
}

Map<String, Object?> _normalizeUpdateKeys(Map<String, Object?> updates) {
  final normalized = <String, Object?>{};
  for (final entry in updates.entries) {
    final normalizedKey = _normalizePath(entry.key);
    if (normalizedKey.isEmpty) {
      continue;
    }
    normalized[normalizedKey] = entry.value;
  }
  return normalized;
}

class _PushIdGenerator {
  _PushIdGenerator._();

  static final _PushIdGenerator instance = _PushIdGenerator._();

  static const String _alphabet =
      '-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz';

  final Random _random = Random.secure();
  int _lastTimestamp = 0;
  final List<int> _lastRandom = List<int>.filled(12, 0);

  String next() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final duplicateTime = now == _lastTimestamp;
    _lastTimestamp = now;

    final timeChars = List<String>.filled(8, '');
    var value = now;
    for (var index = 7; index >= 0; index--) {
      timeChars[index] = _alphabet[value % 64];
      value = value ~/ 64;
    }

    if (!duplicateTime) {
      for (var index = 0; index < 12; index++) {
        _lastRandom[index] = _random.nextInt(64);
      }
    } else {
      for (var index = 11; index >= 0; index--) {
        if (_lastRandom[index] != 63) {
          _lastRandom[index]++;
          break;
        }
        _lastRandom[index] = 0;
      }
    }

    final buffer = StringBuffer()..writeAll(timeChars);
    for (final value in _lastRandom) {
      buffer.write(_alphabet[value]);
    }
    return buffer.toString();
  }
}
