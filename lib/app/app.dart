import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/app/router.dart';
import 'package:sistema_compras/core/app_auth.dart';
import 'package:sistema_compras/core/extensions.dart';
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
        ref.read(currentCompanyProvider.notifier).clearPendingLoginSelection();
        ref.read(brandingVisibilityLockProvider.notifier).state = false;
        ref.read(companySwitchInProgressProvider.notifier).state = false;
      }
      if (nextUser != null) {
        ref.read(brandingVisibilityLockProvider.notifier).state = true;
        unawaited(_restoreBrandingForAuthenticatedUser(nextUser));
      } else {
        ref.read(brandingVisibilityLockProvider.notifier).state = false;
      }
    });
    _companySubscription =
        ref.listenManual<Company>(currentCompanyProvider, (previous, next) {
      if (previous == null || previous == next) return;
      clearOrderSessionSnapshotCache();
      resetPdfCaches();
      resetMappedOrderPdfDataCache();
      unawaited(_finishCompanySwitchOverlay());
    });
  }

  @override
  void dispose() {
    _authSubscription?.close();
    _companySubscription?.close();
    super.dispose();
  }

  Future<void> _finishCompanySwitchOverlay() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    ref.read(companySwitchInProgressProvider.notifier).state = false;
  }

  Future<void> _restoreBrandingForAuthenticatedUser(AppAuthUser user) async {
    await ref.read(currentCompanyProvider.notifier).restoreForUserEmail(user.email);
    if (!mounted) return;
    final currentAuthUser = ref.read(authStateChangesProvider).valueOrNull;
    if (currentAuthUser == null || currentAuthUser.uid != user.uid) return;
    ref.read(brandingVisibilityLockProvider.notifier).state = false;
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final authUser = ref.watch(authStateChangesProvider).valueOrNull;
    final branding = ref.watch(currentBrandingProvider);
    final isBrandingLocked = ref.watch(brandingVisibilityLockProvider);
    final isSwitchingCompany = ref.watch(companySwitchInProgressProvider);
    final shouldShieldBranding = isBrandingLocked || isSwitchingCompany;
    final useNeutralTheme = authUser == null || shouldShieldBranding;
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: MaterialApp.router(
        title: authUser == null || shouldShieldBranding
            ? 'Sistema de Compras'
            : 'Sistema de Compras - ${branding.displayName}',
        debugShowCheckedModeBanner: false,
        theme: useNeutralTheme
            ? _neutralTheme(Brightness.light)
            : AppTheme.lightFor(branding),
        darkTheme: useNeutralTheme
            ? _neutralTheme(Brightness.dark)
            : AppTheme.darkFor(branding),
        locale: const Locale('es', 'MX'),
        supportedLocales: const [Locale('es'), Locale('es', 'MX')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        scaffoldMessengerKey: appScaffoldMessengerKey,
        routerConfig: router,
        builder: (context, child) => Stack(
          children: [
            child ?? const SizedBox.shrink(),
            const OptimisticSyncBanner(),
            if (shouldShieldBranding)
              Positioned.fill(
                child: _BrandingShield(
                  message: isSwitchingCompany
                      ? 'Cambiando empresa...'
                      : 'Cargando...',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

ThemeData _neutralTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF6B7280),
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    dialogTheme: DialogThemeData(backgroundColor: scheme.surface),
  );
}

class _BrandingShield extends StatelessWidget {
  const _BrandingShield({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: SizedBox.expand(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6B7280)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF374151),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
