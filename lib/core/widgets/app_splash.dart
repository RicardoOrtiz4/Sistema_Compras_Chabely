import 'package:flutter/material.dart';

class AppSplash extends StatelessWidget {
  const AppSplash({
    super.key,
    this.message = 'Cargando...',
    this.compact = false,
    this.size,
  });

  final String message;
  final bool compact;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inline = compact || size != null;
    final indicatorSize = size ?? (inline ? 20.0 : 36.0);
    final showMessage = !inline && message.isNotEmpty;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: indicatorSize,
          height: indicatorSize,
          child: CircularProgressIndicator(
            strokeWidth: inline ? 2.5 : 3.0,
            color: scheme.primary,
          ),
        ),
        if (showMessage) ...[
          const SizedBox(height: 12),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface,
                ),
          ),
        ],
      ],
    );

    if (inline) {
      return Center(child: content);
    }

    return ColoredBox(
      color: scheme.surface,
      child: SizedBox.expand(
        child: Center(child: content),
      ),
    );
  }
}
