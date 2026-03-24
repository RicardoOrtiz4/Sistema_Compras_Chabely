import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

enum HomeNotificationTone { info, warning, critical }

class HomeNotificationItem {
  const HomeNotificationItem({
    required this.title,
    required this.message,
    required this.route,
    required this.count,
    required this.icon,
    required this.tone,
  });

  final String title;
  final String message;
  final String route;
  final int count;
  final IconData icon;
  final HomeNotificationTone tone;
}

final homeNotificationsProvider =
    Provider.autoDispose<List<HomeNotificationItem>>((ref) {
      final user = ref.watch(currentUserProfileProvider).value;
      if (user == null) return const <HomeNotificationItem>[];

      final isAdmin = isAdminRole(user.role);
      final isCompras = isComprasLabel(user.areaDisplay);
      final isDireccionGeneral = isDireccionGeneralLabel(user.areaDisplay);
      final isContabilidad = isContabilidadLabel(user.areaDisplay);

      final items = <HomeNotificationItem>[];

      void addNotification({
        required int? count,
        required String title,
        required String message,
        required String route,
        required IconData icon,
        required HomeNotificationTone tone,
      }) {
        if (count == null || count <= 0) return;
        items.add(
          HomeNotificationItem(
            title: title,
            message: message,
            route: route,
            count: count,
            icon: icon,
            tone: tone,
          ),
        );
      }

      if (isAdmin || isCompras) {
        final operationalOrders = ref.watch(operationalOrdersProvider).valueOrNull;
        addNotification(
          count: _ordersWithPendingArrivals(operationalOrders),
          title: 'Llegadas por registrar',
          message: 'Hay ordenes con items en transito que ya requieren seguimiento de llegada.',
          route: '/orders/eta',
          icon: Icons.inventory_outlined,
          tone: HomeNotificationTone.info,
        );
        addNotification(
          count: _lateArrivalOrders(operationalOrders),
          title: 'Entregas atrasadas',
          message: 'Hay ordenes con items vencidos frente a su fecha estimada.',
          route: '/orders/eta',
          icon: Icons.warning_amber_outlined,
          tone: HomeNotificationTone.critical,
        );
        addNotification(
          count: ref.watch(pendingComprasCountProvider).valueOrNull,
          title: 'Autorizar órdenes',
          message: 'Tienes órdenes nuevas o regresadas pendientes de revisión.',
          route: '/orders/pending',
          icon: Icons.fact_check_outlined,
          tone: HomeNotificationTone.critical,
        );
        addNotification(
          count: ref.watch(cotizacionesModuleCountProvider).valueOrNull,
          title: 'Compras pendientes',
          message: 'Hay órdenes o cotizaciones que todavía necesitan trabajo de Compras.',
          route: '/orders/cotizaciones',
          icon: Icons.request_quote_outlined,
          tone: HomeNotificationTone.warning,
        );
        addNotification(
          count: ref.watch(pendingEtaCountProvider).valueOrNull,
          title: 'Fechas de llegada pendientes',
          message: 'Hay órdenes aprobadas que necesitan fecha estimada de entrega.',
          route: '/orders/eta',
          icon: Icons.assignment_turned_in_outlined,
          tone: HomeNotificationTone.warning,
        );
        addNotification(
          count: ref.watch(globalActionMonitoringCountProvider).valueOrNull,
          title: 'Seguimiento pendiente',
          message: 'Hay rechazos o entregas por confirmar que requieren atención.',
          route: '/orders/rejected/all',
          icon: Icons.report_gmailerrorred_outlined,
          tone: HomeNotificationTone.info,
        );
      }

      if (isAdmin || isDireccionGeneral) {
        addNotification(
          count: ref.watch(pendingDireccionBundleCountProvider).valueOrNull,
          title: 'Autorizaciones de Dirección General',
          message: 'Hay compras esperando autorización de pago.',
          route: '/orders/direccion',
          icon: Icons.approval_outlined,
          tone: HomeNotificationTone.critical,
        );
      }

      if (isAdmin || isContabilidad) {
        addNotification(
          count: ref.watch(contabilidadCountProvider).valueOrNull,
          title: 'Contabilidad pendiente',
          message: 'Hay órdenes esperando registro contable y cierre.',
          route: '/orders/contabilidad',
          icon: Icons.receipt_long_outlined,
          tone: HomeNotificationTone.warning,
        );
      }

      addNotification(
        count: ref.watch(rejectedCountProvider).valueOrNull,
        title: 'Órdenes rechazadas',
        message: 'Tienes órdenes que requieren corrección para continuar.',
        route: '/orders/rejected',
        icon: Icons.report_problem_outlined,
        tone: HomeNotificationTone.critical,
      );
      addNotification(
        count: ref.watch(userInProcessOrdersCountProvider).valueOrNull,
        title: 'Órdenes en proceso',
        message: 'Tus solicitudes siguen avanzando y conviene revisarlas.',
        route: '/orders/in-process',
        icon: Icons.track_changes_outlined,
        tone: HomeNotificationTone.info,
      );

      final userOrders = ref.watch(userOrdersProvider).valueOrNull;
      addNotification(
        count: _ordersWithArrivedItems(userOrders),
        title: 'Items ya llegaron',
        message: 'Ya tienes items registrados como llegados y conviene revisar que falta.',
        route: '/orders/in-process',
        icon: Icons.mark_email_read_outlined,
        tone: HomeNotificationTone.critical,
      );
      addNotification(
        count: _lateArrivalOrders(userOrders),
        title: 'Items pendientes y vencidos',
        message: 'Hay items tuyos que siguen pendientes y ya excedieron la fecha estimada.',
        route: '/orders/in-process',
        icon: Icons.pending_actions_outlined,
        tone: HomeNotificationTone.warning,
      );

      return items;
    });

final homeNotificationsCountProvider = Provider.autoDispose<int>((ref) {
  final notifications = ref.watch(homeNotificationsProvider);
  var total = 0;
  for (final item in notifications) {
    total += item.count;
  }
  return total;
});

Color notificationToneColor(ColorScheme scheme, HomeNotificationTone tone) {
  switch (tone) {
    case HomeNotificationTone.info:
      return scheme.primary;
    case HomeNotificationTone.warning:
      return scheme.tertiary;
    case HomeNotificationTone.critical:
      return scheme.error;
  }
}

String notificationContactEmailLabel(AppUser user) {
  final contactEmail = (user.contactEmail ?? '').trim();
  if (contactEmail.isEmpty) {
    return 'No has registrado correo de contacto.';
  }
  return 'Correo de contacto: $contactEmail';
}

int? _ordersWithPendingArrivals(List<PurchaseOrder>? orders) {
  if (orders == null) return null;
  return orders.where((order) {
    return order.items.any(
      (item) => item.deliveryEtaDate != null && !item.isArrivalRegistered,
    );
  }).length;
}

int? _ordersWithArrivedItems(List<PurchaseOrder>? orders) {
  if (orders == null) return null;
  return orders.where(hasAnyArrivedItems).length;
}

int? _lateArrivalOrders(List<PurchaseOrder>? orders) {
  if (orders == null) return null;
  return orders.where(_hasLatePendingArrival).length;
}

bool _hasLatePendingArrival(PurchaseOrder order) {
  return order.items.any((item) {
    if (item.isArrivalRegistered || item.deliveryEtaDate == null) return false;
    return itemPendingArrivalLabel(item).startsWith('Atraso actual');
  });
}
