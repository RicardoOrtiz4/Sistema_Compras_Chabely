import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import 'save_bytes_stub.dart'
    if (dart.library.html) 'save_bytes_web.dart'
    if (dart.library.io) 'save_bytes_io.dart';

Future<void> saveBytesToSelectedPath(String path, Uint8List bytes) {
  final normalizedPath = path.trim();
  if (normalizedPath.isEmpty) {
    throw StateError('Ruta de guardado no valida.');
  }
  return saveBytesToSelectedPathImpl(normalizedPath, bytes);
}

Future<String?> pickSavePath({
  required String suggestedName,
  String? dialogTitle,
  List<String> allowedExtensions = const <String>[],
}) async {
  final normalizedSuggestedName = _normalizeSavePath(
        suggestedName,
        allowedExtensions: allowedExtensions,
      ) ??
      suggestedName.trim();
  if (kIsWeb) return normalizedSuggestedName;
  if (defaultTargetPlatform == TargetPlatform.windows) {
    final selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: normalizedSuggestedName,
      type: allowedExtensions.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions.isEmpty ? null : allowedExtensions,
      lockParentWindow: true,
    );
    return _normalizeSavePath(
      selectedPath,
      allowedExtensions: allowedExtensions,
    );
  }
  final groups = allowedExtensions.isEmpty
      ? const <XTypeGroup>[]
      : <XTypeGroup>[
          XTypeGroup(
            label: allowedExtensions.join(', ').toUpperCase(),
            extensions: allowedExtensions,
          ),
        ];
  final location = await getSaveLocation(
    suggestedName: normalizedSuggestedName,
    acceptedTypeGroups: groups,
  );
  return _normalizeSavePath(
    location?.path,
    allowedExtensions: allowedExtensions,
  );
}

String? _normalizeSavePath(
  String? rawPath, {
  required List<String> allowedExtensions,
}) {
  final trimmed = rawPath?.trim() ?? '';
  if (trimmed.isEmpty) return null;

  final preferredExtension = _preferredExtension(allowedExtensions);
  if (preferredExtension == null || _hasFileExtension(trimmed)) {
    return trimmed;
  }
  return '$trimmed.$preferredExtension';
}

String? _preferredExtension(List<String> allowedExtensions) {
  for (final extension in allowedExtensions) {
    final normalized = extension.trim().replaceFirst(RegExp(r'^\.+'), '');
    if (normalized.isNotEmpty) {
      return normalized.toLowerCase();
    }
  }
  return null;
}

bool _hasFileExtension(String path) {
  final lastSegment = path.split(RegExp(r'[\\/]')).last.trim();
  if (lastSegment.isEmpty) return false;
  final dotIndex = lastSegment.lastIndexOf('.');
  return dotIndex > 0 && dotIndex < lastSegment.length - 1;
}
