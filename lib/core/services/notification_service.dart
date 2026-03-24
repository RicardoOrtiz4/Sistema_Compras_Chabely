import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sistema_compras/core/app_auth.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/navigation/app_shell_keys.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

class NotificationService {
  NotificationService(this._messaging, this._profileRepository, this._auth);

  final FirebaseMessaging? _messaging;
  final ProfileRepository _profileRepository;
  final AppAuthClient _auth;

  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _openedAppSubscription;
  String? _lastSentToken;
  String? _lastUserId;

  Future<void> configure() async {
    final messaging = _messaging;
    if (messaging == null) return;

    await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      provisional: false,
      sound: true,
    );

    await _handleAuthUser(_auth.currentUser);

    _tokenSubscription = messaging.onTokenRefresh.listen((token) async {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      _lastUserId = uid;
      _lastSentToken = token;

      await _profileRepository.updateProfileToken(
        uid: uid,
        token: token,
        add: true,
      );
    });

    _messageSubscription ??= FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    _openedAppSubscription ??=
        FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleOpenedMessage(initialMessage);
    }
  }

  Future<void> _handleAuthUser(AppAuthUser? user) async {
    final messaging = _messaging;
    if (user == null || messaging == null) return;

    _lastUserId = user.uid;

    final token = await messaging.getToken();
    if (token != null) {
      _lastSentToken = token;
      await _profileRepository.updateProfileToken(
        uid: user.uid,
        token: token,
        add: true,
      );
    }
  }

  Future<void> clearToken() async {
    final messaging = _messaging;
    if (messaging == null) return;

    final uid = _lastUserId ?? _auth.currentUser?.uid;

    if (uid != null && _lastSentToken != null) {
      await _profileRepository.updateProfileToken(
        uid: uid,
        token: _lastSentToken!,
        add: false,
      );
    }

    await messaging.deleteToken();
    _lastSentToken = null;
    _lastUserId = null;
  }

  Future<void> handleAuthChanged(AppAuthUser? previous, AppAuthUser? current) async {
    if (previous?.uid != null && previous?.uid != current?.uid) {
      _lastUserId = previous!.uid;
      await clearToken();
    }

    if (current != null) {
      await _handleAuthUser(current);
    }
  }

  void dispose() {
    _tokenSubscription?.cancel();
    _messageSubscription?.cancel();
    _openedAppSubscription?.cancel();
    _tokenSubscription = null;
    _messageSubscription = null;
    _openedAppSubscription = null;
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    final title = notification?.title?.trim();
    final body = notification?.body?.trim();
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }

    final messenger = appScaffoldMessengerKey.currentState;
    if (messenger == null) return;

    final hasTarget =
        _extractRoute(message) != null || _extractOrderId(message) != null;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            [
              if (title != null && title.isNotEmpty) title,
              if (body != null && body.isNotEmpty) body,
            ].join('\n'),
          ),
          action: !hasTarget
              ? null
              : SnackBarAction(
                  label: 'Ver',
                  onPressed: () => _openTarget(message),
                ),
        ),
      );
  }

  void _handleOpenedMessage(RemoteMessage message) {
    _openTarget(message);
  }

  String? _extractOrderId(RemoteMessage message) {
    final rawValue = message.data['orderId'];
    final raw = rawValue is String ? rawValue.trim() : '';
    if (raw.isEmpty) return null;
    return raw;
  }

  String? _extractRoute(RemoteMessage message) {
    final rawValue = message.data['route'];
    final raw = rawValue is String ? rawValue.trim() : '';
    if (raw.isEmpty) return null;
    return raw;
  }

  void _openTarget(RemoteMessage message) {
    final route = _extractRoute(message);
    if (route != null) {
      _openRoute(route);
      return;
    }
    final orderId = _extractOrderId(message);
    if (orderId != null) {
      _openOrder(orderId);
    }
  }

  void _openOrder(String orderId) {
    _openRoute('/orders/$orderId');
  }

  void _openRoute(String route) {
    final context = appNavigatorKey.currentContext;
    if (context != null) {
      GoRouter.of(context).push(route);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final retryContext = appNavigatorKey.currentContext;
      if (retryContext == null) return;
      GoRouter.of(retryContext).push(route);
    });
  }
}

bool _supportsMessaging() {
  if (kIsWeb) return true;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return true;
    default:
      return false;
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  FirebaseMessaging? messaging;

  if (_supportsMessaging()) {
    try {
      messaging = ref.watch(firebaseMessagingProvider);
    } catch (error, stack) {
      logError(error, stack, context: 'NotificationService.messaging');
      messaging = null;
    }
  }

  final profileRepository = ref.watch(profileRepositoryProvider);
  final auth = ref.watch(appAuthProvider);

  final service = NotificationService(messaging, profileRepository, auth);

  ref.onDispose(service.dispose);

  // Configurar sin bloquear el build del provider
  try {
    unawaited(
      service.configure().catchError((error, stack) {
        logError(error, stack, context: 'NotificationService.configure');
      }),
    );
  } catch (error, stack) {
    logError(error, stack, context: 'NotificationService.configure');
  }

  ref.listen(authStateChangesProvider, (previous, next) {
    service.handleAuthChanged(previous?.value, next.value);
  });

  return service;
});
