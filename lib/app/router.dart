import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sistema_compras/features/orders/presentation/preview/pdf_open_helper.dart';

import 'package:sistema_compras/core/navigation/app_shell_keys.dart';
import 'package:sistema_compras/features/screens.dart';
import 'package:sistema_compras/core/navigation_guard.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/features/partners/data/partner_repository.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();
  ref.onDispose(refreshNotifier.dispose);
  ref.listen<_RouterAuthRefreshState>(
    authStateChangesProvider.select(
      (auth) => _RouterAuthRefreshState(
        isLoading: auth.isLoading,
        isLoggedIn: auth.value != null,
      ),
    ),
    (_, __) {
      refreshNotifier.trigger();
    },
  );
  ref.listen<_RouterProfileRefreshState>(
    currentUserProfileProvider.select(
      (profile) => _RouterProfileRefreshState(
        isLoading: profile.isLoading,
        hasValue: profile.hasValue,
      ),
    ),
    (_, __) {
      refreshNotifier.trigger();
    },
  );
  final navObserver = NavigationUnlockObserver();

  return GoRouter(
    navigatorKey: appNavigatorKey,
    initialLocation: '/home',
    refreshListenable: refreshNotifier,
    observers: [navObserver, routeObserver],
    routes: [
      GoRoute(
        path: '/',
        redirect: (_, __) => '/home',
      ),
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/partners/suppliers',
        name: 'supplierManagement',
        builder: (context, state) => const PartnerManagementScreen(type: PartnerType.supplier),
      ),
      GoRoute(
        path: '/partners/clients',
        name: 'clientManagement',
        builder: (context, state) => const PartnerManagementScreen(type: PartnerType.client),
      ),
      GoRoute(
        path: '/admin/users',
        name: 'adminUsers',
        builder: (context, state) => const AdminUsersScreen(),
      ),
      GoRoute(
        path: '/orders/create',
        name: 'createOrder',
        builder: (context, state) {
          final draftId = state.uri.queryParameters['draftId'];
          final copyFromId = state.uri.queryParameters['copyFromId'];
          return CreateOrderScreen(
            draftId: draftId,
            copyFromId: copyFromId,
          );
        },
      ),
      GoRoute(
        path: '/orders/preview',
        name: 'orderPreview',
        builder: (context, state) => const OrderPdfPreviewScreen(),
      ),
      GoRoute(
        path: '/orders/history',
        name: 'orderHistory',
        builder: (context, state) => const OrderHistoryScreen(),
      ),
      GoRoute(
        path: '/orders/history/all',
        name: 'orderHistoryAll',
        builder: (context, state) => const OrderHistoryAllScreen(),
      ),
      GoRoute(
        path: '/reports',
        name: 'reports',
        builder: (context, state) => const ReportsScreen(),
      ),
      GoRoute(
        path: '/orders/pending',
        name: 'pendingOrders',
        builder: (context, state) => const PendingOrdersScreen(),
      ),
      GoRoute(
        path: '/orders/cotizaciones',
        name: 'cotizacionesOrders',
        builder: (context, state) => const CotizacionesOrdersScreen(),
      ),
      GoRoute(
        path: '/orders/cotizaciones/dashboard',
        name: 'cotizacionesDashboard',
        builder: (context, state) => const CotizacionesDashboardScreen(
          mode: CotizacionesDashboardMode.compras,
        ),
      ),
      GoRoute(
        path: '/orders/cotizaciones/:orderId',
        name: 'cotizacionOrderReview',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          final fromDashboard =
              state.uri.queryParameters['fromDashboard'] == '1';
          return CotizacionOrderReviewScreen(
            orderId: orderId,
            fromDashboard: fromDashboard,
          );
        },
      ),
      GoRoute(
        path: '/orders/eta',
        name: 'pendingEtaOrders',
        builder: (context, state) => const InProcessSupplierEtaScreen(),
      ),
      GoRoute(
        path: '/orders/in-process',
        name: 'userInProcessOrders',
        builder: (context, state) => const UserInProcessOrdersScreen(),
      ),
      GoRoute(
        path: '/orders/direccion',
        name: 'direccionOrders',
        builder: (context, state) => const DireccionOrdersScreen(),
      ),
      GoRoute(
        path: '/orders/direccion/dashboard',
        name: 'direccionDashboard',
        builder: (context, state) => CotizacionesDashboardScreen(
          mode: CotizacionesDashboardMode.direccion,
          onOpenOrder: (orderId) => guardedPdfPush(context, '/orders/$orderId/pdf'),
        ),
      ),
      GoRoute(
        path: '/orders/direccion/cotizacion/:quoteId',
        name: 'direccionQuoteReview',
        builder: (context, state) {
          final quoteId = state.pathParameters['quoteId']!;
          return DireccionQuoteReviewScreen(quoteId: quoteId);
        },
      ),
      GoRoute(
        path: '/orders/review/:orderId',
        name: 'pendingOrderReview',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          return PendingOrderReviewScreen(orderId: orderId);
        },
      ),
      GoRoute(
        path: '/orders/review/:orderId/approve',
        name: 'pendingOrderApprove',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          return PendingOrderApprovalScreen(orderId: orderId);
        },
      ),
      GoRoute(
        path: '/orders/rejected',
        name: 'rejectedOrders',
        builder: (context, state) => const RejectedOrdersScreen(),
      ),
      GoRoute(
        path: '/orders/rejected/all',
        name: 'globalActionMonitoring',
        builder: (context, state) => const GlobalActionMonitoringScreen(),
      ),
      GoRoute(
        path: '/orders/monitoring',
        name: 'orderMonitoring',
        builder: (context, state) => const OrderMonitoringScreen(),
      ),
      GoRoute(
        path: '/orders/contabilidad',
        name: 'contabilidadOrders',
        builder: (context, state) => const ContabilidadSupplierGroupsScreen(),
      ),
      GoRoute(
        path: '/orders/contabilidad/:orderId',
        name: 'contabilidadOrderReview',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          return ContabilidadOrderReviewScreen(orderId: orderId);
        },
      ),
      GoRoute(
        path: '/orders/:orderId/pdf',
        name: 'orderPdfView',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          final trackingView = state.uri.queryParameters['tracking'] == '1';
          return OrderPdfViewScreen(
            orderId: orderId,
            hideBuyerFields: trackingView,
          );
        },
      ),
      GoRoute(
        path: '/orders/:orderId',
        name: 'orderDetail',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          return OrderDetailScreen(orderId: orderId);
        },
      ),
    ],
    redirect: (context, state) {
      final authAsync = ref.read(authStateChangesProvider);
      final profileAsync = ref.read(currentUserProfileProvider);
      final isLoading = authAsync.isLoading;
      final loggedIn = authAsync.value != null;
      final profileLoading =
          loggedIn && profileAsync.isLoading && !profileAsync.hasValue;
      final loggingIn = state.matchedLocation == '/login';
      final atSplash = state.matchedLocation == '/splash';
      if (isLoading || profileLoading) {
        return atSplash ? null : '/splash';
      }
      if (!loggedIn) {
        return loggingIn ? null : '/login';
      }
      if (loggingIn || atSplash) {
        return '/home';
      }
      return null;
    },
  );
});

class _RouterRefreshNotifier extends ChangeNotifier {
  void trigger() {
    notifyListeners();
  }
}

class _RouterAuthRefreshState {
  const _RouterAuthRefreshState({
    required this.isLoading,
    required this.isLoggedIn,
  });

  final bool isLoading;
  final bool isLoggedIn;

  @override
  bool operator ==(Object other) {
    return other is _RouterAuthRefreshState &&
        other.isLoading == isLoading &&
        other.isLoggedIn == isLoggedIn;
  }

  @override
  int get hashCode => Object.hash(isLoading, isLoggedIn);
}

class _RouterProfileRefreshState {
  const _RouterProfileRefreshState({
    required this.isLoading,
    required this.hasValue,
  });

  final bool isLoading;
  final bool hasValue;

  @override
  bool operator ==(Object other) {
    return other is _RouterProfileRefreshState &&
        other.isLoading == isLoading &&
        other.hasValue == hasValue;
  }

  @override
  int get hashCode => Object.hash(isLoading, hasValue);
}
