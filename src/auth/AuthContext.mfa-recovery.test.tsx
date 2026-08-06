// @vitest-environment jsdom

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import type { Session } from "@supabase/supabase-js";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { AuthBoundary } from "@/auth/AuthBoundary";
import { AuthProvider, useAuth } from "@/auth/AuthContext";

const mocks = vi.hoisted(() => ({
  authCallback: null as null | ((event: string, session: Session | null) => void),
  getSession: vi.fn(),
  onAuthStateChange: vi.fn(),
  signInWithPassword: vi.fn(),
  signOut: vi.fn(),
  resetPasswordForEmail: vi.fn(),
  updateUser: vi.fn(),
  getAuthenticatorAssuranceLevel: vi.fn(),
  listFactors: vi.fn(),
  enroll: vi.fn(),
  challenge: vi.fn(),
  verify: vi.fn(),
  unsubscribe: vi.fn(),
  from: vi.fn(),
  tableResults: {} as Record<string, { data: unknown; error: unknown }>,
  builders: [] as Array<{
    table: string;
    eq: ReturnType<typeof vi.fn>;
    not: ReturnType<typeof vi.fn>;
    is: ReturnType<typeof vi.fn>;
    lte: ReturnType<typeof vi.fn>;
    or: ReturnType<typeof vi.fn>;
    order: ReturnType<typeof vi.fn>;
    limit: ReturnType<typeof vi.fn>;
  }>,
}));

vi.mock("@/lib/supabase", () => ({
  getSupabaseClient: () => ({
    auth: {
      getSession: mocks.getSession,
      onAuthStateChange: mocks.onAuthStateChange,
      signInWithPassword: mocks.signInWithPassword,
      signOut: mocks.signOut,
      resetPasswordForEmail: mocks.resetPasswordForEmail,
      updateUser: mocks.updateUser,
      mfa: {
        getAuthenticatorAssuranceLevel: mocks.getAuthenticatorAssuranceLevel,
        listFactors: mocks.listFactors,
        enroll: mocks.enroll,
        challenge: mocks.challenge,
        verify: mocks.verify,
      },
    },
    from: mocks.from,
  }),
}));

function sessionFor(userId = "user-1"): Session {
  return {
    access_token: `token-${userId}`,
    refresh_token: `refresh-${userId}`,
    expires_in: 3600,
    token_type: "bearer",
    user: { id: userId },
  } as Session;
}

function makeQueryBuilder(table: string) {
  const builder = {
    select: vi.fn(),
    eq: vi.fn(),
    not: vi.fn(),
    is: vi.fn(),
    lte: vi.fn(),
    or: vi.fn(),
    order: vi.fn(),
    limit: vi.fn(),
    maybeSingle: vi.fn(),
  };
  builder.select.mockReturnValue(builder);
  builder.eq.mockReturnValue(builder);
  builder.not.mockReturnValue(builder);
  builder.is.mockReturnValue(builder);
  builder.lte.mockReturnValue(builder);
  builder.or.mockReturnValue(builder);
  builder.order.mockReturnValue(builder);
  builder.limit.mockReturnValue(builder);
  builder.maybeSingle.mockImplementation(async () => {
    return mocks.tableResults[table] ?? { data: null, error: null };
  });
  mocks.builders.push({
    table,
    eq: builder.eq,
    not: builder.not,
    is: builder.is,
    lte: builder.lte,
    or: builder.or,
    order: builder.order,
    limit: builder.limit,
  });
  return builder;
}

function Probe() {
  const auth = useAuth();
  return (
    <>
      <output>{auth.status}</output>
      <span>{auth.access?.role ?? "sem-papel"}</span>
      <span>{auth.access?.platformAdmin ? "admin-global" : "admin-escopado"}</span>
      <span>{auth.access?.municipalityId ?? "sem-municipio"}</span>
      <span>{auth.access?.municipalityLabel ?? "sem-rotulo"}</span>
      <span>{auth.mfaEnrollment?.secret ?? "sem-chave"}</span>
      <button type="button" onClick={() => void auth.startMfaEnrollment().catch(() => undefined)}>
        cadastrar mfa
      </button>
      <button type="button" onClick={() => void auth.verifyMfa("123456").catch(() => undefined)}>
        verificar mfa
      </button>
      <button
        type="button"
        onClick={() =>
          void auth.updateRecoveredPassword("uma-senha-segura-123").catch(() => undefined)
        }
      >
        trocar senha
      </button>
      <button
        type="button"
        onClick={() => void auth.requestPasswordReset("fiscal@example.com").catch(() => undefined)}
      >
        recuperar senha
      </button>
    </>
  );
}

function renderProvider(children = <Probe />) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <AuthProvider>{children}</AuthProvider>
    </QueryClientProvider>,
  );
  return queryClient;
}

const AAL1 = {
  data: { currentLevel: "aal1", nextLevel: "aal1", currentAuthenticationMethods: ["password"] },
  error: null,
};

const AAL2 = {
  data: {
    currentLevel: "aal2",
    nextLevel: "aal2",
    currentAuthenticationMethods: ["password", "totp"],
  },
  error: null,
};

beforeEach(() => {
  window.sessionStorage.clear();
  window.history.replaceState({}, "", "/");
  mocks.authCallback = null;
  mocks.builders.length = 0;
  mocks.tableResults = {};
  mocks.getSession.mockReset().mockResolvedValue({ data: { session: null }, error: null });
  mocks.onAuthStateChange.mockReset().mockImplementation((callback) => {
    mocks.authCallback = callback;
    return { data: { subscription: { unsubscribe: mocks.unsubscribe } } };
  });
  mocks.signInWithPassword.mockReset().mockResolvedValue({ error: null });
  mocks.signOut.mockReset().mockResolvedValue({ error: null });
  mocks.resetPasswordForEmail.mockReset().mockResolvedValue({ error: null });
  mocks.updateUser.mockReset().mockResolvedValue({ data: { user: null }, error: null });
  mocks.getAuthenticatorAssuranceLevel.mockReset().mockResolvedValue(AAL2);
  mocks.listFactors.mockReset().mockResolvedValue({
    data: { all: [], totp: [], phone: [], webauthn: [] },
    error: null,
  });
  mocks.enroll.mockReset().mockResolvedValue({
    data: {
      id: "factor-new",
      type: "totp",
      totp: { qr_code: "<svg></svg>", secret: "TOTP-SECRET", uri: "otpauth://totp/test" },
    },
    error: null,
  });
  mocks.challenge.mockReset().mockResolvedValue({
    data: { id: "challenge-1", type: "totp", expires_at: 123 },
    error: null,
  });
  mocks.verify.mockReset().mockResolvedValue({ data: {}, error: null });
  mocks.unsubscribe.mockReset();
  mocks.from.mockReset().mockImplementation((table) => makeQueryBuilder(String(table)));
});

afterEach(() => cleanup());

describe("gate MFA e recuperação de senha", () => {
  it("impede acesso AAL1, cadastra TOTP e só libera depois de challenge + verify", async () => {
    const session = sessionFor();
    mocks.getSession.mockResolvedValue({ data: { session }, error: null });
    mocks.getAuthenticatorAssuranceLevel.mockResolvedValueOnce(AAL1).mockResolvedValue(AAL2);
    mocks.tableResults["municipality_memberships"] = {
      data: {
        id: "membership-1",
        municipality_id: "municipality-1",
        role: "fiscal_auditor",
      },
      error: null,
    };
    mocks.tableResults["municipalities"] = {
      data: { id: "municipality-1", name: "Cordeirópolis", state_code: "SP" },
      error: null,
    };

    renderProvider();
    await screen.findByText("mfa_enrollment_required");
    expect(screen.queryByText("ready")).toBeNull();

    fireEvent.click(screen.getByRole("button", { name: "cadastrar mfa" }));
    await screen.findByText("TOTP-SECRET");
    expect(mocks.enroll).toHaveBeenCalledWith({
      factorType: "totp",
      friendlyName: "IA Fiscal",
      issuer: "IA Fiscal",
    });

    fireEvent.click(screen.getByRole("button", { name: "verificar mfa" }));
    await screen.findByText("ready");
    expect(mocks.challenge).toHaveBeenCalledWith({ factorId: "factor-new" });
    expect(mocks.verify).toHaveBeenCalledWith({
      factorId: "factor-new",
      challengeId: "challenge-1",
      code: "123456",
    });
  });

  it("exibe o desafio para um fator TOTP já verificado", async () => {
    const session = sessionFor();
    mocks.getSession.mockResolvedValue({ data: { session }, error: null });
    mocks.getAuthenticatorAssuranceLevel.mockResolvedValue(AAL1);
    mocks.listFactors.mockResolvedValue({
      data: {
        all: [{ id: "factor-existing", factor_type: "totp", status: "verified" }],
        totp: [{ id: "factor-existing", factor_type: "totp", status: "verified" }],
        phone: [],
        webauthn: [],
      },
      error: null,
    });

    renderProvider();
    await screen.findByText("mfa_required");
    expect(mocks.enroll).not.toHaveBeenCalled();
  });

  it("trata PASSWORD_RECOVERY, atualiza a senha e encerra sessões globalmente", async () => {
    renderProvider();
    await screen.findByText("unauthenticated");

    await act(async () => {
      mocks.authCallback?.("PASSWORD_RECOVERY", sessionFor());
    });
    await screen.findByText("password_recovery");

    fireEvent.click(screen.getByRole("button", { name: "trocar senha" }));
    await screen.findByText("unauthenticated");
    expect(mocks.updateUser).toHaveBeenCalledWith({ password: "uma-senha-segura-123" });
    expect(mocks.signOut).toHaveBeenCalledWith({ scope: "global" });
  });

  it("trata type=invite como configuração de senha antes do MFA", async () => {
    const session = sessionFor();
    window.history.replaceState(
      {},
      "",
      "/#access_token=invite-token&refresh_token=invite-refresh&type=invite",
    );
    mocks.getSession.mockResolvedValue({ data: { session }, error: null });

    renderProvider();
    await screen.findByText("password_recovery");
    expect(mocks.getAuthenticatorAssuranceLevel).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole("button", { name: "trocar senha" }));
    await screen.findByText("unauthenticated");
    expect(mocks.updateUser).toHaveBeenCalledWith({ password: "uma-senha-segura-123" });
    expect(mocks.signOut).toHaveBeenCalledWith({ scope: "global" });
    expect(window.location.hash).toBe("");
  });

  it("gera link de recuperação com marcador dedicado", async () => {
    renderProvider();
    await screen.findByText("unauthenticated");
    fireEvent.click(screen.getByRole("button", { name: "recuperar senha" }));

    await waitFor(() =>
      expect(mocks.resetPasswordForEmail).toHaveBeenCalledWith("fiscal@example.com", {
        redirectTo: "http://localhost:3000/?recovery=1",
      }),
    );
  });

  it("aplica validade temporal e verificação a todos os tipos de vínculo", async () => {
    const session = sessionFor();
    mocks.getSession.mockResolvedValue({ data: { session }, error: null });
    mocks.tableResults["municipalities"] = {
      data: { id: "municipality-1", name: "Cordeirópolis", state_code: "SP" },
      error: null,
    };
    mocks.tableResults["accountant_user_links"] = {
      data: { municipality_id: "municipality-1", accounting_firm_id: "firm-1" },
      error: null,
    };

    renderProvider();
    await screen.findByText("ready");

    expect(mocks.builders.map(({ table }) => table)).toEqual([
      "platform_administrators",
      "municipalities",
      "municipality_memberships",
      "taxpayer_user_links",
      "accountant_user_links",
    ]);
    for (const builder of mocks.builders.filter(
      ({ table }) => !["platform_administrators", "municipalities"].includes(table),
    )) {
      expect(builder.lte).toHaveBeenCalledWith("valid_from", expect.any(String));
      expect(builder.or).toHaveBeenCalledWith(
        expect.stringMatching(/^valid_until\.is\.null,valid_until\.gt\./),
      );
    }
    expect(
      mocks.builders.find((builder) => builder.table === "platform_administrators")?.is,
    ).toHaveBeenCalledWith("revoked_at", null);
    for (const table of ["taxpayer_user_links", "accountant_user_links"]) {
      expect(mocks.builders.find((builder) => builder.table === table)?.not).toHaveBeenCalledWith(
        "verified_at",
        "is",
        null,
      );
    }
    expect(
      mocks.builders.find((builder) => builder.table === "taxpayer_user_links")?.order,
    ).toHaveBeenCalledWith("taxpayer_id", { ascending: true });
    expect(
      mocks.builders.find((builder) => builder.table === "accountant_user_links")?.order,
    ).toHaveBeenCalledWith("accounting_firm_id", { ascending: true });
  });

  it("resolve o tenant configurado de forma determinística para usuário multi-município", async () => {
    mocks.getSession.mockResolvedValue({ data: { session: sessionFor() }, error: null });
    mocks.tableResults["municipalities"] = {
      data: {
        id: "municipality-cordeiropolis",
        name: "Cordeirópolis",
        state_code: "SP",
      },
      error: null,
    };
    mocks.tableResults["municipality_memberships"] = {
      data: {
        id: "membership-cordeiropolis",
        municipality_id: "municipality-cordeiropolis",
        role: "fiscal_auditor",
      },
      error: null,
    };

    renderProvider();
    await screen.findByText("ready");
    expect(screen.getByText("fiscal_auditor")).toBeTruthy();
    expect(screen.getByText("municipality-cordeiropolis")).toBeTruthy();
    expect(screen.getByText("Cordeirópolis/SP")).toBeTruthy();

    const municipalityQuery = mocks.builders.find(({ table }) => table === "municipalities");
    expect(municipalityQuery?.eq).toHaveBeenCalledWith("ibge_code", "3512407");

    const membershipQuery = mocks.builders.find(
      ({ table }) => table === "municipality_memberships",
    );
    expect(membershipQuery?.eq).toHaveBeenCalledWith(
      "municipality_id",
      "municipality-cordeiropolis",
    );
    expect(membershipQuery?.limit).not.toHaveBeenCalled();
  });

  it("resolve administrador técnico sem atribuir um vínculo fiscal municipal", async () => {
    mocks.getSession.mockResolvedValue({ data: { session: sessionFor() }, error: null });
    mocks.tableResults["platform_administrators"] = {
      data: { user_id: "user-1" },
      error: null,
    };

    renderProvider();
    await screen.findByText("ready");
    expect(screen.getByText("platform_admin")).toBeTruthy();
    expect(screen.getByText("admin-global")).toBeTruthy();
    expect(mocks.builders.map(({ table }) => table)).toEqual([
      "platform_administrators",
      "municipalities",
    ]);
  });

  it("combina administração global com vínculo municipal explícito", async () => {
    mocks.getSession.mockResolvedValue({ data: { session: sessionFor() }, error: null });
    mocks.tableResults["platform_administrators"] = {
      data: { user_id: "user-1" },
      error: null,
    };
    mocks.tableResults["municipalities"] = {
      data: { id: "municipality-1", name: "Cordeirópolis", state_code: "SP" },
      error: null,
    };
    mocks.tableResults["municipality_memberships"] = {
      data: {
        id: "membership-global",
        municipality_id: "municipality-1",
        role: "municipal_admin",
      },
      error: null,
    };

    renderProvider();
    await screen.findByText("ready");
    expect(screen.getByText("municipal_admin")).toBeTruthy();
    expect(screen.getByText("admin-global")).toBeTruthy();
    expect(screen.getByText("municipality-1")).toBeTruthy();
  });

  it("renderiza a tela de cadastro MFA antes de qualquer conteúdo protegido", async () => {
    mocks.getSession.mockResolvedValue({ data: { session: sessionFor() }, error: null });
    mocks.getAuthenticatorAssuranceLevel.mockResolvedValue(AAL1);
    renderProvider(
      <AuthBoundary>
        <p>conteúdo protegido</p>
      </AuthBoundary>,
    );

    expect(await screen.findByRole("heading", { name: "Proteja seu acesso" })).toBeTruthy();
    expect(screen.queryByText("conteúdo protegido")).toBeNull();
  });
});
