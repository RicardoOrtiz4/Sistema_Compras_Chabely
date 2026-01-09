import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';

class ProfileRepository {
  ProfileRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<AppUser?> watchProfile(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return AppUser.fromMap(snapshot.id, snapshot.data()!);
    });
  }

  Future<void> updateProfileToken({
    required String uid,
    required String token,
    required bool add,
  }) async {
    final docRef = _firestore.collection('users').doc(uid);
    await docRef.update({
      'fcmTokens': add ? FieldValue.arrayUnion([token]) : FieldValue.arrayRemove([token]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return ProfileRepository(firestore);
});
final currentUserProfileProvider = StreamProvider<AppUser?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return const Stream.empty();
  }
  final repository = ref.watch(profileRepositoryProvider);
  return repository.watchProfile(uid);
});

