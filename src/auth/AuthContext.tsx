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
import type { AccessContext, MunicipalityContext, StaffRole } from "@/types/read-models";

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
  municipalityContexts: MunicipalityContext[];
  demo: boolean;
  errorCode: string | null;
  mfaEnrollment: MfaEnrollment | null;
  signIn(email: string, password: string): Promise<void>;
  signUp(fullName: string, email: string, password: string): Promise<void>;
  signOut(): Promise<void>;
  requestPasswordReset(email: string): Promise<void>;
  startMfaEnrollment(): Promise<void>;
  verifyMfa(code: string): Promise<void>;
  updateRecoveredPassword(password: string): Promise<boolean>;
  enterDemo(): void;
  leaveDemo(): void;
  selectMunicipality(municipalityId: string): Promise<MunicipalityContext>;
  reloadAccess(): Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

const MUNICIPAL_STAFF_ROLES = new Set<StaffRole>([
  "municipal_admin",
  "supervisor",
  "fiscal_auditor",
  "legal_reviewer",
  "support_readonly",
]);

const MUNICIPALITY_CONTEXT_STORAGE_PREFIX = "ia-fiscal:municipality-context:v1:";

interface ResolvedAccess {
  access: AccessContext | null;
  municipalityContexts: MunicipalityContext[];
}

interface PasswordSetupProof {
  flowType: "invite" | "recovery";
  accessToken: string;
}

function storedMunicipalityId(userId: string): string | null {
  if (typeof window === "undefined") return null;
  try {
    return window.sessionStorage.getItem(`${MUNICIPALITY_CONTEXT_STORAGE_PREFIX}${userId}`);
  } catch {
    return null;
  }
}

function storeMunicipalityId(userId: string, municipalityId: string): void {
  if (typeof window === "undefined") return;
  try {
    window.sessionStorage.setItem(
      `${MUNICIPALITY_CONTEXT_STORAGE_PREFIX}${userId}`,
      municipalityId,
    );
  } catch {
    // O armazenamento é apenas uma preferência de interface, nunca uma fonte de autorização.
  }
}

function safeErrorCode(error: unknown): string {
  if (error && typeof error === "object" && "code" in error) {
    return String(error.code).slice(0, 80);
  }
  return "access_resolution_failed";
}

function hasPasswordSetupFlowHint(): boolean {
  if (typeof window === "undefined") return false;
  const url = new URL(window.location.href);
  const fragment = new URLSearchParams(url.hash.replace(/^#/, ""));
  const flowTypes = [url.searchParams.get("type"), fragment.get("type")];
  return (
    url.searchParams.get("recovery") === "1" ||
    flowTypes.some((type) => type === "invite" || type === "recovery")
  );
}

function capturePasswordSetupProof(): PasswordSetupProof | null {
  if (typeof window === "undefined") return null;
  const url = new URL(window.location.href);
  const fragment = new URLSearchParams(url.hash.replace(/^#/, ""));
  const flowType = fragment.get("type") ?? url.searchParams.get("type");
  if (flowType !== "invite" && flowType !== "recovery") return null;
  const accessToken = fragment.get("access_token");
  if (!accessToken) return null;
  return { flowType, accessToken };
}

function passwordSetupProofMatchesSession(
  proof: PasswordSetupProof | null,
  session: Session | null,
): boolean {
  if (!proof || !session) return false;
  return proof.accessToken === session.access_token;
}

function clearPasswordSetupLocation(): void {
  if (typeof window === "undefined") return;
  const url = new URL(window.location.href);
  url.searchParams.delete("recovery");
  url.searchParams.delete("type");
  window.history.replaceState({}, "", `${url.pathname}${url.search}`);
}

async function resolveAccess(
  userId: string,
  preferredMunicipalityId?: string,
): Promise<ResolvedAccess> {
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
  const isPlatformAdmin = Boolean(platform.data);

  if (isPlatformAdmin) {
    const [municipalitiesResult, membershipsResult] = await Promise.all([
      supabase
        .from("municipalities")
        .select("id, name, state_code, ibge_code, status")
        .order("name", { ascending: true }),
      supabase
        .from("municipality_memberships")
        .select("id, municipality_id, role")
        .eq("user_id", userId)
        .eq("status", "active")
        .lte("valid_from", now)
        .or(`valid_until.is.null,valid_until.gt.${now}`)
        .order("valid_from", { ascending: false }),
    ]);

    if (municipalitiesResult.error) throw municipalitiesResult.error;
    if (membershipsResult.error) throw membershipsResult.error;

    const municipalities = new Map(
      (municipalitiesResult.data ?? [])
        .filter((row) => row.status !== "archived")
        .map((row) => [String(row.id), row]),
    );
    const municipalityContexts = (membershipsResult.data ?? []).flatMap((membership) => {
      const role = membership.role as StaffRole;
      const municipality = municipalities.get(String(membership.municipality_id));
      if (!municipality || !MUNICIPAL_STAFF_ROLES.has(role)) return [];
      const name = String(municipality.name).trim();
      const stateCode = String(municipality.state_code).trim();
      return [
        {
          id: String(municipality.id),
          label: `${name}/${stateCode}`,
          name,
          stateCode,
          ibgeCode: municipality.ibge_code ? String(municipality.ibge_code) : null,
          role,
          membershipId: String(membership.id),
        } satisfies MunicipalityContext,
      ];
    });

    const selectedMunicipalityId =
      preferredMunicipalityId ?? storedMunicipalityId(userId) ?? undefined;
    const explicitlySelected = preferredMunicipalityId
      ? municipalityContexts.find((item) => item.id === preferredMunicipalityId)
      : undefined;
    if (preferredMunicipalityId && !explicitlySelected) {
      throw Object.assign(new Error("Contexto municipal não autorizado"), {
        code: "municipality_context_denied",
      });
    }
    const selected =
      explicitlySelected ??
      municipalityContexts.find((item) => item.id === selectedMunicipalityId) ??
      municipalityContexts.find((item) => item.ibgeCode === runtimeConfig.municipalityIbge) ??
      municipalityContexts[0];

    if (!selected) {
      return {
        access: {
          role: "platform_admin",
          platformAdmin: true,
          municipalityId: "",
          municipalityLabel: "Administração da plataforma",
        },
        municipalityContexts: [],
      };
    }

    return {
      access: {
        role: selected.role,
        platformAdmin: true,
        municipalityId: selected.id,
        municipalityLabel: selected.label,
        membershipId: selected.membershipId,
      },
      municipalityContexts,
    };
  }

  const municipality = await supabase
    .from("municipalities")
    .select("id, name, state_code")
    .eq("ibge_code", runtimeConfig.municipalityIbge)
    .maybeSingle();

  if (municipality.error) throw municipality.error;
  if (!municipality.data) {
    return { access: null, municipalityContexts: [] };
  }
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
      access: {
        role: staff.data.role as StaffRole,
        municipalityId,
        municipalityLabel,
        membershipId: staff.data.id as string,
      },
      municipalityContexts: [],
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
      access: {
        role: "taxpayer",
        municipalityId,
        municipalityLabel,
        taxpayerId: taxpayer.data.taxpayer_id as string,
      },
      municipalityContexts: [],
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
      access: {
        role: "accountant",
        municipalityId,
        municipalityLabel,
        accountingFirmId: accountant.data.accounting_firm_id as string,
      },
      municipalityContexts: [],
    };
  }

  return { access: null, municipalityContexts: [] };
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient();
  const [status, setStatus] = useState<AuthStatus>("loading");
  const [session, setSession] = useState<Session | null>(null);
  const [access, setAccess] = useState<AccessContext | null>(null);
  const [municipalityContexts, setMunicipalityContexts] = useState<MunicipalityContext[]>([]);
  const [demo, setDemo] = useState(false);
  const [errorCode, setErrorCode] = useState<string | null>(null);
  const [mfaEnrollment, setMfaEnrollment] = useState<MfaEnrollment | null>(null);
  const [mfaFactorId, setMfaFactorId] = useState<string | null>(null);
  const principalRef = useRef<string | null>(null);
  const accessRequestRef = useRef(0);
  const recoveryRef = useRef(false);
  const localLockoutRef = useRef(false);
  const pendingMunicipalityRef = useRef<string | null>(null);
  const municipalitySwitchRef = useRef(0);
  const passwordSetupProofRef = useRef<PasswordSetupProof | null>(capturePasswordSetupProof());

  const loadAccess = useCallback(
    async (nextSession: Session | null, preferredMunicipalityId?: string) => {
      const nextPrincipal = nextSession?.user.id ?? null;
      const requestId = ++accessRequestRef.current;

      if (principalRef.current !== nextPrincipal) {
        queryClient.clear();
        setAccess(null);
        setMunicipalityContexts([]);
        setMfaEnrollment(null);
        setMfaFactorId(null);
        setStatus(nextSession ? "loading" : "unauthenticated");
        principalRef.current = nextPrincipal;
      }

      setSession(nextSession);
      setErrorCode(null);
      if (!nextSession) {
        setAccess(null);
        setMunicipalityContexts([]);
        setMfaEnrollment(null);
        setMfaFactorId(null);
        setStatus("unauthenticated");
        return null;
      }
      if (recoveryRef.current) {
        setAccess(null);
        setMunicipalityContexts([]);
        setMfaEnrollment(null);
        setMfaFactorId(null);
        setStatus("password_recovery");
        return null;
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
          return null;
        }

        if (assurance.data.currentLevel !== "aal2") {
          const factors = await supabase.auth.mfa.listFactors();
          if (factors.error) throw factors.error;
          if (
            requestId !== accessRequestRef.current ||
            principalRef.current !== nextPrincipal ||
            recoveryRef.current
          ) {
            return null;
          }

          const verifiedTotp = factors.data.totp[0] ?? null;
          setAccess(null);
          setMunicipalityContexts([]);
          if (verifiedTotp) {
            setMfaEnrollment(null);
            setMfaFactorId(verifiedTotp.id);
          }
          setStatus(verifiedTotp ? "mfa_required" : "mfa_enrollment_required");
          return null;
        }

        setMfaEnrollment(null);
        setMfaFactorId(null);
        const resolved = await resolveAccess(nextSession.user.id, preferredMunicipalityId);
        if (requestId !== accessRequestRef.current || principalRef.current !== nextPrincipal) {
          return null;
        }
        if (resolved.access?.platformAdmin && resolved.access.municipalityId) {
          storeMunicipalityId(nextSession.user.id, resolved.access.municipalityId);
        }
        setMunicipalityContexts(resolved.municipalityContexts);
        setAccess(resolved.access);
        setStatus(resolved.access ? "ready" : "access_pending");
        return resolved.access;
      } catch (error) {
        if (requestId !== accessRequestRef.current || principalRef.current !== nextPrincipal) {
          return null;
        }
        setAccess(null);
        setMunicipalityContexts([]);
        setErrorCode(safeErrorCode(error));
        setStatus("access_pending");
        return null;
      }
    },
    [queryClient],
  );

  useEffect(() => {
    const demoActive = isDemoMode();
    setDemo(demoActive);
    const passwordSetupHint = Boolean(passwordSetupProofRef.current) || hasPasswordSetupFlowHint();
    recoveryRef.current = false;

    if (demoActive && !passwordSetupHint) {
      setStatus("ready");
      return;
    }
    if (passwordSetupHint) {
      setDemoMode(false);
      setDemo(false);
    }

    const supabase = getSupabaseClient();
    let authEventObserved = false;
    let disposed = false;
    const { data: subscription } = supabase.auth.onAuthStateChange((event, nextSession) => {
      if (disposed) return;
      authEventObserved = true;
      if (localLockoutRef.current && nextSession) return;
      if (
        pendingMunicipalityRef.current &&
        nextSession?.user.id === principalRef.current &&
        (event === "SIGNED_IN" || event === "TOKEN_REFRESHED")
      ) {
        return;
      }
      if (
        event === "PASSWORD_RECOVERY" ||
        passwordSetupProofMatchesSession(passwordSetupProofRef.current, nextSession)
      ) {
        recoveryRef.current = true;
        accessRequestRef.current += 1;
        queryClient.clear();
        principalRef.current = nextSession?.user.id ?? null;
        setSession(nextSession);
        setAccess(null);
        setMunicipalityContexts([]);
        setMfaEnrollment(null);
        setMfaFactorId(null);
        setErrorCode(null);
        setStatus(nextSession ? "password_recovery" : "unauthenticated");
        return;
      }
      if (event === "SIGNED_OUT") recoveryRef.current = false;
      void loadAccess(nextSession);
    });

    void supabase.auth.getSession().then(({ data, error }) => {
      if (disposed || authEventObserved) return;
      if (error) {
        setErrorCode(safeErrorCode(error));
        setStatus("unauthenticated");
        return;
      }
      recoveryRef.current = passwordSetupProofMatchesSession(
        passwordSetupProofRef.current,
        data.session,
      );
      void loadAccess(data.session);
    });
    return () => {
      disposed = true;
      subscription.subscription.unsubscribe();
    };
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
      municipalityContexts: demo
        ? [
            {
              id: "demo-cordeiropolis",
              label: runtimeConfig.municipalityLabel,
              name: "Cordeirópolis",
              stateCode: "SP",
              ibgeCode: runtimeConfig.municipalityIbge,
              role: "fiscal_auditor",
              membershipId: "demo-membership",
            },
          ]
        : municipalityContexts,
      demo,
      errorCode,
      mfaEnrollment,
      async signIn(email, password) {
        setErrorCode(null);
        localLockoutRef.current = false;
        const { error } = await getSupabaseClient().auth.signInWithPassword({ email, password });
        if (error) {
          localLockoutRef.current = true;
          setErrorCode(safeErrorCode(error));
          throw error;
        }
      },
      async signUp(fullName, email, password) {
        setErrorCode(null);
        if (password.length < 12 || password.length > 128) {
          const error = Object.assign(new Error("Senha fora da política"), {
            code: "password_policy_failed",
          });
          setErrorCode(error.code);
          throw error;
        }
        const emailRedirectTo =
          typeof window === "undefined"
            ? undefined
            : new URL("/?signup=confirmed", window.location.origin).toString();
        localLockoutRef.current = false;
        const { error } = await getSupabaseClient().auth.signUp({
          email: email.trim(),
          password,
          options: {
            data: { full_name: fullName.trim() },
            ...(emailRedirectTo ? { emailRedirectTo } : {}),
          },
        });
        if (error) {
          localLockoutRef.current = true;
          setErrorCode(safeErrorCode(error));
          throw error;
        }
      },
      async signOut() {
        localLockoutRef.current = true;
        pendingMunicipalityRef.current = null;
        municipalitySwitchRef.current += 1;
        passwordSetupProofRef.current = null;
        accessRequestRef.current += 1;
        principalRef.current = null;
        recoveryRef.current = false;
        clearPasswordSetupLocation();
        setSession(null);
        setAccess(null);
        setMunicipalityContexts([]);
        setMfaEnrollment(null);
        setMfaFactorId(null);
        setStatus("unauthenticated");
        try {
          await queryClient.cancelQueries();
        } catch (error) {
          setErrorCode(safeErrorCode(error));
        }
        queryClient.clear();
        try {
          const result = await getSupabaseClient().auth.signOut({ scope: "local" });
          if (result.error) setErrorCode(safeErrorCode(result.error));
        } catch (error) {
          setErrorCode(safeErrorCode(error));
        }
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

        localLockoutRef.current = true;
        pendingMunicipalityRef.current = null;
        municipalitySwitchRef.current += 1;
        passwordSetupProofRef.current = null;
        recoveryRef.current = false;
        clearPasswordSetupLocation();
        queryClient.clear();
        accessRequestRef.current += 1;
        principalRef.current = null;
        setSession(null);
        setAccess(null);
        setMunicipalityContexts([]);
        setMfaEnrollment(null);
        setMfaFactorId(null);
        setStatus("unauthenticated");
        try {
          const globalSignOut = await supabase.auth.signOut({ scope: "global" });
          if (!globalSignOut.error) return true;
          setErrorCode(safeErrorCode(globalSignOut.error));
        } catch (error) {
          setErrorCode(safeErrorCode(error));
        }
        try {
          await supabase.auth.signOut({ scope: "local" });
        } catch {
          // A interface já está bloqueada localmente; o próximo login revalida a sessão no servidor.
        }
        return false;
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
      async selectMunicipality(municipalityId) {
        const currentSession = session;
        const authorized = municipalityContexts.find((item) => item.id === municipalityId);
        if (!currentSession || !authorized) {
          const error = Object.assign(new Error("Contexto municipal não autorizado"), {
            code: "municipality_context_denied",
          });
          setErrorCode(error.code);
          throw error;
        }
        if (access?.municipalityId === municipalityId) return authorized;

        const switchId = ++municipalitySwitchRef.current;
        pendingMunicipalityRef.current = municipalityId;
        try {
          setStatus("loading");
          try {
            await queryClient.cancelQueries();
          } catch (error) {
            setErrorCode(safeErrorCode(error));
          }
          queryClient.clear();
          const nextAccess = await loadAccess(currentSession, municipalityId);
          if (switchId !== municipalitySwitchRef.current) {
            throw Object.assign(new Error("Troca municipal substituída"), {
              code: "municipality_context_superseded",
            });
          }
          if (nextAccess?.municipalityId !== municipalityId) {
            throw Object.assign(new Error("Contexto municipal não confirmado"), {
              code: "municipality_context_not_committed",
            });
          }
          return authorized;
        } finally {
          if (switchId === municipalitySwitchRef.current) {
            pendingMunicipalityRef.current = null;
          }
        }
      },
      async reloadAccess() {
        await loadAccess(session);
      },
    }),
    [
      access,
      demo,
      errorCode,
      loadAccess,
      mfaEnrollment,
      mfaFactorId,
      municipalityContexts,
      queryClient,
      session,
      status,
    ],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const value = useContext(AuthContext);
  if (!value) throw new Error("AuthProvider is required");
  return value;
}
