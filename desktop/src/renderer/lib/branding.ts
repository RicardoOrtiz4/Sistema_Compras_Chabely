export type CompanyId = "chabely" | "acerpro";

export type CompanyBranding = {
  id: CompanyId;
  displayName: string;
  tagline: string;
  logoPath: string;
  seedColor: string;
  background: string;
  surface: string;
  surfaceVariant: string;
  primary: string;
  secondary: string;
  tertiary: string;
  secondaryContainer: string;
  tertiaryContainer: string;
  pdfHeaderLine1: string;
  pdfHeaderLine2: string;
  pdfTitle: string;
  pdfTitleBarColor: string;
  pdfAccentColor: string;
  pdfRefCode: string;
  pdfRevision?: string;
};

export type LoginEmailResolution = {
  requestedEmail: string;
  authEmail: string;
  company: CompanyId | null;
};

const chabelyAuthDomain = "chabely.com.mx";

export const companyBrandingMap: Record<CompanyId, CompanyBranding> = {
  chabely: {
    id: "chabely",
    displayName: "Chabely",
    tagline: "Sistema de compras",
    logoPath: "/branding/chabely-logo.png",
    seedColor: "#4A4A4A",
    background: "#F6F6F6",
    surface: "#FFFFFF",
    surfaceVariant: "#E9E9E9",
    primary: "#111111",
    secondary: "#2F2F2F",
    tertiary: "#3B3B3B",
    secondaryContainer: "#4A4A4A",
    tertiaryContainer: "#5A5A5A",
    pdfHeaderLine1: "FORMATO DEL SISTEMA DE GESTIÓN DE CALIDAD",
    pdfHeaderLine2: "GESTIÓN DE COMPRAS",
    pdfTitle: "REQUISICIÓN DE COMPRA",
    pdfTitleBarColor: "#000000",
    pdfAccentColor: "#B00020",
    pdfRefCode: "FORM-COM-01",
    pdfRevision: "REV.02",
  },
  acerpro: {
    id: "acerpro",
    displayName: "Acerpro",
    tagline: "Sistema de compras",
    logoPath: "/branding/acerpro-logo.png",
    seedColor: "#0065B3",
    background: "#F3F5F7",
    surface: "#FFFFFF",
    surfaceVariant: "#E3E8EE",
    primary: "#0065B3",
    secondary: "#7A7A7A",
    tertiary: "#4F5B66",
    secondaryContainer: "#E3E8EE",
    tertiaryContainer: "#D6E1F2",
    pdfHeaderLine1: "FORMATO DEL SISTEMA DE GESTIÓN DE CALIDAD",
    pdfHeaderLine2: "GESTIÓN DE COMPRAS",
    pdfTitle: "REQUISICIÓN DE COMPRA",
    pdfTitleBarColor: "#0065B3",
    pdfAccentColor: "#7A7A7A",
    pdfRefCode: "FCOM-1",
    pdfRevision: "R.00",
  },
};

export const availableBrandings = Object.values(companyBrandingMap);

export function brandingFor(company: CompanyId | null | undefined) {
  return companyBrandingMap[company ?? "chabely"] ?? companyBrandingMap.chabely;
}

export function normalizeEmail(email: string | null | undefined) {
  return (email ?? "").trim().toLowerCase();
}

export function companyFromEmail(email: string | null | undefined): CompanyId | null {
  const normalized = normalizeEmail(email);
  const atIndex = normalized.lastIndexOf("@");
  if (atIndex <= 0 || atIndex >= normalized.length - 1) {
    return null;
  }
  const domain = normalized.slice(atIndex + 1);
  if (domain.includes("acerpro")) return "acerpro";
  if (domain.includes("chabely")) return "chabely";
  return null;
}

export function resolveLoginEmail(rawEmail: string): LoginEmailResolution {
  const requestedEmail = normalizeEmail(rawEmail);
  const atIndex = requestedEmail.lastIndexOf("@");
  if (atIndex > 0 && atIndex < requestedEmail.length - 1) {
    const localPart = requestedEmail.slice(0, atIndex);
    const domain = requestedEmail.slice(atIndex + 1);
    if (domain.includes("acerpro")) {
      return {
        requestedEmail,
        authEmail: `${localPart}@${chabelyAuthDomain}`,
        company: "acerpro",
      };
    }
  }

  return {
    requestedEmail,
    authEmail: requestedEmail,
    company: companyFromEmail(requestedEmail),
  };
}

export function applyBrandingTheme(branding: CompanyBranding) {
  const root = document.documentElement;
  root.dataset.brand = branding.id;
  root.style.setProperty("--app-bg", branding.id === "acerpro" ? "#cfd6de" : "#cbd1d8");
  root.style.setProperty("--app-surface", branding.surface);
  root.style.setProperty("--app-surface-variant", branding.surfaceVariant);
  root.style.setProperty("--app-primary", branding.primary);
  root.style.setProperty("--app-secondary", branding.secondary);
  root.style.setProperty("--app-tertiary", branding.tertiary);
  root.style.setProperty("--app-secondary-container", branding.secondaryContainer);
  root.style.setProperty("--app-tertiary-container", branding.tertiaryContainer);
  root.style.setProperty("--app-header-start", branding.primary);
  root.style.setProperty("--app-header-end", branding.tertiary);
  root.style.setProperty("--app-header-foreground", "#ffffff");
}
