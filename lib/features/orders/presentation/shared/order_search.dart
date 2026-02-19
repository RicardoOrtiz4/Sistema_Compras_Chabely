import 'package:intl/intl.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';

final _shortDateSlash = DateFormat('dd/MM/yyyy');
final _shortDateDash = DateFormat('dd-MM-yyyy');

bool orderMatchesSearch(PurchaseOrder order, String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return true;
  final haystack = _buildOrderSearchText(order);
  final tokens = normalized.split(RegExp(r'\s+')).where((token) => token.isNotEmpty);
  for (final token in tokens) {
    if (!haystack.contains(token)) {
      return false;
    }
  }
  return true;
}

String _buildOrderSearchText(PurchaseOrder order) {
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
  addValue(order.lastReturnReason);
  addValue(order.supplier);
  addValue(order.internalOrder);
  addValue(order.comprasComment);
  addValue(order.budget);
  addValue(order.returnCount);
  addDate(order.createdAt);
  addDate(order.updatedAt);

  for (final item in order.items) {
    addValue(item.line);
    addValue(item.pieces);
    addValue(item.partNumber);
    addValue(item.description);
    addValue(item.quantity);
    addValue(item.unit);
    addValue(item.customer);
    addValue(item.supplier);
    addValue(item.reviewComment);
    addValue(item.reviewFlagged);
    addDate(item.estimatedDate);
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
