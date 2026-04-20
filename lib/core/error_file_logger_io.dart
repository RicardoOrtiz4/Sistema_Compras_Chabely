import 'dart:async';
import 'dart:io';

Future<void> _pendingWrite = Future<void>.value();

void appendErrorToLocalLog(
  String message, {
  String? stackTrace,
}) {
  final normalizedMessage = message.trimRight();
  final normalizedStack = stackTrace?.trimRight();
  if (normalizedMessage.isEmpty && (normalizedStack == null || normalizedStack.isEmpty)) {
    return;
  }
  final buffer = StringBuffer()
    ..writeln(normalizedMessage);
  if (normalizedStack != null && normalizedStack.isNotEmpty) {
    buffer
      ..writeln(normalizedStack)
      ..writeln('---');
  }
  _pendingWrite = _queueWrite(buffer.toString());
}

String? getErrorLogFilePath() {
  final baseDir = Platform.environment['TEMP'];
  final tempDir = (baseDir == null || baseDir.trim().isEmpty)
      ? Directory.systemTemp.path
      : baseDir;
  return '$tempDir${Platform.pathSeparator}sistema_compras_chabely${Platform.pathSeparator}diagnostics${Platform.pathSeparator}errors.log';
}

Future<void> _queueWrite(String content) async {
  try {
    await _pendingWrite;
  } catch (_) {}
  try {
    final file = File(getErrorLogFilePath()!);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      content,
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {}
}
