import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_compras/core/extensions.dart';

import 'package:sistema_compras/core/providers.dart';

const _lastLoginEmailPrefsKey = 'last_login_email_v1';
const _lastLoginEmailForAuthPrefix = 'last_login_email_for_auth_v1::';

Future<void> saveLastLoginEmail(
  String email, {
  String? authenticatedEmail,
}) async {
  final normalized = email.trim().toLowerCase();
  if (normalized.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_lastLoginEmailPrefsKey, normalized);
  final normalizedAuthEmail = authenticatedEmail?.trim().toLowerCase() ?? '';
  if (normalizedAuthEmail.isNotEmpty) {
    await prefs.setString(
      '$_lastLoginEmailForAuthPrefix$normalizedAuthEmail',
      normalized,
    );
  }
}

final lastLoginEmailProvider = FutureProvider<String?>((ref) async {
  final authUser = ref.watch(authStateChangesProvider).valueOrNull;
  final prefs = await SharedPreferences.getInstance();
  final authEmail = authUser?.email?.trim().toLowerCase() ?? '';
  if (authEmail.isNotEmpty) {
    final storedForAuth =
        prefs.getString('$_lastLoginEmailForAuthPrefix$authEmail')?.trim();
    if (storedForAuth != null && storedForAuth.isNotEmpty) {
      return storedForAuth;
    }
  }
  final stored = prefs.getString(_lastLoginEmailPrefsKey)?.trim();
  if (stored != null && stored.isNotEmpty) {
    return stored;
  }
  return authUser?.email;
});
