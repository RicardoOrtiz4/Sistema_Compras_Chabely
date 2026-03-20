import 'package:sistema_compras/features/orders/application/create_order_controller.dart';

class SessionDraftStore {
  static final Map<String, CotizacionDraft> _cotizacion = {};
  static final Map<String, ContabilidadDraft> _contabilidad = {};

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
