import 'package:sistema_compras/core/area_labels.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.areaId,
    this.areaName,
    this.contactEmail,
    required this.isActive,
    this.createdAt,
    this.fcmTokens = const [],
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final String areaId;
  final String? areaName;
  final String? contactEmail;
  final bool isActive;
  final DateTime? createdAt;
  final List<String> fcmTokens;

  factory AppUser.fromMap(String id, Map<String, dynamic> data) {
    final createdAt = _parseDateTime(data['createdAt']);
    final tokensRaw = data['fcmTokens'];
    final tokens = _parseTokens(tokensRaw);
    final resolvedName = _firstNonEmptyString(
      data,
      const ['name', 'displayName', 'fullName', 'nombre', 'userName'],
    );
    final resolvedEmail = _firstNonEmptyString(
      data,
      const ['email', 'mail', 'userEmail'],
    );
    final resolvedAreaId = _firstNonEmptyString(
      data,
      const ['areaId', 'departmentId', 'area'],
    );
    final resolvedAreaName = _firstNonEmptyString(
      data,
      const ['areaName', 'departmentName', 'areaLabel'],
    );
    return AppUser(
      id: id,
      name: resolvedName.isEmpty ? 'Sin nombre' : resolvedName,
      email: resolvedEmail,
      contactEmail: data['contactEmail'] as String?,
      role: (data['role'] as String?) ?? 'usuario',
      areaId: resolvedAreaId,
      areaName: resolvedAreaName.isEmpty ? null : resolvedAreaName,
      isActive: (data['isActive'] as bool?) ?? true,
      createdAt: createdAt,
      fcmTokens: tokens,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'contactEmail': contactEmail,
      'role': role,
      'areaId': areaId,
      'areaName': areaName,
      'isActive': isActive,
      'createdAt': createdAt?.millisecondsSinceEpoch,
      'fcmTokens': fcmTokens,
    };
  }

  String get areaDisplay => normalizeAreaLabel(areaName ?? areaId);
}

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

List<String> _parseTokens(dynamic value) {
  if (value is List) {
    return value.map((token) => token.toString()).toList();
  }
  if (value is Map) {
    final tokens = <String>[];
    value.forEach((key, raw) {
      if (raw is String && raw.isNotEmpty) {
        tokens.add(raw);
      } else if (raw == true) {
        tokens.add(key.toString());
      }
    });
    return tokens;
  }
  return const [];
}

String _firstNonEmptyString(
  Map<String, dynamic> data,
  List<String> keys,
) {
  for (final key in keys) {
    final raw = data[key];
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    if (raw is Map) {
      final nested = Map<String, dynamic>.from(raw);
      final nestedValue = _firstNonEmptyString(
        nested,
        const ['name', 'displayName', 'fullName', 'nombre', 'label', 'value'],
      );
      if (nestedValue.isNotEmpty) return nestedValue;
    }
  }
  return '';
}
