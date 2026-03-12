import 'dart:io';
import 'dart:typed_data';

import 'package:pdfx/pdfx.dart';

final Map<String, String> _cachedPdfPaths = <String, String>{};

Future<PdfDocument> openPdfDocument(
  Uint8List bytes, {
  required String signature,
}) async {
  final file = await _ensurePdfFile(bytes, signature: signature);
  return PdfDocument.openFile(file.path);
}

Future<File> _ensurePdfFile(
  Uint8List bytes, {
  required String signature,
}) async {
  final fileName =
      'sistema_compras_${signature.hashCode.toUnsigned(32).toRadixString(16)}.pdf';
  final cachedPath = _cachedPdfPaths[fileName];
  if (cachedPath != null) {
    final cachedFile = File(cachedPath);
    if (await cachedFile.exists()) {
      return cachedFile;
    }
  }

  final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(bytes, flush: false);
  _cachedPdfPaths[fileName] = file.path;
  return file;
}
