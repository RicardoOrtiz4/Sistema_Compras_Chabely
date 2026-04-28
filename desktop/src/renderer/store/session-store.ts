import { create } from "zustand";
import {
  onAuthStateChanged,
  signInWithEmailAndPassword,
  signOut as firebaseSignOut,
  type User,
} from "firebase/auth";
import { onValue, ref } from "firebase/database";
import { auth, database } from "@/lib/firebase/client";
import { normalizeAreaLabel } from "@/lib/area-labels";
import { resolveLoginEmail } from "@/lib/branding";
import { useBrandingStore } from "@/store/branding-store";

export type AppRole = "administrador" | "admin" | "usuario";

export type AppUser = {
  id: string;
  name: string;
  email: string;
  role: AppRole;
  areaId: string;
  areaName: string;
  areaDisplay: string;
  isActive: boolean;
};

type SessionState = {
  authUser: User | null;
  profile: AppUser | null;
  isAuthenticated: boolean;
  isBootstrapping: boolean;
  isSigningIn: boolean;
  authError: string | null;
  initialize: () => void;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
};

let initialized = false;
let profileUnsubscribe: (() => void) | null = null;

function firstNonEmptyString(data: Record<string, unknown>, keys: string[]) {
  for (const key of keys) {
    const raw = data[key];
    if (typeof raw === "string" && raw.trim()) {
      return raw.trim();
    }
  }
  return "";
}

function mapProfile(uid: string, value: unknown, fallbackEmail: string): AppUser | null {
  if (!value || typeof value !== "object") {
    return null;
  }

  const data = value as Record<string, unknown>;
  const areaId = firstNonEmptyString(data, ["areaId", "departmentId", "area"]);
  const areaName =
    firstNonEmptyString(data, ["areaName", "departmentName", "areaLabel"]) || areaId;
  const role = firstNonEmptyString(data, ["role"]).toLowerCase();

  return {
    id: uid,
    name: firstNonEmptyString(data, ["name", "displayName", "fullName", "nombre"]) || "Sin nombre",
    email: firstNonEmptyString(data, ["email", "mail", "userEmail"]) || fallbackEmail,
    role: role === "administrador" || role === "admin" ? role : "usuario",
    areaId,
    areaName,
    areaDisplay: normalizeAreaLabel(areaName || areaId),
    isActive: data.isActive !== false,
  };
}

function mapFirebaseAuthError(error: unknown) {
  const code =
    typeof error === "object" && error && "code" in error ? String(error.code) : "";

  switch (code) {
    case "auth/wrong-password":
    case "auth/invalid-credential":
    case "auth/user-not-found":
      return "Las credenciales son incorrectas.";
    case "auth/too-many-requests":
      return "Demasiados intentos. Intenta más tarde.";
    case "auth/network-request-failed":
      return "No se pudo conectar con Firebase Auth.";
    default:
      return "No se pudo iniciar sesión.";
  }
}

function buildInactiveProfileMessage(profile: AppUser | null) {
  if (!profile) {
    return "No se encontro un perfil valido para este usuario.";
  }

  if (!profile.isActive) {
    return "Tu usuario esta inactivo. Solicita acceso al administrador.";
  }

  return null;
}

export const useSessionStore = create<SessionState>((set) => ({
  authUser: null,
  profile: null,
  isAuthenticated: false,
  isBootstrapping: true,
  isSigningIn: false,
  authError: null,
  initialize: () => {
    if (initialized) return;
    initialized = true;

    onAuthStateChanged(auth, (user) => {
      profileUnsubscribe?.();
      profileUnsubscribe = null;

      if (!user) {
        useBrandingStore.getState().restoreForUserEmail(null);
        set({
          authUser: null,
          profile: null,
          isAuthenticated: false,
          isBootstrapping: false,
          authError: null,
        });
        return;
      }

      useBrandingStore.getState().restoreForUserEmail(user.email);
      set({
        authUser: user,
        isAuthenticated: false,
        profile: null,
        isBootstrapping: true,
        authError: null,
      });

      profileUnsubscribe = onValue(
        ref(database, `users/${user.uid}`),
        (snapshot) => {
          const profile = mapProfile(user.uid, snapshot.val(), user.email ?? "");
          const inactiveMessage = buildInactiveProfileMessage(profile);

          set({
            profile,
            isAuthenticated: inactiveMessage === null,
            isBootstrapping: false,
            authError: inactiveMessage,
          });
        },
        () => {
          set({
            profile: null,
            isAuthenticated: false,
            isBootstrapping: false,
            authError: "No se pudo cargar el perfil del usuario.",
          });
        },
      );
    });
  },
  signIn: async (email, password) => {
    set({ isSigningIn: true, authError: null });
    try {
      const normalizedEmail = email.trim();
      const resolution = resolveLoginEmail(normalizedEmail);
      useBrandingStore.getState().prepareForLoginEmail(normalizedEmail);
      await signInWithEmailAndPassword(auth, resolution.authEmail, password);
      set({ isSigningIn: false, authError: null });
    } catch (error) {
      set({
        isSigningIn: false,
        authError: mapFirebaseAuthError(error),
      });
      throw error;
    }
  },
  signOut: async () => {
    await firebaseSignOut(auth);
    set({
      authUser: null,
      profile: null,
      isAuthenticated: false,
      authError: null,
    });
  },
}));
