import 'dart:async';
import 'dart:io';

Future<void> _pendingWrite = Future<void>.value();

void appendAppLogLine(String line) {
  final normalized = line.trimRight();
  if (normalized.isEmpty) return;
  _pendingWrite = _queueWrite('$normalized\n');
}

String? getAppLogFilePath() {
  final baseDir = Platform.environment['TEMP'];
  final tempDir = (baseDir == null || baseDir.trim().isEmpty)
      ? Directory.systemTemp.path
      : baseDir;
  return '$tempDir${Platform.pathSeparator}sistema_compras_chabely${Platform.pathSeparator}diagnostics${Platform.pathSeparator}app.log';
}

Future<void> _queueWrite(String content) async {
  try {
    await _pendingWrite;
  } catch (_) {}
  try {
    final file = File(getAppLogFilePath()!);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      content,
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {}
}
