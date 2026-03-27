import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_compras/features/orders/application/create_order_controller.dart';

class SessionDraftStore {
  static final Map<String, CotizacionDraft> _cotizacion = {};
  static final Map<String, ContabilidadDraft> _contabilidad = {};
  static final Map<String, SupplierDashboardDraft> _supplierDashboard = {};
  static const _supplierDashboardPrefsKey = 'supplier.dashboard.drafts';
  static bool _supplierDashboardHydrated = false;

  static Future<void> ensureInitialized() async {
    if (_supplierDashboardHydrated) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_supplierDashboardPrefsKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.key is! String || entry.value is! Map) continue;
            final data = Map<String, dynamic>.from(entry.value as Map);
            _supplierDashboard[entry.key as String] =
                SupplierDashboardDraft.fromMap(data);
          }
        }
      } catch (_) {}
    }
    _supplierDashboardHydrated = true;
  }

  static CotizacionDraft? cotizacion(String orderId) => _cotizacion[orderId];
  static void saveCotizacion(String orderId, CotizacionDraft draft) {
    _cotizacion[orderId] = draft;
  }

  static void clearCotizacion(String orderId) {
    _cotizacion.remove(orderId);
  }

  static ContabilidadDraft? contabilidad(String orderId) => _contabilidad[orderId];
  static void saveContabilidad(String orderId, ContabilidadDraft draft) {
    _contabilidad[orderId] = draft;
  }

  static void clearContabilidad(String orderId) {
    _contabilidad.remove(orderId);
  }

  static SupplierDashboardDraft? supplierDashboard(String supplier) {
    return _supplierDashboard[_normalizeSupplierKey(supplier)];
  }

  static void saveSupplierDashboard(
    String supplier,
    SupplierDashboardDraft draft,
  ) {
    _supplierDashboard[_normalizeSupplierKey(supplier)] = draft;
    unawaited(_persistSupplierDashboard());
  }

  static void clearSupplierDashboard(String supplier) {
    _supplierDashboard.remove(_normalizeSupplierKey(supplier));
    unawaited(_persistSupplierDashboard());
  }

  static Future<void> _persistSupplierDashboard() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, Object?>{
      for (final entry in _supplierDashboard.entries) entry.key: entry.value.toMap(),
    };
    await prefs.setString(_supplierDashboardPrefsKey, jsonEncode(payload));
  }
}

class CotizacionDraft {
  const CotizacionDraft({
    required this.items,
  });

  final List<OrderItemDraft> items;
}

class ContabilidadDraft {
  const ContabilidadDraft({
    required this.facturaLinks,
    required this.pendingLink,
    required this.linksConfirmed,
    this.items = const [],
  });

  final List<String> facturaLinks;
  final String pendingLink;
  final bool linksConfirmed;
  final List<OrderItemDraft> items;
}

class SupplierDashboardDraft {
  const SupplierDashboardDraft({
    required this.links,
    this.comprasComment = '',
  });

  final List<String> links;
  final String comprasComment;

  factory SupplierDashboardDraft.fromMap(Map<String, dynamic> data) {
    final rawLinks = data['links'];
    final links = <String>[];
    if (rawLinks is List) {
      for (final entry in rawLinks) {
        final text = entry?.toString().trim() ?? '';
        if (text.isNotEmpty) links.add(text);
      }
    }
    return SupplierDashboardDraft(
      links: links,
      comprasComment: (data['comprasComment'] as String?) ?? '',
    );
  }

  Map<String, Object?> toMap() {
    return {
      'links': links,
      'comprasComment': comprasComment,
    };
  }
}

String _normalizeSupplierKey(String supplier) {
  return supplier.trim().toLowerCase();
}
