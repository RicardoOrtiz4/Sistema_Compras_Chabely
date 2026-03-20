import 'package:flutter/material.dart';

import 'package:sistema_compras/features/orders/presentation/preview/supplier_quote_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/supplier_quote_pdf_inline_view.dart';
import 'package:sistema_compras/features/orders/presentation/preview/pdf_download_helper.dart';

class SupplierQuotePdfViewScreen extends StatefulWidget {
  const SupplierQuotePdfViewScreen({
    required this.data,
    this.title = 'Ver PDF',
    super.key,
  });

  final SupplierQuotePdfData data;
  final String title;

  @override
  State<SupplierQuotePdfViewScreen> createState() =>
      _SupplierQuotePdfViewScreenState();
}

class _SupplierQuotePdfViewScreenState extends State<SupplierQuotePdfViewScreen> {
  bool _downloading = false;

  @override
  Widget build(BuildContext context) {
    warmUpSupplierQuotePdfAssets(widget.data.branding);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _downloading ? null : _downloadPdf,
            tooltip: 'Descargar PDF',
            icon: _downloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SupplierQuotePdfInlineView(data: widget.data),
      ),
    );
  }

  Future<void> _downloadPdf() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final bytes = await buildSupplierQuotePdf(widget.data);
      if (!mounted) return;
      await savePdfBytes(
        context,
        bytes: bytes,
        suggestedName: 'cotizacion_${widget.data.quoteId}.pdf',
      );
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }
}
