import { FormEvent, useState } from "react";
import { Eye, EyeOff, Lock, Mail } from "lucide-react";
import { Navigate } from "react-router-dom";
import { useSessionStore } from "@/store/session-store";

export function LoginPage() {
  const isAuthenticated = useSessionStore((state) => state.isAuthenticated);
  const isSigningIn = useSessionStore((state) => state.isSigningIn);
  const authError = useSessionStore((state) => state.authError);
  const signIn = useSessionStore((state) => state.signIn);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);

  if (isAuthenticated) {
    return <Navigate to="/" replace />;
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!email.trim() || !password.trim()) {
      return;
    }
    void signIn(email.trim(), password);
  }

  return (
    <div className="login-page-bg flex min-h-screen items-center justify-center px-6 py-10">
      <div className="login-page-blob login-page-blob-a" />
      <div className="login-page-blob login-page-blob-b" />
      <div className="relative z-[1] w-full max-w-[420px]">
        <form className="space-y-4" onSubmit={handleSubmit}>
          <div className="flex flex-col items-center text-center">
            <h1 className="text-3xl font-semibold text-slate-900">
              Sistema de Compras
            </h1>
            <p className="mt-2 text-sm text-slate-600">
              Acceso al sistema
            </p>
          </div>

          <div
            className="rounded-[28px] border px-6 py-7 shadow-[0_18px_50px_rgba(15,23,42,0.08)]"
            style={{
              background: "linear-gradient(180deg, rgba(245,246,248,0.94) 0%, rgba(229,232,236,0.96) 100%)",
              borderColor: "rgba(15, 23, 42, 0.12)",
              backdropFilter: "blur(10px)",
            }}
          >
            <div>
              <label className="mb-2 block text-sm font-medium text-slate-700">
                Correo corporativo
              </label>
              <div className="relative">
                <Mail
                  className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2"
                  style={{ color: "#64748b" }}
                  size={18}
                />
                <input
                  className="app-input pl-11"
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                  placeholder="correo@empresa.com"
                  autoComplete="username"
                />
              </div>
            </div>

            <div className="mt-4">
              <label className="mb-2 block text-sm font-medium text-slate-700">
                Contraseña
              </label>
              <div className="relative">
                <Lock
                  className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2"
                  style={{ color: "#64748b" }}
                  size={18}
                />
                <input
                  className="app-input pl-11 pr-12"
                  type={showPassword ? "text" : "password"}
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  placeholder="Ingresa tu contraseña"
                  autoComplete="current-password"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword((current) => !current)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 rounded-xl p-2"
                  style={{ color: "#64748b" }}
                >
                  {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                </button>
              </div>
            </div>

            {authError ? (
              <div className="mt-4 rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
                {authError}
              </div>
            ) : null}

            <button type="submit" disabled={isSigningIn} className="app-button-primary mt-6 w-full">
              {isSigningIn ? "Iniciando sesión..." : "Iniciar sesión"}
            </button>

            <p className="mt-4 text-center text-sm text-slate-600">
              El acceso está protegido. Solicita tu cuenta a TI.
            </p>
          </div>
        </form>
      </div>
    </div>
  );
}
