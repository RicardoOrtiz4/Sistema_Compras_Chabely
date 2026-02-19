import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/providers.dart';

class AuthRepository {
  AuthRepository(this._auth, this._database);

  final FirebaseAuth _auth;
  final FirebaseDatabase _database;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<void> signIn({required String email, required String password}) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> ensureUserDocument(User user) async {
    final ref = _database.ref('users/${user.uid}');
    final snapshot = await ref.get();
    if (snapshot.exists) return;
    await ref.set({
      'name': user.displayName ?? user.email?.split('@').first ?? 'Usuario',
      'email': user.email,
      'role': 'usuario',
      'areaId': 'por-definir',
      'isActive': true,
      'createdAt': ServerValue.timestamp,
      'updatedAt': ServerValue.timestamp,
    });
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  final database = ref.watch(firebaseDatabaseProvider);
  return AuthRepository(auth, database);
});
