type SnackbarTone = "success" | "error";

const toneClasses: Record<SnackbarTone, string> = {
  success: "bg-slate-900 text-white",
  error: "bg-red-700 text-white",
};

export function Snackbar({
  message,
  tone = "success",
}: {
  message: string | null;
  tone?: SnackbarTone;
}) {
  if (!message) return null;

  return (
    <div className="pointer-events-none fixed bottom-5 left-1/2 z-40 w-[min(92vw,720px)] -translate-x-1/2">
      <div
        className={`rounded-2xl px-5 py-4 text-sm font-medium shadow-[0_22px_60px_rgba(15,23,42,0.28)] ${toneClasses[tone]}`}
      >
        {message}
      </div>
    </div>
  );
}
