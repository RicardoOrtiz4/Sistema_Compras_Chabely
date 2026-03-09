class SharedQuote {
  const SharedQuote({
    required this.id,
    required this.supplier,
    required this.orderIds,
    required this.pdfUrl,
    this.createdAt,
    this.updatedAt,
    this.approvedOrderIds = const [],
    this.approvedAt,
    this.needsUpdate = false,
    this.version = 1,
  });

  final String id;
  final String supplier;
  final List<String> orderIds;
  final String pdfUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<String> approvedOrderIds;
  final DateTime? approvedAt;
  final bool needsUpdate;
  final int version;

  factory SharedQuote.fromMap(String id, Map<String, dynamic> data) {
    return SharedQuote(
      id: id,
      supplier: (data['supplier'] as String?) ?? '',
      orderIds: _parseOrderIds(data['orderIds']),
      pdfUrl: (data['pdfUrl'] as String?) ?? '',
      createdAt: _parseDateTime(data['createdAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
      approvedOrderIds: _parseOrderIds(data['approvedOrderIds']),
      approvedAt: _parseDateTime(data['approvedAt']),
      needsUpdate: _parseBool(data['needsUpdate']),
      version: (data['version'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'supplier': supplier,
      'orderIds': {for (final id in orderIds) id: true},
      'pdfUrl': pdfUrl.trim().isEmpty ? null : pdfUrl.trim(),
      'needsUpdate': needsUpdate,
      'version': version,
      'createdAt': createdAt?.millisecondsSinceEpoch,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
      'approvedOrderIds': approvedOrderIds.isEmpty
          ? null
          : {for (final id in approvedOrderIds) id: true},
      'approvedAt': approvedAt?.millisecondsSinceEpoch,
    };
  }
}

List<String> _parseOrderIds(dynamic value) {
  final ids = <String>[];

  if (value is List) {
    for (final entry in value) {
      final text = entry?.toString().trim() ?? '';
      if (text.isNotEmpty) ids.add(text);
    }
    return ids;
  }

  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString().trim();
      if (key.isEmpty) continue;

      // Caso típico: { "ORDER_ID": true }
      if (entry.value == true) {
        ids.add(key);
        continue;
      }

      // Caso alterno: { "x": "ORDER_ID" }
      final valueText = entry.value?.toString().trim() ?? '';
      if (valueText.isNotEmpty) ids.add(valueText);
    }
    return ids;
  }

  if (value is String) {
    final text = value.trim();
    if (text.isNotEmpty) ids.add(text);
    return ids;
  }

  return ids;
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is double) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  return null;
}

bool _parseBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'si' || normalized == 'sí';
  }
  return false;
}
