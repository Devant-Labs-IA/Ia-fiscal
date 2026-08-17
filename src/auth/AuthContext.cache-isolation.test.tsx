// @vitest-environment jsdom

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import type { Session } from "@supabase/supabase-js";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { AuthProvider, useAuth } from "@/auth/AuthContext";
import { fiscalKeys } from "@/services/fiscal-service";

const mocks = vi.hoisted(() => ({
  authCallback: null as null | ((event: string, session: unknown) => void),
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

function queryBuilder() {
  const builder = {
    select: vi.fn(),
    eq: vi.fn(),
    not: vi.fn(),
    is: vi.fn(),
    lte: vi.fn(),
    or: vi.fn(),
    order: vi.fn(),
    limit: vi.fn(),
    maybeSingle: vi.fn().mockResolvedValue({ data: null, error: null }),
  };
  builder.select.mockReturnValue(builder);
  builder.eq.mockReturnValue(builder);
  builder.not.mockReturnValue(builder);
  builder.is.mockReturnValue(builder);
  builder.lte.mockReturnValue(builder);
  builder.or.mockReturnValue(builder);
  builder.order.mockReturnValue(builder);
  builder.limit.mockReturnValue(builder);
  return builder;
}

function sessionFor(userId: string): Session {
  return {
    access_token: `token-${userId}`,
    refresh_token: `refresh-${userId}`,
    expires_in: 3600,
    token_type: "bearer",
    user: { id: userId },
  } as Session;
}

function Probe() {
  const auth = useAuth();
  return (
    <>
      <output>{auth.status}</output>
      <button type="button" onClick={() => void auth.signOut()}>
        sair
      </button>
      <button type="button" onClick={auth.enterDemo}>
        entrar demo
      </button>
      <button type="button" onClick={auth.leaveDemo}>
        sair demo
      </button>
    </>
  );
}

function renderProvider() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  render(
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <Probe />
      </AuthProvider>
    </QueryClientProvider>,
  );
  return queryClient;
}

beforeEach(() => {
  window.sessionStorage.clear();
  mocks.authCallback = null;
  mocks.getSession.mockReset().mockResolvedValue({ data: { session: null }, error: null });
  mocks.signOut.mockReset().mockResolvedValue({ error: null });
  mocks.signInWithPassword.mockReset().mockResolvedValue({ error: null });
  mocks.resetPasswordForEmail.mockReset().mockResolvedValue({ error: null });
  mocks.updateUser.mockReset().mockResolvedValue({ data: { user: null }, error: null });
  mocks.getAuthenticatorAssuranceLevel.mockReset().mockResolvedValue({
    data: { currentLevel: "aal2", nextLevel: "aal2", currentAuthenticationMethods: [] },
    error: null,
  });
  mocks.listFactors.mockReset().mockResolvedValue({
    data: { all: [], totp: [], phone: [], webauthn: [] },
    error: null,
  });
  mocks.enroll.mockReset();
  mocks.challenge.mockReset();
  mocks.verify.mockReset();
  mocks.unsubscribe.mockReset();
  mocks.from.mockReset().mockImplementation(() => queryBuilder());
  mocks.onAuthStateChange.mockReset().mockImplementation((callback) => {
    mocks.authCallback = callback;
    return { data: { subscription: { unsubscribe: mocks.unsubscribe } } };
  });
});

afterEach(() => {
  cleanup();
});

describe("isolamento do cache fiscal por identidade", () => {
  it("remove dados fiscais antes do logout", async () => {
    const queryClient = renderProvider();
    await screen.findByText("unauthenticated");
    queryClient.setQueryData(fiscalKeys.cases("municipality-1"), [{ caseNumber: "sigiloso-A" }]);

    fireEvent.click(screen.getByRole("button", { name: "sair" }));

    await waitFor(() =>
      expect(queryClient.getQueryData(fiscalKeys.cases("municipality-1"))).toBeUndefined(),
    );
    expect(mocks.signOut).toHaveBeenCalledWith({ scope: "local" });
  });

  it("remove o cache ao entrar e sair da demonstração", async () => {
    const queryClient = renderProvider();
    await screen.findByText("unauthenticated");
    queryClient.setQueryData(fiscalKeys.cases("municipality-1"), [{ caseNumber: "sigiloso-A" }]);

    fireEvent.click(screen.getByRole("button", { name: "entrar demo" }));
    expect(queryClient.getQueryData(fiscalKeys.cases("municipality-1"))).toBeUndefined();
    expect(window.sessionStorage.getItem("ia-fiscal:demo-mode")).toBeNull();

    queryClient.setQueryData(fiscalKeys.cases("municipality-1"), [{ caseNumber: "demo" }]);
    fireEvent.click(screen.getByRole("button", { name: "sair demo" }));
    expect(queryClient.getQueryData(fiscalKeys.cases("municipality-1"))).toBeUndefined();
  });

  it("limpa o principal anterior antes de resolver uma nova sessão", async () => {
    const queryClient = renderProvider();
    await screen.findByText("unauthenticated");

    await act(async () => {
      mocks.authCallback?.("SIGNED_IN", sessionFor("usuario-A"));
    });
    await screen.findByText("access_pending");
    queryClient.setQueryData(fiscalKeys.cases("municipality-1"), [{ caseNumber: "sigiloso-A" }]);

    act(() => {
      mocks.authCallback?.("SIGNED_IN", sessionFor("usuario-B"));
    });

    expect(queryClient.getQueryData(fiscalKeys.cases("municipality-1"))).toBeUndefined();
  });
});
