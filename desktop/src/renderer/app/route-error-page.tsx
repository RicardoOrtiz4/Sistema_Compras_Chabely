import { isRouteErrorResponse, Link, useRouteError } from "react-router-dom";

function describeError(error: unknown) {
  if (isRouteErrorResponse(error)) {
    return `${error.status} ${error.statusText}`;
  }
  if (error instanceof Error) {
    return error.message;
  }
  return "Ocurrio un error inesperado.";
}

export function RouteErrorPage() {
  const error = useRouteError();
  const message = describeError(error);

  return (
    <div className="flex min-h-screen items-center justify-center bg-canvas p-6 text-ink">
      <div className="w-full max-w-2xl rounded-[28px] border border-red-200 bg-white p-8 shadow-shell">
        <p className="text-xs font-semibold uppercase tracking-[0.24em] text-red-500">Error</p>
        <h1 className="mt-2 text-2xl font-semibold text-slate-900">La aplicacion encontro un problema</h1>
        <p className="mt-4 text-sm text-slate-700">{message}</p>
        {error instanceof Error && error.stack ? (
          <pre className="mt-6 overflow-auto rounded-2xl bg-slate-950 p-4 text-xs text-slate-200">
            {error.stack}
          </pre>
        ) : null}
        <div className="mt-6 flex gap-3">
          <button
            type="button"
            onClick={() => window.location.reload()}
            className="rounded-2xl bg-slate-900 px-4 py-3 text-sm font-semibold text-white"
          >
            Recargar
          </button>
          <Link
            to="/"
            className="rounded-2xl border border-line bg-white px-4 py-3 text-sm font-semibold text-slate-700"
          >
            Ir al inicio
          </Link>
        </div>
      </div>
    </div>
  );
}
