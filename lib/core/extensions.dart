import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final _dateFormat = DateFormat('dd MMM yyyy', 'es_MX');
final _dateTimeFormat = DateFormat('dd MMM yyyy • HH:mm', 'es_MX');

extension DateFormatting on DateTime {
  String toShortDate() => _dateFormat.format(this);
  String toFullDateTime() => _dateTimeFormat.format(this);
}

extension AsyncValueCompatX<T> on AsyncValue<T> {
  T? get valueOrNull {
    return maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );
  }
}
