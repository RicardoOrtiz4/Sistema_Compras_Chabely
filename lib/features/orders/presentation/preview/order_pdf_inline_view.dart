
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';

import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/navigation_guard.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';

const double _webRenderScale = 1.9;
const double _nativeRenderScale = 2.4;
const int _webRenderQuality = 90;

class OrderPdfInlineView extends StatefulWidget {
  const OrderPdfInlineView({
    required this.data,
    this.skipCache = false,
    this.preferOrderCache = false,
    this.pdfBuilder,
    super.key,
  });

  final OrderPdfData data;
  final bool skipCache;
  final bool preferOrderCache;
  final Future<Uint8List> Function(
    OrderPdfData data, {
    bool useIsolate,
  })? pdfBuilder;

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
    if (_signature != nextSignature ||
        oldWidget.skipCache != widget.skipCache ||
        oldWidget.preferOrderCache != widget.preferOrderCache ||
        oldWidget.pdfBuilder != widget.pdfBuilder) {
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
    if (widget.preferOrderCache && !widget.skipCache) {
      final cachedByFolio = getCachedOrderPdfForFolio(widget.data);
      if (cachedByFolio != null) {
        _bytesFuture = Future.value(cachedByFolio);
        return;
      }
    }
    if (widget.pdfBuilder == null && !widget.skipCache) {
      final cached = getCachedOrderPdf(widget.data);
      if (cached != null) {
        _bytesFuture = Future.value(cached);
        return;
      }
    }
    _bytesFuture = Future(() async {
      await WidgetsBinding.instance.endOfFrame;
      final builder = widget.pdfBuilder;
      if (builder != null) {
        return builder(
          widget.data,
          useIsolate: !kIsWeb,
        );
      }
      if (widget.skipCache) {
        return buildOrderPdfUncached(
          widget.data,
          useIsolate: !kIsWeb,
        );
      }
      return buildOrderPdf(
        widget.data,
        useIsolate: !kIsWeb,
      );
    });
  }

  void _disposeController() {
    final controller = _controller;
    if (controller != null) {
      controller.document.then((doc) => doc.close()).catchError((error, stack) {
        logError(error, stack, context: 'OrderPdfInlineView.dispose');
      });
      controller.dispose();
      _controller = null;
    }
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
    final useStandardViewer =
        kIsWeb || defaultTargetPlatform == TargetPlatform.windows;
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      descendantsAreFocusable: false,
      descendantsAreTraversable: false,
      child: ExcludeFocus(
        child: FutureBuilder<Uint8List>(
          future: _bytesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return _PdfLoading(label: 'Generando PDF...');
            }
            if (snapshot.hasError) {
              reportError(
                snapshot.error!,
                snapshot.stackTrace,
                context: 'OrderPdfInlineView',
              );
              return _PdfErrorDetails(
                title: 'No se pudo abrir el PDF.',
                error: snapshot.error!,
              );
            }
            final bytes = snapshot.data;
            if (bytes == null) {
              return const Center(child: Text('No se pudo generar el PDF.'));
            }
            final bytesForPdf = kIsWeb ? Uint8List.fromList(bytes) : bytes;
            if (useStandardViewer) {
              _webController ??= PdfController(
                document: _openDocument(bytesForPdf),
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
                      _applyWebZoom(dy > 0 ? 1 / 1.1 : 1.1);
                    },
                    child: PdfView(
                      controller: _webController!,
                      scrollDirection: Axis.vertical,
                      pageSnapping: false,
                      renderer: useStandardViewer && !kIsWeb
                          ? _renderNativePage
                          : _renderWebPage,
                      builders: PdfViewBuilders<DefaultBuilderOptions>(
                        options: const DefaultBuilderOptions(),
                        errorBuilder: (context, error) {
                          reportError(
                            error,
                            StackTrace.current,
                            context: 'OrderPdfInlineView.PdfView',
                          );
                          return _PdfErrorDetails(
                            title: 'Error del visor PDF.',
                            error: error,
                          );
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
            _controller ??= PdfControllerPinch(
              document: _openDocument(bytesForPdf),
            );
            return Stack(
              children: [
                PdfViewPinch(
                  controller: _controller!,
                  minScale: 1.0,
                  maxScale: 6.0,
                  onDocumentError: (error) {
                    logError(
                      error,
                      StackTrace.current,
                      context: 'OrderPdfInlineView.PdfViewPinch',
                    );
                  },
                  builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
                    options: const DefaultBuilderOptions(),
                    errorBuilder: (context, error) {
                      reportError(
                        error,
                        StackTrace.current,
                        context: 'OrderPdfInlineView.PdfViewPinch',
                      );
                      return _PdfErrorDetails(
                        title: 'Error del visor PDF.',
                        error: error,
                      );
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
        ),
      ),
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

Future<PdfPageImage?> _renderNativePage(PdfPage page) {
  return page.render(
    width: page.width * _nativeRenderScale,
    height: page.height * _nativeRenderScale,
    format: PdfPageImageFormat.jpeg,
    backgroundColor: '#ffffff',
  );
}

class _PdfLoading extends StatelessWidget {
  const _PdfLoading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: SizedBox.expand(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(strokeWidth: 4),
                ),
                const SizedBox(height: 16),
                Text(label),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PdfErrorDetails extends StatelessWidget {
  const _PdfErrorDetails({
    required this.title,
    required this.error,
  });

  final String title;
  final Object error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final detail = _buildExplicitErrorMessage(error);
    return ColoredBox(
      color: scheme.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      detail,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
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

String _buildExplicitErrorMessage(Object error) {
  final raw = error.toString().trim();
  if (raw.isEmpty) {
    return 'Tipo: ${error.runtimeType}';
  }
  return 'Tipo: ${error.runtimeType}\nDetalle: $raw';
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
  addHash(data.suppressCreatedTime);
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
  addHash(data.comprasReviewerName);
  addHash(data.comprasReviewerArea);
  addHash(data.direccionGeneralName);
  addHash(data.direccionGeneralArea);
  addHash(data.urgentJustification);
  addHash(data.requestedDeliveryDate?.millisecondsSinceEpoch);
  addHash(data.etaDate?.millisecondsSinceEpoch);
  addHash(data.pendingResubmissionLabel);
  for (final date in data.resubmissionDates) {
    addHash(date.millisecondsSinceEpoch);
  }
  addHash(data.cacheSalt);
  for (final item in data.items) {
    addHash(item.line);
    addHash(item.pieces);
    addHash(item.partNumber);
    addHash(item.description);
    addHash(item.quantity);
    addHash(item.unit);
    addHash(item.customer);
    addHash(item.internalOrder);
    addHash(item.supplier);
    addHash(item.budget);
    addHash(item.estimatedDate?.millisecondsSinceEpoch);
    addHash(item.reviewFlagged);
    addHash(item.reviewComment);
    addHash(item.receivedQuantity);
    addHash(item.receivedComment);
  }
  return hash.toString();
}
