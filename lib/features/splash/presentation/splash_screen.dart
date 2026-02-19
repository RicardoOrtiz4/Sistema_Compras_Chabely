import 'package:flutter/material.dart';

import 'package:sistema_compras/core/widgets/app_splash.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: AppSplash());
  }
}
