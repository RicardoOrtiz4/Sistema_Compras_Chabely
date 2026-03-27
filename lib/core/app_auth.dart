import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

abstract class AppAuthUser {
  String get uid;

  String? get email;

  String? get displayName;

  Future<String?> getIdToken({bool forceRefresh = false});
}

abstract class AppAuthClient {
  AppAuthUser? get currentUser;

  Stream<AppAuthUser?> authStateChanges();

  Future<AppAuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  });

  Future<void> signOut();

  void dispose() {}
}

AppAuthClient createAppAuthClient() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    return RestAppAuthClient(
      apiKey: Firebase.app().options.apiKey,
    );
  }
  return FirebaseAppAuthClient(FirebaseAuth.instance);
}

bool get _useWindowsReleaseRestAuthCompatibility =>
    kReleaseMode && !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

class FirebaseAppAuthClient implements AppAuthClient {
  FirebaseAppAuthClient(this._auth);

  final FirebaseAuth _auth;

  @override
  AppAuthUser? get currentUser {
    final user = _auth.currentUser;
    return user == null ? null : FirebaseAppAuthUser(user);
  }

  @override
  Stream<AppAuthUser?> authStateChanges() {
    return _auth.authStateChanges().map((user) {
      return user == null ? null : FirebaseAppAuthUser(user);
    });
  }

  @override
  Future<AppAuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'unknown-error',
        message: 'No se pudo obtener el usuario autenticado.',
      );
    }
    return FirebaseAppAuthUser(user);
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  void dispose() {}
}

class FirebaseAppAuthUser implements AppAuthUser {
  FirebaseAppAuthUser(this._user);

  final User _user;

  @override
  String? get displayName => _user.displayName;

  @override
  String? get email => _user.email;

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) {
    return _user.getIdToken(forceRefresh);
  }

  @override
  String get uid => _user.uid;
}

class RestAppAuthClient implements AppAuthClient {
  RestAppAuthClient({
    required String apiKey,
    http.Client? client,
  })  : _apiKey = apiKey,
        _client = client ?? http.Client() {
    unawaited(_restorePersistedSession());
  }

  static const String _prefsKey = 'windows_rest_auth_session_v1';
  static const Duration _refreshSkew = Duration(minutes: 5);

  final String _apiKey;
  final http.Client _client;
  final StreamController<AppAuthUser?> _controller =
      StreamController<AppAuthUser?>.broadcast();

  _RestAuthSession? _session;
  AppAuthUser? _currentUser;
  Future<void>? _restoreFuture;
  Future<void>? _refreshFuture;

  @override
  AppAuthUser? get currentUser => _currentUser;

  @override
  Stream<AppAuthUser?> authStateChanges() => _controller.stream;

  @override
  Future<AppAuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final response = await _postRequest(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$_apiKey',
      ),
      headers: const <String, String>{
        'Content-Type': 'application/json',
        'Connection': 'close',
      },
      body: jsonEncode(<String, Object>{
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
    );

    final body = _decodeJsonBody(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _parseAuthException(body);
    }

    final session = _RestAuthSession.fromSignInResponse(body);
    await _persistSession(session);
    _setSession(session, emit: true);
    final user = _currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'unknown-error',
        message: 'No se pudo restablecer la sesión en Windows.',
      );
    }
    return user;
  }

  @override
  Future<void> signOut() async {
    await _clearSession();
    _setSession(null, emit: true);
  }

  @override
  void dispose() {
    _controller.close();
    _client.close();
  }

  Future<void> _restorePersistedSession() {
    return _restoreFuture ??= _restorePersistedSessionImpl();
  }

  Future<void> _restorePersistedSessionImpl() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) {
      _setSession(null, emit: true);
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await _clearSession();
        _setSession(null, emit: true);
        return;
      }

      final session = _RestAuthSession.fromStoredJson(decoded);
      _setSession(session, emit: false);
      await _ensureFreshToken(forceRefresh: session.needsRefresh);
      _controller.add(_currentUser);
    } catch (_) {
      await _clearSession();
      _setSession(null, emit: true);
    }
  }

  Future<String?> getIdToken({bool forceRefresh = false}) async {
    _logWindowsReleaseAuthStep(
      'getIdToken:start forceRefresh=$forceRefresh hasSession=${_session != null}',
    );
    await _restorePersistedSession();
    _logWindowsReleaseAuthStep(
      'getIdToken:restored hasSession=${_session != null}',
    );
    if (_session == null) return null;
    await _ensureFreshToken(forceRefresh: forceRefresh || _session!.needsRefresh);
    _logWindowsReleaseAuthStep(
      'getIdToken:done hasToken=${_session?.idToken.isNotEmpty ?? false}',
    );
    return _session?.idToken;
  }

  Future<void> _ensureFreshToken({required bool forceRefresh}) async {
    final session = _session;
    if (session == null) return;
    if (!forceRefresh && !session.needsRefresh) return;

    _refreshFuture ??= _refreshToken(session.refreshToken);
    try {
      await _refreshFuture;
    } finally {
      _refreshFuture = null;
    }
  }

  Future<void> _refreshToken(String refreshToken) async {
    _logWindowsReleaseAuthStep('refreshToken:start');
    final response = await _postRequest(
      Uri.parse(
        'https://securetoken.googleapis.com/v1/token?key=$_apiKey',
      ),
      headers: const <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded',
        'Connection': 'close',
      },
      body: <String, String>{
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    );

    final body = _decodeJsonBody(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await _clearSession();
      _setSession(null, emit: true);
      throw _parseAuthException(body);
    }

    final current = _session;
    if (current == null) return;

    final refreshed = current.refresh(body);
    await _persistSession(refreshed);
    _setSession(refreshed, emit: true);
    _logWindowsReleaseAuthStep('refreshToken:done');
  }

  Future<void> _persistSession(_RestAuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(session.toJson()));
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  Future<http.Response> _postRequest(
    Uri uri, {
    required Map<String, String> headers,
    required Object body,
  }) async {
    _logWindowsReleaseAuthStep('_postRequest:start uri=${uri.host}${uri.path}');
    if (_useWindowsReleaseRestAuthCompatibility) {
      final client = http.Client();
      try {
        final response = await client.post(
          uri,
          headers: headers,
          body: body,
        );
        _logWindowsReleaseAuthStep(
          '_postRequest:done uri=${uri.host}${uri.path} status=${response.statusCode}',
        );
        return response;
      } finally {
        client.close();
      }
    }
    final response = await _client.post(
      uri,
      headers: headers,
      body: body,
    );
    _logWindowsReleaseAuthStep(
      '_postRequest:done uri=${uri.host}${uri.path} status=${response.statusCode}',
    );
    return response;
  }

  void _setSession(_RestAuthSession? session, {required bool emit}) {
    _session = session;
    _currentUser = session == null ? null : _RestAppAuthUser(this, session);
    if (emit) {
      _controller.add(_currentUser);
    }
  }
}

void _logWindowsReleaseAuthStep(String message) {
  // Crash investigation instrumentation removed.
}

class _RestAppAuthUser implements AppAuthUser {
  _RestAppAuthUser(this._client, this._session);

  final RestAppAuthClient _client;
  final _RestAuthSession _session;

  @override
  String? get displayName => _session.displayName;

  @override
  String? get email => _session.email;

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) {
    return _client.getIdToken(forceRefresh: forceRefresh);
  }

  @override
  String get uid => _session.localId;
}

class _RestAuthSession {
  const _RestAuthSession({
    required this.localId,
    required this.email,
    required this.displayName,
    required this.idToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String localId;
  final String? email;
  final String? displayName;
  final String idToken;
  final String refreshToken;
  final DateTime expiresAt;

  bool get needsRefresh =>
      DateTime.now().isAfter(expiresAt.subtract(RestAppAuthClient._refreshSkew));

  factory _RestAuthSession.fromSignInResponse(Map<String, dynamic> json) {
    return _RestAuthSession(
      localId: (json['localId'] as String?) ?? '',
      email: json['email'] as String?,
      displayName: json['displayName'] as String?,
      idToken: (json['idToken'] as String?) ?? '',
      refreshToken: (json['refreshToken'] as String?) ?? '',
      expiresAt: DateTime.now().add(
        Duration(seconds: _parseExpiresIn(json['expiresIn'])),
      ),
    );
  }

  factory _RestAuthSession.fromStoredJson(Map<String, dynamic> json) {
    return _RestAuthSession(
      localId: (json['localId'] as String?) ?? '',
      email: json['email'] as String?,
      displayName: json['displayName'] as String?,
      idToken: (json['idToken'] as String?) ?? '',
      refreshToken: (json['refreshToken'] as String?) ?? '',
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (json['expiresAtMillis'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  _RestAuthSession refresh(Map<String, dynamic> json) {
    return _RestAuthSession(
      localId: (json['user_id'] as String?) ?? localId,
      email: email,
      displayName: displayName,
      idToken: (json['id_token'] as String?) ?? idToken,
      refreshToken: (json['refresh_token'] as String?) ?? refreshToken,
      expiresAt: DateTime.now().add(
        Duration(seconds: _parseExpiresIn(json['expires_in'])),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'localId': localId,
      'email': email,
      'displayName': displayName,
      'idToken': idToken,
      'refreshToken': refreshToken,
      'expiresAtMillis': expiresAt.millisecondsSinceEpoch,
    };
  }
}

Map<String, dynamic> _decodeJsonBody(String body) {
  if (body.trim().isEmpty) return const <String, dynamic>{};
  final decoded = jsonDecode(body);
  if (decoded is Map<String, dynamic>) return decoded;
  return const <String, dynamic>{};
}

FirebaseAuthException _parseAuthException(Map<String, dynamic> body) {
  final error = body['error'];
  final rawMessage = error is Map ? error['message']?.toString() : null;
  final normalized = (rawMessage ?? 'UNKNOWN').trim().toUpperCase();

  switch (normalized) {
    case 'INVALID_PASSWORD':
      return FirebaseAuthException(
        code: 'wrong-password',
        message: 'Contraseña incorrecta.',
      );
    case 'EMAIL_NOT_FOUND':
      return FirebaseAuthException(
        code: 'user-not-found',
        message: 'No existe una cuenta con ese correo.',
      );
    case 'INVALID_LOGIN_CREDENTIALS':
      return FirebaseAuthException(
        code: 'invalid-credential',
        message: 'Correo o contraseña incorrectos.',
      );
    case 'USER_DISABLED':
      return FirebaseAuthException(
        code: 'user-disabled',
        message: 'La cuenta está deshabilitada.',
      );
    case 'TOO_MANY_ATTEMPTS_TRY_LATER':
      return FirebaseAuthException(
        code: 'too-many-requests',
        message: 'Demasiados intentos. Intenta más tarde.',
      );
    case 'INVALID_API_KEY':
      return FirebaseAuthException(
        code: 'invalid-api-key',
        message: 'La configuración de Firebase Auth es inválida en Windows.',
      );
    case 'NETWORK_REQUEST_FAILED':
      return FirebaseAuthException(
        code: 'network-request-failed',
        message: 'No se pudo conectar con Firebase Auth.',
      );
    case 'OPERATION_NOT_ALLOWED':
      return FirebaseAuthException(
        code: 'operation-not-allowed',
        message: 'El acceso con correo y contraseña no está habilitado.',
      );
    default:
      return FirebaseAuthException(
        code: 'unknown-error',
        message: rawMessage ?? 'Ocurrió un error interno en Firebase Auth.',
      );
  }
}

int _parseExpiresIn(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) {
    final parsed = int.tryParse(raw);
    if (parsed != null) return parsed;
  }
  return 3600;
}
