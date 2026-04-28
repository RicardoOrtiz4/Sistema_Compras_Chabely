import {
  BarChart3,
  FileClock,
  FileStack,
  FileText,
  LayoutDashboard,
  ShieldCheck,
  ShoppingCart,
  Users,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import type { AppUser } from "@/store/session-store";
import { hasAdminAccess, hasComprasAccess, hasDireccionApprovalAccess, hasReportsAccess } from "@/lib/access-control";

export type NavigationItem = {
  label: string;
  to: string;
  icon: LucideIcon;
  visible: (user: AppUser | null) => boolean;
};

export const navigationItems: NavigationItem[] = [
  {
    label: "Inicio",
    to: "/",
    icon: LayoutDashboard,
    visible: () => true,
  },
  {
    label: "Crear Orden",
    to: "/orders/create",
    icon: ShoppingCart,
    visible: () => true,
  },
  {
    label: "Autorizaciones",
    to: "/workflow/authorize",
    icon: ShieldCheck,
    visible: (user) => hasComprasAccess(user) || hasDireccionApprovalAccess(user),
  },
  {
    label: "Paquetes",
    to: "/purchase-packets",
    icon: FileStack,
    visible: (user) => hasComprasAccess(user) || hasDireccionApprovalAccess(user),
  },
  {
    label: "ETA / Facturas",
    to: "/workflow/follow-up",
    icon: FileText,
    visible: (user) => hasComprasAccess(user) || hasDireccionApprovalAccess(user),
  },
  {
    label: "Historial",
    to: "/orders/history",
    icon: FileClock,
    visible: () => true,
  },
  {
    label: "Reportes",
    to: "/reports",
    icon: BarChart3,
    visible: (user) => hasReportsAccess(user),
  },
  {
    label: "Usuarios",
    to: "/admin/users",
    icon: Users,
    visible: (user) => hasAdminAccess(user),
  },
];
