
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdfx/pdfx.dart';

import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/monitoring/order_monitoring_support.dart';
import 'package:sistema_compras/features/orders/presentation/preview/pdf_download_helper.dart';

const double _monitoringPdfWebRenderScale = 2.2;

class MonitoringPdfViewScreen extends StatefulWidget {
  const MonitoringPdfViewScreen({
    required this.orders,
    required this.now,
    required this.companyName,
    required this.scopeLabel,
    required this.eventsByOrder,
    required this.actorNamesById,
    super.key,
  });

  final List<PurchaseOrder> orders;
  final DateTime now;
  final String companyName;
  final String scopeLabel;
  final Map<String, List<PurchaseOrderEvent>> eventsByOrder;
  final Map<String, String> actorNamesById;

  @override
  State<MonitoringPdfViewScreen> createState() => _MonitoringPdfViewScreenState();
}

class _MonitoringPdfViewScreenState extends State<MonitoringPdfViewScreen> {
  late final Future<Uint8List> _bytesFuture;
  PdfController? _webController;
  PhotoViewController? _photoController;
  TransformationController? _windowsTransformController;
  bool _downloading = false;

  bool get _usesWindowsSafePdfView =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    _bytesFuture = buildMonitoringPdf(
      orders: widget.orders,
      now: widget.now,
      companyName: widget.companyName,
      scopeLabel: widget.scopeLabel,
      eventsByOrder: widget.eventsByOrder,
      actorNamesById: widget.actorNamesById,
    );
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    final webController = _webController;
    if (webController != null) {
      if (!(defaultTargetPlatform == TargetPlatform.windows && !kIsWeb)) {
        webController.document.then((doc) => doc.close()).catchError((_) {});
      }
      webController.dispose();
      _webController = null;
    }
    // PhotoView removes its listeners during child dispose; disposing the
    // shared controller here first can trigger a null-listener crash on unmount.
    _photoController = null;
    _windowsTransformController?.dispose();
    _windowsTransformController = null;
  }

  Future<void> _downloadPdf() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final bytes = await _bytesFuture;
      if (!mounted) return;
      await savePdfBytes(
        context,
        bytes: bytes,
        suggestedName:
            'monitoreo_ordenes_${DateFormat('yyyyMMdd_HHmm').format(widget.now)}.pdf',
      );
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF de monitoreo'),
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
      body: FutureBuilder<Uint8List>(
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
                  context: 'MonitoringPdfViewScreen',
                ),
              ),
            );
          }
          final bytes = snapshot.data;
          if (bytes == null) {
            return const Center(child: Text('No se pudo generar el PDF.'));
          }
          final bytesForPdf = Uint8List.fromList(bytes);
          if (_usesWindowsSafePdfView) {
            _webController ??= PdfController(
              document: PdfDocument.openData(bytesForPdf),
            );
            _windowsTransformController ??= TransformationController();
            return Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    transformationController: _windowsTransformController,
                    minScale: 1.0,
                    maxScale: 4.0,
                    scaleEnabled: false,
                    panEnabled: true,
                    child: SizedBox.expand(
                      child: PdfView(
                        controller: _webController!,
                        scrollDirection: Axis.vertical,
                        pageSnapping: false,
                        renderer: _renderMonitoringPdfPage,
                        builders: PdfViewBuilders<DefaultBuilderOptions>(
                          options: const DefaultBuilderOptions(),
                          errorBuilder: (context, error) {
                            final message = reportError(
                              error,
                              StackTrace.current,
                              context: 'MonitoringPdfViewScreen.PdfView.windows',
                            );
                            return Center(child: Text(message));
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: _MonitoringPdfZoomControls(
                    onZoomIn: () => _applyWindowsZoom(1.2),
                    onZoomOut: () => _applyWindowsZoom(1 / 1.2),
                    onReset: _resetWindowsZoom,
                  ),
                ),
              ],
            );
          }
          _webController ??= PdfController(
            document: PdfDocument.openData(bytesForPdf),
          );
          if (kIsWeb) {
            _photoController ??= PhotoViewController();
            return Stack(
              children: [
                PdfView(
                  controller: _webController!,
                  scrollDirection: Axis.vertical,
                  pageSnapping: false,
                  renderer: _renderMonitoringPdfPage,
                  builders: PdfViewBuilders<DefaultBuilderOptions>(
                    options: const DefaultBuilderOptions(),
                    errorBuilder: (context, error) {
                      final message = reportError(
                        error,
                        StackTrace.current,
                        context: 'MonitoringPdfViewScreen.PdfView',
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
                        controller: _usesWindowsSafePdfView
                            ? null
                            : _photoController,
                        minScale: PhotoViewComputedScale.contained * 1.0,
                        maxScale: PhotoViewComputedScale.contained * 3.0,
                        initialScale: PhotoViewComputedScale.contained * 1.0,
                        filterQuality: FilterQuality.high,
                      );
                    },
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: _MonitoringPdfZoomControls(
                    onZoomIn: () => _applyZoom(1.2),
                    onZoomOut: () => _applyZoom(1 / 1.2),
                    onReset: _resetZoom,
                  ),
                ),
              ],
            );
          }
          return PdfView(
            controller: _webController!,
            scrollDirection: Axis.vertical,
            pageSnapping: false,
            renderer: _renderMonitoringPdfPage,
            builders: PdfViewBuilders<DefaultBuilderOptions>(
              options: const DefaultBuilderOptions(),
              errorBuilder: (context, error) {
                final message = reportError(
                  error,
                  StackTrace.current,
                  context: 'MonitoringPdfViewScreen.PdfView.native',
                );
                return Center(child: Text(message));
              },
            ),
          );
        },
      ),
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

  void _applyWindowsZoom(double factor) {
    final controller = _windowsTransformController;
    if (controller == null) return;
    final current = controller.value.clone();
    final currentScale = current.getMaxScaleOnAxis();
    final nextScale = (currentScale * factor).clamp(1.0, 4.0);
    final delta = nextScale / currentScale;
    if (delta == 1.0) return;
    final zoomed = Matrix4.identity()
      ..scale(delta)
      ..multiply(current);
    controller.value = zoomed;
  }

  void _resetWindowsZoom() {
    _windowsTransformController?.value = Matrix4.identity();
  }
}

Future<PdfPageImage?> _renderMonitoringPdfPage(PdfPage page) {
  if (kIsWeb) {
    return page.render(
      width: page.width * _monitoringPdfWebRenderScale,
      height: page.height * _monitoringPdfWebRenderScale,
      format: PdfPageImageFormat.png,
      backgroundColor: '#ffffff',
    );
  }
  return page.render(
    width: page.width * 2,
    height: page.height * 2,
    format: PdfPageImageFormat.jpeg,
    backgroundColor: '#ffffff',
  );
}

class _MonitoringPdfZoomControls extends StatelessWidget {
  const _MonitoringPdfZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MonitoringPdfZoomButton(
            icon: Icons.add,
            tooltip: 'Acercar',
            onPressed: onZoomIn,
          ),
          const SizedBox(height: 8),
          _MonitoringPdfZoomButton(
            icon: Icons.remove,
            tooltip: 'Alejar',
            onPressed: onZoomOut,
          ),
          const SizedBox(height: 8),
          _MonitoringPdfZoomButton(
            icon: Icons.refresh,
            tooltip: 'Restablecer zoom',
            onPressed: onReset,
          ),
        ],
      ),
    );
  }
}

class _MonitoringPdfZoomButton extends StatelessWidget {
  const _MonitoringPdfZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

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
