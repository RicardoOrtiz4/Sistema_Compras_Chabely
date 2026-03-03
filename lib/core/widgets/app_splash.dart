import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

const String _lottieTwoAsset = 'assets/animations/lottie2.json';

enum _LoadingAnimation { lottieTwo }

class AppSplash extends StatefulWidget {
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
  State<AppSplash> createState() => _AppSplashState();
}

class _AppSplashState extends State<AppSplash>
    with SingleTickerProviderStateMixin {
  static int _sequence = 0;
  late final _LoadingAnimation _animation;
  late final AnimationController _lottieController;

  @override
  void initState() {
    super.initState();
    _lottieController = AnimationController(vsync: this);
    _animation = _LoadingAnimation.values[
      _sequence % _LoadingAnimation.values.length
    ];
    _sequence += 1;
  }

  @override
  void dispose() {
    _lottieController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inline = widget.compact || widget.size != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final animationSize = widget.size ??
            (inline
                ? 120.0
                : (constraints.hasBoundedHeight
                    ? constraints.maxHeight * 0.5
                    : 260.0));
        final animationWidth = widget.size ??
            (inline
                ? 160.0
                : (constraints.hasBoundedWidth
                    ? constraints.maxWidth * 0.8
                    : 340.0));
        final clampedHeight = constraints.hasBoundedHeight
            ? math.min(animationSize, constraints.maxHeight * 0.7)
            : animationSize;
        final clampedWidth = constraints.hasBoundedWidth
            ? math.min(animationWidth, constraints.maxWidth * 0.9)
            : animationWidth;
        final showMessage = !inline && widget.message.isNotEmpty;
        final content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: clampedHeight,
              width: clampedWidth,
              child: _buildAnimation(),
            ),
            if (showMessage) ...[
              const SizedBox(height: 12),
              Text(
                widget.message,
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
      },
    );
  }

  Widget _buildAnimation() {
    switch (_animation) {
      case _LoadingAnimation.lottieTwo:
        return Lottie.asset(
          _lottieTwoAsset,
          controller: _lottieController,
          fit: BoxFit.contain,
          animate: false,
          onLoaded: (composition) {
            _lottieController
              ..duration = composition.duration
              ..repeat();
          },
          errorBuilder: (context, error, stack) => const _FallbackPlaceholder(),
        );
    }
  }
}

class _FallbackPlaceholder extends StatelessWidget {
  const _FallbackPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hourglass_empty_outlined),
          SizedBox(height: 8),
          Text('Cargando...'),
        ],
      ),
    );
  }
}
