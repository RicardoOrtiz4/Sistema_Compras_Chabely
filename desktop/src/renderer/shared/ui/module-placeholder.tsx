import { StatusBadge } from "@/shared/ui/status-badge";

type ModulePlaceholderProps = {
  title: string;
  description: string;
  source: string;
  nextStep: string;
};

export function ModulePlaceholder({
  title,
  description,
  source,
  nextStep,
}: ModulePlaceholderProps) {
  return (
    <div className="rounded-[28px] border border-line bg-panel p-8 shadow-shell">
      <div className="flex items-center justify-between gap-4">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-400">
            Módulo en preparación
          </p>
          <h3 className="mt-2 text-2xl font-semibold text-slate-900">{title}</h3>
        </div>
        <StatusBadge label="Pendiente migración" tone="warning" />
      </div>

      <p className="mt-5 max-w-3xl text-sm leading-7 text-slate-600">{description}</p>

      <div className="mt-8 grid gap-4 md:grid-cols-2">
        <div className="rounded-3xl bg-slate-50 p-5">
          <p className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-400">
            Fuente Flutter
          </p>
          <p className="mt-2 text-sm font-medium text-slate-800">{source}</p>
        </div>
        <div className="rounded-3xl bg-slate-50 p-5">
          <p className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-400">
            Siguiente paso
          </p>
          <p className="mt-2 text-sm font-medium text-slate-800">{nextStep}</p>
        </div>
      </div>
    </div>
  );
}
