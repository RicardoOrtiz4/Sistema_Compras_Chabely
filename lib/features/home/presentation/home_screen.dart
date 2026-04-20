import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import 'package:sistema_compras/core/access_control.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/save_bytes.dart';
import 'package:sistema_compras/core/widgets/app_logo.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/features/profile/presentation/profile_sheet.dart';
import 'package:sistema_compras/features/orders/application/create_order_controller.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_inline_view.dart';
import 'package:sistema_compras/features/purchase_packets/application/purchase_packet_use_cases.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  ProviderSubscription<AsyncValue<AppUser?>>? _profileSubscription;
  ProviderSubscription<CompanyBranding>? _brandingSubscription;
  ProviderSubscription<AsyncValue<List<PurchaseOrder>>>?
  _userOrdersSubscription;
  ProviderSubscription<AsyncValue<List<PurchaseOrder>>>?
  _operationalOrdersSubscription;
  final Set<String> _autoFinalizeInFlight = <String>{};
  bool _isDrawerOpen = false;

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
    _operationalOrdersSubscription = ref
        .listenManual<AsyncValue<List<PurchaseOrder>>>(
          operationalOrdersProvider,
          (_, next) {
            final user = ref.read(currentUserProfileProvider).value;
            if (user == null) return;
            final canProcessAll = canViewMonitoring(user);
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
      await ref
          .read(purchaseOrderRepositoryProvider)
          .autoConfirmRequesterReceived(order: order);
      refreshRequesterReceiptWorkflowData(ref, orderIds: <String>[order.id]);
    } catch (error, stack) {
      logError(
        error,
        stack,
        context: 'HomeScreen.autoConfirmRequesterReceived',
      );
    } finally {
      _autoFinalizeInFlight.remove(order.id);
    }
  }

  Future<void> _navigateFromDrawer(String location) async {
    final reopenDrawer = _isDrawerOpen;
    Navigator.of(context).pop();
    await guardedPush(context, location);
    if (!mounted || !reopenDrawer) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scaffoldKey.currentState?.openDrawer();
    });
  }


  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final userAsync = ref.watch(currentUserProfileProvider);
    final user = userAsync.value;
    final branding = ref.watch(currentBrandingProvider);
    final dashboardSubmissionCount = ref.watch(
      dashboardPacketSubmissionCountProvider,
    );
    final isAdmin = hasAdminAccess(user);
    final canSwitchCompany = isAdmin;
    final canAccessMonitoring = canViewMonitoring(user);
    final surfaceColor = scheme.surface;

    return Scaffold(
      key: _scaffoldKey,
      onDrawerChanged: (isOpen) {
        if (_isDrawerOpen == isOpen) return;
        setState(() => _isDrawerOpen = isOpen);
      },
      drawer: _HomeDrawer(
        user: user,
        onOpenProfile: () => showProfileSheet(context, ref),
        onNavigate: _navigateFromDrawer,
      ),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: _isDrawerOpen
              ? 'Cerrar menú de navegacion'
              : 'Abrir menú de navegacion',
          onPressed: () {
            if (_isDrawerOpen) {
              Navigator.of(context).maybePop();
              return;
            }
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
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
                  user == null ? 'Bienvenido' : 'Bienvenido, ${user.name}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.monitor_heart_outlined),
            tooltip: 'Monitoreo',
            onPressed: canAccessMonitoring
                ? () => guardedPush(context, '/orders/monitoring')
                : null,
          ),
          if (canSwitchCompany)
            _CompanySwitcherAction(
              currentBranding: branding,
              userEmail: user?.email,
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
            _HomeBlockData(
              title: 'Autorizar ordenes',
              subtitle: 'Primera etapa despues de crear la orden',
              icon: Icons.fact_check_outlined,
              color: scheme.secondary,
              foreground: scheme.onSecondary,
              enabled: hasAuthorizeOrdersAccess(user),
              countProvider: intakeReviewCountProvider,
              onTap: () => guardedPush(context, '/orders/authorize'),
            ),
            _HomeBlockData(
              title: 'Compras',
              subtitle: 'Pendientes y dashboard de agrupacion por proveedor',
              icon: Icons.request_quote_outlined,
              color: scheme.secondaryContainer,
              foreground: scheme.onSecondaryContainer,
              enabled: hasComprasAccess(user),
              countProvider: sourcingModuleCountProvider,
              onTap: () => guardedPush(context, '/orders/compras'),
            ),
            _HomeBlockData(
              title: 'Direccion General',
              subtitle: 'Aprobacion ejecutiva separada de Compras',
              icon: Icons.approval_outlined,
              color: scheme.tertiaryContainer,
              foreground: scheme.onTertiaryContainer,
              enabled: hasDireccionApprovalAccess(user),
              countProvider: pendingDireccionPacketsCountProvider,
              onTap: () => guardedPush(context, '/orders/direccion-general'),
            ),
            _HomeBlockData(
              title: 'Agregar fecha estimada',
              subtitle: 'Registrar ETA despues de la aprobacion ejecutiva',
              icon: Icons.event_available_outlined,
              color: scheme.tertiary,
              foreground: scheme.onTertiary,
              enabled: hasEtaAccess(user),
              countProvider: pendingEtaCountProvider,
              onTap: () => guardedPush(context, '/orders/agregar-fecha-estimada'),
            ),
            _HomeBlockData(
              title: 'Facturas y evidencias',
              subtitle: 'Ultima etapa documental antes del cierre final',
              icon: Icons.receipt_long_outlined,
              color: scheme.tertiaryFixed,
              foreground: scheme.onTertiaryFixed,
              enabled: hasFacturasEvidenciasAccess(user),
              countProvider: contabilidadCountProvider,
              onTap: () => guardedPush(context, '/orders/facturas-evidencias'),
            ),
            _HomeBlockData(
              title: 'Ordenes en proceso',
              subtitle: 'Seguimiento y cierre final de tus solicitudes',
              icon: Icons.track_changes_outlined,
              color: scheme.primaryContainer,
              foreground: scheme.onPrimaryContainer,
              countProvider: userInProcessOrdersCountProvider,
              onTap: () => guardedPush(context, '/orders/in-process'),
            ),
            _HomeBlockData(
              title: 'Ordenes rechazadas',
              subtitle: 'Avisos de rechazo pendientes de enterado',
              icon: Icons.report_problem_outlined,
              color: scheme.error,
              foreground: scheme.onError,
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
                      if (dashboardSubmissionCount > 0) ...[
                        Material(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                const Icon(Icons.sync_outlined),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    dashboardSubmissionCount == 1
                                        ? 'Hay 1 paquete enviandose a Direccion General. Puedes salir de la pantalla; el envio continua.'
                                        : 'Hay $dashboardSubmissionCount paquetes enviandose a Direccion General. Puedes salir de la pantalla; el envio continua.',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
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
    required this.user,
    required this.onOpenProfile,
    required this.onNavigate,
  });

  final AppUser? user;
  final VoidCallback onOpenProfile;
  final Future<void> Function(String location) onNavigate;

  @override
  Widget build(BuildContext context) {
    final canManageSuppliersAccess = canManageSuppliers(user);
    final canManageClientsAccess = canManageClients(user);
    final canViewReportsAccess = canViewReports(user);
    final canManageUsersAccess = canManageUsers(user);
    final canViewGlobalHistoryAccess = canViewGlobalHistory(user);
    final canComprasModule = hasComprasAccess(user);
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.menu),
                    tooltip: 'Cerrar menú de navegacion',
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Text('Menú', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
            _DrawerTile(
              enabled: canManageSuppliersAccess,
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Gestión de proveedores'),
              onTap: () => unawaited(onNavigate('/partners/suppliers')),
            ),
            _DrawerTile(
              enabled: canManageClientsAccess,
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Gestión de clientes'),
              onTap: () => unawaited(onNavigate('/partners/clients')),
            ),
            _DrawerTile(
              enabled: canViewReportsAccess,
              leading: const Icon(Icons.insights_outlined),
              title: const Text('Reportes'),
              onTap: () => unawaited(onNavigate('/reports')),
            ),
            _DrawerTile(
              enabled: canComprasModule,
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Historial de PDFs de paquetes por proveedor'),
              onTap: () => unawaited(onNavigate('/orders/compras/historial-pdfs')),
            ),
            _DrawerTile(
              enabled: canManageUsersAccess,
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Administrar usuarios'),
              onTap: () => unawaited(onNavigate('/admin/users')),
            ),
            ListTile(
              leading: const Icon(Icons.history_outlined),
              title: const Text('Historial de mis ordenes'),
              onTap: () => unawaited(onNavigate('/orders/history')),
            ),
            _DrawerTile(
              enabled: canViewGlobalHistoryAccess,
              leading: const Icon(Icons.manage_search_outlined),
              title: const Text('Historial general'),
              onTap: () => unawaited(onNavigate('/orders/history/all')),
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Ejemplo CSV'),
              subtitle: const Text('Plantilla para importar articulos'),
              onTap: () {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(context);
                unawaited(_downloadCsvImportExample(messenger));
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

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.enabled,
    required this.leading,
    required this.title,
    required this.onTap,
  });

  final bool enabled;
  final Widget leading;
  final Widget title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      leading: leading,
      title: title,
      onTap: enabled ? onTap : null,
    );
  }
}

Future<void> _downloadCsvImportExample(ScaffoldMessengerState messenger) async {
  const suggestedName = 'ejemplo_requisicion.csv';
  final csv = buildCsvImportExample();
  final bytes = Uint8List.fromList(utf8.encode('\uFEFF$csv'));

  try {
    final savedPath = await pickSavePath(
      suggestedName: suggestedName,
      dialogTitle: 'Guardar ejemplo CSV',
      allowedExtensions: const <String>['csv'],
    );
    if (savedPath == null) return;
    await saveBytesToSelectedPath(savedPath, bytes);

    if (messenger.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Ejemplo CSV descargado.')),
      );
    }
  } catch (_) {
    if (messenger.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo descargar el ejemplo CSV.')),
      );
    }
  }
}

String buildCsvImportExample() {
  const rows = <List<String>>[
    [
      'linea',
      'noParte',
      'descripcion',
      'cantidad',
      'unidad',
    ],
    [
      '1',
      'ROD-6204',
      'Rodamiento sellado 6204 2RS',
      '12',
      'PZA',
    ],
    [
      '2',
      'ACE-HID-46',
      'Aceite hidraulico ISO VG 46',
      '4',
      'GAL',
    ],
    [
      '3',
      'TOR-M8X30',
      'Tornillo hexagonal M8 x 30 mm grado 8.8',
      '100',
      'PZA',
    ],
  ];

  const converter = ListToCsvConverter();
  return converter.convert(rows);
}

class _BlankRequisitionFormatScreen extends ConsumerStatefulWidget {
  const _BlankRequisitionFormatScreen();

  @override
  ConsumerState<_BlankRequisitionFormatScreen> createState() =>
      _BlankRequisitionFormatScreenState();
}

class _BlankRequisitionFormatScreenState
    extends ConsumerState<_BlankRequisitionFormatScreen> {

  @override
  Widget build(BuildContext context) {
    final branding = ref.watch(currentBrandingProvider);
    final pdfData = _blankRequisitionFormatData(branding);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Formato de requisición'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: OrderPdfInlineView(data: pdfData),
      ),
    );
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
    this.onTap,
    this.enabled = true,
    this.countProvider,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color foreground;
  final bool enabled;
  final ProviderListenable<AsyncValue<int>>? countProvider;
  final VoidCallback? onTap;
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
    final scheme = Theme.of(context).colorScheme;
    final enabled = data.enabled && data.onTap != null;
    final effectiveHovered = enabled && _hovered;
    final foreground = enabled ? data.foreground : scheme.outline;
    final background = enabled
        ? data.color
        : (Color.lerp(
              scheme.surfaceContainerHighest,
              scheme.outlineVariant,
              0.45,
            ) ??
            scheme.surfaceContainerHighest);
    final borderColor = effectiveHovered
        ? foreground.withValues(alpha: 0.34)
        : (enabled ? foreground.withValues(alpha: 0.14) : scheme.outline);
    final shadowColor = effectiveHovered
        ? foreground.withValues(alpha: 0.16)
        : (enabled ? Colors.black.withValues(alpha: 0.08) : Colors.transparent);
    final softError =
        Color.lerp(scheme.error, Colors.white, 0.35) ?? scheme.error;
    final badgeColor = softError;
    final badgeTextColor = Colors.white;
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: foreground,
      fontSize: 13.5,
    );
    final subtitleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: foreground.withValues(alpha: effectiveHovered ? 0.88 : 0.78),
      fontSize: 11,
      fontWeight: enabled ? null : FontWeight.w600,
    );
    final iconSurface = effectiveHovered
        ? foreground.withValues(alpha: 0.18)
        : foreground.withValues(alpha: enabled ? 0.1 : 0.16);
    final subtitle = enabled ? data.subtitle : 'Sin permiso para acceder';

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onEnter: (_) {
        if (enabled) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        transform:
            Matrix4.translationValues(0, effectiveHovered ? -2.5 : 0, 0),
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(22),
          elevation: 0,
          child: AbsorbPointer(
            absorbing: !enabled,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: enabled ? data.onTap : null,
              canRequestFocus: enabled,
              enableFeedback: enabled,
              mouseCursor:
                  enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
              child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: borderColor,
                  width: effectiveHovered ? 1.2 : (enabled ? 1 : 1.4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: effectiveHovered ? 24 : 14,
                    offset: Offset(0, effectiveHovered ? 12 : 8),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: effectiveHovered ? 1 : (enabled ? 0.72 : 0.1),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(
                                  alpha: effectiveHovered ? 0.14 : 0.06,
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
                            foreground.withValues(
                              alpha: effectiveHovered ? 0.92 : 0.0,
                            ),
                            foreground.withValues(
                              alpha: effectiveHovered ? 0.26 : 0.0,
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
                                color: foreground.withValues(
                                  alpha: effectiveHovered ? 0.18 : 0.08,
                                ),
                              ),
                            ),
                            child: Icon(
                              data.icon,
                              color: foreground,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: AnimatedSlide(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              offset: effectiveHovered
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
                          if (enabled)
                            _HomeBlockBadgeSlot(
                              data: data,
                              hovered: effectiveHovered,
                              badgeColor: badgeColor,
                              badgeTextColor: badgeTextColor,
                            )
                          else
                            const _DisabledHomeBadge(),
                        ],
                      ),
                      const SizedBox(height: 6),
                      AnimatedSlide(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        offset: effectiveHovered
                            ? const Offset(0.01, 0)
                            : Offset.zero,
                        child: Text(
                          subtitle,
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

class _DisabledHomeBadge extends StatelessWidget {
  const _DisabledHomeBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 12, color: scheme.outline),
            const SizedBox(width: 4),
            Text(
              'Sin permiso',
              style: TextStyle(
                color: scheme.outline,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompanySwitcherAction extends ConsumerWidget {
  const _CompanySwitcherAction({
    required this.currentBranding,
    required this.userEmail,
  });

  final CompanyBranding currentBranding;
  final String? userEmail;

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
        userEmail,
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

Future<void> _showCompanySwitcher(
  BuildContext context,
  WidgetRef ref,
  CompanyBranding currentBranding,
  List<CompanyBranding> brandings,
  String? userEmail,
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
                  if (branding.id == currentBranding.id) {
                    Navigator.of(context).pop();
                    return;
                  }
                  ref.read(companySwitchInProgressProvider.notifier).state = true;
                  unawaited(
                    ref.read(currentCompanyProvider.notifier).selectCompany(
                          branding.company,
                          authenticatedEmail: userEmail,
                        ),
                  );
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      );
    },
  );
}
