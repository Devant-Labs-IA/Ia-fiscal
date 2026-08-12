import { beforeEach, describe, expect, it, vi } from "vitest";

import { supabaseFiscalService } from "@/services/supabase-fiscal-service";

const mocks = vi.hoisted(() => ({
  from: vi.fn(),
}));

vi.mock("@/lib/supabase", () => ({
  getSupabaseClient: () => ({ from: mocks.from }),
}));

function createWriteChain(returnedId = "taxpayer-1") {
  const chain = {
    insert: vi.fn(),
    update: vi.fn(),
    select: vi.fn(),
    eq: vi.fn(),
    single: vi.fn().mockResolvedValue({ data: { id: returnedId }, error: null }),
  };
  chain.insert.mockReturnValue(chain);
  chain.update.mockReturnValue(chain);
  chain.select.mockReturnValue(chain);
  chain.eq.mockReturnValue(chain);
  return chain;
}

const validInput = {
  municipalRegistration: " 12345 ",
  taxId: "12.345.678/0001-90",
  legalName: " Contribuinte Teste Ltda. ",
  tradeName: " Teste ",
  taxpayerType: "company" as const,
};

beforeEach(() => mocks.from.mockReset());

describe("escritas municipais de contribuinte", () => {
  it("cadastra com município explícito e dados normalizados", async () => {
    const chain = createWriteChain();
    mocks.from.mockReturnValue(chain);

    await expect(supabaseFiscalService.createTaxpayer("municipality-1", validInput)).resolves.toBe(
      "taxpayer-1",
    );

    expect(mocks.from).toHaveBeenCalledWith("taxpayers");
    expect(chain.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        municipality_id: "municipality-1",
        municipal_registration: "12345",
        tax_id: "12345678000190",
        legal_name: "Contribuinte Teste Ltda.",
        status: "active",
      }),
    );
  });

  it("edita somente o identificador dentro do município esperado", async () => {
    const chain = createWriteChain();
    mocks.from.mockReturnValue(chain);

    await supabaseFiscalService.updateTaxpayer("municipality-1", "taxpayer-1", validInput);

    expect(chain.eq).toHaveBeenCalledWith("municipality_id", "municipality-1");
    expect(chain.eq).toHaveBeenCalledWith("id", "taxpayer-1");
  });

  it("arquiva por atualização de status e nunca executa remoção física", async () => {
    const chain = createWriteChain();
    mocks.from.mockReturnValue(chain);

    await supabaseFiscalService.archiveTaxpayer("municipality-1", "taxpayer-1");

    expect(chain.update).toHaveBeenCalledWith(expect.objectContaining({ status: "inactive" }));
    expect(chain.eq).toHaveBeenCalledWith("municipality_id", "municipality-1");
    expect(chain.eq).toHaveBeenCalledWith("id", "taxpayer-1");
    expect("delete" in chain).toBe(false);
  });

  it("rejeita entrada inválida antes de acessar o banco", async () => {
    await expect(
      supabaseFiscalService.createTaxpayer("municipality-1", {
        ...validInput,
        taxId: "123",
      }),
    ).rejects.toThrow("invalid_taxpayer_input");
    expect(mocks.from).not.toHaveBeenCalled();
  });
});
