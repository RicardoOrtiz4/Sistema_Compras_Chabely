import { useMemo } from "react";
import type { LucideIcon } from "lucide-react";
import {
  AlertTriangle,
  CheckCheck,
  CalendarClock,
  FileSpreadsheet,
  ReceiptText,
  ShieldCheck,
  ShoppingCart,
  TimerReset,
} from "lucide-react";
import { useNavigate } from "react-router-dom";
import { hasComprasAccess, hasDireccionApprovalAccess } from "@/lib/access-control";
import { useRtdbValue } from "@/lib/firebase/hooks";
import type { CompanyBranding } from "@/lib/branding";
import { emptyCounts, mapDashboardCounts } from "@/features/dashboard/dashboard-data";
import {
  isArrivalPendingConfirmation,
  isRequesterReceiptConfirmed,
  mapOrders,
} from "@/features/orders/orders-data";
import { useBrandingStore } from "@/store/branding-store";
import { useSessionStore } from "@/store/session-store";

type HomeBlock = {
  key: string;
  title: string;
  subtitle: string;
  icon: LucideIcon;
  to: string;
  background: string;
  foreground: string;
  count: number | null;
  enabled: boolean;
};

function hasAuthorizeOrdersAccess(profile: ReturnType<typeof useSessionStore.getState>["profile"]) {
  return hasComprasAccess(profile) || hasDireccionApprovalAccess(profile);
}

function hasEtaAccess(profile: ReturnType<typeof useSessionStore.getState>["profile"]) {
  return hasComprasAccess(profile) || hasDireccionApprovalAccess(profile);
}

function hasFacturasAccess(profile: ReturnType<typeof useSessionStore.getState>["profile"]) {
  return hasComprasAccess(profile) || hasDireccionApprovalAccess(profile);
}

function brandHomePalette(branding: CompanyBranding) {
  if (branding.id === "acerpro") {
    return {
      darkGray: "#4E5C69",
      mediumGray: "#667587",
      softGray: "#B7C4D1",
      lightGray: "#C7D3DE",
      panelGray: "#D4DDE6",
      royalBlue: "#1D4ED8",
      red: "#C62828",
      textStrong: "#0F172A",
    };
  }

  return {
    darkGray: "#333333",
    mediumGray: "#4A4A4A",
    softGray: "#C8C8C8",
    lightGray: "#D3D3D3",
    panelGray: "#DEDEDE",
    royalBlue: "#1D4ED8",
    red: "#C62828",
    textStrong: "#111111",
  };
}

function buildBlocks(
  branding: CompanyBranding,
  counts: ReturnType<typeof mapDashboardCounts>,
  profile: ReturnType<typeof useSessionStore.getState>["profile"],
  pendingReceiptCount: number,
): HomeBlock[] {
  const palette = brandHomePalette(branding);

  return [
    {
      key: "create",
      title: "Crear orden",
      subtitle: "Inicia una nueva solicitud",
      icon: ShoppingCart,
      to: "/orders/create",
      background: palette.darkGray,
      foreground: "#FFFFFF",
      count: null,
      enabled: true,
    },
    {
      key: "authorize",
      title: "Autorizar ordenes",
      subtitle: "Primera etapa despues de crear la orden",
      icon: ShieldCheck,
      to: "/workflow/authorize",
      background: palette.mediumGray,
      foreground: "#FFFFFF",
      count: counts.intakeReview,
      enabled: hasAuthorizeOrdersAccess(profile),
    },
    {
      key: "compras",
      title: "Compras",
      subtitle: "Pendientes de preparacion y captura operativa",
      icon: FileSpreadsheet,
      to: "/workflow/compras",
      background: palette.darkGray,
      foreground: "#FFFFFF",
      count: counts.sourcing,
      enabled: hasComprasAccess(profile),
    },
    {
      key: "direccion",
      title: "Direccion General",
      subtitle: "Aprobacion ejecutiva separada de Compras",
      icon: ShieldCheck,
      to: "/purchase-packets",
      background: palette.softGray,
      foreground: palette.textStrong,
      count: counts.pendingDireccion,
      enabled: hasDireccionApprovalAccess(profile),
    },
    {
      key: "eta",
      title: "Agregar fecha estimada",
      subtitle: "Registrar ETA despues de la aprobacion ejecutiva",
      icon: CalendarClock,
      to: "/workflow/follow-up",
      background: palette.lightGray,
      foreground: palette.textStrong,
      count: counts.pendingEta,
      enabled: hasEtaAccess(profile),
    },
    {
      key: "facturas",
      title: "Facturas y evidencias",
      subtitle: "Ultima etapa documental antes del cierre final",
      icon: ReceiptText,
      to: "/workflow/follow-up",
      background: palette.panelGray,
      foreground: palette.textStrong,
      count: counts.contabilidad,
      enabled: hasFacturasAccess(profile),
    },
    {
      key: "receipts",
      title: "Confirmar recibido",
      subtitle: "Cierre final por parte del solicitante",
      icon: CheckCheck,
      to: "/orders/receipts",
      background: palette.mediumGray,
      foreground: "#FFFFFF",
      count: pendingReceiptCount,
      enabled: true,
    },
    {
      key: "in-process",
      title: "Ordenes en proceso",
      subtitle: "Seguimiento y cierre final de tus solicitudes",
      icon: TimerReset,
      to: "/orders/history?mode=in-process",
      background: palette.royalBlue,
      foreground: "#FFFFFF",
      count: null,
      enabled: true,
    },
    {
      key: "rejected",
      title: "Ordenes rechazadas",
      subtitle: "Avisos de rechazo pendientes de enterado",
      icon: AlertTriangle,
      to: "/orders/history?mode=rejected",
      background: palette.red,
      foreground: "#FFFFFF",
      count: null,
      enabled: true,
    },
  ];
}

export function DashboardPage() {
  const navigate = useNavigate();
  const profile = useSessionStore((state) => state.profile);
  const branding = useBrandingStore((state) => state.branding);
  const countsState = useRtdbValue("purchaseOrderCounters", mapDashboardCounts, Boolean(profile));
  const ordersState = useRtdbValue("purchaseOrders", mapOrders, Boolean(profile));
  const counts = countsState.data ?? emptyCounts;
  const pendingReceiptCount = useMemo(
    () =>
      (ordersState.data ?? []).filter(
        (order) =>
          order.requesterId === profile?.id &&
          order.status === "eta" &&
          !isRequesterReceiptConfirmed(order) &&
          isArrivalPendingConfirmation(order),
      ).length,
    [ordersState.data, profile?.id],
  );

  const blocks = useMemo(
    () => buildBlocks(branding, counts, profile, pendingReceiptCount),
    [branding, counts, pendingReceiptCount, profile],
  );

  return (
    <div className="app-page">
      <section className="grid gap-4 md:grid-cols-2">
        {blocks.map((block) => {
          const Icon = block.icon;
          const isDark = block.foreground === "#FFFFFF";
          const borderColor = isDark ? "rgba(255,255,255,0.1)" : "rgba(15,23,42,0.08)";
          const chipBackground = isDark ? "rgba(255,255,255,0.12)" : "rgba(15,23,42,0.06)";
          const textMuted = isDark ? "rgba(255,255,255,0.84)" : "rgba(15,23,42,0.72)";

          return (
            <button
              key={block.key}
              type="button"
              onClick={() => block.enabled && navigate(block.to)}
              className="rounded-[24px] border p-5 text-left shadow-[0_18px_50px_rgba(15,23,42,0.08)] transition duration-200 hover:-translate-y-1 hover:shadow-[0_22px_60px_rgba(15,23,42,0.16)] active:translate-y-0 active:scale-[0.99] disabled:cursor-not-allowed disabled:opacity-60"
              disabled={!block.enabled}
              style={{
                borderColor,
                background: block.background,
                color: block.foreground,
              }}
            >
              <div className="flex items-start justify-between gap-4">
                <div
                  className="rounded-[18px] p-3"
                  style={{
                    background: chipBackground,
                    color: block.foreground,
                  }}
                >
                  <Icon size={21} />
                </div>
                {block.count != null ? (
                  <div
                    className="rounded-full px-3 py-1 text-xs font-semibold"
                    style={{
                      background: chipBackground,
                      color: block.foreground,
                    }}
                  >
                    {block.count}
                  </div>
                ) : null}
              </div>
              <h4 className="mt-5 text-[17px] font-semibold">{block.title}</h4>
              <p className="mt-2 text-sm leading-6" style={{ color: textMuted }}>
                {block.subtitle}
              </p>
              {!block.enabled ? (
                <div
                  className="mt-4 inline-flex rounded-full px-3 py-1 text-xs font-semibold"
                  style={{
                    background: chipBackground,
                    color: block.foreground,
                  }}
                >
                  Sin permiso
                </div>
              ) : null}
            </button>
          );
        })}
      </section>
    </div>
  );
}
