import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

enum Company { chabely, acerpro }

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
  pdfHeaderLine2: 'GESTION DE COMPRAS',
  pdfTitle: 'REQUISICION DE COMPRA',
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
  pdfHeaderLine2: 'GESTION DE COMPRAS',
  pdfTitle: 'REQUISICION DE COMPRA',
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

Company? companyFromEmail(String? email) {
  if (email == null) return null;
  final trimmed = email.trim().toLowerCase();
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

final currentCompanyProvider = StateProvider<Company>((ref) => Company.chabely);

final currentBrandingProvider = Provider<CompanyBranding>((ref) {
  final company = ref.watch(currentCompanyProvider);
  return brandingFor(company);
});

final availableBrandingsProvider = Provider<List<CompanyBranding>>((ref) {
  return const [chabelyBranding, acerproBranding];
});
