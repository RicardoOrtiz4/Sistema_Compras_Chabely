import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/app_auth.dart';
import 'package:sistema_compras/core/firebase_database_compat.dart';

final appAuthProvider = Provider<AppAuthClient>((ref) {
  final auth = createAppAuthClient();
  ref.onDispose(auth.dispose);
  return auth;
});

final firebaseDatabaseProvider = Provider<AppDatabase>((ref) {
  final auth = ref.watch(appAuthProvider);
  return createAppDatabase(auth);
});

final firebaseFunctionsProvider = Provider<FirebaseFunctions>((ref) {
  return FirebaseFunctions.instanceFor(region: 'us-central1');
});

final firebaseMessagingProvider = Provider<FirebaseMessaging>((ref) {
  return FirebaseMessaging.instance;
});

final authStateChangesProvider = StreamProvider<AppAuthUser?>((ref) {
  final auth = ref.watch(appAuthProvider);
  return auth.authStateChanges();
});

final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authStateChangesProvider).value?.uid;
});
