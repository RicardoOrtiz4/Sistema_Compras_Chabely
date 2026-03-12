import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/widgets/app_splash.dart';

class PreloadGate extends ConsumerStatefulWidget {
  const PreloadGate({
    required this.loaders,
    required this.child,
    this.gracePeriod = const Duration(milliseconds: 180),
    super.key,
  });

  final List<AsyncValue<dynamic>> Function(WidgetRef ref) loaders;
  final Widget child;
  final Duration gracePeriod;

  @override
  ConsumerState<PreloadGate> createState() => _PreloadGateState();
}

class _PreloadGateState extends ConsumerState<PreloadGate> {
  bool _allowBlockingSplash = false;
  bool _didRenderChild = false;
  Timer? _graceTimer;

  @override
  void initState() {
    super.initState();
    _scheduleGraceWindow();
  }

  @override
  void didUpdateWidget(covariant PreloadGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gracePeriod != widget.gracePeriod) {
      _allowBlockingSplash = false;
      _scheduleGraceWindow();
    }
  }

  @override
  void dispose() {
    _graceTimer?.cancel();
    super.dispose();
  }

  void _scheduleGraceWindow() {
    _graceTimer?.cancel();
    if (_didRenderChild) return;
    _graceTimer = Timer(widget.gracePeriod, () {
      if (!mounted) return;
      if (_didRenderChild) return;
      setState(() => _allowBlockingSplash = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final asyncValues = widget.loaders(ref);
    for (final value in asyncValues) {
      final hasResolvedState = value.hasValue || value.hasError;
      if (!_didRenderChild &&
          value.isLoading &&
          !hasResolvedState &&
          _allowBlockingSplash) {
        return const AppSplash();
      }
    }
    if (!_didRenderChild) {
      _graceTimer?.cancel();
    }
    _didRenderChild = true;
    return widget.child;
  }
}
