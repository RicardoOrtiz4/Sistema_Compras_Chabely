const int normalRequestedDeliveryLeadDays = 3;
const int urgentRequestedDeliveryWindowDays = 3;

// Días de descanso obligatorio de México usados para validar días hábiles.
DateTime normalizeCalendarDate(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

bool isBusinessDay(DateTime value) {
  final date = normalizeCalendarDate(value);
  if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
    return false;
  }
  return !isMandatoryRestDayInMexico(date);
}

DateTime firstAllowedNormalRequestedDeliveryDate({
  DateTime? today,
}) {
  final minimumDate = normalizeCalendarDate(
    today ?? DateTime.now(),
  ).add(const Duration(days: normalRequestedDeliveryLeadDays));
  var cursor = minimumDate;
  while (!isBusinessDay(cursor)) {
    cursor = cursor.add(const Duration(days: 1));
  }
  return cursor;
}

bool isAllowedNormalRequestedDeliveryDate(
  DateTime value, {
  DateTime? today,
}) {
  final date = normalizeCalendarDate(value);
  final minimumDate = normalizeCalendarDate(
    today ?? DateTime.now(),
  ).add(const Duration(days: normalRequestedDeliveryLeadDays));
  if (date.isBefore(minimumDate)) {
    return false;
  }
  return isBusinessDay(date);
}

bool isAllowedUrgentRequestedDeliveryDate(
  DateTime value, {
  DateTime? today,
}) {
  final date = normalizeCalendarDate(value);
  final normalizedToday = normalizeCalendarDate(today ?? DateTime.now());
  final lastAllowedDate = normalizedToday.add(
    const Duration(days: urgentRequestedDeliveryWindowDays),
  );
  if (date.isBefore(normalizedToday)) {
    return false;
  }
  return !date.isAfter(lastAllowedDate);
}

bool isSameCalendarDate(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

bool isMandatoryRestDayInMexico(DateTime value) {
  final date = normalizeCalendarDate(value);

  if (_isMonthDay(date, 1, 1)) return true;
  if (_isNthWeekdayOfMonth(date, month: 2, weekday: DateTime.monday, occurrence: 1)) {
    return true;
  }
  if (_isNthWeekdayOfMonth(date, month: 3, weekday: DateTime.monday, occurrence: 3)) {
    return true;
  }
  if (_isMonthDay(date, 5, 1)) return true;
  if (_isMonthDay(date, 9, 16)) return true;
  if (_isNthWeekdayOfMonth(date, month: 11, weekday: DateTime.monday, occurrence: 3)) {
    return true;
  }
  if (_isMonthDay(date, 12, 25)) return true;
  if (_isPresidentialTransitionDay(date)) return true;

  return false;
}

bool _isMonthDay(DateTime value, int month, int day) {
  return value.month == month && value.day == day;
}

bool _isNthWeekdayOfMonth(
  DateTime value, {
  required int month,
  required int weekday,
  required int occurrence,
}) {
  if (value.month != month || value.weekday != weekday) return false;
  final ordinal = ((value.day - 1) ~/ 7) + 1;
  return ordinal == occurrence;
}

bool _isPresidentialTransitionDay(DateTime value) {
  if (value.month != 10 || value.day != 1 || value.year < 2024) {
    return false;
  }
  return (value.year - 2024) % 6 == 0;
}
