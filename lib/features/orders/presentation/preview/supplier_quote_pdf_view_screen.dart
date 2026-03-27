import 'package:flutter/material.dart';

import 'package:sistema_compras/features/orders/presentation/preview/supplier_quote_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/supplier_quote_pdf_inline_view.dart';
import 'package:sistema_compras/features/orders/presentation/preview/pdf_download_helper.dart';

class SupplierQuotePdfViewScreen extends StatefulWidget {
  const SupplierQuotePdfViewScreen({
    required this.data,
    this.title = 'Ver PDF',
    this.primaryActionLabel,
    this.onPrimaryAction,
    this.primaryActionEnabled = true,
    this.closeOnPrimaryAction = false,
    this.returnPrimaryActionResult = false,
    super.key,
  });

  final SupplierQuotePdfData data;
  final String title;
  final String? primaryActionLabel;
  final Future<bool> Function()? onPrimaryAction;
  final bool primaryActionEnabled;
  final bool closeOnPrimaryAction;
  final bool returnPrimaryActionResult;

  @override
  State<SupplierQuotePdfViewScreen> createState() =>
      _SupplierQuotePdfViewScreenState();
}

class _SupplierQuotePdfViewScreenState extends State<SupplierQuotePdfViewScreen> {
  bool _downloading = false;
  bool _runningPrimaryAction = false;

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
      bottomNavigationBar: widget.primaryActionLabel == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: FilledButton.icon(
                  onPressed: _runningPrimaryAction ||
                          !widget.primaryActionEnabled ||
                          (!widget.returnPrimaryActionResult &&
                              widget.onPrimaryAction == null)
                      ? null
                      : _runPrimaryAction,
                  icon: _runningPrimaryAction
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                  label: Text(widget.primaryActionLabel!),
                ),
              ),
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
        suggestedName: 'compra_${widget.data.quoteId}.pdf',
      );
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }

  Future<void> _runPrimaryAction() async {
    if (widget.returnPrimaryActionResult) {
      Navigator.of(context).pop(true);
      return;
    }
    final action = widget.onPrimaryAction;
    if (action == null || _runningPrimaryAction) return;
    setState(() => _runningPrimaryAction = true);
    try {
      final completed = await action();
      if (!mounted) return;
      if (completed && widget.closeOnPrimaryAction) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _runningPrimaryAction = false);
      }
    }
  }
}
