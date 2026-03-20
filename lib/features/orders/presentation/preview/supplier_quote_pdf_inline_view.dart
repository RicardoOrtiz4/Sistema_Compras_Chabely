
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';

import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/features/orders/presentation/preview/supplier_quote_pdf_builder.dart';

const double _supplierQuoteWebRenderScale = 2.6;
const double _supplierQuoteNativeRenderScale = 2.4;

class SupplierQuotePdfInlineView extends StatefulWidget {
  const SupplierQuotePdfInlineView({
    required this.data,
    super.key,
  });

  final SupplierQuotePdfData data;

  @override
  State<SupplierQuotePdfInlineView> createState() =>
      _SupplierQuotePdfInlineViewState();
}

class _SupplierQuotePdfInlineViewState extends State<SupplierQuotePdfInlineView> {
  late Future<Uint8List> _bytesFuture;
  PdfController? _webController;
  PhotoViewController? _photoController;
  String? _signature;

  @override
  void initState() {
    super.initState();
    _queueBuild();
  }

  @override
  void didUpdateWidget(covariant SupplierQuotePdfInlineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSignature = supplierQuotePdfCacheKey(widget.data);
    if (_signature != nextSignature) {
      _disposeControllers();
      _queueBuild();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _queueBuild() {
    _signature = supplierQuotePdfCacheKey(widget.data);
    _bytesFuture = buildSupplierQuotePdf(widget.data);
  }

  void _disposeControllers() {
    final webController = _webController;
    if (webController != null) {
      webController.document.then((doc) => doc.close()).catchError((error, stack) {
        logError(error, stack, context: 'SupplierQuotePdfInlineView.dispose');
      });
      webController.dispose();
      _webController = null;
    }
    _photoController?.dispose();
    _photoController = null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              reportError(
                snapshot.error!,
                snapshot.stackTrace,
                context: 'SupplierQuotePdfInlineView',
              ),
            ),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return const Center(child: Text('No se pudo generar el PDF.'));
        }
        final bytesForPdf = Uint8List.fromList(bytes);
        _webController ??= PdfController(
          document: PdfDocument.openData(bytesForPdf),
        );
        _photoController ??= PhotoViewController();
        return Stack(
          children: [
            Listener(
              onPointerSignal: (event) {
                if (event is! PointerScrollEvent) return;
                final keyboard = HardwareKeyboard.instance;
                final zoomModifier =
                    keyboard.isControlPressed || keyboard.isMetaPressed;
                if (!zoomModifier) return;
                final dy = event.scrollDelta.dy;
                if (dy == 0) return;
                _applyZoom(dy > 0 ? 1 / 1.1 : 1.1);
              },
              child: PdfView(
                controller: _webController!,
                scrollDirection: Axis.vertical,
                pageSnapping: false,
                renderer: _renderPage,
                builders: PdfViewBuilders<DefaultBuilderOptions>(
                  options: const DefaultBuilderOptions(),
                  errorBuilder: (context, error) {
                    final message = reportError(
                      error,
                      StackTrace.current,
                      context: 'SupplierQuotePdfInlineView.PdfView',
                    );
                    return Center(child: Text(message));
                  },
                  pageBuilder: (context, pageImage, index, document) {
                    return PhotoViewGalleryPageOptions(
                      imageProvider: PdfPageImageProvider(
                        pageImage,
                        index,
                        document.id,
                      ),
                      controller: _photoController,
                      minScale: PhotoViewComputedScale.contained * 1.0,
                      maxScale: PhotoViewComputedScale.contained * 3.0,
                      initialScale: PhotoViewComputedScale.contained * 1.0,
                      filterQuality: FilterQuality.high,
                    );
                  },
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: _ZoomControls(
                onZoomIn: () => _applyZoom(1.2),
                onZoomOut: () => _applyZoom(1 / 1.2),
                onReset: _resetZoom,
              ),
            ),
          ],
        );
      },
    );
  }

  void _applyZoom(double factor) {
    final controller = _photoController;
    if (controller == null) return;
    final currentScale = controller.scale ?? 1.0;
    final nextScale = (currentScale * factor).clamp(0.5, 6.0);
    controller.scale = nextScale;
  }

  void _resetZoom() {
    _photoController?.reset();
  }
}

Future<PdfPageImage?> _renderWebPage(PdfPage page) {
  return page.render(
    width: page.width * _supplierQuoteWebRenderScale,
    height: page.height * _supplierQuoteWebRenderScale,
    format: PdfPageImageFormat.png,
    backgroundColor: '#ffffff',
  );
}

Future<PdfPageImage?> _renderPage(PdfPage page) {
  if (kIsWeb) {
    return _renderWebPage(page);
  }
  return page.render(
    width: page.width * _supplierQuoteNativeRenderScale,
    height: page.height * _supplierQuoteNativeRenderScale,
    format: PdfPageImageFormat.jpeg,
    backgroundColor: '#ffffff',
  );
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(
            icon: Icons.add,
            tooltip: 'Acercar',
            onPressed: onZoomIn,
          ),
          const SizedBox(height: 8),
          _ZoomButton(
            icon: Icons.remove,
            tooltip: 'Alejar',
            onPressed: onZoomOut,
          ),
          const SizedBox(height: 8),
          _ZoomButton(
            icon: Icons.refresh,
            tooltip: 'Restablecer zoom',
            onPressed: onReset,
          ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        elevation: 2,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20),
          ),
        ),
      ),
    );
  }
}
