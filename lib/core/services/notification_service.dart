import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

class NotificationService {
  NotificationService(this._messaging, this._profileRepository, this._auth);

  final FirebaseMessaging _messaging;
  final ProfileRepository _profileRepository;
  final FirebaseAuth _auth;

  StreamSubscription<String>? _tokenSubscription;
  String? _lastSentToken;
  String? _lastUserId;

  Future<void> configure() async {
    await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      provisional: false,
      sound: true,
    );
    await _handleAuthUser(_auth.currentUser);
    _tokenSubscription ??= _messaging.onTokenRefresh.listen((token) async {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;
      _lastUserId = uid;
      _lastSentToken = token;
      await _profileRepository.updateProfileToken(uid: uid, token: token, add: true);
    });
  }

  Future<void> _handleAuthUser(User? user) async {
    if (user == null) return;
    _lastUserId = user.uid;
    final token = await _messaging.getToken();
    if (token != null) {
      _lastSentToken = token;
      await _profileRepository.updateProfileToken(uid: user.uid, token: token, add: true);
    }
  }

  Future<void> clearToken() async {
    final uid = _lastUserId ?? _auth.currentUser?.uid;
    if (uid != null && _lastSentToken != null) {
      await _profileRepository.updateProfileToken(
        uid: uid,
        token: _lastSentToken!,
        add: false,
      );
    }
    await _messaging.deleteToken();
    _lastSentToken = null;
  }

  Future<void> handleAuthChanged(User? previous, User? current) async {
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
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final messaging = ref.watch(firebaseMessagingProvider);
  final profileRepository = ref.watch(profileRepositoryProvider);
  final auth = ref.watch(firebaseAuthProvider);
  final service = NotificationService(messaging, profileRepository, auth);
  ref.onDispose(service.dispose);
  service.configure();
  ref.listen(authStateChangesProvider, (previous, next) {
    service.handleAuthChanged(previous?.value, next.value);
  });
  return service;
});
