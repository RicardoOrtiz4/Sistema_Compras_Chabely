import 'package:intl/intl.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';

final _shortDateSlash = DateFormat('dd/MM/yyyy');
final _shortDateDash = DateFormat('dd-MM-yyyy');

class OrderSearchCache {
  final Map<String, _OrderSearchEntry> _cache = <String, _OrderSearchEntry>{};

  String textFor(
    PurchaseOrder order, {
    bool includeDates = true,
  }) {
    final version = _orderVersion(order);
    final cached = _cache[order.id];
    if (cached != null && cached.version == version) {
      return includeDates ? cached.textWithDates : cached.textWithoutDates;
    }
    final textWithDates = _buildOrderSearchText(order, includeDates: true);
    final textWithoutDates = _buildOrderSearchText(order, includeDates: false);
    _cache[order.id] = _OrderSearchEntry(
      version,
      textWithDates,
      textWithoutDates,
    );
    return includeDates ? textWithDates : textWithoutDates;
  }

  void retainFor(Iterable<PurchaseOrder> orders) {
    if (_cache.isEmpty) return;
    final keep = {for (final order in orders) order.id};
    _cache.removeWhere((key, _) => !keep.contains(key));
  }
}

class _OrderSearchEntry {
  const _OrderSearchEntry(
    this.version,
    this.textWithDates,
    this.textWithoutDates,
  );

  final int version;
  final String textWithDates;
  final String textWithoutDates;
}

int _orderVersion(PurchaseOrder order) {
  final timestamp = order.updatedAt ?? order.createdAt;
  if (timestamp != null) return timestamp.millisecondsSinceEpoch;
  return order.items.length;
}

bool orderMatchesSearch(
  PurchaseOrder order,
  String query, {
  OrderSearchCache? cache,
  bool includeDates = true,
}) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return true;
  final haystack = cache == null
      ? _buildOrderSearchText(order, includeDates: includeDates)
      : cache.textFor(order, includeDates: includeDates);
  final tokens = normalized.split(RegExp(r'\s+')).where((token) => token.isNotEmpty);
  for (final token in tokens) {
    if (!haystack.contains(token)) {
      return false;
    }
  }
  return true;
}

String _buildOrderSearchText(
  PurchaseOrder order, {
  required bool includeDates,
}) {
  final buffer = StringBuffer();
  void addValue(Object? value) {
    if (value == null) return;
    final text = value.toString().trim();
    if (text.isEmpty) return;
    buffer.write(text.toLowerCase());
    buffer.write(' ');
  }

  void addDate(DateTime? date) {
    if (date == null) return;
    addValue(date.toIso8601String());
    addValue(date.toShortDate());
    addValue(date.toFullDateTime());
    addValue(_shortDateSlash.format(date));
    addValue(_shortDateDash.format(date));
    addValue('${date.year}-${_pad2(date.month)}-${_pad2(date.day)}');
  }

  addValue(order.id);
  _addFolioVariants(order.id, addValue);
  addValue(order.requesterId);
  addValue(order.requesterName);
  addValue(order.areaId);
  addValue(order.areaName);
  addValue(order.urgency.label);
  addValue(order.status.label);
  addValue(order.clientNote);
  addValue(order.urgentJustification);
  addValue(order.supplier);
  addValue(order.internalOrder);
  addValue(order.budget);
  if (includeDates) {
    addDate(order.createdAt);
    addDate(order.updatedAt);
  }

  for (final item in order.items) {
    addValue(item.line);
    addValue(item.pieces);
    addValue(item.partNumber);
    addValue(item.description);
    addValue(item.quantity);
    addValue(item.unit);
    addValue(item.customer);
    addValue(item.supplier);
    addValue(item.internalOrder);
    if (includeDates) {
      addDate(item.estimatedDate);
    }
  }

  return buffer.toString();
}

String _pad2(int value) {
  if (value >= 10) return value.toString();
  return '0$value';
}

void _addFolioVariants(String folio, void Function(Object?) addValue) {
  final trimmed = folio.trim();
  if (trimmed.isEmpty) return;
  final normalized = trimmed.replaceAll(' ', '').toLowerCase();
  if (normalized.contains('-')) {
    final noDash = normalized.replaceAll('-', '');
    addValue(noDash);
    final parts = normalized.split('-');
    if (parts.length == 2) {
      addValue(parts[0]);
      addValue(parts[1]);
    }
  }
}
