import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/company_branding.dart';

class AppLogo extends ConsumerWidget {
  const AppLogo({super.key, this.size = 140});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(currentBrandingProvider);
    return Image.asset(
      branding.logoAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}
