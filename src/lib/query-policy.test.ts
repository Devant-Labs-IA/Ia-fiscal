import { describe, expect, it } from "vitest";

import { fiscalQueryErrorMessage, shouldRetryFiscalQuery } from "@/lib/query-policy";

describe("política de consultas fiscais", () => {
  it("repete uma única vez apenas falhas transitórias", () => {
    expect(shouldRetryFiscalQuery(0, new TypeError("Failed to fetch"))).toBe(true);
    expect(shouldRetryFiscalQuery(1, new TypeError("Failed to fetch"))).toBe(false);
    expect(shouldRetryFiscalQuery(0, { code: "503" })).toBe(true);
    expect(shouldRetryFiscalQuery(0, { code: "42883" })).toBe(false);
  });

  it("apresenta timeout com linguagem acionável", () => {
    expect(fiscalQueryErrorMessage({ code: "query_timeout" }, "Falha genérica")).toBe(
      "A consulta demorou mais do que o esperado. Tente novamente.",
    );
  });
});
