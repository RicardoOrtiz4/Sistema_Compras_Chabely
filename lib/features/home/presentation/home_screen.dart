import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/legacy.dart';

import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/widgets/app_logo.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/core/widgets/info_action.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/features/profile/presentation/profile_sheet.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

final _reminderSeenUserIdProvider = StateProvider<String?>((ref) => null);
final _reminderOpenProvider = StateProvider<bool>((ref) => false);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _reminderScheduled = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserProfileProvider, (previous, next) {
      if (previous?.value == null && next.value != null) {
        final branding = ref.read(currentBrandingProvider);
        warmUpPdfAssets(branding);
        warmUpPdfEngine(branding);
      }
    });
    ref.listen(currentBrandingProvider, (previous, next) {
      if (previous?.id == next.id) return;
      warmUpPdfAssets(next);
      warmUpPdfEngine(next);
    });
    final scheme = Theme.of(context).colorScheme;
    final userAsync = ref.watch(currentUserProfileProvider);
    final user = userAsync.value;
    final branding = ref.watch(currentBrandingProvider);
    final availableBrandings = ref.watch(availableBrandingsProvider);
    final isAdmin = user != null && isAdminRole(user.role);
    final canSwitchCompany = _canSwitchCompany(user, isAdmin);
    final isCompras = user != null && isComprasLabel(user.areaDisplay);
    final isDireccionGeneral =
        user != null && isDireccionGeneralLabel(user.areaDisplay);
    final canViewGeneralHistory = user != null && (isAdmin || isDireccionGeneral);
    final isContabilidad =
        user != null && isContabilidadLabel(user.areaDisplay);
    final isAlmacen = user != null && isAlmacenLabel(user.areaDisplay);
    final pendingAsync = ref.watch(pendingComprasOrdersProvider);
    final cotizacionesAsync = ref.watch(cotizacionesOrdersProvider);
    final rejectedAsync = ref.watch(rejectedOrdersProvider);
    final direccionAsync = ref.watch(pendingDireccionOrdersProvider);
    final etaAsync = ref.watch(pendingEtaOrdersProvider);
    final contabilidadAsync = ref.watch(contabilidadOrdersProvider);
    final almacenAsync = ref.watch(almacenOrdersProvider);
    final pendingCount = pendingAsync.value?.length ?? 0;
    final cotizacionesCount = cotizacionesAsync.value?.length ?? 0;
    final readyToSendCount = _readyToSendCount(cotizacionesAsync.value);
    final rejectedCount = rejectedAsync.value?.length ?? 0;
    final direccionCount = direccionAsync.value?.length ?? 0;
    final etaCount = etaAsync.value?.length ?? 0;
    final contabilidadCount = contabilidadAsync.value?.length ?? 0;
    final almacenCount = almacenAsync.value?.length ?? 0;
    final surfaceColor = scheme.surface;

    return Scaffold(
      drawer: _HomeDrawer(isAdmin: isAdmin),
      appBar: AppBar(
        toolbarHeight: 96,
        backgroundColor: surfaceColor,
        surfaceTintColor: surfaceColor,
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const AppLogo(size: 72),
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
            IconButton(
              icon: const Icon(Icons.business_outlined),
              tooltip: 'Cambiar empresa',
              onPressed: () => _showCompanySwitcher(
                context,
                ref,
                branding,
                availableBrandings,
              ),
            ),
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
          infoAction(
            context,
            title: 'Inicio',
            message:
                'Desde aqu? accedes a los m?dulos seg?n tu rol.\n'
                'Usa los botones de historial para ver tus ?rdenes o el historial general.\n'
                'Si tienes permiso, cambia empresa con el ?cono de negocio.\n'
                'Las tarjetas muestran conteos y te llevan a cada flujo.',
            ),
        ],
      ),
      body: userAsync.when(
        data: (user) {
          if (user == null) {
            return const AppSplash();
          }
          _maybeShowReminder(
            context,
            user: user,
            isAdmin: isAdmin,
            isCompras: isCompras,
            isDireccionGeneral: isDireccionGeneral,
            isContabilidad: isContabilidad,
            isAlmacen: isAlmacen,
            pendingCount: pendingCount,
            cotizacionesCount: cotizacionesCount,
            direccionCount: direccionCount,
            etaCount: etaCount,
            contabilidadCount: contabilidadCount,
            almacenCount: almacenCount,
            rejectedCount: rejectedCount,
            pendingReady: pendingAsync.hasValue,
            cotizacionesReady: cotizacionesAsync.hasValue,
            direccionReady: direccionAsync.hasValue,
            etaReady: etaAsync.hasValue,
            contabilidadReady: contabilidadAsync.hasValue,
            almacenReady: almacenAsync.hasValue,
            rejectedReady: rejectedAsync.hasValue,
          );
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
                count: pendingCount,
                onTap: () => guardedPush(context, '/orders/pending'),
              ),
            if (isAdmin || isCompras)
              _HomeBlockData(
                title: 'Cotizaciones',
                subtitle: readyToSendCount > 0
                    ? 'Asignar proveedor y presupuesto | Listas para enviar: $readyToSendCount'
                    : 'Asignar proveedor y presupuesto',
                icon: Icons.request_quote_outlined,
                color: scheme.secondaryContainer,
                foreground: scheme.onSecondaryContainer,
                count: cotizacionesCount,
                onTap: () => guardedPush(context, '/orders/cotizaciones'),
              ),
            if (isAdmin || isDireccionGeneral)
              _HomeBlockData(
                title: 'Dirección General',
                subtitle: 'Autorización de órdenes',
                icon: Icons.approval_outlined,
                color: scheme.tertiary,
                foreground: scheme.onTertiary,
                count: direccionCount,
                onTap: () => guardedPush(context, '/orders/direccion'),
              ),
            if (isAdmin || isCompras)
              _HomeBlockData(
                title: 'Pendientes de fecha estimada',
                subtitle: 'Confirmar entregas',
                icon: Icons.assignment_turned_in_outlined,
                color: scheme.secondary,
                foreground: scheme.onSecondary,
                count: etaCount,
                onTap: () => guardedPush(context, '/orders/eta'),
              ),
            if (isAdmin || isContabilidad)
              _HomeBlockData(
                title: 'Contabilidad',
                subtitle: 'Registro y pagos',
                icon: Icons.receipt_long_outlined,
                color: scheme.tertiary,
                foreground: scheme.onTertiary,
                count: contabilidadCount,
                onTap: () => guardedPush(context, '/orders/contabilidad'),
              ),
            if (isAdmin || isAlmacen)
              _HomeBlockData(
                title: 'Almacén',
                subtitle: 'Recepción de compras',
                icon: Icons.inventory_2_outlined,
                color: scheme.primary,
                foreground: scheme.onPrimary,
                count: almacenCount,
                onTap: () => guardedPush(context, '/orders/almacen'),
              ),


            _HomeBlockData(
              title: 'Órdenes rechazadas',
              subtitle: 'Correcciones pendientes',
              icon: Icons.report_problem_outlined,
              color: scheme.error,
              foreground: scheme.onError,
              isRejected: true,
              count: rejectedCount,
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
                  final cardWidth = (constraints.maxWidth -
                          (tileSpacing * (columns - 1))) /
                      columns;
                  final rows = (blocks.length / columns).ceil();
                  final screenHeight = MediaQuery.of(context).size.height;
                  final reserved = 120.0;
                  final maxCardHeight = (screenHeight -
                          reserved -
                          (tileSpacing * (rows - 1))) /
                      rows;
                  final targetHeight =
                      maxCardHeight.clamp(104.0, cardWidth < 200 ? 145.0 : 135.0);
                  final aspectRatio = cardWidth / targetHeight;

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    children: [
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: tileSpacing,
                          mainAxisSpacing: tileSpacing,
                          childAspectRatio: aspectRatio,
                        ),
                        itemCount: blocks.length,
                        itemBuilder: (context, index) => _HomeBlockCard(
                          data: blocks[index],
                        ),
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

  void _maybeShowReminder(
    BuildContext context, {
    required AppUser user,
    required bool isAdmin,
    required bool isCompras,
    required bool isDireccionGeneral,
    required bool isContabilidad,
    required bool isAlmacen,
    required int pendingCount,
    required int cotizacionesCount,
    required int direccionCount,
    required int etaCount,
    required int contabilidadCount,
    required int almacenCount,
    required int rejectedCount,
    required bool pendingReady,
    required bool cotizacionesReady,
    required bool direccionReady,
    required bool etaReady,
    required bool contabilidadReady,
    required bool almacenReady,
    required bool rejectedReady,
  }) {
    if (!_isHomeRouteActive(context)) return;
    final seenForUser = ref.read(_reminderSeenUserIdProvider);
    if (seenForUser == user.id) return;
    if (ref.read(_reminderOpenProvider)) return;
    if (_reminderScheduled) return;
    if (!_isReminderReady(
      isAdmin: isAdmin,
      isCompras: isCompras,
      isDireccionGeneral: isDireccionGeneral,
      isContabilidad: isContabilidad,
      isAlmacen: isAlmacen,
      pendingReady: pendingReady,
      cotizacionesReady: cotizacionesReady,
      direccionReady: direccionReady,
      etaReady: etaReady,
      contabilidadReady: contabilidadReady,
      almacenReady: almacenReady,
      rejectedReady: rejectedReady,
    )) {
      return;
    }
    final options = _buildReminderOptions(
      isAdmin: isAdmin,
      isCompras: isCompras,
      isDireccionGeneral: isDireccionGeneral,
      isContabilidad: isContabilidad,
      isAlmacen: isAlmacen,
      pendingCount: pendingCount,
      cotizacionesCount: cotizacionesCount,
      direccionCount: direccionCount,
      etaCount: etaCount,
      contabilidadCount: contabilidadCount,
      almacenCount: almacenCount,
      rejectedCount: rejectedCount,
    );
    if (options.isEmpty) {
      return;
    }
    _reminderScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reminderScheduled = false;
      if (!mounted) {
        return;
      }
      if (!_isHomeRouteActive(context)) return;
      if (ref.read(_reminderOpenProvider)) return;
      if (ref.read(_reminderSeenUserIdProvider) == user.id) return;
      ref.read(_reminderSeenUserIdProvider.notifier).state = user.id;
      ref.read(_reminderOpenProvider.notifier).state = true;
      _showReminderDialog(context, options: options).then((selection) {
        if (!mounted) return;
        ref.read(_reminderOpenProvider.notifier).state = false;
        if (selection == null) return;
        guardedPush(context, selection.route);
      });
    });
  }
}

bool _isHomeRouteActive(BuildContext context) {
  final route = ModalRoute.of(context);
  if (route == null) return true;
  return route.isCurrent;
}

Future<_ReminderOption?> _showReminderDialog(
  BuildContext context, {
  required List<_ReminderOption> options,
}) {
  return showDialog<_ReminderOption>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Resumen de pendientes'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Selecciona la sección a revisar:'),
            const SizedBox(height: 12),
            for (final option in options)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ReminderOptionTile(option: option),
              ),

          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}

bool _isReminderReady({
  required bool isAdmin,
  required bool isCompras,
  required bool isDireccionGeneral,
  required bool isContabilidad,
  required bool isAlmacen,
  required bool pendingReady,
  required bool cotizacionesReady,
  required bool direccionReady,
  required bool etaReady,
  required bool contabilidadReady,
  required bool almacenReady,
  required bool rejectedReady,
}) {
  if (isAdmin || isCompras) {
    if (!pendingReady || !cotizacionesReady || !etaReady) {
      return false;
    }
  }
  if (isAdmin || isDireccionGeneral) {
    if (!direccionReady) return false;
  }
  if (isAdmin || isContabilidad) {
    if (!contabilidadReady) return false;
  }
  if (isAdmin || isAlmacen) {
    if (!almacenReady) return false;
  }
  if (!rejectedReady) return false;
  return true;
}

List<_ReminderOption> _buildReminderOptions({
  required bool isAdmin,
  required bool isCompras,
  required bool isDireccionGeneral,
  required bool isContabilidad,
  required bool isAlmacen,
  required int pendingCount,
  required int cotizacionesCount,
  required int direccionCount,
  required int etaCount,
  required int contabilidadCount,
  required int almacenCount,
  required int rejectedCount,
}) {
  final options = <_ReminderOption>[];
  if (isAdmin || isCompras) {
    if (pendingCount > 0) {
      options.add(_ReminderOption('Órdenes por confirmar', '/orders/pending', pendingCount));
    }
    if (cotizacionesCount > 0) {
      options.add(_ReminderOption('Cotizaciones', '/orders/cotizaciones', cotizacionesCount));
    }
    if (etaCount > 0) {
      options.add(
        _ReminderOption(
          'Pendientes de fecha estimada',
          '/orders/eta',
          etaCount,
        ),
      );
    }
  }
  if (isAdmin || isDireccionGeneral) {
    if (direccionCount > 0) {
      options.add(
        _ReminderOption('Dirección General', '/orders/direccion', direccionCount),
      );
    }
  }
  if (isAdmin || isContabilidad) {
    if (contabilidadCount > 0) {
      options.add(
        _ReminderOption('Contabilidad', '/orders/contabilidad', contabilidadCount),
      );
    }
  }
  if (isAdmin || isAlmacen) {
    if (almacenCount > 0) {
      options.add(_ReminderOption('Almac?n', '/orders/almacen', almacenCount));
    }
  }
  if (rejectedCount > 0) {
    options.add(
      _ReminderOption('?rdenes rechazadas', '/orders/rejected', rejectedCount, isRejected: true),
    );
  }
  return options;
}



int _readyToSendCount(List<PurchaseOrder>? orders) {
  if (orders == null) return 0;
  var count = 0;
  for (final order in orders) {
    if (_orderReadyToSend(order)) {
      count += 1;
    }
  }
  return count;
}

bool _orderReadyToSend(PurchaseOrder order) {
  if (order.items.isEmpty) return false;
  return order.items.every(_itemReadyForDashboard) && _hasQuoteLink(order);
}

bool _hasQuoteLink(PurchaseOrder order) {
  return order.cotizacionLinks.any((link) => link.url.trim().isNotEmpty);
}

bool _itemReadyForDashboard(PurchaseOrderItem item) {
  final supplier = (item.supplier ?? '').trim();
  final budget = item.budget ?? 0;
  return supplier.isNotEmpty && budget > 0;
}

class _ReminderOption {
  const _ReminderOption(this.label, this.route, this.count, {this.isRejected = false});

  final String label;
  final String route;
  final int count;
  final bool isRejected;
}

class _ReminderOptionTile extends StatelessWidget {
  const _ReminderOptionTile({required this.option});

  final _ReminderOption option;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final softError = Color.lerp(scheme.error, Colors.white, 0.35) ?? scheme.error;
    final badgeColor = option.isRejected ? Colors.white : softError;
    final badgeTextColor = option.isRejected ? Colors.black : Colors.white;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.pop(context, option),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(child: Text(option.label)),
            _CountBadge(
              count: option.count,
              color: badgeColor,
              textColor: badgeTextColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeDrawer extends ConsumerWidget {
  const _HomeDrawer({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    showProfileSheet(context, ref);
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
    this.count,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color foreground;
  final int? count;
  final VoidCallback onTap;
  final bool isRejected;
}

class _HomeBlockCard extends StatelessWidget {
  const _HomeBlockCard({required this.data});

  final _HomeBlockData data;

  @override
  Widget build(BuildContext context) {
    final background = data.color;
    final borderColor = data.foreground.withOpacity(0.18);
    final shadowColor = Colors.black.withOpacity(0.12);
    final scheme = Theme.of(context).colorScheme;
    final softError = Color.lerp(scheme.error, Colors.white, 0.35) ?? scheme.error;
    final badgeColor = data.isRejected ? Colors.white : softError;
    final badgeTextColor = data.isRejected ? Colors.black : Colors.white;
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: data.foreground,
          fontSize: 13.5,
        );
    final subtitleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: data.foreground.withOpacity(0.85),
          fontSize: 11,
        );
    final showBadge = data.count != null && data.count! > 0;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(22),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: data.onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: data.foreground.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      data.icon,
                      color: data.foreground,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      data.title,
                      style: titleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (showBadge) ...[
                    const SizedBox(width: 6),
                    _CountBadge(
                      count: data.count!,
                      color: badgeColor,
                      textColor: badgeTextColor,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                data.subtitle,
                style: subtitleStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
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







