import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Company { chabely, acerpro }

const sharedCompanyDataId = 'shared';
const _activeCompanyPrefsKey = 'active_company_v2';
const _userCompanyPrefsPrefix = 'active_company_user_v2::';
const _chabelyAuthDomain = 'chabely.com.mx';

class CompanyBranding {
  const CompanyBranding({
    required this.company,
    required this.displayName,
    required this.tagline,
    required this.logoAsset,
    required this.seedColor,
    required this.lightBackground,
    required this.lightSurface,
    required this.lightSurfaceVariant,
    this.primaryColor,
    this.secondaryColor,
    this.tertiaryColor,
    this.secondaryContainerColor,
    this.tertiaryContainerColor,
    required this.pdfHeaderLine1,
    required this.pdfHeaderLine2,
    required this.pdfTitle,
    required this.pdfTitleBarColor,
    required this.pdfAccentColor,
    required this.pdfRefCode,
    this.pdfRevision,
  });

  final Company company;
  final String displayName;
  final String tagline;
  final String logoAsset;
  final Color seedColor;
  final Color lightBackground;
  final Color lightSurface;
  final Color lightSurfaceVariant;
  final Color? primaryColor;
  final Color? secondaryColor;
  final Color? tertiaryColor;
  final Color? secondaryContainerColor;
  final Color? tertiaryContainerColor;
  final String pdfHeaderLine1;
  final String pdfHeaderLine2;
  final String pdfTitle;
  final Color pdfTitleBarColor;
  final Color pdfAccentColor;
  final String pdfRefCode;
  final String? pdfRevision;

  String get id => company.name;
}

const _chabelyBranding = CompanyBranding(
  company: Company.chabely,
  displayName: 'Chabely',
  tagline: 'Sistema de compras',
  logoAsset: 'evidencias/LOGO_CHABELY_1500.png',
  seedColor: Color(0xFF4A4A4A),
  lightBackground: Color(0xFFF6F6F6),
  lightSurface: Color(0xFFFFFFFF),
  lightSurfaceVariant: Color(0xFFE9E9E9),
  primaryColor: Color(0xFF111111),
  // En Chabely reservamos el rojo para estados de error/rechazo.
  secondaryColor: Color(0xFF2F2F2F),
  tertiaryColor: Color(0xFF3B3B3B),
  secondaryContainerColor: Color(0xFF4A4A4A),
  tertiaryContainerColor: Color(0xFF5A5A5A),
  pdfHeaderLine1: 'FORMATO DEL SISTEMA DE GESTION DE CALIDAD',
  pdfHeaderLine2: 'GESTIÓN DE COMPRAS',
  pdfTitle: 'REQUISICIÓN DE COMPRA',
  pdfTitleBarColor: Color(0xFF000000),
  pdfAccentColor: Color(0xFFB00020),
  pdfRefCode: 'FORM-COM-01',
  pdfRevision: 'REV.02',
);

const _acerproBranding = CompanyBranding(
  company: Company.acerpro,
  displayName: 'Acerpro',
  tagline: 'Sistema de compras',
  logoAsset: 'evidencias acerpro/ACERPRO_LOGO_1500_TRIM.png',
  seedColor: Color(0xFF0065B3),
  lightBackground: Color(0xFFF3F5F7),
  lightSurface: Color(0xFFFFFFFF),
  lightSurfaceVariant: Color(0xFFE3E8EE),
  primaryColor: Color(0xFF0065B3),
  secondaryColor: Color(0xFF7A7A7A),
  tertiaryColor: Color(0xFF4F5B66),
  secondaryContainerColor: Color(0xFFE3E8EE),
  tertiaryContainerColor: Color(0xFFD6E1F2),
  pdfHeaderLine1: 'FORMATO DEL SISTEMA DE GESTION DE CALIDAD',
  pdfHeaderLine2: 'GESTIÓN DE COMPRAS',
  pdfTitle: 'REQUISICIÓN DE COMPRA',
  pdfTitleBarColor: Color(0xFF0065B3),
  pdfAccentColor: Color(0xFF7A7A7A),
  pdfRefCode: 'FCOM-1',
  pdfRevision: 'R.00',
);

const chabelyBranding = _chabelyBranding;
const acerproBranding = _acerproBranding;

CompanyBranding brandingFor(Company company) {
  switch (company) {
    case Company.acerpro:
      return _acerproBranding;
    case Company.chabely:
      return _chabelyBranding;
  }
}

class LoginEmailResolution {
  const LoginEmailResolution({
    required this.requestedEmail,
    required this.authEmail,
    required this.authEmailCandidates,
    required this.company,
  });

  final String requestedEmail;
  final String authEmail;
  final List<String> authEmailCandidates;
  final Company? company;
}

Company? companyFromEmail(String? email) {
  if (email == null) return null;
  final trimmed = _normalizeEmail(email);
  final atIndex = trimmed.lastIndexOf('@');
  if (atIndex <= 0 || atIndex >= trimmed.length - 1) {
    return null;
  }
  final domain = trimmed.substring(atIndex + 1);
  if (domain.contains('acerpro')) {
    return Company.acerpro;
  }
  if (domain.contains('chabely')) {
    return Company.chabely;
  }
  return null;
}

LoginEmailResolution resolveLoginEmail(String rawEmail) {
  final requestedEmail = _normalizeEmail(rawEmail);
  final requestedParts = _splitEmail(requestedEmail);

  if (requestedParts != null && requestedParts.domain.contains('acerpro')) {
    final authEmail = '${requestedParts.localPart}@$_chabelyAuthDomain';
    return LoginEmailResolution(
      requestedEmail: requestedEmail,
      authEmail: authEmail,
      authEmailCandidates: [authEmail],
      company: Company.acerpro,
    );
  }
  if (requestedEmail.endsWith('@$_chabelyAuthDomain')) {
    return LoginEmailResolution(
      requestedEmail: requestedEmail,
      authEmail: requestedEmail,
      authEmailCandidates: [requestedEmail],
      company: Company.chabely,
    );
  }
  return LoginEmailResolution(
    requestedEmail: requestedEmail,
    authEmail: requestedEmail,
    authEmailCandidates: [requestedEmail],
    company: companyFromEmail(requestedEmail),
  );
}

class CurrentCompanyController extends StateNotifier<Company> {
  CurrentCompanyController() : super(Company.chabely) {
    unawaited(_restoreLastSelection());
  }

  Company? _pendingLoginCompany;

  void prepareForLoginEmail(String rawEmail) {
    final resolution = resolveLoginEmail(rawEmail);
    final pending =
        resolution.company ?? companyFromEmail(resolution.requestedEmail);
    if (pending == null) return;
    _pendingLoginCompany = pending;
    state = pending;
  }

  void clearPendingLoginSelection() {
    _pendingLoginCompany = null;
  }

  Future<void> restoreForUserEmail(String? authEmail) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedAuthEmail = _normalizeEmail(authEmail);
    final storedForUser =
        normalizedAuthEmail.isEmpty
            ? null
            : prefs.getString('$_userCompanyPrefsPrefix$normalizedAuthEmail');
    final storedGlobal = _parseCompany(prefs.getString(_activeCompanyPrefsKey));
    final resolved =
        _pendingLoginCompany ??
        (normalizedAuthEmail.isEmpty
            ? storedGlobal
            : _parseCompany(storedForUser) ??
                storedGlobal ??
                companyFromEmail(normalizedAuthEmail));
    if (resolved == null) return;
    state = resolved;
    await prefs.setString(_activeCompanyPrefsKey, resolved.name);
    if (normalizedAuthEmail.isNotEmpty) {
      await prefs.setString(
        '$_userCompanyPrefsPrefix$normalizedAuthEmail',
        resolved.name,
      );
    }
  }

  Future<void> selectCompany(
    Company company, {
    String? authenticatedEmail,
  }) async {
    await _persistCompany(company, authenticatedEmail: authenticatedEmail);
  }

  Future<void> selectForAuthenticatedUser({
    required String requestedEmail,
    required String authenticatedEmail,
  }) async {
    final resolution = resolveLoginEmail(requestedEmail);
    final company = resolution.company ?? companyFromEmail(authenticatedEmail);
    if (company == null) return;
    await _persistCompany(
      company,
      authenticatedEmail: authenticatedEmail,
      linkedEmails: [
        requestedEmail,
        resolution.requestedEmail,
        resolution.authEmail,
      ],
    );
  }

  Future<void> _restoreLastSelection() async {
    final prefs = await SharedPreferences.getInstance();
    final restored = _parseCompany(prefs.getString(_activeCompanyPrefsKey));
    if (restored != null) {
      state = restored;
    }
  }

  Future<void> _persistCompany(
    Company company, {
    String? authenticatedEmail,
    Iterable<String?> linkedEmails = const [],
  }) async {
    _pendingLoginCompany = null;
    state = company;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeCompanyPrefsKey, company.name);
    final normalizedEmails = <String>{
      _normalizeEmail(authenticatedEmail),
      for (final email in linkedEmails) _normalizeEmail(email),
    }..removeWhere((email) => email.isEmpty);
    for (final email in normalizedEmails) {
      await prefs.setString(
        '$_userCompanyPrefsPrefix$email',
        company.name,
      );
    }
  }
}

final currentCompanyProvider =
    StateNotifierProvider<CurrentCompanyController, Company>((ref) {
      return CurrentCompanyController();
    });

final currentBrandingProvider = Provider<CompanyBranding>((ref) {
  final company = ref.watch(currentCompanyProvider);
  return brandingFor(company);
});

final availableBrandingsProvider = Provider<List<CompanyBranding>>((ref) {
  return const [chabelyBranding, acerproBranding];
});

final companySwitchInProgressProvider = StateProvider<bool>((ref) => false);
final brandingVisibilityLockProvider = StateProvider<bool>((ref) => true);

Company? _parseCompany(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  for (final company in Company.values) {
    if (company.name == raw.trim()) return company;
  }
  return null;
}

String _normalizeEmail(String? email) {
  return (email ?? '').trim().toLowerCase();
}

_EmailParts? _splitEmail(String email) {
  final atIndex = email.lastIndexOf('@');
  if (atIndex <= 0 || atIndex >= email.length - 1) {
    return null;
  }
  return _EmailParts(
    localPart: email.substring(0, atIndex),
    domain: email.substring(atIndex + 1),
  );
}

class _EmailParts {
  const _EmailParts({
    required this.localPart,
    required this.domain,
  });

  final String localPart;
  final String domain;
}
