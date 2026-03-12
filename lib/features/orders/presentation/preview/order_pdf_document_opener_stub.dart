import 'dart:typed_data';

import 'package:pdfx/pdfx.dart';

Future<PdfDocument> openPdfDocument(
  Uint8List bytes, {
  required String signature,
}) {
  return PdfDocument.openData(bytes);
}
