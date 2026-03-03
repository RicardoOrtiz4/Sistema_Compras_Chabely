import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sistema_compras/features/orders/presentation/preview/pdf_open_helper.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/features/screens.dart';
import 'package:sistema_compras/core/navigation_guard.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/core/widgets/preload_gate.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import '../features/orders/presentation/almacen/almacen_orders_screen.dart';
import 'package:sistema_compras/features/partners/data/partner_repository.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();
  ref.onDispose(refreshNotifier.dispose);
  ref.listen(authStateChangesProvider, (_, __) {
    refreshNotifier.trigger();
  });
  ref.listen(currentUserProfileProvider, (_, __) {
    refreshNotifier.trigger();
  });
  final navObserver = NavigationUnlockObserver();

  return GoRouter(
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
        builder: (context, state) => PreloadGate(
          loaders: (ref) => [
            ref.watch(currentUserProfileProvider),
            ref.watch(userOrdersPagedProvider(defaultOrderPageSize)),
          ],
          child: const OrderHistoryScreen(),
        ),
      ),
      GoRoute(
        path: '/orders/history/all',
        name: 'orderHistoryAll',
        builder: (context, state) => PreloadGate(
          loaders: (ref) => [
            ref.watch(currentUserProfileProvider),
            ref.watch(allOrdersPagedProvider(defaultOrderPageSize)),
          ],
          child: const OrderHistoryAllScreen(),
        ),
      ),
      GoRoute(
        path: '/reports',
        name: 'reports',
        builder: (context, state) => PreloadGate(
          loaders: (ref) => [
            ref.watch(currentUserProfileProvider),
            ref.watch(allOrdersProvider),
          ],
          child: const ReportsScreen(),
        ),
      ),
      GoRoute(
        path: '/orders/pending',
        name: 'pendingOrders',
        builder: (context, state) => PreloadGate(
          loaders: (ref) => [
            ref.watch(currentUserProfileProvider),
            ref.watch(pendingComprasOrdersPagedProvider(defaultOrderPageSize)),
          ],
          child: const PendingOrdersScreen(),
        ),
      ),
      GoRoute(
        path: '/orders/cotizaciones',
        name: 'cotizacionesOrders',
        builder: (context, state) => PreloadGate(
          loaders: (ref) => [
            ref.watch(currentUserProfileProvider),
            ref.watch(cotizacionesOrdersPagedProvider(defaultOrderPageSize)),
          ],
          child: const CotizacionesOrdersScreen(),
        ),
      ),
      GoRoute(
        path: '/orders/cotizaciones/dashboard',
        name: 'cotizacionesDashboard',
        builder: (context, state) => PreloadGate(
          loaders: (ref) => [
            ref.watch(currentUserProfileProvider),
            ref.watch(cotizacionesOrdersPagedProvider(defaultOrderPageSize)),
          ],
          child: const CotizacionesOrdersScreen(initialTab: 1),
        ),
      ),
      GoRoute(
        path: '/orders/cotizaciones/:orderId',
        name: 'cotizacionOrderReview',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          return PreloadGate(
            loaders: (ref) => [
              ref.watch(orderByIdStreamProvider(orderId)),
            ],
            child: CotizacionOrderReviewScreen(orderId: orderId),
          );
        },
      ),
      GoRoute(
        path: '/orders/eta',
        name: 'pendingEtaOrders',
        builder: (context, state) => PreloadGate(
          loaders: (ref) => [
            ref.watch(currentUserProfileProvider),
            ref.watch(pendingEtaOrdersPagedProvider(defaultOrderPageSize)),
          ],
          child: const PendingEtaOrdersScreen(),
        ),
      ),
      GoRoute(
        path: '/orders/direccion',
        name: 'direccionOrders',
        builder: (context, state) => PreloadGate(
          loaders: (ref) => [
            ref.watch(currentUserProfileProvider),
            ref.watch(pendingDireccionOrdersPagedProvider(defaultOrderPageSize)),
          ],
          child: const DireccionOrdersScreen(),
        ),
      ),
      GoRoute(
        path: '/orders/direccion/dashboard',
        name: 'direccionDashboard',
        builder: (context, state) => const CotizacionesDashboardScreen(
          mode: CotizacionesDashboardMode.direccion,
        ),
      ),
      GoRoute(
        path: '/orders/direccion/:orderId',
        name: 'direccionOrderReview',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          return PreloadGate(
            loaders: (ref) => [
              ref.watch(orderByIdStreamProvider(orderId)),
              ref.watch(orderEventsProvider(orderId)),
            ],
            child: DireccionOrderReviewScreen(orderId: orderId),
          );
        },
      ),
      GoRoute(
        path: '/orders/review/:orderId',
        name: 'pendingOrderReview',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          return PreloadGate(
            loaders: (ref) => [
              ref.watch(orderByIdStreamProvider(orderId)),
              ref.watch(orderEventsProvider(orderId)),
            ],
            child: PendingOrderReviewScreen(orderId: orderId),
          );
        },
      ),
      GoRoute(
        path: '/orders/review/:orderId/approve',
        name: 'pendingOrderApprove',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          return PreloadGate(
            loaders: (ref) => [
              ref.watch(orderByIdStreamProvider(orderId)),
            ],
            child: PendingOrderApprovalScreen(orderId: orderId),
          );
        },
      ),
      GoRoute(
        path: '/orders/rejected',
        name: 'rejectedOrders',
        builder: (context, state) => PreloadGate(
          loaders: (ref) => [
            ref.watch(currentUserProfileProvider),
            ref.watch(rejectedOrdersPagedProvider(defaultOrderPageSize)),
          ],
          child: const RejectedOrdersScreen(),
        ),
      ),
      GoRoute(
        path: '/orders/contabilidad',
        name: 'contabilidadOrders',
        builder: (context, state) => PreloadGate(
          loaders: (ref) => [
            ref.watch(currentUserProfileProvider),
            ref.watch(contabilidadOrdersPagedProvider(defaultOrderPageSize)),
          ],
          child: const ContabilidadOrdersScreen(),
        ),
      ),
      GoRoute(
        path: '/orders/contabilidad/:orderId',
        name: 'contabilidadOrderReview',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          return PreloadGate(
            loaders: (ref) => [
              ref.watch(orderByIdStreamProvider(orderId)),
            ],
            child: ContabilidadOrderReviewScreen(orderId: orderId),
          );
        },
      ),
      GoRoute(
        path: '/orders/almacen',
        name: 'almacenOrders',
        builder: (context, state) => PreloadGate(
          loaders: (ref) => [
            ref.watch(currentUserProfileProvider),
            ref.watch(almacenOrdersPagedProvider(defaultOrderPageSize)),
          ],
          child: const AlmacenOrdersScreen(),
        ),
      ),
      GoRoute(
        path: '/orders/almacen/:orderId',
        name: 'almacenOrderReview',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          return PreloadGate(
            loaders: (ref) => [
              ref.watch(orderByIdStreamProvider(orderId)),
            ],
            child: AlmacenOrderReviewScreen(orderId: orderId),
          );
        },
      ),
      GoRoute(
        path: '/orders/:orderId/pdf',
        name: 'orderPdfView',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          return PreloadGate(
            loaders: (ref) => [
              ref.watch(orderByIdStreamProvider(orderId)),
            ],
            child: OrderPdfViewScreen(orderId: orderId),
          );
        },
      ),
      GoRoute(
        path: '/orders/:orderId',
        name: 'orderDetail',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          return PreloadGate(
            loaders: (ref) => [
              ref.watch(orderByIdStreamProvider(orderId)),
            ],
            child: OrderDetailScreen(orderId: orderId),
          );
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
