import { create } from "zustand";
import {
  availableBrandings,
  applyBrandingTheme,
  brandingFor,
  companyFromEmail,
  normalizeEmail,
  resolveLoginEmail,
  type CompanyBranding,
  type CompanyId,
} from "@/lib/branding";

const activeCompanyPrefsKey = "active_company_v2";
const userCompanyPrefsPrefix = "active_company_user_v2::";

type BrandingState = {
  company: CompanyId;
  branding: CompanyBranding;
  initialize: () => void;
  prepareForLoginEmail: (email: string) => void;
  restoreForUserEmail: (email: string | null | undefined) => void;
  selectCompany: (company: CompanyId, authenticatedEmail?: string | null) => void;
  availableBrandings: CompanyBranding[];
};

function parseCompany(raw: string | null | undefined): CompanyId | null {
  if (raw === "chabely" || raw === "acerpro") {
    return raw;
  }
  return null;
}

function readStoredCompanyForUser(email: string | null | undefined) {
  const normalizedEmail = normalizeEmail(email);
  if (!normalizedEmail) return null;
  return parseCompany(window.localStorage.getItem(`${userCompanyPrefsPrefix}${normalizedEmail}`));
}

let initialized = false;

export const useBrandingStore = create<BrandingState>((set, get) => ({
  company: "chabely",
  branding: brandingFor("chabely"),
  availableBrandings,
  initialize: () => {
    if (initialized) {
      applyBrandingTheme(get().branding);
      return;
    }
    initialized = true;
    const storedCompany = parseCompany(window.localStorage.getItem(activeCompanyPrefsKey)) ?? "chabely";
    const branding = brandingFor(storedCompany);
    set({ company: storedCompany, branding });
    applyBrandingTheme(branding);
  },
  prepareForLoginEmail: (email) => {
    const resolution = resolveLoginEmail(email);
    if (!resolution.company) return;
    const branding = brandingFor(resolution.company);
    window.localStorage.setItem(activeCompanyPrefsKey, resolution.company);
    set({ company: resolution.company, branding });
    applyBrandingTheme(branding);
  },
  restoreForUserEmail: (email) => {
    const normalizedEmail = normalizeEmail(email);
    const storedUserCompany = readStoredCompanyForUser(normalizedEmail);
    const storedGlobalCompany = parseCompany(window.localStorage.getItem(activeCompanyPrefsKey));
    const resolvedCompany = storedUserCompany ?? storedGlobalCompany ?? companyFromEmail(normalizedEmail) ?? "chabely";
    const branding = brandingFor(resolvedCompany);
    window.localStorage.setItem(activeCompanyPrefsKey, resolvedCompany);
    if (normalizedEmail) {
      window.localStorage.setItem(`${userCompanyPrefsPrefix}${normalizedEmail}`, resolvedCompany);
    }
    set({ company: resolvedCompany, branding });
    applyBrandingTheme(branding);
  },
  selectCompany: (company, authenticatedEmail) => {
    const normalizedEmail = normalizeEmail(authenticatedEmail);
    const branding = brandingFor(company);
    window.localStorage.setItem(activeCompanyPrefsKey, company);
    if (normalizedEmail) {
      window.localStorage.setItem(`${userCompanyPrefsPrefix}${normalizedEmail}`, company);
    }
    set({ company, branding });
    applyBrandingTheme(branding);
  },
}));
