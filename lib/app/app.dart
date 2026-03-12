import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/app/router.dart';
import 'package:sistema_compras/core/app_logger.dart';
import 'package:sistema_compras/core/app_theme.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/optimistic_action.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/core/services/notification_service.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';

class SistemaComprasApp extends ConsumerStatefulWidget {
  const SistemaComprasApp({super.key});

  @override
  ConsumerState<SistemaComprasApp> createState() => _SistemaComprasAppState();
}

class _SistemaComprasAppState extends ConsumerState<SistemaComprasApp> {
  ProviderSubscription<AsyncValue<User?>>? _authSubscription;
  ProviderSubscription<Company>? _companySubscription;

  @override
  void initState() {
    super.initState();
    ref.read(notificationServiceProvider);
    _authSubscription =
        ref.listenManual<AsyncValue<User?>>(authStateChangesProvider, (
      previous,
      next,
    ) {
      final previousUser = previous?.value;
      final nextUser = next.value;
      if (previousUser != null && nextUser == null) {
        clearOrderSessionSnapshotCache();
        resetPdfCaches();
        resetMappedOrderPdfDataCache();
      }
      final email = nextUser?.email;
      final detected = companyFromEmail(email);
      if (detected != null) {
        ref.read(currentCompanyProvider.notifier).state = detected;
      }
    });
    _companySubscription =
        ref.listenManual<Company>(currentCompanyProvider, (previous, next) {
      if (previous == null || previous == next) return;
      clearOrderSessionSnapshotCache();
      resetPdfCaches();
      resetMappedOrderPdfDataCache();
    });
  }

  @override
  void dispose() {
    _authSubscription?.close();
    _companySubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        child: FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: MaterialApp.router(
            title: 'Sistema de Compras - ${branding.displayName}',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightFor(branding),
            darkTheme: AppTheme.darkFor(branding),
            routerConfig: router,
            builder: (context, child) => Stack(
              children: [
                child ?? const SizedBox.shrink(),
                const OptimisticSyncBanner(),
              ],
            ),
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
