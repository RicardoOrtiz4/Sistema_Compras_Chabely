import 'package:flutter/material.dart';

import 'package:sistema_compras/core/company_branding.dart';

/// Muestra los dos logos corporativos (Chabely y Acerpro) juntos.
/// Se usa en pantallas neutrales como login y splash.
class CompanyLogos extends StatelessWidget {
  const CompanyLogos({
    super.key,
    this.height = 96,
    this.spacing = 20,
    this.acerproScale = 0.88,
  });

  final double height;
  final double spacing;
  final double acerproScale;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: height,
          child: Image.asset(
            chabelyBranding.logoAsset,
            fit: BoxFit.contain,
          ),
        ),
        SizedBox(width: spacing),
        SizedBox(
          height: height * acerproScale,
          child: Image.asset(
            acerproBranding.logoAsset,
            fit: BoxFit.contain,
          ),
        ),
      ],
    );
  }
}
