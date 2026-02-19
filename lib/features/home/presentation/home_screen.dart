import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod/legacy.dart';

import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/widgets/app_logo.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/features/profile/presentation/profile_sheet.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';

final _reminderSeenUserIdProvider = StateProvider<String?>((ref) => null);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
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
    final pendingBadgeColor = _badgeColorFor(scheme.secondary);
    final cotizacionesBadgeColor = _badgeColorFor(scheme.secondaryContainer);
    final direccionBadgeColor = _badgeColorFor(scheme.tertiary);
    final etaBadgeColor = scheme.outlineVariant;
    final contabilidadBadgeColor = _badgeColorFor(scheme.tertiary);
    final almacenBadgeColor = _badgeColorFor(scheme.primary);
    final pendingAsync = ref.watch(pendingComprasOrdersProvider);
    final cotizacionesAsync = ref.watch(cotizacionesOrdersProvider);
    final rejectedAsync = ref.watch(rejectedOrdersProvider);
    final direccionAsync = ref.watch(pendingDireccionOrdersProvider);
    final etaAsync = ref.watch(pendingEtaOrdersProvider);
    final contabilidadAsync = ref.watch(contabilidadOrdersProvider);
    final almacenAsync = ref.watch(almacenOrdersProvider);
    final pendingCount = pendingAsync.maybeWhen(data: (orders) => orders.length, orElse: () => 0);
    final cotizacionesCount =
        cotizacionesAsync.maybeWhen(data: (orders) => orders.length, orElse: () => 0);
    final rejectedCount =
        rejectedAsync.maybeWhen(data: (orders) => orders.length, orElse: () => 0);
    final direccionCount =
        direccionAsync.maybeWhen(data: (orders) => orders.length, orElse: () => 0);
    final etaCount = etaAsync.maybeWhen(data: (orders) => orders.length, orElse: () => 0);
    final contabilidadCount =
        contabilidadAsync.maybeWhen(data: (orders) => orders.length, orElse: () => 0);
    final almacenCount =
        almacenAsync.maybeWhen(data: (orders) => orders.length, orElse: () => 0);
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
              onPressed: () => context.push('/orders/history'),
            ),
          if (canViewGeneralHistory)
            IconButton(
              icon: const Icon(Icons.manage_search_outlined),
              tooltip: 'Historial general',
              onPressed: () => context.push('/orders/history/all'),
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
            pendingReady: !pendingAsync.isLoading,
            cotizacionesReady: !cotizacionesAsync.isLoading,
            direccionReady: !direccionAsync.isLoading,
            etaReady: !etaAsync.isLoading,
            contabilidadReady: !contabilidadAsync.isLoading,
            almacenReady: !almacenAsync.isLoading,
            rejectedReady: !rejectedAsync.isLoading,
          );
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                children: [
                  FilledButton.icon(
                    onPressed: () => context.push('/orders/create'),
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      side: BorderSide(color: scheme.primary, width: 1.2),
                      padding: const EdgeInsets.symmetric(vertical: 32),
                    ),
                    icon: const Icon(Icons.add_shopping_cart_outlined),
                    label: const Text(
                      'Crear orden de compra',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (isAdmin || isCompras) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => context.push('/orders/pending'),
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.secondary,
                        foregroundColor: scheme.onSecondary,
                        side: BorderSide(color: scheme.secondary, width: 1.2),
                        padding: const EdgeInsets.symmetric(vertical: 24),
                      ),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: _PendingBadgeLabel(
                        count: pendingCount,
                        badgeColor: pendingBadgeColor,
                      ),
                    ),
                  ],
                  if (isAdmin || isCompras) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => context.push('/orders/cotizaciones'),
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.secondaryContainer,
                        foregroundColor: scheme.onSecondaryContainer,
                        side: BorderSide(
                          color: scheme.secondaryContainer,
                          width: 1.2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 24),
                      ),
                      icon: const Icon(Icons.request_quote_outlined),
                      label: _CotizacionesBadgeLabel(
                        count: cotizacionesCount,
                        badgeColor: cotizacionesBadgeColor,
                      ),
                    ),
                  ],
                  if (isAdmin || isDireccionGeneral) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => context.push('/orders/direccion'),
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.tertiary,
                        foregroundColor: scheme.onTertiary,
                        side: BorderSide(color: scheme.tertiary, width: 1.2),
                        padding: const EdgeInsets.symmetric(vertical: 24),
                      ),
                      icon: const Icon(Icons.approval_outlined),
                      label: _DireccionBadgeLabel(
                        count: direccionCount,
                        badgeColor: direccionBadgeColor,
                      ),
                    ),
                  ],
                  if (isAdmin || isCompras) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/orders/eta'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.secondary,
                        side: BorderSide(color: scheme.secondary, width: 1.2),
                        padding: const EdgeInsets.symmetric(vertical: 24),
                      ),
                      icon: const Icon(Icons.assignment_turned_in_outlined),
                      label: _PendingEtaBadgeLabel(
                        count: etaCount,
                        badgeColor: etaBadgeColor,
                      ),
                    ),
                  ],
                  if (isAdmin || isContabilidad) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => context.push('/orders/contabilidad'),
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.tertiary,
                        foregroundColor: scheme.onTertiary,
                        side: BorderSide(color: scheme.tertiary, width: 1.2),
                        padding: const EdgeInsets.symmetric(vertical: 24),
                      ),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: _ContabilidadBadgeLabel(
                        count: contabilidadCount,
                        badgeColor: contabilidadBadgeColor,
                      ),
                    ),
                  ],
                  if (isAdmin || isAlmacen) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => context.push('/orders/almacen'),
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        side: BorderSide(color: scheme.primary, width: 1.2),
                        padding: const EdgeInsets.symmetric(vertical: 24),
                      ),
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: _AlmacenBadgeLabel(
                        count: almacenCount,
                        badgeColor: almacenBadgeColor,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => context.push('/orders/rejected'),
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.error,
                      foregroundColor: scheme.onError,
                      side: BorderSide(color: scheme.error, width: 1.2),
                      padding: const EdgeInsets.symmetric(vertical: 24),
                    ),
                    icon: const Icon(Icons.report_problem_outlined),
                    label: _RejectedBadgeLabel(count: rejectedCount),
                  ),
                ],
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
    final seenForUser = ref.read(_reminderSeenUserIdProvider);
    if (seenForUser == user.id) return;
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
    final lines = _buildReminderLines(
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(_reminderSeenUserIdProvider.notifier).state = user.id;
      if (lines.isEmpty) return;
      _showReminderDialog(context, lines, options: options).then((selection) {
        if (!mounted || selection == null) return;
        context.push(selection.route);
      });
    });
  }
}

Future<_ReminderOption?> _showReminderDialog(
  BuildContext context,
  List<String> lines, {
  required List<_ReminderOption> options,
}) {
  return showDialog<_ReminderOption>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Resumen de pendientes'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(line),
              ),
            if (options.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Selecciona la sección a revisar:'),
              const SizedBox(height: 8),
              for (final option in options)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(option.label),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.pop(dialogContext, option);
                  },
                ),
            ],
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

List<String> _buildReminderLines({
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
  final lines = <String>[];
  if (isAdmin || isCompras) {
    if (pendingCount > 0) {
      lines.add('Te faltan $pendingCount ${_plural(pendingCount)} por confirmar.');
    }
    if (cotizacionesCount > 0) {
      lines.add('Tienes $cotizacionesCount ${_plural(cotizacionesCount)} en cotizaciones.');
    }
    if (etaCount > 0) {
      lines.add('Tienes $etaCount ${_plural(etaCount)} pendientes de fecha estimada.');
    }
  }
  if (isAdmin || isDireccionGeneral) {
    if (direccionCount > 0) {
      lines.add('Tienes $direccionCount ${_plural(direccionCount)} en Dirección General.');
    }
  }
  if (isAdmin || isContabilidad) {
    if (contabilidadCount > 0) {
      lines.add('Tienes $contabilidadCount ${_plural(contabilidadCount)} en Contabilidad.');
    }
  }
  if (isAdmin || isAlmacen) {
    if (almacenCount > 0) {
      lines.add('Tienes $almacenCount ${_plural(almacenCount)} en Almacén.');
    }
  }
  if (rejectedCount > 0) {
    lines.add('Tienes $rejectedCount ${_plural(rejectedCount)} rechazadas por corregir.');
  }
  return lines;
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
      options.add(const _ReminderOption('Órdenes por confirmar', '/orders/pending'));
    }
    if (cotizacionesCount > 0) {
      options.add(const _ReminderOption('Cotizaciones', '/orders/cotizaciones'));
    }
    if (etaCount > 0) {
      options.add(const _ReminderOption('Pendientes de fecha estimada', '/orders/eta'));
    }
  }
  if (isAdmin || isDireccionGeneral) {
    if (direccionCount > 0) {
      options.add(const _ReminderOption('Dirección General', '/orders/direccion'));
    }
  }
  if (isAdmin || isContabilidad) {
    if (contabilidadCount > 0) {
      options.add(const _ReminderOption('Contabilidad', '/orders/contabilidad'));
    }
  }
  if (isAdmin || isAlmacen) {
    if (almacenCount > 0) {
      options.add(const _ReminderOption('Almacén', '/orders/almacen'));
    }
  }
  if (rejectedCount > 0) {
    options.add(const _ReminderOption('Órdenes rechazadas', '/orders/rejected'));
  }
  return options;
}

String _plural(int count) {
  return count == 1 ? 'orden' : 'Órdenes';
}

class _ReminderOption {
  const _ReminderOption(this.label, this.route);

  final String label;
  final String route;
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
            ExpansionTile(
              leading: const Icon(Icons.build_outlined),
              title: const Text('Herramientas'),
              children: [
                ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: const Text('Gestión de proveedores'),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/partners/suppliers');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.groups_outlined),
                  title: const Text('Gestión de clientes'),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/partners/clients');
                  },
                ),
                if (isAdmin)
                  ListTile(
                    leading: const Icon(Icons.insights_outlined),
                    title: const Text('Reportes'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/reports');
                    },
                  ),
                if (isAdmin)
                  ListTile(
                    leading: const Icon(Icons.admin_panel_settings_outlined),
                    title: const Text('Administrar usuarios'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/admin/users');
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
          ],
        ),
      ),
    );
  }
}

class _PendingBadgeLabel extends StatelessWidget {
  const _PendingBadgeLabel({required this.count, required this.badgeColor});

  final int count;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const Text('Órdenes por confirmar');
    }
    final display = count > 99 ? '99+' : count.toString();
    final textColor =
        ThemeData.estimateBrightnessForColor(badgeColor) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Órdenes por confirmar'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: badgeColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            display,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

class _RejectedBadgeLabel extends StatelessWidget {
  const _RejectedBadgeLabel({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const Text('Órdenes rechazadas');
    }
    final display = count > 99 ? '99+' : count.toString();
    final badgeColor = Colors.red;
    final textColor =
        ThemeData.estimateBrightnessForColor(badgeColor) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Órdenes rechazadas'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            display,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

class _DireccionBadgeLabel extends StatelessWidget {
  const _DireccionBadgeLabel({required this.count, required this.badgeColor});

  final int count;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const Text('Órdenes en Dirección General');
    }
    final display = count > 99 ? '99+' : count.toString();
    final textColor =
        ThemeData.estimateBrightnessForColor(badgeColor) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Órdenes en Dirección General'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: badgeColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            display,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

class _PendingEtaBadgeLabel extends StatelessWidget {
  const _PendingEtaBadgeLabel({required this.count, required this.badgeColor});

  final int count;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const Text('Pendientes de fecha estimada');
    }
    final display = count > 99 ? '99+' : count.toString();
    final textColor =
        ThemeData.estimateBrightnessForColor(badgeColor) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Pendientes de fecha estimada'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: badgeColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            display,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

class _ContabilidadBadgeLabel extends StatelessWidget {
  const _ContabilidadBadgeLabel({required this.count, required this.badgeColor});

  final int count;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const Text('Contabilidad');
    }
    final display = count > 99 ? '99+' : count.toString();
    final textColor =
        ThemeData.estimateBrightnessForColor(badgeColor) == Brightness.dark
            ? Colors.white
            : Colors.black;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Contabilidad'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: badgeColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            display,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

class _AlmacenBadgeLabel extends StatelessWidget {
  const _AlmacenBadgeLabel({required this.count, required this.badgeColor});

  final int count;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const Text('Almac\u00e9n');
    }
    final display = count > 99 ? '99+' : count.toString();
    final textColor =
        ThemeData.estimateBrightnessForColor(badgeColor) == Brightness.dark
            ? Colors.white
            : Colors.black;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Almac\u00e9n'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: badgeColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            display,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

Color _badgeColorFor(Color background) {
  final brightness = ThemeData.estimateBrightnessForColor(background);
  return brightness == Brightness.dark ? Colors.white : Colors.black;
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

class _CotizacionesBadgeLabel extends StatelessWidget {
  const _CotizacionesBadgeLabel({
    required this.count,
    required this.badgeColor,
  });

  final int count;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const Text('Cotizaciones');
    }
    final display = count > 99 ? '99+' : count.toString();
    final textColor =
        ThemeData.estimateBrightnessForColor(badgeColor) == Brightness.dark
            ? Colors.white
            : Colors.black;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Cotizaciones'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: badgeColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            display,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
