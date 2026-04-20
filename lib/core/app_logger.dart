import 'package:flutter/foundation.dart';

import 'app_log_file_sink_stub.dart'
    if (dart.library.io) 'app_log_file_sink_io.dart';

class AppLogger {
  static final List<String> _buffer = <String>[];
  static DebugPrintCallback? _originalDebugPrint;
  static bool _initialized = false;
  static int _limit = 200;
  static bool _isDumping = false;

  static void init({int maxEntries = 200}) {
    if (_initialized) return;
    _initialized = true;
    _limit = maxEntries;
    _originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message == null) return;
      _emit(_format(message), wrapWidth: wrapWidth);
    };
    log('logger initialized file=${currentLogFilePath ?? 'disabled'}', tag: 'LOGGER');
  }

  static void _add(String line) {
    _buffer.add(line);
    if (_buffer.length > _limit) {
      _buffer.removeRange(0, _buffer.length - _limit);
    }
  }

  static String _format(String message) {
    final timestamp = DateTime.now().toIso8601String();
    return '[$timestamp] $message';
  }

  static String? get currentLogFilePath => getAppLogFilePath();

  static void log(String message, {String tag = 'APP'}) {
    _emit(_format('[$tag] $message'));
  }

  static void _emit(String line, {int? wrapWidth}) {
    _add(line);
    appendAppLogLine(line);
    _originalDebugPrint?.call(line, wrapWidth: wrapWidth);
  }

  static void dumpToConsole({int count = 120, String? reason}) {
    if (_isDumping) return;
    _isDumping = true;
    final printer = _originalDebugPrint ?? debugPrint;
    if (_buffer.isEmpty) {
      printer.call(_format('(log buffer empty)'));
      _isDumping = false;
      return;
    }
    final start = _buffer.length > count ? _buffer.length - count : 0;
    final reasonLabel = reason == null ? '' : ' reason=$reason';
    printer.call(
      _format(
        '===== APP LOG DUMP (${_buffer.length} total, showing ${_buffer.length - start})$reasonLabel =====',
      ),
    );
    for (final line in _buffer.sublist(start)) {
      printer.call(line);
    }
    printer.call(_format('===== END APP LOG DUMP ====='));
    _isDumping = false;
  }
}
