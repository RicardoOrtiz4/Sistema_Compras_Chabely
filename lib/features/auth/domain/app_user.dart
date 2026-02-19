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
    return AppUser(
      id: id,
      name: (data['name'] as String?) ?? 'Sin nombre',
      email: (data['email'] as String?) ?? '',
      contactEmail: data['contactEmail'] as String?,
      role: (data['role'] as String?) ?? 'usuario',
      areaId: (data['areaId'] as String?) ?? '',
      areaName: data['areaName'] as String?,
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
