import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/widgets/app_splash.dart';

class PreloadGate extends ConsumerWidget {
  const PreloadGate({
    required this.loaders,
    required this.child,
    super.key,
  });

  final List<AsyncValue<dynamic>> Function(WidgetRef ref) loaders;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncValues = loaders(ref);
    for (final value in asyncValues) {
      if (value.isLoading) {
        return const AppSplash();
      }
    }
    return child;
  }
}
