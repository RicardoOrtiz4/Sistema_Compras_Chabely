import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/providers.dart';

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
  });

  final String id;
  final String name;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'createdAt': createdAt?.millisecondsSinceEpoch,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
    };
  }

  factory PartnerEntry.fromMap(String id, Map<String, dynamic> data) {
    return PartnerEntry(
      id: id,
      name: (data['name'] as String?) ?? '',
      createdAt: _parseDateTime(data['createdAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
    );
  }
}

class PartnerRepository {
  PartnerRepository(this._database, this._company);

  final FirebaseDatabase _database;
  final Company _company;

  DatabaseReference _partnersRef(PartnerType type, String uid) {
    return _database.ref('companies/${_company.name}/partners/${type.path}/$uid');
  }

  Stream<List<PartnerEntry>> watchPartners({
    required String uid,
    required PartnerType type,
  }) {
    return _partnersRef(type, uid).onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <PartnerEntry>[];

      final partners = <PartnerEntry>[];
      value.forEach((key, raw) {
        if (raw is Map) {
          partners.add(
            PartnerEntry.fromMap(
              key.toString(),
              Map<String, dynamic>.from(raw),
            ),
          );
        }
      });

      partners.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return partners;
    });
  }

  Future<void> createPartner({
    required String uid,
    required PartnerType type,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw StateError('Nombre requerido.');
    }

    final ref = _partnersRef(type, uid).push();
    await ref.set({
      'name': trimmed,
      'createdAt': ServerValue.timestamp,
      'updatedAt': ServerValue.timestamp,
    });
  }

  Future<void> updatePartner({
    required String uid,
    required PartnerType type,
    required String id,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw StateError('Nombre requerido.');
    }

    await _partnersRef(type, uid).child(id).update({
      'name': trimmed,
      'updatedAt': ServerValue.timestamp,
    });
  }

  Future<void> deletePartner({
    required String uid,
    required PartnerType type,
    required String id,
  }) async {
    await _partnersRef(type, uid).child(id).remove();
  }
}

final partnerRepositoryProvider = Provider<PartnerRepository>((ref) {
  final database = ref.watch(firebaseDatabaseProvider);
  final company = ref.watch(currentCompanyProvider);
  return PartnerRepository(database, company);
});

final userSuppliersProvider = StreamProvider<List<PartnerEntry>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(const <PartnerEntry>[]);

  final repository = ref.watch(partnerRepositoryProvider);
  return repository.watchPartners(uid: uid, type: PartnerType.supplier);
});

final userClientsProvider = StreamProvider<List<PartnerEntry>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(const <PartnerEntry>[]);

  final repository = ref.watch(partnerRepositoryProvider);
  return repository.watchPartners(uid: uid, type: PartnerType.client);
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
