import 'package:intl/intl.dart';

final _dateFormat = DateFormat('dd MMM yyyy');
final _dateTimeFormat = DateFormat('dd MMM yyyy � HH:mm');

extension DateFormatting on DateTime {
  String toShortDate() => _dateFormat.format(this);
  String toFullDateTime() => _dateTimeFormat.format(this);
}
