import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

class ZoomablePdfPreview extends StatefulWidget {
  const ZoomablePdfPreview({
    required this.build,
    super.key,
    this.pages,
    this.maxPageWidth,
    this.padding,
    this.previewPageMargin,
    this.scrollViewDecoration,
    this.pdfPreviewPageDecoration,
    this.showHint = true,
  });

  final LayoutCallback build;
  final List<int>? pages;
  final double? maxPageWidth;
  final EdgeInsets? padding;
  final EdgeInsets? previewPageMargin;
  final Decoration? scrollViewDecoration;
  final Decoration? pdfPreviewPageDecoration;
  final bool showHint;

  @override
  State<ZoomablePdfPreview> createState() => _ZoomablePdfPreviewState();
}

class _ZoomablePdfPreviewState extends State<ZoomablePdfPreview> {
  bool _isZoomed = false;
  final Key _previewKey = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        PdfPreview(
          key: _previewKey,
          allowPrinting: false,
          allowSharing: false,
          canChangePageFormat: false,
          canChangeOrientation: false,
          build: widget.build,
          pages: widget.pages,
          maxPageWidth: widget.maxPageWidth,
          padding: widget.padding,
          previewPageMargin: widget.previewPageMargin,
          scrollViewDecoration: widget.scrollViewDecoration,
          pdfPreviewPageDecoration: widget.pdfPreviewPageDecoration,
          onZoomChanged: (zoomed) {
            if (_isZoomed != zoomed && mounted) {
              setState(() => _isZoomed = zoomed);
            }
          },
        ),
        if (widget.showHint && !_isZoomed)
          Positioned(
            right: 12,
            bottom: 12,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.zoom_in, size: 16, color: scheme.onSurface),
                      const SizedBox(width: 6),
                      Text(
                        'Doble toque para zoom',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
