import { beforeEach, describe, expect, it, vi } from "vitest";

import { supabaseFiscalService } from "@/services/supabase-fiscal-service";

const mocks = vi.hoisted(() => ({ rpc: vi.fn() }));

vi.mock("@/lib/supabase", () => ({
  getSupabaseClient: () => ({ rpc: mocks.rpc }),
}));

beforeEach(() => mocks.rpc.mockReset());

describe("gestão interna de usuários municipais", () => {
  it("lista e traduz o diretório retornado pela RPC administrativa", async () => {
    mocks.rpc.mockResolvedValue({
      data: [
        {
          membership_id: "membership-1",
          user_id: "user-1",
          full_name: "Fiscal Teste",
          email: "fiscal@prefeitura.gov.br",
          role: "fiscal_auditor",
          status: "active",
          valid_from: "2026-08-01T10:00:00Z",
          valid_until: null,
          last_seen_at: "2026-08-11T10:00:00Z",
        },
      ],
      error: null,
    });

    const users = await supabaseFiscalService.listMunicipalityUsers("municipality-1");

    expect(mocks.rpc).toHaveBeenCalledWith("ia_list_municipality_users", {
      p_municipality_id: "municipality-1",
    });
    expect(users[0]).toEqual({
      membershipId: "membership-1",
      userId: "user-1",
      fullName: "Fiscal Teste",
      email: "fiscal@prefeitura.gov.br",
      role: "fiscal_auditor",
      status: "active",
      validFrom: "2026-08-01T10:00:00Z",
      validUntil: null,
      lastSeenAt: "2026-08-11T10:00:00Z",
    });
  });

  it("vincula somente conta existente sem acionar qualquer envio", async () => {
    mocks.rpc.mockResolvedValue({ data: "membership-2", error: null });

    await expect(
      supabaseFiscalService.addExistingMunicipalityUser(
        "municipality-1",
        "  Fiscal@Prefeitura.gov.br ",
        "fiscal_auditor",
      ),
    ).resolves.toBe("membership-2");

    expect(mocks.rpc).toHaveBeenCalledWith("ia_add_existing_municipality_user", {
      p_municipality_id: "municipality-1",
      p_email: "fiscal@prefeitura.gov.br",
      p_role: "fiscal_auditor",
    });
  });

  it("atualiza papel e situação dentro do município selecionado", async () => {
    mocks.rpc.mockResolvedValue({ data: "membership-2", error: null });

    await expect(
      supabaseFiscalService.updateMunicipalityMembership(
        "municipality-1",
        "membership-2",
        "supervisor",
        "suspended",
      ),
    ).resolves.toBe("membership-2");

    expect(mocks.rpc).toHaveBeenCalledWith("ia_update_municipality_membership", {
      p_municipality_id: "municipality-1",
      p_membership_id: "membership-2",
      p_role: "supervisor",
      p_status: "suspended",
    });
  });
});
