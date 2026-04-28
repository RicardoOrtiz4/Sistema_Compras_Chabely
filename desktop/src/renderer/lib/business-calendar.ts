export const normalRequestedDeliveryLeadDays = 3;
export const urgentRequestedDeliveryWindowDays = 3;

export function normalizeCalendarDate(value: Date) {
  return new Date(value.getFullYear(), value.getMonth(), value.getDate());
}

export function isBusinessDay(value: Date) {
  const date = normalizeCalendarDate(value);
  const weekday = date.getDay();
  if (weekday === 0 || weekday === 6) {
    return false;
  }
  return !isMandatoryRestDayInMexico(date);
}

export function firstAllowedNormalRequestedDeliveryDate(today = new Date()) {
  const minimumDate = normalizeCalendarDate(today);
  minimumDate.setDate(minimumDate.getDate() + normalRequestedDeliveryLeadDays);
  const cursor = new Date(minimumDate);
  while (!isBusinessDay(cursor)) {
    cursor.setDate(cursor.getDate() + 1);
  }
  return cursor;
}

export function isAllowedNormalRequestedDeliveryDate(value: Date, today = new Date()) {
  const date = normalizeCalendarDate(value);
  const minimumDate = normalizeCalendarDate(today);
  minimumDate.setDate(minimumDate.getDate() + normalRequestedDeliveryLeadDays);
  if (date < minimumDate) {
    return false;
  }
  return isBusinessDay(date);
}

export function isAllowedUrgentRequestedDeliveryDate(value: Date, today = new Date()) {
  const date = normalizeCalendarDate(value);
  const normalizedToday = normalizeCalendarDate(today);
  const lastAllowedDate = normalizeCalendarDate(today);
  lastAllowedDate.setDate(lastAllowedDate.getDate() + urgentRequestedDeliveryWindowDays);
  return date >= normalizedToday && date <= lastAllowedDate;
}

function isMandatoryRestDayInMexico(value: Date) {
  return (
    isMonthDay(value, 1, 1) ||
    isNthWeekdayOfMonth(value, 1, 2, 1) ||
    isNthWeekdayOfMonth(value, 1, 3, 3) ||
    isMonthDay(value, 5, 1) ||
    isMonthDay(value, 9, 16) ||
    isNthWeekdayOfMonth(value, 1, 11, 3) ||
    isMonthDay(value, 12, 25) ||
    isPresidentialTransitionDay(value)
  );
}

function isMonthDay(value: Date, month: number, day: number) {
  return value.getMonth() + 1 === month && value.getDate() === day;
}

function isNthWeekdayOfMonth(value: Date, weekday: number, month: number, occurrence: number) {
  if (value.getMonth() + 1 !== month) return false;
  if (value.getDay() !== weekday) return false;
  const ordinal = Math.floor((value.getDate() - 1) / 7) + 1;
  return ordinal === occurrence;
}

function isPresidentialTransitionDay(value: Date) {
  const year = value.getFullYear();
  return value.getMonth() + 1 === 10 && value.getDate() === 1 && year >= 2024 && (year - 2024) % 6 === 0;
}
