import { useEffect } from "react";
import { applyBrandingTheme } from "@/lib/branding";
import { useBrandingStore } from "@/store/branding-store";
import { useSessionStore } from "@/store/session-store";

export function AppBootstrap() {
  const initialize = useSessionStore((state) => state.initialize);
  const initializeBranding = useBrandingStore((state) => state.initialize);
  const branding = useBrandingStore((state) => state.branding);

  useEffect(() => {
    initialize();
    initializeBranding();
  }, [initialize, initializeBranding]);

  useEffect(() => {
    applyBrandingTheme(branding);
  }, [branding]);

  return null;
}
