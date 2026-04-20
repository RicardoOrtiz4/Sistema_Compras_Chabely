import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistema_compras/core/extensions.dart';

import 'package:sistema_compras/core/firebase_database_compat.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';

enum PartnerType { supplier, client }

extension PartnerTypeX on PartnerType {
  String get label {
    switch (this) {
      case PartnerType.supplier:
        return 'Proveedor';
      case PartnerType.client:
        return 'Cliente';
    }
  }

  String get pluralLabel {
    switch (this) {
      case PartnerType.supplier:
        return 'Proveedores';
      case PartnerType.client:
        return 'Clientes';
    }
  }

  String get path {
    switch (this) {
      case PartnerType.supplier:
        return 'suppliers';
      case PartnerType.client:
        return 'clients';
    }
  }
}

class PartnerEntry {
  const PartnerEntry({
    required this.id,
    required this.name,
    this.createdAt,
    this.updatedAt,
    this.createdById,
    this.createdByName,
    this.createdByArea,
    this.updatedById,
    this.updatedByName,
    this.updatedByArea,
  });

  final String id;
  final String name;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdById;
  final String? createdByName;
  final String? createdByArea;
  final String? updatedById;
  final String? updatedByName;
  final String? updatedByArea;

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'createdAt': createdAt?.millisecondsSinceEpoch,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
      'createdById': createdById,
      'createdByName': createdByName,
      'createdByArea': createdByArea,
      'updatedById': updatedById,
      'updatedByName': updatedByName,
      'updatedByArea': updatedByArea,
    };
  }

  factory PartnerEntry.fromMap(String id, Map<String, dynamic> data) {
    return PartnerEntry(
      id: id,
      name: (data['name'] as String?) ?? '',
      createdAt: _parseDateTime(data['createdAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
      createdById: data['createdById'] as String?,
      createdByName: data['createdByName'] as String?,
      createdByArea: data['createdByArea'] as String?,
      updatedById: data['updatedById'] as String?,
      updatedByName: data['updatedByName'] as String?,
      updatedByArea: data['updatedByArea'] as String?,
    );
  }
}

class PartnerRepository {
  PartnerRepository(this._database);

  final AppDatabase _database;

  AppDatabaseRef _partnersRef(PartnerType type) {
    return _database.ref('partners/${type.path}');
  }

  Stream<List<PartnerEntry>> watchPartners({
    required PartnerType type,
  }) {
    return _partnersRef(type).onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <PartnerEntry>[];

      final partners = <PartnerEntry>[];
      value.forEach((key, raw) {
        if (raw is Map) {
          final data = Map<String, dynamic>.from(raw);
          if (data['name'] is String) {
            partners.add(
              PartnerEntry.fromMap(
                key.toString(),
                data,
              ),
            );
            return;
          }

          data.forEach((legacyKey, legacyRaw) {
            if (legacyRaw is! Map) return;
            final legacyData = Map<String, dynamic>.from(legacyRaw);
            if (legacyData['name'] is! String) return;
            partners.add(
              PartnerEntry.fromMap(
                '${key.toString()}/${legacyKey.toString()}',
                {
                  ...legacyData,
                  'createdById': legacyData['createdById'] ?? key.toString(),
                },
              ),
            );
          });
        }
      });

      partners.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return partners;
    });
  }

  Future<String> createPartner({
    required String uid,
    required PartnerType type,
    required String name,
    AppUser? actor,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw StateError('Nombre requerido.');
    }

    final ref = _partnersRef(type).push();
    await ref.set({
      'name': trimmed,
      'createdAt': appServerTimestamp,
      'updatedAt': appServerTimestamp,
      'createdById': actor?.id ?? uid,
      'createdByName': actor?.name.trim(),
      'createdByArea': actor?.areaDisplay.trim(),
      'updatedById': actor?.id ?? uid,
      'updatedByName': actor?.name.trim(),
      'updatedByArea': actor?.areaDisplay.trim(),
    });
    return ref.key ?? trimmed;
  }

  Future<void> updatePartner({
    required String uid,
    required PartnerType type,
    required String id,
    required String name,
    AppUser? actor,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw StateError('Nombre requerido.');
    }

    await _partnersRef(type).child(id).update({
      'name': trimmed,
      'updatedAt': appServerTimestamp,
      'updatedById': actor?.id ?? uid,
      'updatedByName': actor?.name.trim(),
      'updatedByArea': actor?.areaDisplay.trim(),
    });
  }

  Future<void> deletePartner({
    required String uid,
    required PartnerType type,
    required String id,
  }) async {
    await _partnersRef(type).child(id).remove();
  }
}

final partnerRepositoryProvider = Provider<PartnerRepository>((ref) {
  final database = ref.watch(firebaseDatabaseProvider);
  return PartnerRepository(database);
});

final userSuppliersProvider = StreamProvider<List<PartnerEntry>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(const <PartnerEntry>[]);

  final repository = ref.watch(partnerRepositoryProvider);
  return repository.watchPartners(type: PartnerType.supplier);
});

final userClientsProvider = StreamProvider<List<PartnerEntry>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(const <PartnerEntry>[]);

  final repository = ref.watch(partnerRepositoryProvider);
  return repository.watchPartners(type: PartnerType.client);
});

final userSupplierNamesProvider = Provider<List<String>>((ref) {
  final suppliers = ref.watch(userSuppliersProvider).valueOrNull;
  if (suppliers == null || suppliers.isEmpty) {
    return const <String>[];
  }
  return List<String>.unmodifiable(
    suppliers.map((entry) => entry.name),
  );
});

final userClientNamesProvider = Provider<List<String>>((ref) {
  final clients = ref.watch(userClientsProvider).valueOrNull;
  if (clients == null || clients.isEmpty) {
    return const <String>[];
  }
  return List<String>.unmodifiable(
    clients.map((entry) => entry.name),
  );
});

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;

  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is double) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }

  return null;
}
