import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

Future<void> savePdfBytes(
  BuildContext context, {
  required Uint8List bytes,
  required String suggestedName,
  String successMessage = 'PDF descargado.',
  String errorMessage = 'No se pudo descargar el PDF.',
}) async {
  try {
    final location = await getSaveLocation(suggestedName: suggestedName);
    if (location == null) return;

    final file = XFile.fromData(
      bytes,
      mimeType: 'application/pdf',
      name: suggestedName,
    );
    await file.saveTo(location.path);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
  }
}
