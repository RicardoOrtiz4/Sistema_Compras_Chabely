import 'package:sistema_compras/features/orders/application/create_order_controller.dart';

class SessionDraftStore {
  static final Map<String, CotizacionDraft> _cotizacion = {};
  static final Map<String, ContabilidadDraft> _contabilidad = {};
  static final Map<String, AlmacenDraft> _almacen = {};

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

  static AlmacenDraft? almacen(String orderId) => _almacen[orderId];
  static void saveAlmacen(String orderId, AlmacenDraft draft) {
    _almacen[orderId] = draft;
  }

  static void clearAlmacen(String orderId) {
    _almacen.remove(orderId);
  }
}

class CotizacionDraft {
  const CotizacionDraft({
    required this.internalOrder,
    required this.comprasComment,
    required this.items,
  });

  final String internalOrder;
  final String comprasComment;
  final List<OrderItemDraft> items;
}

class ContabilidadDraft {
  const ContabilidadDraft({
    required this.facturaLinks,
    required this.pendingLink,
  });

  final List<String> facturaLinks;
  final String pendingLink;
}

class AlmacenDraft {
  const AlmacenDraft({
    required this.comment,
    required this.qtyByLine,
    required this.commentByLine,
  });

  final String comment;
  final Map<int, String> qtyByLine;
  final Map<int, String> commentByLine;
}
