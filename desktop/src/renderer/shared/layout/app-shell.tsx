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
  const location = useLocation();
  const navigate = useNavigate();
  const profile = useSessionStore((state) => state.profile);
  const signOut = useSessionStore((state) => state.signOut);
  const branding = useBrandingStore((state) => state.branding);
  const selectCompany = useBrandingStore((state) => state.selectCompany);

  const currentSection = useMemo(() => {
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
                  navigate("/");
                  return;
                }
                setDrawerOpen(true);
              }}
              title={showBackHome ? "Volver a Inicio" : "Abrir menú de navegación"}
            >
              {showBackHome ? <ArrowLeft size={22} /> : <Menu size={22} />}
            </Button>

            <div
              className="flex h-[76px] w-[76px] items-center justify-center overflow-hidden rounded-2xl shadow-sm"
              style={{ background: "#ffffff" }}
            >
              <img src={branding.logoPath} alt={branding.displayName} className="h-full w-full object-contain" />
            </div>

            <div>
              <p className="text-[24px] font-semibold leading-tight text-white sm:text-[28px]">
                {location.pathname === "/" ? "Inicio" : currentSection}
              </p>
              <p className="text-sm text-white/78">{profile?.name ?? "Sin sesión"} · {branding.displayName}</p>
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
                        <img src={company.logoPath} alt={company.displayName} className="h-8 w-8 object-contain" />
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
              <p className="text-sm font-semibold text-white">{profile?.name ?? "Sin sesión"}</p>
              <p className="text-xs text-white/72">{profile?.areaDisplay ?? "Sin perfil"}</p>
            </div>

            <Button
              type="button"
              variant="ghost"
              className="text-white hover:bg-white/10"
              onClick={async () => {
                await signOut();
                navigate("/login");
              }}
            >
              <LogOut size={16} className="mr-2" />
              Cerrar sesión
            </Button>
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
                  title="Cerrar menú de navegación"
                >
                  <Menu size={22} />
                </button>
                <img src={branding.logoPath} alt={branding.displayName} className="h-9 w-9 object-contain" />
                <div>
                  <p className="text-lg font-semibold" style={{ color: branding.primary }}>
                    Menú
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
                label="Historial de mis órdenes"
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
              <DrawerLink
                to="/profile"
                label="Perfil"
                icon={<User size={18} />}
                onClick={() => setDrawerOpen(false)}
                disabled
                color={branding.secondary}
              />
            </div>
          </aside>
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
  disabled = false,
  color,
}: {
  to: string;
  label: string;
  icon: ReactNode;
  onClick: () => void;
  disabled?: boolean;
  color: string;
}) {
  if (disabled) {
    return (
      <div className="mb-1 flex items-center justify-between rounded-2xl px-4 py-3 text-sm opacity-50" style={{ color }}>
        <span className="flex items-center gap-3">
          {icon}
          <span>{label}</span>
        </span>
        <ChevronRight size={16} />
      </div>
    );
  }

  return (
    <Link to={to} onClick={onClick} className="mb-1 flex items-center justify-between rounded-2xl px-4 py-3 text-sm" style={{ color }}>
      <span className="flex items-center gap-3">
        {icon}
        <span>{label}</span>
      </span>
      <ChevronRight size={16} />
    </Link>
  );
}
