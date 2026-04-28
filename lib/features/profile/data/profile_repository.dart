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

  Future<AppUser?> fetchProfile(String uid) async {
    final trimmedUid = uid.trim();
    if (trimmedUid.isEmpty) return null;
    final snapshot = await _database.ref('users/$trimmedUid').get();
    final value = snapshot.value;
    if (value is! Map) return null;
    return AppUser.fromMap(trimmedUid, Map<String, dynamic>.from(value));
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
    return Stream.value(_requiredAreaOptions);
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

  Future<void> updateAdminEditableProfile({
    required String uid,
    required String name,
    required String role,
    required String areaId,
    required String areaName,
  }) async {
    final trimmedName = name.trim();
    await _database.ref('users/$uid').update({
      'name': trimmedName,
      'role': role,
      'areaId': areaId,
      'areaName': areaName,
      'updatedAt': appServerTimestamp,
    });
  }

  Future<void> seedAreas() async {
    final areasRef = _database.ref('areas');
    final snapshot = await areasRef.get();
    if (!snapshot.exists) {
      await areasRef.set(_requiredDefaultAreas);
      return;
    }
    if (snapshot.value is! Map) {
      await areasRef.set(_requiredDefaultAreas);
      return;
    }
    final existing = Map<String, dynamic>.from(snapshot.value as Map);
    final updates = <String, dynamic>{};
    for (final entry in _requiredDefaultAreas.entries) {
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

const _requiredDefaultAreas = <String, Map<String, String>>{
  adminAreaLabel: {'name': adminAreaLabel},
  direccionGeneralLabel: {'name': direccionGeneralLabel},
  contraloriaLabel: {'name': contraloriaLabel},
  comprasLabel: {'name': comprasLabel},
  'Sistema de Gestión de Calidad (SGC)': {
    'name': 'Sistema de Gestión de Calidad (SGC)',
  },
  'Ventas (VEN)': {'name': 'Ventas (VEN)'},
  'Desarrollo y Nuevos Proyectos (DNP)': {
    'name': 'Desarrollo y Nuevos Proyectos (DNP)',
  },
  'Ingenieria de Manufactura (IMA)': {
    'name': 'Ingenieria de Manufactura (IMA)',
  },
  'Planeacion y Control de la Produccion (PPR)': {
    'name': 'Planeacion y Control de la Produccion (PPR)',
  },
  'Produccion (PRO)': {'name': 'Produccion (PRO)'},
  'Control de Calidad (CCA)': {'name': 'Control de Calidad (CCA)'},
  'Almacenes (ALM)': {'name': 'Almacenes (ALM)'},
  'Mantenimiento (MAN)': {'name': 'Mantenimiento (MAN)'},
  'Recursos Humanos (RHU)': {'name': 'Recursos Humanos (RHU)'},
  'Seguridad e Higiene (EHS)': {'name': 'Seguridad e Higiene (EHS)'},
  contabilidadLabel: {'name': contabilidadLabel},
  tesoreriaLabel: {'name': tesoreriaLabel},
  nominasLabel: {'name': nominasLabel},
};

const _requiredAreaOptions = <AreaOption>[
  AreaOption(id: direccionGeneralLabel, name: direccionGeneralLabel),
  AreaOption(id: contraloriaLabel, name: contraloriaLabel),
  AreaOption(id: comprasLabel, name: comprasLabel),
  AreaOption(
    id: 'Sistema de Gestión de Calidad (SGC)',
    name: 'Sistema de Gestión de Calidad (SGC)',
  ),
  AreaOption(id: 'Ventas (VEN)', name: 'Ventas (VEN)'),
  AreaOption(
    id: 'Desarrollo y Nuevos Proyectos (DNP)',
    name: 'Desarrollo y Nuevos Proyectos (DNP)',
  ),
  AreaOption(
    id: 'Ingenieria de Manufactura (IMA)',
    name: 'Ingenieria de Manufactura (IMA)',
  ),
  AreaOption(
    id: 'Planeacion y Control de la Produccion (PPR)',
    name: 'Planeacion y Control de la Produccion (PPR)',
  ),
  AreaOption(id: 'Produccion (PRO)', name: 'Produccion (PRO)'),
  AreaOption(id: 'Control de Calidad (CCA)', name: 'Control de Calidad (CCA)'),
  AreaOption(id: 'Almacenes (ALM)', name: 'Almacenes (ALM)'),
  AreaOption(id: 'Mantenimiento (MAN)', name: 'Mantenimiento (MAN)'),
  AreaOption(id: 'Recursos Humanos (RHU)', name: 'Recursos Humanos (RHU)'),
  AreaOption(
    id: 'Seguridad e Higiene (EHS)',
    name: 'Seguridad e Higiene (EHS)',
  ),
  AreaOption(id: contabilidadLabel, name: contabilidadLabel),
  AreaOption(id: tesoreriaLabel, name: tesoreriaLabel),
  AreaOption(id: nominasLabel, name: nominasLabel),
];
final currentUserProfileProvider = StreamProvider<AppUser?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream.value(null);
  }
  final repository = ref.watch(profileRepositoryProvider);
  return Stream<AppUser?>.multi((controller) {
    final timeout = Timer(const Duration(seconds: 12), () {
      controller.addError(
        TimeoutException(
          'No se pudo cargar el perfil del usuario a tiempo.',
        ),
      );
    });
    var firstEventReceived = false;
    final proxiedSubscription = repository.watchProfile(uid).listen(
      (event) {
        if (!firstEventReceived) {
          firstEventReceived = true;
          timeout.cancel();
        }
        controller.add(event);
      },
      onError: (Object error, StackTrace stackTrace) {
        timeout.cancel();
        controller.addError(error, stackTrace);
      },
      onDone: () {
        timeout.cancel();
        controller.close();
      },
    );
    controller.onCancel = () async {
      timeout.cancel();
      await proxiedSubscription.cancel();
    };
  });
});

final allUsersProvider = StreamProvider<List<AppUser>>((ref) {
  final repository = ref.watch(profileRepositoryProvider);
  return repository.watchUsers();
});

final areasProvider = StreamProvider<List<AreaOption>>((ref) {
  final repository = ref.watch(profileRepositoryProvider);
  return repository.watchAreas();
});
