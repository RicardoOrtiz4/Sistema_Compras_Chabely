class OrderDashboardCounts {
  const OrderDashboardCounts({
    required this.intakeReview,
    required this.sourcing,
    required this.sourcingReadyToSend,
    required this.pendingDireccion,
    required this.pendingEta,
    required this.contabilidad,
    required this.hasRemoteCounters,
  });

  static const empty = OrderDashboardCounts(
    intakeReview: 0,
    sourcing: 0,
    sourcingReadyToSend: 0,
    pendingDireccion: 0,
    pendingEta: 0,
    contabilidad: 0,
    hasRemoteCounters: false,
  );

  final int intakeReview;
  final int sourcing;
  final int sourcingReadyToSend;
  final int pendingDireccion;
  final int pendingEta;
  final int contabilidad;
  final bool hasRemoteCounters;

  factory OrderDashboardCounts.fromMap(
    Map<String, dynamic> data, {
    required String? userId,
  }) {
    final status = _asMap(data['status']);
    final sourcing = _asMap(data['sourcing']);

    final hasRemoteCounters = status.isNotEmpty || sourcing.isNotEmpty;

    return OrderDashboardCounts(
      intakeReview: _asInt(status['intakeReview']),
      sourcing: _asInt(status['sourcing']),
      sourcingReadyToSend: _asInt(sourcing['readyToSend']),
      pendingDireccion: _asInt(status['approvalQueue']),
      pendingEta: _asInt(status['paymentDone']),
      contabilidad: _asInt(status['contabilidad']),
      hasRemoteCounters: hasRemoteCounters,
    );
  }

  factory OrderDashboardCounts.fromLocalMap(Map<String, dynamic> data) {
    return OrderDashboardCounts(
      intakeReview: _asInt(data['intakeReview']),
      sourcing: _asInt(data['sourcing']),
      sourcingReadyToSend: _asInt(data['sourcingReadyToSend']),
      pendingDireccion: _asInt(data['pendingDireccion']),
      pendingEta: _asInt(data['pendingEta']),
      contabilidad: _asInt(data['contabilidad']),
      hasRemoteCounters: _asBool(data['hasRemoteCounters']),
    );
  }

  Map<String, dynamic> toLocalMap() {
    return {
      'intakeReview': intakeReview,
      'sourcing': sourcing,
      'sourcingReadyToSend': sourcingReadyToSend,
      'pendingDireccion': pendingDireccion,
      'pendingEta': pendingEta,
      'contabilidad': contabilidad,
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
