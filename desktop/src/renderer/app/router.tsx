import { Suspense, lazy, type ReactNode } from "react";
import { Navigate, createBrowserRouter } from "react-router-dom";
import { RouteErrorPage } from "@/app/route-error-page";
import { AppShell } from "@/shared/layout/app-shell";
import { useSessionStore } from "@/store/session-store";

const AdminUsersPage = lazy(async () => ({
  default: (await import("@/features/admin/admin-users-page")).AdminUsersPage,
}));
const LoginPage = lazy(async () => ({
  default: (await import("@/features/auth/login-page")).LoginPage,
}));
const DashboardPage = lazy(async () => ({
  default: (await import("@/features/dashboard/dashboard-page")).DashboardPage,
}));
const CreateOrderPage = lazy(async () => ({
  default: (await import("@/features/orders/create-order-page")).CreateOrderPage,
}));
const CreateOrderPreviewPage = lazy(async () => ({
  default: (await import("@/features/orders/create-order-preview-page")).CreateOrderPreviewPage,
}));
const OrderDetailPage = lazy(async () => ({
  default: (await import("@/features/orders/order-detail-page")).OrderDetailPage,
}));
const OrderHistoryPage = lazy(async () => ({
  default: (await import("@/features/orders/order-history-page")).OrderHistoryPage,
}));
const RequesterReceiptsPage = lazy(async () => ({
  default: (await import("@/features/orders/requester-receipts-page")).RequesterReceiptsPage,
}));
const OrderMonitoringPage = lazy(async () => ({
  default: (await import("@/features/orders/order-monitoring-page")).OrderMonitoringPage,
}));
const OrderPrintPage = lazy(async () => ({
  default: (await import("@/features/orders/order-print-page")).OrderPrintPage,
}));
const PurchasePacketsPage = lazy(async () => ({
  default: (await import("@/features/purchase-packets/purchase-packets-page")).PurchasePacketsPage,
}));
const PurchasePacketPreviewPage = lazy(async () => ({
  default: (await import("@/features/purchase-packets/purchase-packet-preview-page")).PurchasePacketPreviewPage,
}));
const PurchasePacketHistoryPage = lazy(async () => ({
  default: (await import("@/features/purchase-packets/purchase-packet-history-page")).PurchasePacketHistoryPage,
}));
const ReportsPage = lazy(async () => ({
  default: (await import("@/features/reports/reports-page")).ReportsPage,
}));
const AuthorizeOrdersPage = lazy(async () => ({
  default: (await import("@/features/workflow/authorize-orders-page")).AuthorizeOrdersPage,
}));
const ComprasPendingPage = lazy(async () => ({
  default: (await import("@/features/workflow/compras-pending-page")).ComprasPendingPage,
}));
const ComprasPendingPdfPage = lazy(async () => ({
  default: (await import("@/features/workflow/compras-pending-pdf-page")).ComprasPendingPdfPage,
}));
const ComprasPendingDataPage = lazy(async () => ({
  default: (await import("@/features/workflow/compras-pending-data-page")).ComprasPendingDataPage,
}));
const PacketFollowUpPage = lazy(async () => ({
  default: (await import("@/features/workflow/packet-follow-up-page")).PacketFollowUpPage,
}));

function SessionLoading() {
  const authUser = useSessionStore((state) => state.authUser);
  const signOut = useSessionStore((state) => state.signOut);

  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-4 bg-canvas px-6 text-slate-600">
      <div>Cargando sesion...</div>
      {authUser ? (
        <button
          type="button"
          onClick={() => {
            void signOut();
          }}
          className="rounded-full border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 transition hover:border-slate-400 hover:bg-slate-50"
        >
          Cerrar sesion
        </button>
      ) : null}
    </div>
  );
}

function RouteLoading() {
  return (
    <div className="rounded-[28px] border border-line bg-panel p-8 text-sm text-slate-600 shadow-shell">
      Cargando modulo...
    </div>
  );
}

function withSuspense(node: ReactNode) {
  return <Suspense fallback={<RouteLoading />}>{node}</Suspense>;
}

function ProtectedLayout() {
  const isAuthenticated = useSessionStore((state) => state.isAuthenticated);
  const isBootstrapping = useSessionStore((state) => state.isBootstrapping);

  if (isBootstrapping) {
    return <SessionLoading />;
  }

  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  return <AppShell />;
}

function ProtectedPage({ children }: { children: ReactNode }) {
  const isAuthenticated = useSessionStore((state) => state.isAuthenticated);
  const isBootstrapping = useSessionStore((state) => state.isBootstrapping);

  if (isBootstrapping) {
    return <SessionLoading />;
  }

  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  return <>{children}</>;
}

function RedirectIfSignedIn() {
  const isAuthenticated = useSessionStore((state) => state.isAuthenticated);
  const isBootstrapping = useSessionStore((state) => state.isBootstrapping);

  if (isBootstrapping) {
    return <SessionLoading />;
  }

  return isAuthenticated ? <Navigate to="/" replace /> : withSuspense(<LoginPage />);
}

export const appRouter = createBrowserRouter([
  {
    path: "/login",
    element: <RedirectIfSignedIn />,
    errorElement: <RouteErrorPage />,
  },
  {
    path: "/",
    element: <ProtectedLayout />,
    errorElement: <RouteErrorPage />,
    children: [
      {
        index: true,
        element: withSuspense(<DashboardPage />),
      },
      {
        path: "orders/create",
        element: withSuspense(<CreateOrderPage />),
      },
      {
        path: "workflow/authorize",
        element: withSuspense(<AuthorizeOrdersPage />),
      },
      {
        path: "workflow/compras",
        element: withSuspense(<ComprasPendingPage />),
      },
      {
        path: "workflow/compras/:orderId",
        element: withSuspense(<ComprasPendingPdfPage />),
      },
      {
        path: "workflow/compras/:orderId/data",
        element: withSuspense(<ComprasPendingDataPage />),
      },
      {
        path: "purchase-packets",
        element: withSuspense(<PurchasePacketsPage />),
      },
      {
        path: "purchase-packets/history",
        element: withSuspense(<PurchasePacketHistoryPage />),
      },
      {
        path: "purchase-packets/:packetId/pdf",
        element: withSuspense(<PurchasePacketPreviewPage />),
      },
      {
        path: "workflow/follow-up",
        element: withSuspense(<PacketFollowUpPage />),
      },
      {
        path: "orders/monitoring",
        element: withSuspense(<OrderMonitoringPage />),
      },
      {
        path: "orders/history",
        element: withSuspense(<OrderHistoryPage />),
      },
      {
        path: "orders/receipts",
        element: withSuspense(<RequesterReceiptsPage />),
      },
      {
        path: "orders/history/:orderId",
        element: withSuspense(<OrderDetailPage />),
      },
      {
        path: "orders/history/:orderId/print",
        element: withSuspense(<OrderPrintPage />),
      },
      {
        path: "reports",
        element: withSuspense(<ReportsPage />),
      },
      {
        path: "admin/users",
        element: withSuspense(<AdminUsersPage />),
      },
    ],
  },
  {
    path: "/orders/create/preview",
    element: <ProtectedPage>{withSuspense(<CreateOrderPreviewPage />)}</ProtectedPage>,
    errorElement: <RouteErrorPage />,
  },
  {
    path: "/purchase-packets/preview",
    element: <ProtectedPage>{withSuspense(<PurchasePacketPreviewPage />)}</ProtectedPage>,
    errorElement: <RouteErrorPage />,
  },
  {
    path: "*",
    element: <Navigate to="/" replace />,
    errorElement: <RouteErrorPage />,
  },
]);
