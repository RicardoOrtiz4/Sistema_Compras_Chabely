import 'package:firebase_core/firebase_core.dart';

void assertNoLocalhostEndpoints(FirebaseOptions options) {
  _assertRemoteEndpoint(
    label: 'Firebase Realtime Database',
    rawValue: options.databaseURL,
  );
  _assertRemoteEndpoint(
    label: 'Firebase Auth domain',
    rawValue: options.authDomain,
  );
}

void _assertRemoteEndpoint({
  required String label,
  required String? rawValue,
}) {
  final value = rawValue?.trim();
  if (value == null || value.isEmpty) return;

  final normalizedValue = value.contains('://') ? value : 'https://$value';
  final uri = Uri.tryParse(normalizedValue);
  final host = uri?.host.trim().toLowerCase() ?? '';

  if (host.isEmpty) {
    throw StateError('$label invalido: "$value".');
  }
  if (_isLoopbackHost(host)) {
    throw StateError(
      '$label apunta a "$host". El ejecutable debe usar endpoints remotos, no localhost.',
    );
  }
}

bool _isLoopbackHost(String host) {
  return host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '0.0.0.0' ||
      host == '::1' ||
      host == '[::1]' ||
      host == '10.0.2.2';
}
