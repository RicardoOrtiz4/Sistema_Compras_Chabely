import 'package:sistema_compras/core/company_branding.dart';

const _companyPrefixes = <Company, String>{
  Company.chabely: 'CHA',
  Company.acerpro: 'ACE',
};

String companyFolioPrefix(Company company) {
  final prefix = _companyPrefixes[company];
  if (prefix != null) return prefix;
  final raw = company.name.toUpperCase();
  return raw.length >= 3 ? raw.substring(0, 3) : raw.padRight(3, 'X');
}

String formatFolio(Company company, int value) {
  return value.toString().padLeft(6, '0');
}

String? normalizeFolio(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim().toUpperCase();
  if (trimmed.isEmpty) return null;
  if (RegExp(r'^\d{6}$').hasMatch(trimmed)) {
    return trimmed;
  }
  final parts = trimmed.split('-');
  if (parts.length != 2) return null;
  final prefix = parts[0];
  final number = parts[1];
  if (!_companyPrefixes.values.contains(prefix)) return null;
  if (!RegExp(r'^\d{6}$').hasMatch(number)) return null;
  return '$prefix-$number';
}

bool isFolioId(String? raw) {
  return normalizeFolio(raw) != null;
}
