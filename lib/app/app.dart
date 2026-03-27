import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/app/router.dart';
import 'package:sistema_compras/core/app_auth.dart';
import 'package:sistema_compras/core/navigation/app_shell_keys.dart';
import 'package:sistema_compras/core/app_theme.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/optimistic_action.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';

class SistemaComprasApp extends ConsumerStatefulWidget {
  const SistemaComprasApp({super.key});

  @override
  ConsumerState<SistemaComprasApp> createState() => _SistemaComprasAppState();
}

class _SistemaComprasAppState extends ConsumerState<SistemaComprasApp> {
  ProviderSubscription<AsyncValue<AppAuthUser?>>? _authSubscription;
  ProviderSubscription<Company>? _companySubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription =
        ref.listenManual<AsyncValue<AppAuthUser?>>(authStateChangesProvider, (
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
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: MaterialApp.router(
        title: 'Sistema de Compras - ${branding.displayName}',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightFor(branding),
        darkTheme: AppTheme.darkFor(branding),
        scaffoldMessengerKey: appScaffoldMessengerKey,
        routerConfig: router,
        builder: (context, child) => Stack(
          children: [
            child ?? const SizedBox.shrink(),
            const OptimisticSyncBanner(),
          ],
        ),
      ),
    );
  }
}
