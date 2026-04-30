import { ClipboardList, LayoutDashboard } from "lucide-react";
import { useMemo } from "react";
import { useNavigate } from "react-router-dom";
import { hasComprasAccess } from "@/lib/access-control";
import { useRtdbValue } from "@/lib/firebase/hooks";
import { emptyCounts, mapDashboardCounts } from "@/features/dashboard/dashboard-data";
import { useSessionStore } from "@/store/session-store";

type HubCardProps = {
  title: string;
  subtitle: string;
  count: number;
  icon: typeof ClipboardList;
  onClick: () => void;
};

function HubCard({ title, subtitle, count, icon: Icon, onClick }: HubCardProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="w-full rounded-[24px] border border-slate-200 bg-white px-5 py-5 text-left shadow-[0_18px_50px_rgba(15,23,42,0.08)] transition duration-200 hover:-translate-y-1 hover:shadow-[0_22px_60px_rgba(15,23,42,0.14)]"
    >
      <div className="flex items-start justify-between gap-4">
        <div className="rounded-[18px] bg-slate-100 p-3 text-slate-900">
          <Icon size={22} />
        </div>
        <div className="rounded-full bg-blue-700 px-3 py-1 text-xs font-semibold text-white">
          {count}
        </div>
      </div>
      <p className="mt-5 text-[18px] font-semibold text-slate-900">{title}</p>
      <p className="mt-2 text-sm leading-6 text-slate-600">{subtitle}</p>
    </button>
  );
}

export function ComprasHubPage() {
  const navigate = useNavigate();
  const profile = useSessionStore((state) => state.profile);
  const canAccess = hasComprasAccess(profile);
  const countsState = useRtdbValue("purchaseOrders", mapDashboardCounts, canAccess);
  const counts = countsState.data ?? emptyCounts;

  const cards = useMemo(
    () => [
      {
        title: "Pendientes",
        subtitle: "Agregar datos faltantes antes de agrupar por proveedor.",
        count: counts.sourcing,
        icon: ClipboardList,
        to: "/workflow/compras/pendientes",
      },
      {
        title: "Dashboard",
        subtitle: "Agrupar items por proveedor y enviar a Direccion General.",
        count: counts.sourcingReadyToSend,
        icon: LayoutDashboard,
        to: "/workflow/compras/dashboard",
      },
    ],
    [counts.sourcing, counts.sourcingReadyToSend],
  );

  if (!canAccess) {
    return (
      <div className="rounded-[18px] border border-slate-200 bg-white px-5 py-4 text-sm text-slate-600">
        Tu perfil no tiene acceso a Compras.
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-5xl space-y-6 pb-4">
      <section className="space-y-4">
        {cards.map((card) => (
          <HubCard
            key={card.to}
            title={card.title}
            subtitle={card.subtitle}
            count={card.count}
            icon={card.icon}
            onClick={() => navigate(card.to)}
          />
        ))}
      </section>
    </div>
  );
}
