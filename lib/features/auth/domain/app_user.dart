import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.areaId,
    this.areaName,
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
  final bool isActive;
  final DateTime? createdAt;
  final List<String> fcmTokens;

  factory AppUser.fromMap(String id, Map<String, dynamic> data) {
    return AppUser(
      id: id,
      name: (data['name'] as String?) ?? 'Sin nombre',
      email: (data['email'] as String?) ?? '',
      role: (data['role'] as String?) ?? 'usuario',
      areaId: (data['areaId'] as String?) ?? '',
      areaName: data['areaName'] as String?,
      isActive: (data['isActive'] as bool?) ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      fcmTokens: (data['fcmTokens'] as List<dynamic>?)
              ?.map((token) => token.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'role': role,
      'areaId': areaId,
      'areaName': areaName,
      'isActive': isActive,
      'createdAt': createdAt,
      'fcmTokens': fcmTokens,
    };
  }

  String get areaDisplay => areaName ?? areaId;
}
