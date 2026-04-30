import { type ReactNode, useMemo, useState } from "react";
import { Link, Outlet, useLocation, useNavigate } from "react-router-dom";
import {
  ArrowLeft,
  BarChart3,
  Building2,
  ChevronRight,
  Clock3,
  LogOut,
  Menu,
  MonitorCog,
  User,
  Users,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { availableBrandings } from "@/lib/branding";
import {
  hasAdminAccess,
  hasComprasAccess,
  hasDireccionApprovalAccess,
  hasReportsAccess,
} from "@/lib/access-control";
import { navigationItems } from "@/shared/navigation/navigation";
import { useBrandingStore } from "@/store/branding-store";
import { useSessionStore } from "@/store/session-store";

export function AppShell() {
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [brandMenuOpen, setBrandMenuOpen] = useState(false);
  const [profileModalOpen, setProfileModalOpen] = useState(false);
  const location = useLocation();
  const navigate = useNavigate();
  const profile = useSessionStore((state) => state.profile);
  const signOut = useSessionStore((state) => state.signOut);
  const branding = useBrandingStore((state) => state.branding);
  const selectCompany = useBrandingStore((state) => state.selectCompany);

  const currentSection = useMemo(() => {
    if (location.pathname.startsWith("/workflow/compras")) {
      return "Compras";
    }
    const match = navigationItems.find((item) =>
      item.to === "/" ? location.pathname === "/" : location.pathname.startsWith(item.to),
    );
    return match?.label ?? "Sistema";
  }, [location.pathname]);

  const canSwitchCompany = profile?.role === "admin" || profile?.role === "administrador";
  const showBackHome = location.pathname !== "/";
  const canOpenMonitoring = hasComprasAccess(profile) || hasDireccionApprovalAccess(profile);
  const canOpenReports = hasReportsAccess(profile);
  const canOpenUsers = hasAdminAccess(profile);

  return (
    <div className="app-shell-bg min-h-screen text-slate-900">
      <header className="app-topbar sticky top-0 z-30">
        <div className="mx-auto flex max-w-[1120px] flex-col gap-4 px-4 py-4 lg:flex-row lg:items-center lg:justify-between">
          <div className="flex min-w-0 items-center gap-3">
            <Button
              type="button"
              variant="ghost"
              size="icon"
              className="text-white hover:bg-white/10"
              onClick={() => {
                if (showBackHome) {
                  if (location.pathname.startsWith("/workflow/compras/")) {
                    navigate("/workflow/compras");
                    return;
                  }
                  navigate("/");
                  return;
                }
                setDrawerOpen(true);
              }}
              title={showBackHome ? "Volver a Inicio" : "Abrir menu de navegacion"}
            >
              {showBackHome ? <ArrowLeft size={22} /> : <Menu size={22} />}
            </Button>

            <div
              className="flex h-[76px] w-[76px] items-center justify-center overflow-hidden rounded-2xl shadow-sm"
              style={{ background: "#ffffff" }}
            >
              <img
                src={branding.logoPath}
                alt={branding.displayName}
                className="h-full w-full object-contain"
              />
            </div>

            <div>
              <p className="text-[24px] font-semibold leading-tight text-white sm:text-[28px]">
                {location.pathname === "/" ? "Inicio" : currentSection}
              </p>
              <p className="text-sm text-white/78">
                {profile?.name ?? "Sin sesion"} | {branding.displayName}
              </p>
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-3 lg:justify-end">
            {canSwitchCompany ? (
              <div className="relative hidden md:block">
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  className="text-white hover:bg-white/10"
                  title="Cambiar empresa"
                  onClick={() => setBrandMenuOpen((current) => !current)}
                >
                  <Building2 size={18} />
                </Button>
                {brandMenuOpen ? (
                  <div
                    className="absolute right-0 top-[calc(100%+8px)] w-56 rounded-2xl p-2 shadow-lg"
                    style={{
                      background: branding.surface,
                      border: "1px solid color-mix(in srgb, var(--app-primary) 12%, white)",
                    }}
                  >
                    {availableBrandings.map((company) => (
                      <button
                        key={company.id}
                        type="button"
                        className="flex w-full items-center gap-3 rounded-2xl px-3 py-3 text-left text-sm"
                        style={{
                          background:
                            company.id === branding.id
                              ? "color-mix(in srgb, var(--app-primary) 10%, white)"
                              : "transparent",
                          color: branding.primary,
                        }}
                        onClick={() => {
                          selectCompany(company.id, profile?.email);
                          setBrandMenuOpen(false);
                        }}
                      >
                        <img
                          src={company.logoPath}
                          alt={company.displayName}
                          className="h-8 w-8 object-contain"
                        />
                        <span>{company.displayName}</span>
                      </button>
                    ))}
                  </div>
                ) : null}
              </div>
            ) : null}

            {canOpenMonitoring ? (
              <Button
                type="button"
                variant="ghost"
                size="icon"
                className="text-white hover:bg-white/10"
                title="Monitoreo"
                onClick={() => navigate("/orders/monitoring")}
              >
                <MonitorCog size={18} />
              </Button>
            ) : null}

            <div
              className="hidden rounded-2xl px-4 py-2 text-right md:block"
              style={{
                border: "1px solid color-mix(in srgb, white 12%, transparent)",
                background: "color-mix(in srgb, white 12%, transparent)",
              }}
            >
              <p className="text-sm font-semibold text-white">{profile?.name ?? "Sin sesion"}</p>
              <p className="text-xs text-white/72">{profile?.areaDisplay ?? "Sin perfil"}</p>
            </div>
          </div>
        </div>
      </header>

      {drawerOpen ? (
        <div className="fixed inset-0 z-40 bg-slate-950/30" onClick={() => setDrawerOpen(false)}>
          <aside
            className="h-full w-[340px] border-r"
            style={{
              borderColor: "color-mix(in srgb, var(--app-primary) 12%, white)",
              background: branding.surface,
            }}
            onClick={(event) => event.stopPropagation()}
          >
            <div
              className="border-b px-4 py-4"
              style={{ borderColor: "color-mix(in srgb, var(--app-primary) 12%, white)" }}
            >
              <div className="flex items-center gap-3">
                <button
                  type="button"
                  className="inline-flex h-11 w-11 items-center justify-center rounded-full"
                  style={{ color: branding.secondary }}
                  onClick={() => setDrawerOpen(false)}
                  title="Cerrar menu de navegacion"
                >
                  <Menu size={22} />
                </button>
                <img
                  src={branding.logoPath}
                  alt={branding.displayName}
                  className="h-9 w-9 object-contain"
                />
                <div>
                  <p className="text-lg font-semibold" style={{ color: branding.primary }}>
                    Menu
                  </p>
                  <p className="text-xs" style={{ color: branding.secondary }}>
                    {branding.displayName}
                  </p>
                </div>
              </div>
            </div>

            <div className="px-3 py-3">
              <MenuNavLink
                to="/"
                label="Inicio"
                onClick={() => setDrawerOpen(false)}
                active={location.pathname === "/"}
                brandingPrimary={branding.primary}
                color={branding.secondary}
              />
              <DrawerLink
                to="/orders/history"
                label="Historial de mis ordenes"
                icon={<Clock3 size={18} />}
                onClick={() => setDrawerOpen(false)}
                color={branding.secondary}
              />
              {canOpenReports ? (
                <DrawerLink
                  to="/reports"
                  label="Reportes"
                  icon={<BarChart3 size={18} />}
                  onClick={() => setDrawerOpen(false)}
                  color={branding.secondary}
                />
              ) : null}
              {canOpenUsers ? (
                <DrawerLink
                  to="/admin/users"
                  label="Administrar usuarios"
                  icon={<Users size={18} />}
                  onClick={() => setDrawerOpen(false)}
                  color={branding.secondary}
                />
              ) : null}
              <DrawerAction
                label="Perfil"
                icon={<User size={18} />}
                onClick={() => {
                  setDrawerOpen(false);
                  setProfileModalOpen(true);
                }}
                color={branding.secondary}
              />
            </div>
          </aside>
        </div>
      ) : null}

      {profileModalOpen ? (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/40 px-4"
          onClick={() => setProfileModalOpen(false)}
        >
          <div
            className="w-full max-w-[460px] rounded-[28px] border bg-white p-6 shadow-[0_30px_80px_rgba(15,23,42,0.24)]"
            style={{ borderColor: "color-mix(in srgb, var(--app-primary) 12%, white)" }}
            onClick={(event) => event.stopPropagation()}
          >
            <div className="flex items-start gap-4">
              <div
                className="flex h-14 w-14 items-center justify-center rounded-full"
                style={{
                  background: "color-mix(in srgb, var(--app-primary) 10%, white)",
                  color: branding.primary,
                }}
              >
                <User size={22} />
              </div>
              <div className="min-w-0 flex-1">
                <p className="text-[20px] font-semibold text-slate-900">Perfil</p>
                <p className="mt-1 text-sm text-slate-500">Informacion de la sesion actual</p>
              </div>
            </div>

            <div className="mt-6 space-y-4 rounded-[24px] bg-slate-50 px-5 py-5">
              <ProfileRow label="Nombre" value={profile?.name ?? "Sin sesion"} />
              <ProfileRow label="Area" value={profile?.areaDisplay ?? "Sin perfil"} />
              <ProfileRow label="Correo" value={profile?.email ?? "Sin correo"} breakAll />
            </div>

            <div className="mt-6 flex flex-col gap-3 sm:flex-row sm:justify-end">
              <button
                type="button"
                onClick={() => setProfileModalOpen(false)}
                className="rounded-2xl border border-slate-300 bg-white px-4 py-2.5 text-sm font-medium text-slate-700"
              >
                Cerrar
              </button>
              <button
                type="button"
                onClick={async () => {
                  setProfileModalOpen(false);
                  await signOut();
                  navigate("/login");
                }}
                className="inline-flex items-center justify-center rounded-2xl border border-slate-900 bg-slate-900 px-4 py-2.5 text-sm font-medium text-white"
              >
                <LogOut size={16} className="mr-2" />
                Cerrar sesion
              </button>
            </div>
          </div>
        </div>
      ) : null}

      <main className="mx-auto max-w-[1120px] px-4 py-4">
        <Outlet />
      </main>
    </div>
  );
}

function MenuNavLink({
  to,
  label,
  onClick,
  active,
  brandingPrimary,
  color,
}: {
  to: string;
  label: string;
  onClick: () => void;
  active: boolean;
  brandingPrimary: string;
  color: string;
}) {
  return (
    <Link
      to={to}
      onClick={onClick}
      className="mb-1 flex items-center justify-between rounded-2xl px-4 py-3 text-sm transition"
      style={{
        background: active ? brandingPrimary : "transparent",
        color: active ? "#ffffff" : color,
      }}
    >
      <span>{label}</span>
    </Link>
  );
}

function DrawerLink({
  to,
  label,
  icon,
  onClick,
  color,
}: {
  to: string;
  label: string;
  icon: ReactNode;
  onClick: () => void;
  color: string;
}) {
  return (
    <Link
      to={to}
      onClick={onClick}
      className="mb-1 flex items-center justify-between rounded-2xl px-4 py-3 text-sm"
      style={{ color }}
    >
      <span className="flex items-center gap-3">
        {icon}
        <span>{label}</span>
      </span>
      <ChevronRight size={16} />
    </Link>
  );
}

function DrawerAction({
  label,
  icon,
  onClick,
  color,
}: {
  label: string;
  icon: ReactNode;
  onClick: () => void;
  color: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="mb-1 flex w-full items-center justify-between rounded-2xl px-4 py-3 text-sm"
      style={{ color }}
    >
      <span className="flex items-center gap-3">
        {icon}
        <span>{label}</span>
      </span>
      <ChevronRight size={16} />
    </button>
  );
}

function ProfileRow({
  label,
  value,
  breakAll = false,
}: {
  label: string;
  value: string;
  breakAll?: boolean;
}) {
  return (
    <div>
      <p className="text-xs font-medium uppercase tracking-[0.18em] text-slate-500">{label}</p>
      <p className={["mt-1 text-sm font-medium text-slate-900", breakAll ? "break-all" : ""].join(" ")}>
        {value}
      </p>
    </div>
  );
}
