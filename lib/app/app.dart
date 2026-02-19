import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/app/router.dart';
import 'package:sistema_compras/core/app_logger.dart';
import 'package:sistema_compras/core/app_theme.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/core/services/notification_service.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';

class SistemaComprasApp extends ConsumerWidget {
  const SistemaComprasApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(notificationServiceProvider);
    ref.listen(authStateChangesProvider, (previous, next) {
      final previousUser = previous?.value;
      final nextUser = next.value;
      if (previousUser != null && nextUser == null) {
        resetPdfCaches();
      }
      final email = nextUser?.email;
      final detected = companyFromEmail(email);
      if (detected != null) {
        ref.read(currentCompanyProvider.notifier).state = detected;
      }
    });
    final router = ref.watch(appRouterProvider);
    final branding = ref.watch(currentBrandingProvider);

    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyL,
        ): const _LogDumpIntent(),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyL,
        ): const _LogDumpIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _LogDumpIntent: CallbackAction<_LogDumpIntent>(
            onInvoke: (intent) {
              AppLogger.dumpToConsole(reason: 'shortcut');
              final rootContext = appNavigatorKey.currentContext;
              if (rootContext != null) {
                ScaffoldMessenger.of(rootContext)
                  ..clearSnackBars()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text('Log enviado a consola.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: MaterialApp.router(
            title: 'Sistema de Compras - ${branding.displayName}',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightFor(branding),
            darkTheme: AppTheme.darkFor(branding),
            routerConfig: router,
          ),
        ),
      ),
    );
  }
}

class _LogDumpIntent extends Intent {
  const _LogDumpIntent();
}

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
