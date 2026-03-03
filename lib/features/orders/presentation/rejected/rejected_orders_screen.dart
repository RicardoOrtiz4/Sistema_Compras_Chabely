import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';

Future<void> openPdfExternal(
  BuildContext context,
  OrderPdfData data, {
  String? filename,
}) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _PdfLoadingDialog(),
  );

  try {
    final bytes = await buildOrderPdf(
      data,
      useIsolate: true,
    );

    if (!navigator.mounted) return;
    navigator.pop();

    await Printing.sharePdf(
      bytes: bytes,
      filename: filename ?? 'orden.pdf',
    );
  } catch (error, stack) {
    if (navigator.mounted) {
      navigator.pop();
    }
    if (!messenger.mounted) return;

    final message = reportError(error, stack, context: 'openPdfExternal');
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PdfLoadingDialog extends StatelessWidget {
  const _PdfLoadingDialog();

  @override
  Widget build(BuildContext context) {
    return const Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 48),
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: AppSplash(compact: true, size: 24),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('Generando PDF...')),
          ],
        ),
      ),
    );
  }
}
