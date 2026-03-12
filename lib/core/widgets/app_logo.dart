import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 140,
    required this.logoAsset,
  });

  final double size;
  final String logoAsset;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      logoAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}
