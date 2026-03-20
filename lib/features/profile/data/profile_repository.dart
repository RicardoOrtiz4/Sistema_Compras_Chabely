import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/firebase_database_compat.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';

class AreaOption {
  const AreaOption({required this.id, required this.name});

  final String id;
  final String name;
}

class ProfileRepository {
  ProfileRepository(this._database);

  final AppDatabase _database;

  Stream<AppUser?> watchProfile(String uid) {
    return _database.ref('users/$uid').onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return null;
      return AppUser.fromMap(uid, Map<String, dynamic>.from(value));
    });
  }

  Stream<List<AppUser>> watchUsers() {
    return _database.ref('users').onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <AppUser>[];
      final users = <AppUser>[];
      value.forEach((key, raw) {
        if (raw is Map) {
          users.add(AppUser.fromMap(key.toString(), Map<String, dynamic>.from(raw)));
        }
      });
      users.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return users;
    });
  }

  Stream<List<AreaOption>> watchAreas() {
    return _database.ref('areas').onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <AreaOption>[];
      final areas = <AreaOption>[];
      value.forEach((key, raw) {
        final id = key.toString();
        var name = id;
        if (raw is Map && raw['name'] is String) {
          final rawName = (raw['name'] as String).trim();
          if (rawName.isNotEmpty) {
            name = rawName;
          }
        } else if (raw is String) {
          final rawName = raw.trim();
          if (rawName.isNotEmpty) {
            name = rawName;
          }
        }
        areas.add(AreaOption(id: id, name: normalizeAreaLabel(name)));
      });
      areas.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return areas;
    });
  }

  Future<void> updateProfileToken({
    required String uid,
    required String token,
    required bool add,
  }) async {
    final ref = _database.ref('users/$uid');
    await ref.update({'updatedAt': appServerTimestamp});
    final tokenKey = _encodeTokenKey(token);
    final tokenRef = ref.child('fcmTokens/$tokenKey');
    if (add) {
      await tokenRef.set(token);
    } else {
      await tokenRef.remove();
    }
  }

  Future<void> updateUserProfile({
    required String uid,
    required String role,
    required String areaId,
    required String areaName,
  }) async {
    await _database.ref('users/$uid').update({
      'role': role,
      'areaId': areaId,
      'areaName': areaName,
      'updatedAt': appServerTimestamp,
    });
  }

  Future<void> updateContactEmail({
    required String uid,
    required String contactEmail,
  }) async {
    final trimmed = contactEmail.trim();
    await _database.ref('users/$uid').update({
      'contactEmail': trimmed.isEmpty ? null : trimmed,
      'updatedAt': appServerTimestamp,
    });
  }

  Future<void> createUserWithRole({
    required String name,
    required String email,
    required String password,
    required String role,
    required String areaId,
  }) async {
    throw StateError('Operacion no disponible sin Cloud Functions.');
  }

  Future<void> deleteUser({required String uid}) async {
    throw StateError('Operacion no disponible sin Cloud Functions.');
  }

  Future<void> seedAreas() async {
    final areasRef = _database.ref('areas');
    final snapshot = await areasRef.get();
    if (!snapshot.exists) {
      await areasRef.set(_defaultAreas);
      return;
    }
    if (snapshot.value is! Map) {
      await areasRef.set(_defaultAreas);
      return;
    }
    final existing = Map<String, dynamic>.from(snapshot.value as Map);
    final updates = <String, dynamic>{};
    for (final entry in _defaultAreas.entries) {
      if (!existing.containsKey(entry.key)) {
        updates[entry.key] = entry.value;
      }
    }
    if (updates.isNotEmpty) {
      await areasRef.update(updates);
    }
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final database = ref.watch(firebaseDatabaseProvider);
  return ProfileRepository(database);
});

String _encodeTokenKey(String token) {
  return token.replaceAll(RegExp(r'[.#$\\[\\]/]'), '_');
}

const _defaultAreas = <String, Map<String, String>>{
  'Compras': {'name': 'Compras'},
  'Gerencia': {'name': 'Dirección General'},
  'Contabilidad': {'name': 'Contabilidad'},
  'Software': {'name': 'Software'},
};
final currentUserProfileProvider = StreamProvider<AppUser?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream.value(null);
  }
  final repository = ref.watch(profileRepositoryProvider);
  return repository.watchProfile(uid);
});

final allUsersProvider = StreamProvider<List<AppUser>>((ref) {
  final repository = ref.watch(profileRepositoryProvider);
  return repository.watchUsers();
});

final areasProvider = StreamProvider<List<AreaOption>>((ref) {
  final repository = ref.watch(profileRepositoryProvider);
  return repository.watchAreas();
});
