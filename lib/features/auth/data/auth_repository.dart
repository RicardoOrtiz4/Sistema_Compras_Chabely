import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/app_auth.dart';
import 'package:sistema_compras/core/firebase_database_compat.dart';
import 'package:sistema_compras/core/providers.dart';

class AuthRepository {
  AuthRepository(this._auth, this._database);

  final AppAuthClient _auth;
  final AppDatabase _database;

  Stream<AppAuthUser?> authStateChanges() => _auth.authStateChanges();

  Future<AppAuthUser> signIn({
    required String email,
    required String password,
  }) async {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> ensureUserDocument(AppAuthUser user) async {
    final ref = _database.ref('users/${user.uid}');
    final snapshot = await ref.get();
    if (snapshot.exists) return;
    await ref.set({
      'name': user.displayName ?? user.email?.split('@').first ?? 'Usuario',
      'email': user.email,
      'role': 'usuario',
      'areaId': 'por-definir',
      'isActive': true,
      'createdAt': appServerTimestamp,
      'updatedAt': appServerTimestamp,
    });
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final auth = ref.watch(appAuthProvider);
  final database = ref.watch(firebaseDatabaseProvider);
  return AuthRepository(auth, database);
});
