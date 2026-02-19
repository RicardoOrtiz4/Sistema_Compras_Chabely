import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sistema_compras/features/orders/presentation/preview/pdf_open_helper.dart';

import 'package:sistema_compras/features/screens.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/features/partners/data/partner_repository.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authAsync = ref.watch(authStateChangesProvider);
  final authNotifier = GoRouterRefreshStream(ref.read(firebaseAuthProvider).authStateChanges());
  ref.onDispose(authNotifier.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: authNotifier,
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
        path: '/orders/cotizaciones/:orderId',
        name: 'cotizacionOrderReview',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          return CotizacionOrderReviewScreen(orderId: orderId);
        },
      ),
      GoRoute(
        path: '/orders/eta',
        name: 'pendingEtaOrders',
        builder: (context, state) => const PendingEtaOrdersScreen(),
      ),
      GoRoute(
        path: '/orders/direccion',
        name: 'direccionOrders',
        builder: (context, state) => const DireccionOrdersScreen(),
      ),
      GoRoute(
        path: '/orders/direccion/:orderId',
        name: 'direccionOrderReview',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          return DireccionOrderReviewScreen(orderId: orderId);
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
        path: '/orders/contabilidad',
        name: 'contabilidadOrders',
        builder: (context, state) => const ContabilidadOrdersScreen(),
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
        path: '/orders/almacen',
        name: 'almacenOrders',
        builder: (context, state) => const AlmacenOrdersScreen(),
      ),
      GoRoute(
        path: '/orders/almacen/:orderId',
        name: 'almacenOrderReview',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          return AlmacenOrderReviewScreen(orderId: orderId);
        },
      ),
      GoRoute(
        path: '/orders/:orderId/pdf',
        name: 'orderPdfView',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          return OrderPdfViewScreen(orderId: orderId);
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
      final isLoading = authAsync.isLoading;
      final loggedIn = authAsync.value != null;
      final loggingIn = state.matchedLocation == '/login';
      final atSplash = state.matchedLocation == '/splash';
      if (isLoading) {
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

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
