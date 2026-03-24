import 'dart:async';

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
import 'package:sistema_compras/features/home/application/home_notifications.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/features/profile/presentation/profile_sheet.dart';
import 'package:sistema_compras/features/orders/application/create_order_controller.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_inline_view.dart';
import 'package:sistema_compras/features/orders/presentation/preview/pdf_download_helper.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  ProviderSubscription<AsyncValue<AppUser?>>? _profileSubscription;
  ProviderSubscription<CompanyBranding>? _brandingSubscription;
  ProviderSubscription<AsyncValue<List<PurchaseOrder>>>? _userOrdersSubscription;
  ProviderSubscription<AsyncValue<List<PurchaseOrder>>>?
      _operationalOrdersSubscription;
  final Set<String> _autoFinalizeInFlight = <String>{};

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
    _userOrdersSubscription = ref.listenManual<AsyncValue<List<PurchaseOrder>>>(
      userOrdersProvider,
      (_, next) {
        _scheduleAutoFinalize(next.valueOrNull ?? const <PurchaseOrder>[]);
      },
    );
    _operationalOrdersSubscription =
        ref.listenManual<AsyncValue<List<PurchaseOrder>>>(
      operationalOrdersProvider,
      (_, next) {
        final user = ref.read(currentUserProfileProvider).value;
        if (user == null) return;
        final canProcessAll = isAdminRole(user.role) ||
            isComprasLabel(user.areaDisplay) ||
            isDireccionGeneralLabel(user.areaDisplay);
        if (!canProcessAll) return;
        _scheduleAutoFinalize(next.valueOrNull ?? const <PurchaseOrder>[]);
      },
    );
  }

  @override
  void dispose() {
    _profileSubscription?.close();
    _brandingSubscription?.close();
    _userOrdersSubscription?.close();
    _operationalOrdersSubscription?.close();
    super.dispose();
  }

  void _scheduleAutoFinalize(List<PurchaseOrder> orders) {
    for (final order in orders) {
      if (!isOrderAutoReceiptDue(order)) continue;
      if (_autoFinalizeInFlight.contains(order.id)) continue;
      _autoFinalizeInFlight.add(order.id);
      unawaited(_autoFinalizeOrder(order));
    }
  }

  Future<void> _autoFinalizeOrder(PurchaseOrder order) async {
    try {
      await ref.read(purchaseOrderRepositoryProvider).autoConfirmRequesterReceived(
            order: order,
          );
    } catch (error, stack) {
      logError(error, stack, context: 'HomeScreen.autoConfirmRequesterReceived');
    } finally {
      _autoFinalizeInFlight.remove(order.id);
    }
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
        user != null && (isAdmin || isDireccionGeneral || isCompras);
    final isContabilidad =
        user != null && isContabilidadLabel(user.areaDisplay);
    final surfaceColor = scheme.surface;

    return Scaffold(
      drawer: _HomeDrawer(
        isAdmin: isAdmin,
        canViewOrderHistory: user != null,
        canViewGeneralHistory: canViewGeneralHistory,
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
                  user == null ? 'Bienvenido' : 'Bienvenido ${user.name}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
        actions: [
          _HomeNotificationsAction(
            onOpenProfile: () => showProfileSheet(context, ref),
          ),
          if (isAdmin || isCompras)
            IconButton(
              icon: const Icon(Icons.monitor_heart_outlined),
              tooltip: 'Monitoreo',
              onPressed: () => guardedPush(context, '/orders/monitoring'),
            ),
          if (canSwitchCompany)
            _CompanySwitcherAction(currentBranding: branding),
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
                title: 'Autorizar ordenes',
                subtitle: 'Revision inicial del requerimiento',
                icon: Icons.fact_check_outlined,
                color: scheme.secondary,
                foreground: scheme.onSecondary,
                countProvider: pendingComprasCountProvider,
                onTap: () => guardedPush(context, '/orders/pending'),
              ),
            if (isAdmin || isCompras)
              _HomeBlockData(
                title: 'Compras',
                subtitle: 'Completar datos y armar compras por proveedor',
                icon: Icons.request_quote_outlined,
                color: scheme.secondaryContainer,
                foreground: scheme.onSecondaryContainer,
                countProvider: cotizacionesModuleCountProvider,
                onTap: () => guardedPush(context, '/orders/cotizaciones'),
              ),
            if (isAdmin || isDireccionGeneral)
              _HomeBlockData(
                title: 'Dirección General',
                subtitle: 'Autorizacion de pago por proveedor',
                icon: Icons.approval_outlined,
                color: scheme.tertiary,
                foreground: scheme.onTertiary,
                countProvider: pendingDireccionBundleCountProvider,
                onTap: () => guardedPush(context, '/orders/direccion'),
              ),
            if (isAdmin || isCompras)
              _HomeBlockData(
                title: 'Agregar fecha de llegada',
                subtitle: 'Definir fecha estimada y enviar a Contabilidad',
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
            _HomeBlockData(
              title: 'Ordenes en proceso',
              subtitle: 'Seguimiento del avance de tus solicitudes',
              icon: Icons.track_changes_outlined,
              color: scheme.primaryContainer,
              foreground: scheme.onPrimaryContainer,
              countProvider: userInProcessOrdersCountProvider,
              onTap: () => guardedPush(context, '/orders/in-process'),
            ),
            if (isAdmin || isCompras)
              _HomeBlockData(
                title: 'Monitoreo de acciones',
                subtitle: 'Rechazadas y finalizadas pendientes de recibido',
                icon: Icons.report_gmailerrorred_outlined,
                color: scheme.errorContainer,
                foreground: scheme.onErrorContainer,
                countProvider: globalActionMonitoringCountProvider,
                onTap: () => guardedPush(context, '/orders/rejected/all'),
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
  const _HomeDrawer({
    required this.isAdmin,
    required this.canViewOrderHistory,
    required this.canViewGeneralHistory,
    required this.onOpenProfile,
  });

  final bool isAdmin;
  final bool canViewOrderHistory;
  final bool canViewGeneralHistory;
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
            if (canViewOrderHistory)
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text('Historial de ordenes'),
                onTap: () {
                  Navigator.pop(context);
                  guardedPush(context, '/orders/history');
                },
              ),
            if (canViewGeneralHistory)
              ListTile(
                leading: const Icon(Icons.manage_search_outlined),
                title: const Text('Historial general'),
                onTap: () {
                  Navigator.pop(context);
                  guardedPush(context, '/orders/history/all');
                },
              ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Formato'),
              onTap: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(
                  MaterialPageRoute(
                    builder: (_) => const _BlankRequisitionFormatScreen(),
                  ),
                );
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

class _HomeNotificationsAction extends ConsumerWidget {
  const _HomeNotificationsAction({required this.onOpenProfile});

  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(homeNotificationsCountProvider);
    return IconButton(
      tooltip: 'Notificaciones',
      onPressed: () => _showHomeNotificationsSheet(
        context,
        ref,
        onOpenProfile: onOpenProfile,
      ),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none_outlined),
          if (total > 0)
            Positioned(
              right: -4,
              top: -4,
              child: _CountBadge(
                count: total,
                color: Theme.of(context).colorScheme.error,
                textColor: Theme.of(context).colorScheme.onError,
              ),
            ),
        ],
      ),
    );
  }
}

class _BlankRequisitionFormatScreen extends ConsumerStatefulWidget {
  const _BlankRequisitionFormatScreen();

  @override
  ConsumerState<_BlankRequisitionFormatScreen> createState() =>
      _BlankRequisitionFormatScreenState();
}

class _BlankRequisitionFormatScreenState
    extends ConsumerState<_BlankRequisitionFormatScreen> {
  bool _downloading = false;

  @override
  Widget build(BuildContext context) {
    final branding = ref.watch(currentBrandingProvider);
    final pdfData = _blankRequisitionFormatData(branding);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Formato de requisicion'),
        actions: [
          IconButton(
            onPressed: _downloading ? null : () => _downloadPdf(pdfData),
            tooltip: 'Descargar PDF',
            icon: _downloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: OrderPdfInlineView(data: pdfData),
      ),
    );
  }

  Future<void> _downloadPdf(OrderPdfData pdfData) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final bytes = await buildOrderPdf(pdfData, useIsolate: false);
      if (!mounted) return;
      await savePdfBytes(
        context,
        bytes: bytes,
        suggestedName: 'formato_requisicion_compra.pdf',
      );
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }
}

OrderPdfData _blankRequisitionFormatData(CompanyBranding branding) {
  return OrderPdfData(
    branding: branding,
    requesterName: '',
    requesterArea: '',
    areaName: '',
    urgency: PurchaseOrderUrgency.normal,
    items: const <OrderItemDraft>[],
    createdAt: DateTime.now(),
    observations: '',
    folio: '',
    internalOrder: '',
    supplier: '',
    comprasComment: '',
    comprasReviewerName: '',
    comprasReviewerArea: '',
    processedByName: '',
    processedByArea: '',
    direccionGeneralName: '',
    direccionGeneralArea: '',
    urgentJustification: '',
    blankTemplate: true,
    cacheSalt: 'blank-requisition-format',
  );
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

Future<void> _showHomeNotificationsSheet(
  BuildContext parentContext,
  WidgetRef ref, {
  required VoidCallback onOpenProfile,
}) async {
  await showModalBottomSheet<void>(
    context: parentContext,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return _HomeNotificationsSheet(
        parentContext: parentContext,
        onOpenProfile: onOpenProfile,
      );
    },
  );
}

class _HomeNotificationsSheet extends ConsumerWidget {
  const _HomeNotificationsSheet({
    required this.parentContext,
    required this.onOpenProfile,
  });

  final BuildContext parentContext;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProfileProvider).value;
    final notifications = ref.watch(homeNotificationsProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notificaciones',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Avisos internos basados en tus pendientes y el estado de tus órdenes.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              if (user != null)
                _HomeNotificationsEmailCard(
                  user: user,
                  onOpenProfile: () {
                    Navigator.of(context).pop();
                    onOpenProfile();
                  },
                ),
              const SizedBox(height: 12),
              Expanded(
                child: notifications.isEmpty
                    ? Center(
                        child: Text(
                          'No hay notificaciones internas por ahora.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    : ListView.separated(
                        itemCount: notifications.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = notifications[index];
                          return _HomeNotificationCard(
                            item: item,
                            onTap: () {
                              Navigator.of(context).pop();
                              guardedPush(parentContext, item.route);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeNotificationsEmailCard extends StatelessWidget {
  const _HomeNotificationsEmailCard({
    required this.user,
    required this.onOpenProfile,
  });

  final AppUser user;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasContactEmail = (user.contactEmail ?? '').trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasContactEmail ? Icons.mail_outline : Icons.mark_email_unread_outlined,
            color: scheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notificationContactEmailLabel(user),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasContactEmail
                      ? 'Este correo se usa como contacto para recibir avisos y preparar correos desde tu dispositivo.'
                      : 'Registra tu correo de contacto para recibir avisos manuales y preparar correos desde la app.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onOpenProfile,
            child: Text(hasContactEmail ? 'Editar' : 'Configurar'),
          ),
        ],
      ),
    );
  }
}

class _HomeNotificationCard extends StatelessWidget {
  const _HomeNotificationCard({
    required this.item,
    required this.onTap,
  });

  final HomeNotificationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = notificationToneColor(scheme, item.tone);

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.message,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                children: [
                  _CountBadge(
                    count: item.count,
                    color: accent,
                    textColor: Colors.white,
                  ),
                  const SizedBox(height: 8),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
