import { FormEvent, useMemo, useState } from "react";
import { hasAdminAccess } from "@/lib/access-control";
import { useRtdbValue } from "@/lib/firebase/hooks";
import { useSessionStore } from "@/store/session-store";
import { StatusBadge } from "@/shared/ui/status-badge";
import { adminAreaId, mapAdminUsers, mergeAreaOptions, roleLabels } from "@/features/admin/admin-users-data";
import { updateAdminUserProfile } from "@/features/admin/admin-users-service";

type EditableUser = {
  id: string;
  name: string;
  role: string;
  areaId: string;
  areaName: string;
};

export function AdminUsersPage() {
  const profile = useSessionStore((state) => state.profile);
  const canManage = hasAdminAccess(profile);
  const usersState = useRtdbValue("users", mapAdminUsers, canManage);
  const [editingUser, setEditingUser] = useState<EditableUser | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  const users = usersState.data ?? [];
  const activeUsers = useMemo(() => users.filter((user) => user.isActive), [users]);
  const inactiveUsers = users.length - activeUsers.length;
  const areaOptions = useMemo(() => {
    if (!editingUser) return [];
    return mergeAreaOptions(editingUser.areaId, editingUser.areaName || editingUser.areaId);
  }, [editingUser]);

  if (!canManage) {
    return <div className="app-card text-sm text-slate-600">No tienes permisos para ver esta pantalla.</div>;
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!editingUser) return;
    if (!editingUser.name.trim()) {
      setSaveError("Ingresa un nombre.");
      return;
    }
    if (!editingUser.areaId.trim()) {
      setSaveError("Selecciona un area.");
      return;
    }

    setIsSaving(true);
    setSaveError(null);
    try {
      await updateAdminUserProfile(editingUser);
      setEditingUser(null);
    } catch (error) {
      setSaveError(error instanceof Error ? error.message : "No se pudo guardar el usuario.");
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <div className="app-page">
      <section className="app-card">
        <div className="mb-5 flex gap-2">
          <StatusBadge label={`${activeUsers.length} activo(s)`} tone="info" />
          {inactiveUsers > 0 ? <StatusBadge label={`${inactiveUsers} inactivo(s)`} tone="warning" /> : null}
        </div>
        {usersState.isLoading ? (
          <div className="text-sm text-slate-500">Cargando usuarios...</div>
        ) : usersState.error ? (
          <div className="text-sm text-red-600">No se pudieron cargar los usuarios: {usersState.error}</div>
        ) : !users.length ? (
          <div className="text-sm text-slate-500">
            No hay usuarios registrados. Las altas y bajas se hacen manualmente en Firebase Console.
          </div>
        ) : (
          <div className="space-y-3">
            {users.map((user) => (
              <article key={user.id} className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
                <div className="flex flex-wrap items-start justify-between gap-4">
                  <div>
                    <p className="text-sm font-semibold text-slate-900">{user.name}</p>
                    <p className="mt-1 text-xs text-slate-500">{user.email || "Sin correo"}</p>
                    <p className="mt-2 text-sm text-slate-600">
                      Rol: {roleLabels[user.role.toLowerCase()] ?? user.role} · Area: {user.areaDisplay}
                    </p>
                  </div>
                  <div className="flex items-center gap-3">
                    <StatusBadge label={user.isActive ? "Activo" : "Inactivo"} tone={user.isActive ? "success" : "warning"} />
                    <button
                      type="button"
                      className="app-button-secondary"
                      onClick={() => {
                        setSaveError(null);
                        setEditingUser({
                          id: user.id,
                          name: user.name,
                          role: user.role.toLowerCase() === "admin" ? "administrador" : user.role.toLowerCase(),
                          areaId: user.areaId || user.areaDisplay,
                          areaName: user.areaName || user.areaDisplay,
                        });
                      }}
                    >
                      Editar
                    </button>
                  </div>
                </div>
              </article>
            ))}
          </div>
        )}
      </section>

      {editingUser ? (
        <div className="fixed inset-0 z-40 flex items-center justify-center bg-slate-950/40 px-6 py-10">
          <div className="w-full max-w-xl rounded-[24px] border border-slate-200 bg-white p-6 shadow-xl">
            <p className="app-kicker">Edicion interna</p>
            <h4 className="mt-1 text-xl font-semibold text-slate-900">Editar usuario</h4>
            <p className="mt-2 text-sm text-slate-500">{editingUser.id}</p>

            <form className="mt-6 space-y-5" onSubmit={handleSubmit}>
              <label className="block">
                <span className="mb-2 block text-sm font-medium text-slate-700">Nombre</span>
                <input
                  value={editingUser.name}
                  onChange={(event) => {
                    setSaveError(null);
                    setEditingUser((current) => (current ? { ...current, name: event.target.value } : current));
                  }}
                  className="app-input"
                />
              </label>

              <label className="block">
                <span className="mb-2 block text-sm font-medium text-slate-700">Rol</span>
                <select
                  value={editingUser.role}
                  onChange={(event) => {
                    const nextRole = event.target.value;
                    setSaveError(null);
                    setEditingUser((current) =>
                      current
                        ? {
                            ...current,
                            role: nextRole,
                            areaId: nextRole === "administrador" ? adminAreaId : current.areaId,
                            areaName: nextRole === "administrador" ? adminAreaId : current.areaName,
                          }
                        : current,
                    );
                  }}
                  className="app-select w-full"
                >
                  <option value="usuario">Usuario</option>
                  <option value="administrador">Administrador</option>
                </select>
              </label>

              <label className="block">
                <span className="mb-2 block text-sm font-medium text-slate-700">Area</span>
                <select
                  value={editingUser.role === "administrador" ? adminAreaId : editingUser.areaId}
                  disabled={editingUser.role === "administrador"}
                  onChange={(event) => {
                    const nextId = event.target.value;
                    const area = areaOptions.find((item) => item.id === nextId);
                    setSaveError(null);
                    setEditingUser((current) =>
                      current
                        ? {
                            ...current,
                            areaId: nextId,
                            areaName: area?.name ?? nextId,
                          }
                        : current,
                    );
                  }}
                  className="app-select w-full disabled:bg-slate-100"
                >
                  {(editingUser.role === "administrador" ? [{ id: adminAreaId, name: adminAreaId }] : areaOptions).map((area) => (
                    <option key={area.id} value={area.id}>
                      {area.name}
                    </option>
                  ))}
                </select>
              </label>

              {saveError ? <div className="rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">{saveError}</div> : null}

              <div className="flex justify-end gap-3">
                <button type="button" onClick={() => { setEditingUser(null); setSaveError(null); }} className="app-button-secondary">
                  Cancelar
                </button>
                <button type="submit" disabled={isSaving} className="app-button-primary">
                  {isSaving ? "Guardando..." : "Guardar"}
                </button>
              </div>
            </form>
          </div>
        </div>
      ) : null}
    </div>
  );
}
