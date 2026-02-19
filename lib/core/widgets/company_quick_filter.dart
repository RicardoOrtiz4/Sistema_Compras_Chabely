import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/company_branding.dart';

class CompanyQuickFilter extends ConsumerWidget {
  const CompanyQuickFilter({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 0),
  });

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(currentBrandingProvider);
    return Padding(
      padding: padding,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Empresa:',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Chip(label: Text(branding.displayName)),
        ],
      ),
    );
  }
}
