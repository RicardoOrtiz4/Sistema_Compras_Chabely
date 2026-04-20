import 'dart:io';
import 'dart:typed_data';

Future<void> saveBytesToSelectedPathImpl(String path, Uint8List bytes) async {
  final normalizedPath = path.trim();
  if (normalizedPath.isEmpty) {
    throw StateError('Ruta de guardado no valida.');
  }
  final file = File(normalizedPath);
  final parent = file.parent;
  if (!await parent.exists()) {
    await parent.create(recursive: true);
  }
  await file.writeAsBytes(bytes, flush: true);
}

Future<String?> resolvePreferredSavePathImpl(
  String suggestedName,
  List<String> _,
) async {
  if (!Platform.isWindows) {
    return null;
  }
  final normalizedName = suggestedName.trim();
  if (normalizedName.isEmpty) {
    return null;
  }

  final userProfile = Platform.environment['USERPROFILE']?.trim() ?? '';
  final candidateDirectories = <Directory>[
    if (userProfile.isNotEmpty) Directory('$userProfile\\Downloads'),
    if (userProfile.isNotEmpty) Directory('$userProfile\\Desktop'),
    Directory.current,
  ];

  for (final directory in candidateDirectories) {
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return _buildUniqueFilePath(directory.path, normalizedName);
    } catch (_) {
      continue;
    }
  }

  return null;
}

String _buildUniqueFilePath(String directoryPath, String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  final hasExtension = dotIndex > 0 && dotIndex < fileName.length - 1;
  final baseName = hasExtension ? fileName.substring(0, dotIndex) : fileName;
  final extension = hasExtension ? fileName.substring(dotIndex) : '';

  var candidate = '$directoryPath\\$fileName';
  var counter = 1;
  while (File(candidate).existsSync()) {
    candidate = '$directoryPath\\$baseName ($counter)$extension';
    counter += 1;
  }
  return candidate;
}
