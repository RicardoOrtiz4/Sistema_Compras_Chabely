import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/app/router.dart';
import 'package:sistema_compras/core/app_theme.dart';
import 'package:sistema_compras/core/services/notification_service.dart';

class SistemaComprasApp extends ConsumerWidget {
  const SistemaComprasApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(notificationServiceProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Sistema de Compras',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
