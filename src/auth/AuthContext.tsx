import type { Session, User } from "@supabase/supabase-js";
import { useQueryClient } from "@tanstack/react-query";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";

import { isDemoMode, runtimeConfig, setDemoMode } from "@/config/runtime";
import { getSupabaseClient } from "@/lib/supabase";
import type { AccessContext, StaffRole } from "@/types/read-models";

type AuthStatus =
  | "loading"
  | "unauthenticated"
  | "mfa_enrollment_required"
  | "mfa_required"
  | "password_recovery"
  | "access_pending"
  | "ready";

interface MfaEnrollment {
  factorId: string;
  qrCode: string;
  secret: string;
}

interface AuthContextValue {
  status: AuthStatus;
  session: Session | null;
  user: User | null;
  access: AccessContext | null;
  demo: boolean;
  errorCode: string | null;
  mfaEnrollment: MfaEnrollment | null;
  signIn(email: string, password: string): Promise<void>;
  signOut(): Promise<void>;
  requestPasswordReset(email: string): Promise<void>;
  startMfaEnrollment(): Promise<void>;
  verifyMfa(code: string): Promise<void>;
  updateRecoveredPassword(password: string): Promise<void>;
  enterDemo(): void;
  leaveDemo(): void;
  reloadAccess(): Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

const MUNICIPAL_STAFF_ROLES = new Set<StaffRole>([
  "municipal_admin",
  "supervisor",
  "fiscal_auditor",
  "legal_reviewer",
]);

function safeErrorCode(error: unknown): string {
  if (error && typeof error === "object" && "code" in error) {
    return String(error.code).slice(0, 80);
  }
  return "access_resolution_failed";
}

function isPasswordSetupLocation(): boolean {
  if (typeof window === "undefined") return false;
  const url = new URL(window.location.href);
  const fragment = new URLSearchParams(url.hash.replace(/^#/, ""));
  const flowTypes = [url.searchParams.get("type"), fragment.get("type")];
  return (
    url.searchParams.get("recovery") === "1" ||
    flowTypes.some((type) => type === "invite" || type === "recovery")
  );
}

function clearPasswordSetupLocation(): void {
  if (typeof window === "undefined") return;
  const url = new URL(window.location.href);
  url.searchParams.delete("recovery");
  url.searchParams.delete("type");
  window.history.replaceState({}, "", `${url.pathname}${url.search}`);
}

async function resolveAccess(userId: string): Promise<AccessContext | null> {
  const supabase = getSupabaseClient();
  const now = new Date().toISOString();

  const platform = await supabase
    .from("platform_administrators")
    .select("user_id")
    .eq("user_id", userId)
    .eq("active", true)
    .is("revoked_at", null)
    .maybeSingle();

  if (platform.error) throw platform.error;
  if (platform.data) {
    return {
      role: "platform_admin",
      municipalityId: "",
      municipalityLabel: "Administração da plataforma",
    };
  }

  const municipality = await supabase
    .from("municipalities")
    .select("id, name, state_code")
    .eq("ibge_code", runtimeConfig.municipalityIbge)
    .maybeSingle();

  if (municipality.error) throw municipality.error;
  if (!municipality.data) return null;
  const municipalityId = municipality.data.id as string;
  const municipalityLabel = `${String(municipality.data.name).trim()}/${String(
    municipality.data.state_code,
  ).trim()}`;

  const staff = await supabase
    .from("municipality_memberships")
    .select("id, municipality_id, role")
    .eq("user_id", userId)
    .eq("municipality_id", municipalityId)
    .eq("status", "active")
    .lte("valid_from", now)
    .or(`valid_until.is.null,valid_until.gt.${now}`)
    .maybeSingle();

  if (staff.error) throw staff.error;
  if (staff.data && MUNICIPAL_STAFF_ROLES.has(staff.data.role as StaffRole)) {
    return {
      role: staff.data.role as StaffRole,
      municipalityId,
      municipalityLabel,
      membershipId: staff.data.id as string,
    };
  }

  const taxpayer = await supabase
    .from("taxpayer_user_links")
    .select("municipality_id, taxpayer_id")
    .eq("user_id", userId)
    .eq("municipality_id", municipalityId)
    .eq("status", "active")
    .not("verified_at", "is", null)
    .lte("valid_from", now)
    .or(`valid_until.is.null,valid_until.gt.${now}`)
    .order("taxpayer_id", { ascending: true })
    .limit(1)
    .maybeSingle();

  if (taxpayer.error) throw taxpayer.error;
  if (taxpayer.data) {
    return {
      role: "taxpayer",
      municipalityId,
      municipalityLabel,
      taxpayerId: taxpayer.data.taxpayer_id as string,
    };
  }

  const accountant = await supabase
    .from("accountant_user_links")
    .select("municipality_id, accounting_firm_id")
    .eq("user_id", userId)
    .eq("municipality_id", municipalityId)
    .eq("status", "active")
    .not("verified_at", "is", null)
    .lte("valid_from", now)
    .or(`valid_until.is.null,valid_until.gt.${now}`)
    .order("accounting_firm_id", { ascending: true })
    .limit(1)
    .maybeSingle();

  if (accountant.error) throw accountant.error;
  if (accountant.data) {
    return {
      role: "accountant",
      municipalityId,
      municipalityLabel,
      accountingFirmId: accountant.data.accounting_firm_id as string,
    };
  }

  return null;
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient();
  const [status, setStatus] = useState<AuthStatus>("loading");
  const [session, setSession] = useState<Session | null>(null);
  const [access, setAccess] = useState<AccessContext | null>(null);
  const [demo, setDemo] = useState(false);
  const [errorCode, setErrorCode] = useState<string | null>(null);
  const [mfaEnrollment, setMfaEnrollment] = useState<MfaEnrollment | null>(null);
  const [mfaFactorId, setMfaFactorId] = useState<string | null>(null);
  const principalRef = useRef<string | null>(null);
  const accessRequestRef = useRef(0);
  const recoveryRef = useRef(false);

  const loadAccess = useCallback(
    async (nextSession: Session | null) => {
      const nextPrincipal = nextSession?.user.id ?? null;
      const requestId = ++accessRequestRef.current;

      if (principalRef.current !== nextPrincipal) {
        queryClient.clear();
        setAccess(null);
        setMfaEnrollment(null);
        setMfaFactorId(null);
        setStatus(nextSession ? "loading" : "unauthenticated");
        principalRef.current = nextPrincipal;
      }

      setSession(nextSession);
      setErrorCode(null);
      if (!nextSession) {
        setAccess(null);
        setMfaEnrollment(null);
        setMfaFactorId(null);
        setStatus("unauthenticated");
        return;
      }
      if (recoveryRef.current) {
        setAccess(null);
        setMfaEnrollment(null);
        setMfaFactorId(null);
        setStatus("password_recovery");
        return;
      }
      try {
        const supabase = getSupabaseClient();
        const assurance = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
        if (assurance.error) throw assurance.error;
        if (
          requestId !== accessRequestRef.current ||
          principalRef.current !== nextPrincipal ||
          recoveryRef.current
        ) {
          return;
        }

        if (assurance.data.currentLevel !== "aal2") {
          const factors = await supabase.auth.mfa.listFactors();
          if (factors.error) throw factors.error;
          if (
            requestId !== accessRequestRef.current ||
            principalRef.current !== nextPrincipal ||
            recoveryRef.current
          ) {
            return;
          }

          const verifiedTotp = factors.data.totp[0] ?? null;
          setAccess(null);
          if (verifiedTotp) {
            setMfaEnrollment(null);
            setMfaFactorId(verifiedTotp.id);
          }
          setStatus(verifiedTotp ? "mfa_required" : "mfa_enrollment_required");
          return;
        }

        setMfaEnrollment(null);
        setMfaFactorId(null);
        const nextAccess = await resolveAccess(nextSession.user.id);
        if (requestId !== accessRequestRef.current || principalRef.current !== nextPrincipal) {
          return;
        }
        setAccess(nextAccess);
        setStatus(nextAccess ? "ready" : "access_pending");
      } catch (error) {
        if (requestId !== accessRequestRef.current || principalRef.current !== nextPrincipal) {
          return;
        }
        setAccess(null);
        setErrorCode(safeErrorCode(error));
        setStatus("access_pending");
      }
    },
    [queryClient],
  );

  useEffect(() => {
    const demoActive = isDemoMode();
    setDemo(demoActive);
    const recoveryFromUrl = isPasswordSetupLocation();
    recoveryRef.current = recoveryFromUrl;

    if (demoActive && !recoveryFromUrl) {
      setStatus("ready");
      return;
    }
    if (recoveryFromUrl) {
      setDemoMode(false);
      setDemo(false);
    }

    const supabase = getSupabaseClient();
    void supabase.auth.getSession().then(({ data, error }) => {
      if (error) {
        setErrorCode(safeErrorCode(error));
        setStatus("unauthenticated");
        return;
      }
      void loadAccess(data.session);
    });

    const { data: subscription } = supabase.auth.onAuthStateChange((event, nextSession) => {
      if (event === "PASSWORD_RECOVERY") {
        recoveryRef.current = true;
        accessRequestRef.current += 1;
        queryClient.clear();
        principalRef.current = nextSession?.user.id ?? null;
        setSession(nextSession);
        setAccess(null);
        setMfaEnrollment(null);
        setMfaFactorId(null);
        setErrorCode(null);
        setStatus(nextSession ? "password_recovery" : "unauthenticated");
        return;
      }
      void loadAccess(nextSession);
    });
    return () => subscription.subscription.unsubscribe();
  }, [loadAccess, queryClient]);

  const value = useMemo<AuthContextValue>(
    () => ({
      status,
      session,
      user: session?.user ?? null,
      access: demo
        ? {
            role: "fiscal_auditor",
            municipalityId: "demo-cordeiropolis",
            municipalityLabel: runtimeConfig.municipalityLabel,
            membershipId: "demo-membership",
          }
        : access,
      demo,
      errorCode,
      mfaEnrollment,
      async signIn(email, password) {
        setErrorCode(null);
        const { error } = await getSupabaseClient().auth.signInWithPassword({ email, password });
        if (error) {
          setErrorCode(safeErrorCode(error));
          throw error;
        }
      },
      async signOut() {
        queryClient.clear();
        accessRequestRef.current += 1;
        principalRef.current = null;
        recoveryRef.current = false;
        clearPasswordSetupLocation();
        setMfaEnrollment(null);
        setMfaFactorId(null);
        await getSupabaseClient().auth.signOut({ scope: "local" });
        setSession(null);
        setAccess(null);
        setStatus("unauthenticated");
      },
      async requestPasswordReset(email) {
        const options =
          typeof window === "undefined"
            ? {}
            : { redirectTo: new URL("/?recovery=1", window.location.origin).toString() };
        const { error } = await getSupabaseClient().auth.resetPasswordForEmail(email, options);
        if (error) {
          setErrorCode(safeErrorCode(error));
          throw error;
        }
      },
      async startMfaEnrollment() {
        setErrorCode(null);
        const principal = session?.user.id;
        if (!principal || principalRef.current !== principal) {
          const error = Object.assign(new Error("Sessão ausente"), { code: "session_missing" });
          setErrorCode(error.code);
          throw error;
        }

        const { data, error } = await getSupabaseClient().auth.mfa.enroll({
          factorType: "totp",
          friendlyName: "IA Fiscal",
          issuer: "IA Fiscal",
        });
        if (error) {
          setErrorCode(safeErrorCode(error));
          throw error;
        }
        if (principalRef.current !== principal) return;

        const qrCode = data.totp.qr_code.startsWith("data:")
          ? data.totp.qr_code
          : `data:image/svg+xml;utf-8,${encodeURIComponent(data.totp.qr_code)}`;
        setMfaEnrollment({ factorId: data.id, qrCode, secret: data.totp.secret });
        setMfaFactorId(data.id);
        setStatus("mfa_enrollment_required");
      },
      async verifyMfa(code) {
        setErrorCode(null);
        const normalizedCode = code.replace(/\s/g, "");
        if (!/^\d{6}$/.test(normalizedCode)) {
          const error = Object.assign(new Error("Código inválido"), { code: "invalid_totp_code" });
          setErrorCode(error.code);
          throw error;
        }
        if (!mfaFactorId) {
          const error = Object.assign(new Error("Fator MFA ausente"), {
            code: "mfa_factor_missing",
          });
          setErrorCode(error.code);
          throw error;
        }

        const supabase = getSupabaseClient();
        const challenge = await supabase.auth.mfa.challenge({ factorId: mfaFactorId });
        if (challenge.error) {
          setErrorCode(safeErrorCode(challenge.error));
          throw challenge.error;
        }
        const verification = await supabase.auth.mfa.verify({
          factorId: mfaFactorId,
          challengeId: challenge.data.id,
          code: normalizedCode,
        });
        if (verification.error) {
          setErrorCode(safeErrorCode(verification.error));
          throw verification.error;
        }

        setMfaEnrollment(null);
        setMfaFactorId(null);
        const current = await supabase.auth.getSession();
        if (current.error) {
          setErrorCode(safeErrorCode(current.error));
          throw current.error;
        }
        await loadAccess(current.data.session);
      },
      async updateRecoveredPassword(password) {
        setErrorCode(null);
        if (password.length < 12 || password.length > 128) {
          const error = Object.assign(new Error("Senha fora da política"), {
            code: "password_policy_failed",
          });
          setErrorCode(error.code);
          throw error;
        }

        const supabase = getSupabaseClient();
        const update = await supabase.auth.updateUser({ password });
        if (update.error) {
          setErrorCode(safeErrorCode(update.error));
          throw update.error;
        }

        recoveryRef.current = false;
        clearPasswordSetupLocation();
        queryClient.clear();
        accessRequestRef.current += 1;
        principalRef.current = null;
        const globalSignOut = await supabase.auth.signOut({ scope: "global" });
        if (globalSignOut.error) {
          await supabase.auth.signOut({ scope: "local" });
        }
        setSession(null);
        setAccess(null);
        setMfaEnrollment(null);
        setMfaFactorId(null);
        setStatus("unauthenticated");
        if (globalSignOut.error) {
          setErrorCode(safeErrorCode(globalSignOut.error));
          throw globalSignOut.error;
        }
      },
      enterDemo() {
        queryClient.clear();
        accessRequestRef.current += 1;
        recoveryRef.current = false;
        clearPasswordSetupLocation();
        setMfaEnrollment(null);
        setMfaFactorId(null);
        if (!runtimeConfig.allowDemo) {
          setDemoMode(false);
          setDemo(false);
          if (session) void loadAccess(session);
          else setStatus("unauthenticated");
          return;
        }
        setDemoMode(true);
        setDemo(true);
        setStatus("ready");
      },
      leaveDemo() {
        queryClient.clear();
        accessRequestRef.current += 1;
        setMfaEnrollment(null);
        setMfaFactorId(null);
        setDemoMode(false);
        setDemo(false);
        if (session) void loadAccess(session);
        else setStatus("unauthenticated");
      },
      async reloadAccess() {
        await loadAccess(session);
      },
    }),
    [access, demo, errorCode, loadAccess, mfaEnrollment, mfaFactorId, queryClient, session, status],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const value = useContext(AuthContext);
  if (!value) throw new Error("AuthProvider is required");
  return value;
}
