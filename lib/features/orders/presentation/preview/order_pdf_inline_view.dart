
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';

import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/navigation_guard.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';

const double _webRenderScale = 1.6;
const int _webRenderQuality = 85;

class OrderPdfInlineView extends StatefulWidget {
  const OrderPdfInlineView({
    required this.data,
    super.key,
  });

  final OrderPdfData data;

  @override
  State<OrderPdfInlineView> createState() => _OrderPdfInlineViewState();
}

class _OrderPdfInlineViewState extends State<OrderPdfInlineView>
    with RouteAware {
  late Future<Uint8List> _bytesFuture;
  PdfControllerPinch? _controller;
  PdfController? _webController;
  PhotoViewController? _photoController;
  String? _signature;
  bool _isRouteSubscribed = false;

  @override
  void initState() {
    super.initState();
    _queueBuild();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      if (_isRouteSubscribed) {
        routeObserver.unsubscribe(this);
      }
      routeObserver.subscribe(this, route);
      _isRouteSubscribed = true;
    }
  }

  @override
  void didUpdateWidget(covariant OrderPdfInlineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSignature = _signatureFor(widget.data);
    if (_signature != nextSignature) {
      _disposeController();
      _queueBuild();
    }
  }

  @override
  void dispose() {
    if (_isRouteSubscribed) {
      routeObserver.unsubscribe(this);
    }
    _disposeController();
    super.dispose();
  }

  @override
  void didPopNext() {
    if (!mounted) return;
    setState(() {
      _disposeController();
      _queueBuild();
    });
  }

  void _queueBuild() {
    _signature = _signatureFor(widget.data);
    final cached = getCachedOrderPdf(widget.data);
    if (cached != null) {
      _bytesFuture = Future.value(cached);
      return;
    }
    _bytesFuture = Future(() async {
      await WidgetsBinding.instance.endOfFrame;
      return buildOrderPdf(
        widget.data,
        useIsolate: !kIsWeb,
      );
    });
  }

  void _disposeController() {
    final controller = _controller;
    if (controller == null) return;
    controller.document.then((doc) => doc.close()).catchError((error, stack) {
      logError(error, stack, context: 'OrderPdfInlineView.dispose');
    });
    controller.dispose();
    _controller = null;
    final webController = _webController;
    if (webController != null) {
      webController.document.then((doc) => doc.close()).catchError((error, stack) {
        logError(error, stack, context: 'OrderPdfInlineView.dispose');
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
          return _PdfLoading(label: 'Generando PDF...');
        }
        if (snapshot.hasError) {
          final message = reportError(
            snapshot.error!,
            snapshot.stackTrace,
            context: 'OrderPdfInlineView',
          );
          return Center(child: Text(message));
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return const Center(child: Text('No se pudo generar el PDF.'));
        }
        final bytesForPdf = kIsWeb ? Uint8List.fromList(bytes) : bytes;
        if (kIsWeb) {
          _webController  = PdfController(document: _openDocument(bytesForPdf));
          _photoController  = PhotoViewController();
          return Stack(
            children: [
              Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    final keyboard = HardwareKeyboard.instance;
                    final zoomModifier =
                        keyboard.isControlPressed || keyboard.isMetaPressed;
                    if (!zoomModifier) return;
                    final dy = event.scrollDelta.dy;
                    if (dy == 0) return;
                    _applyWebZoom(dy > 0 ? 1 / 1.1 : 1.1);
                  }
                },
                child: PdfView(
                  controller: _webController!,
                  scrollDirection: Axis.vertical,
                  pageSnapping: false,
                  renderer: _renderWebPage,
                  builders: PdfViewBuilders<DefaultBuilderOptions>(
                    options: const DefaultBuilderOptions(),
                    errorBuilder: (context, error) {
                      final message = reportError(error, StackTrace.current, context: 'PdfView');
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
                  onZoomIn: () => _applyWebZoom(1.2),
                  onZoomOut: () => _applyWebZoom(1 / 1.2),
                  onReset: _resetWebZoom,
                ),
              ),
            ],
          );
        }
        _controller  = PdfControllerPinch(
          document: _openDocument(bytesForPdf),
        );
        return Stack(
          children: [
            PdfViewPinch(
              controller: _controller!,
              minScale: 1.0,
              maxScale: 6.0,
              onDocumentError: (error) {
  logError(error, StackTrace.current, context: 'OrderPdfInlineView.PdfViewPinch');
},

              builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
                options: const DefaultBuilderOptions(),
                errorBuilder: (context, error) {
  final message = reportError(error, StackTrace.current, context: 'PdfViewPinch');
  return Center(child: Text(message));
},

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

  void _applyWebZoom(double factor) {
    final controller = _photoController;
    if (controller == null) return;
    final currentScale = controller.scale ?? 1.0;
    final nextScale = (currentScale * factor).clamp(0.5, 6.0);
    controller.scale = nextScale;
  }

  void _resetWebZoom() {
    _photoController?.reset();
  }

  void _applyZoom(double factor) {
    final controller = _controller;
    if (controller == null) return;
    final current = controller.value.clone();
    final currentScale = current.getMaxScaleOnAxis();
    final nextScale = (currentScale * factor).clamp(1.0, 6.0);
    final delta = nextScale / currentScale;
    if (delta == 1.0) return;
    Offset center = Offset.zero;
    try {
      center = controller.viewRect.center;
    } catch (_) {}
    final zoomed = Matrix4.identity()
      ..translate(center.dx, center.dy)
      ..scale(delta)
      ..translate(-center.dx, -center.dy)
      ..multiply(current);
    controller.value = zoomed;
  }

  void _resetZoom() {
    final controller = _controller;
    if (controller == null) return;
    try {
      final page = controller.page;
      final matrix = controller.calculatePageFitMatrix(pageNumber: page);
      if (matrix != null) {
        controller.value = matrix;
        return;
      }
    } catch (_) {}
    controller.value = Matrix4.identity();
  }
}

Future<PdfPageImage?> _renderWebPage(PdfPage page) {
  return page.render(
    width: page.width * _webRenderScale,
    height: page.height * _webRenderScale,
    format: PdfPageImageFormat.jpeg,
    backgroundColor: '#ffffff',
    quality: _webRenderQuality,
  );
}

Future<PdfDocument> _openDocument(Uint8List bytes) async {
  try {
    return await PdfDocument.openData(bytes);
  } catch (error, stack) {
    logError(error, stack, context: 'OrderPdfInlineView.openDocument');
    if (error is Exception) {
      rethrow;
    }
    throw Exception(error.toString());
  }
}

class _PdfLoading extends StatelessWidget {
  const _PdfLoading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppSplash(compact: true, size: 140),
            const SizedBox(height: 12),
            Text(label),
          ],
        ),
      ),
    );
  }
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

String _signatureFor(OrderPdfData data) {
  var hash = 17;
  void addHash(Object? value) {
    hash = 37 * hash + (value?.hashCode ?? 0);
  }

  addHash(data.branding.id);
  addHash(data.folio);
  addHash(data.requesterName);
  addHash(data.requesterArea);
  addHash(data.areaName);
  addHash(data.urgency.name);
  addHash(data.createdAt.millisecondsSinceEpoch);
  addHash(data.updatedAt?.millisecondsSinceEpoch);
  addHash(data.observations);
  addHash(data.supplier);
  addHash(data.internalOrder);
  addHash(data.budget);
  if (data.supplierBudgets.isNotEmpty) {
    final entries = data.supplierBudgets.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in entries) {
      addHash(entry.key);
      addHash(entry.value);
    }
  }
  addHash(data.comprasComment);
  addHash(data.comprasReviewerName);
  addHash(data.comprasReviewerArea);
  addHash(data.direccionGeneralName);
  addHash(data.direccionGeneralArea);
  addHash(data.requestedDeliveryDate?.millisecondsSinceEpoch);
  addHash(data.etaDate?.millisecondsSinceEpoch);
  for (final date in data.resubmissionDates) {
    addHash(date.millisecondsSinceEpoch);
  }
  for (final item in data.items) {
    addHash(item.line);
    addHash(item.pieces);
    addHash(item.partNumber);
    addHash(item.description);
    addHash(item.quantity);
    addHash(item.unit);
    addHash(item.customer);
    addHash(item.supplier);
    addHash(item.budget);
    addHash(item.estimatedDate?.millisecondsSinceEpoch);
    addHash(item.reviewFlagged);
    addHash(item.reviewComment);
  }
  return hash.toString();
}
