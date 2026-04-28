import { forwardRef, type ButtonHTMLAttributes } from "react";
import { cn } from "@/lib/utils";

type ButtonVariant = "default" | "secondary" | "ghost";
type ButtonSize = "default" | "sm" | "lg" | "icon";

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: ButtonVariant;
  size?: ButtonSize;
};

const variantClasses: Record<ButtonVariant, string> = {
  default:
    "border-transparent bg-[var(--app-primary)] text-white shadow-[0_12px_30px_color-mix(in_srgb,var(--app-primary)_28%,transparent)] hover:opacity-95",
  secondary:
    "border-[color:color-mix(in_srgb,var(--app-primary)_14%,white)] bg-[var(--app-surface)] text-[var(--app-secondary)] hover:bg-[color:color-mix(in_srgb,var(--app-surface)_82%,var(--app-primary)_18%)]",
  ghost:
    "border-transparent bg-transparent text-[var(--app-secondary)] hover:bg-[color:color-mix(in_srgb,var(--app-primary)_8%,white)]",
};

const sizeClasses: Record<ButtonSize, string> = {
  default: "h-11 px-4 py-2",
  sm: "h-9 rounded-xl px-3 text-sm",
  lg: "h-12 rounded-2xl px-6 text-base",
  icon: "h-11 w-11 rounded-full p-0",
};

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  { className, variant = "default", size = "default", ...props },
  ref,
) {
  return (
    <button
      ref={ref}
      className={cn(
        "inline-flex items-center justify-center gap-2 rounded-2xl border text-sm font-semibold transition disabled:pointer-events-none disabled:opacity-55",
        variantClasses[variant],
        sizeClasses[size],
        className,
      )}
      {...props}
    />
  );
});
