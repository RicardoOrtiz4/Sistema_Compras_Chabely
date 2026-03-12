class OrderDashboardCounts {
  const OrderDashboardCounts({
    required this.pendingCompras,
    required this.cotizaciones,
    required this.cotizacionesReadyToSend,
    required this.pendingDireccion,
    required this.pendingEta,
    required this.contabilidad,
    required this.almacen,
    required this.rejected,
    required this.hasRemoteCounters,
  });

  static const empty = OrderDashboardCounts(
    pendingCompras: 0,
    cotizaciones: 0,
    cotizacionesReadyToSend: 0,
    pendingDireccion: 0,
    pendingEta: 0,
    contabilidad: 0,
    almacen: 0,
    rejected: 0,
    hasRemoteCounters: false,
  );

  final int pendingCompras;
  final int cotizaciones;
  final int cotizacionesReadyToSend;
  final int pendingDireccion;
  final int pendingEta;
  final int contabilidad;
  final int almacen;
  final int rejected;
  final bool hasRemoteCounters;

  factory OrderDashboardCounts.fromMap(
    Map<String, dynamic> data, {
    required String? userId,
  }) {
    final status = _asMap(data['status']);
    final cotizaciones = _asMap(data['cotizaciones']);
    final rejectedByUser = _asMap(data['rejectedByUser']);

    final hasRemoteCounters =
        status.isNotEmpty || cotizaciones.isNotEmpty || rejectedByUser.isNotEmpty;

    return OrderDashboardCounts(
      pendingCompras: _asInt(status['pendingCompras']),
      cotizaciones: _asInt(status['cotizaciones']),
      cotizacionesReadyToSend: _asInt(cotizaciones['readyToSend']),
      pendingDireccion: _asInt(status['authorizedGerencia']),
      pendingEta: _asInt(status['paymentDone']),
      contabilidad: _asInt(status['contabilidad']),
      almacen: _asInt(status['almacen']),
      rejected: userId == null ? 0 : _asInt(rejectedByUser[userId]),
      hasRemoteCounters: hasRemoteCounters,
    );
  }

  factory OrderDashboardCounts.fromLocalMap(Map<String, dynamic> data) {
    return OrderDashboardCounts(
      pendingCompras: _asInt(data['pendingCompras']),
      cotizaciones: _asInt(data['cotizaciones']),
      cotizacionesReadyToSend: _asInt(data['cotizacionesReadyToSend']),
      pendingDireccion: _asInt(data['pendingDireccion']),
      pendingEta: _asInt(data['pendingEta']),
      contabilidad: _asInt(data['contabilidad']),
      almacen: _asInt(data['almacen']),
      rejected: _asInt(data['rejected']),
      hasRemoteCounters: _asBool(data['hasRemoteCounters']),
    );
  }

  Map<String, dynamic> toLocalMap() {
    return {
      'pendingCompras': pendingCompras,
      'cotizaciones': cotizaciones,
      'cotizacionesReadyToSend': cotizacionesReadyToSend,
      'pendingDireccion': pendingDireccion,
      'pendingEta': pendingEta,
      'contabilidad': contabilidad,
      'almacen': almacen,
      'rejected': rejected,
      'hasRemoteCounters': hasRemoteCounters,
    };
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return const <String, dynamic>{};
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value.trim()) ?? 0;
  }
  return 0;
}

bool _asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1';
  }
  return false;
}
