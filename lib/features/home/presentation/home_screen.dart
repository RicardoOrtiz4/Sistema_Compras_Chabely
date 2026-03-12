import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/widgets/app_logo.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/features/profile/presentation/profile_sheet.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  ProviderSubscription<AsyncValue<AppUser?>>? _profileSubscription;
  ProviderSubscription<CompanyBranding>? _brandingSubscription;

  @override
  void initState() {
    super.initState();
    _profileSubscription = ref.listenManual<AsyncValue<AppUser?>>(
      currentUserProfileProvider,
      (previous, next) {
        if (previous?.value == null && next.value != null) {
          final branding = ref.read(currentBrandingProvider);
          warmUpPdfAssets(branding);
        }
      },
    );
    _brandingSubscription = ref.listenManual<CompanyBranding>(
      currentBrandingProvider,
      (previous, next) {
        if (previous?.id == next.id) return;
        warmUpPdfAssets(next);
      },
    );
  }

  @override
  void dispose() {
    _profileSubscription?.close();
    _brandingSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final userAsync = ref.watch(currentUserProfileProvider);
    final user = userAsync.value;
    final branding = ref.watch(currentBrandingProvider);
    final isAdmin = user != null && isAdminRole(user.role);
    final canSwitchCompany = _canSwitchCompany(user, isAdmin);
    final isCompras = user != null && isComprasLabel(user.areaDisplay);
    final isDireccionGeneral =
        user != null && isDireccionGeneralLabel(user.areaDisplay);
    final canViewGeneralHistory =
        user != null && (isAdmin || isDireccionGeneral);
    final isContabilidad =
        user != null && isContabilidadLabel(user.areaDisplay);
    final isAlmacen = user != null && isAlmacenLabel(user.areaDisplay);
    final surfaceColor = scheme.surface;

    return Scaffold(
      drawer: _HomeDrawer(
        isAdmin: isAdmin,
        onOpenProfile: () => showProfileSheet(context, ref),
      ),
      appBar: AppBar(
        toolbarHeight: 96,
        backgroundColor: surfaceColor,
        surfaceTintColor: surfaceColor,
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AppLogo(size: 72, logoAsset: branding.logoAsset),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Inicio'),
                Text(
                  branding.displayName,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (canSwitchCompany)
            _CompanySwitcherAction(currentBranding: branding),
          if (user != null)
            IconButton(
              icon: const Icon(Icons.access_time),
              tooltip: 'Historial de órdenes de compra',
              onPressed: () => guardedPush(context, '/orders/history'),
            ),
          if (canViewGeneralHistory)
            IconButton(
              icon: const Icon(Icons.manage_search_outlined),
              tooltip: 'Historial general',
              onPressed: () => guardedPush(context, '/orders/history/all'),
            ),
        ],
      ),
      body: userAsync.when(
        data: (user) {
          if (user == null) {
            return const AppSplash();
          }
          final blocks = <_HomeBlockData>[
            _HomeBlockData(
              title: 'Crear orden de compra',
              subtitle: 'Inicia una nueva solicitud',
              icon: Icons.add_shopping_cart_outlined,
              color: scheme.primary,
              foreground: scheme.onPrimary,
              onTap: () => guardedPush(context, '/orders/create'),
            ),
            if (isAdmin || isCompras)
              _HomeBlockData(
                title: 'Órdenes por confirmar',
                subtitle: 'Revisión pendiente de compras',
                icon: Icons.fact_check_outlined,
                color: scheme.secondary,
                foreground: scheme.onSecondary,
                countProvider: pendingComprasCountProvider,
                onTap: () => guardedPush(context, '/orders/pending'),
              ),
            if (isAdmin || isCompras)
              _HomeBlockData(
                title: 'Cotizaciones',
                subtitle: 'Asignar proveedor y presupuesto',
                icon: Icons.request_quote_outlined,
                color: scheme.secondaryContainer,
                foreground: scheme.onSecondaryContainer,
                countProvider: cotizacionesModuleCountProvider,
                onTap: () => guardedPush(context, '/orders/cotizaciones'),
              ),
            if (isAdmin || isDireccionGeneral)
              _HomeBlockData(
                title: 'Dirección General',
                subtitle: 'Autorización de órdenes',
                icon: Icons.approval_outlined,
                color: scheme.tertiary,
                foreground: scheme.onTertiary,
                countProvider: pendingDireccionBundleCountProvider,
                onTap: () => guardedPush(context, '/orders/direccion'),
              ),
            if (isAdmin || isCompras)
              _HomeBlockData(
                title: 'Pendientes de fecha estimada',
                subtitle: 'Confirmar entregas',
                icon: Icons.assignment_turned_in_outlined,
                color: scheme.secondary,
                foreground: scheme.onSecondary,
                countProvider: pendingEtaCountProvider,
                onTap: () => guardedPush(context, '/orders/eta'),
              ),
            if (isAdmin || isContabilidad)
              _HomeBlockData(
                title: 'Contabilidad',
                subtitle: 'Registro y pagos',
                icon: Icons.receipt_long_outlined,
                color: scheme.tertiary,
                foreground: scheme.onTertiary,
                countProvider: contabilidadCountProvider,
                onTap: () => guardedPush(context, '/orders/contabilidad'),
              ),
            if (isAdmin || isAlmacen)
              _HomeBlockData(
                title: 'Almacén',
                subtitle: 'Recepción de compras',
                icon: Icons.inventory_2_outlined,
                color: scheme.primary,
                foreground: scheme.onPrimary,
                countProvider: almacenCountProvider,
                onTap: () => guardedPush(context, '/orders/almacen'),
              ),

            _HomeBlockData(
              title: 'Órdenes rechazadas',
              subtitle: 'Correcciones pendientes',
              icon: Icons.report_problem_outlined,
              color: scheme.error,
              foreground: scheme.onError,
              isRejected: true,
              countProvider: rejectedCountProvider,
              onTap: () => guardedPush(context, '/orders/rejected'),
            ),
          ];

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const tileSpacing = 10.0;
                  const columns = 2;
                  final cardWidth =
                      (constraints.maxWidth - (tileSpacing * (columns - 1))) /
                      columns;
                  final rows = (blocks.length / columns).ceil();
                  final screenHeight = MediaQuery.of(context).size.height;
                  final reserved = 120.0;
                  final maxCardHeight =
                      (screenHeight - reserved - (tileSpacing * (rows - 1))) /
                      rows;
                  final targetHeight = maxCardHeight.clamp(
                    104.0,
                    cardWidth < 200 ? 145.0 : 135.0,
                  );
                  final aspectRatio = cardWidth / targetHeight;

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    children: [
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: tileSpacing,
                          mainAxisSpacing: tileSpacing,
                          childAspectRatio: aspectRatio,
                        ),
                        itemCount: blocks.length,
                        itemBuilder: (context, index) =>
                            _HomeBlockCard(data: blocks[index]),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            'Error al cargar usuario: ${reportError(error, stack, context: 'HomeScreen')}',
          ),
        ),
      ),
    );
  }
}

class _HomeDrawer extends StatelessWidget {
  const _HomeDrawer({required this.isAdmin, required this.onOpenProfile});

  final bool isAdmin;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Gestión de proveedores'),
              onTap: () {
                Navigator.pop(context);
                guardedPush(context, '/partners/suppliers');
              },
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Gestión de clientes'),
              onTap: () {
                Navigator.pop(context);
                guardedPush(context, '/partners/clients');
              },
            ),
            if (isAdmin)
              ListTile(
                leading: const Icon(Icons.insights_outlined),
                title: const Text('Reportes'),
                onTap: () {
                  Navigator.pop(context);
                  guardedPush(context, '/reports');
                },
              ),
            if (isAdmin)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Administrar usuarios'),
                onTap: () {
                  Navigator.pop(context);
                  guardedPush(context, '/admin/users');
                },
              ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Perfil'),
              onTap: () {
                Navigator.pop(context);
                onOpenProfile();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeBlockData {
  const _HomeBlockData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.foreground,
    required this.onTap,
    this.isRejected = false,
    this.countProvider,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color foreground;
  final ProviderListenable<AsyncValue<int>>? countProvider;
  final VoidCallback onTap;
  final bool isRejected;
}

class _HomeBlockCard extends StatefulWidget {
  const _HomeBlockCard({required this.data});

  final _HomeBlockData data;

  @override
  State<_HomeBlockCard> createState() => _HomeBlockCardState();
}

class _HomeBlockCardState extends State<_HomeBlockCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final background = data.color;
    final borderColor = _hovered
        ? data.foreground.withValues(alpha: 0.34)
        : data.foreground.withValues(alpha: 0.14);
    final shadowColor = _hovered
        ? data.foreground.withValues(alpha: 0.16)
        : Colors.black.withValues(alpha: 0.08);
    final scheme = Theme.of(context).colorScheme;
    final softError =
        Color.lerp(scheme.error, Colors.white, 0.35) ?? scheme.error;
    final badgeColor = data.isRejected ? Colors.white : softError;
    final badgeTextColor = data.isRejected ? Colors.black : Colors.white;
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: data.foreground,
      fontSize: 13.5,
    );
    final subtitleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: data.foreground.withValues(alpha: _hovered ? 0.88 : 0.8),
      fontSize: 11,
    );
    final iconSurface = _hovered
        ? data.foreground.withValues(alpha: 0.18)
        : data.foreground.withValues(alpha: 0.1);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hovered ? -2.5 : 0, 0),
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(22),
          elevation: 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: data.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: borderColor,
                  width: _hovered ? 1.2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: _hovered ? 24 : 14,
                    offset: Offset(0, _hovered ? 12 : 8),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: _hovered ? 1 : 0.72,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(
                                  alpha: _hovered ? 0.14 : 0.06,
                                ),
                                Colors.white.withValues(alpha: 0.02),
                                Colors.transparent,
                              ],
                              stops: const [0, 0.38, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    right: 10,
                    top: 0,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      height: 2.2,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: LinearGradient(
                          colors: [
                            data.foreground.withValues(
                              alpha: _hovered ? 0.92 : 0.0,
                            ),
                            data.foreground.withValues(
                              alpha: _hovered ? 0.26 : 0.0,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: iconSurface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: data.foreground.withValues(
                                  alpha: _hovered ? 0.18 : 0.08,
                                ),
                              ),
                            ),
                            child: Icon(
                              data.icon,
                              color: data.foreground,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: AnimatedSlide(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              offset: _hovered
                                  ? const Offset(0.01, 0)
                                  : Offset.zero,
                              child: Text(
                                data.title,
                                style: titleStyle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          _HomeBlockBadgeSlot(
                            data: data,
                            hovered: _hovered,
                            badgeColor: badgeColor,
                            badgeTextColor: badgeTextColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      AnimatedSlide(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        offset: _hovered ? const Offset(0.01, 0) : Offset.zero,
                        child: Text(
                          data.subtitle,
                          style: subtitleStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeBlockBadgeSlot extends ConsumerWidget {
  const _HomeBlockBadgeSlot({
    required this.data,
    required this.hovered,
    required this.badgeColor,
    required this.badgeTextColor,
  });

  final _HomeBlockData data;
  final bool hovered;
  final Color badgeColor;
  final Color badgeTextColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countProvider = data.countProvider;
    if (countProvider == null) {
      return const SizedBox.shrink();
    }

    final countAsync = ref.watch(countProvider);
    final count = countAsync.valueOrNull;
    final showBadge = count != null && count > 0;

    if (!showBadge) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        offset: hovered ? const Offset(0, -0.04) : Offset.zero,
        child: _CountBadge(
          count: count,
          color: badgeColor,
          textColor: badgeTextColor,
        ),
      ),
    );
  }
}

class _CompanySwitcherAction extends ConsumerWidget {
  const _CompanySwitcherAction({required this.currentBranding});

  final CompanyBranding currentBranding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final availableBrandings = ref.watch(availableBrandingsProvider);
    return IconButton(
      icon: const Icon(Icons.business_outlined),
      tooltip: 'Cambiar empresa',
      onPressed: () => _showCompanySwitcher(
        context,
        ref,
        currentBranding,
        availableBrandings,
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.count,
    required this.color,
    required this.textColor,
  });

  final int count;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final display = count > 99 ? '99+' : count.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        display,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

bool _canSwitchCompany(AppUser? user, bool isAdmin) {
  if (user == null) return false;
  if (isAdmin) return true;
  return companyFromEmail(user.email) == null;
}

Future<void> _showCompanySwitcher(
  BuildContext context,
  WidgetRef ref,
  CompanyBranding currentBranding,
  List<CompanyBranding> brandings,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          shrinkWrap: true,
          children: [
            for (final branding in brandings)
              ListTile(
                leading: const Icon(Icons.apartment_outlined),
                title: Text(branding.displayName),
                subtitle: Text(branding.tagline),
                trailing: branding.id == currentBranding.id
                    ? const Icon(Icons.check_circle_outline)
                    : null,
                onTap: () {
                  ref.read(currentCompanyProvider.notifier).state =
                      branding.company;
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      );
    },
  );
}
