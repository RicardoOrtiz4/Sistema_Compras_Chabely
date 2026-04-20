import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sistema_compras/core/save_bytes.dart';

Future<void> savePdfBytes(
  BuildContext context, {
  required Uint8List bytes,
  required String suggestedName,
  String successMessage = 'PDF descargado.',
  String errorMessage = 'No se pudo descargar el PDF.',
}) async {
  try {
    final path = await pickSavePath(
      suggestedName: suggestedName,
      allowedExtensions: const <String>['pdf'],
    );
    if (path == null) return;
    await saveBytesToSelectedPath(path, bytes);

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
