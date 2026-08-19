import { describe, expect, it } from "vitest";

import {
  knowledgeSearchCorsHeaders,
  parseKnowledgeSearchRequest,
  SEARCH_LEXICAL_LANGUAGE,
  SEARCH_RETRIEVAL_MODE,
  SEARCH_SEMANTIC_STATUS,
} from "./policy.ts";

describe("knowledge search request", () => {
  it("accepts a bounded tenant query", async () => {
    await expect(parseKnowledgeSearchRequest(new Request("https://edge.invalid", {
      method: "POST",
      body: JSON.stringify({
        municipality_id: "11111111-1111-4111-8111-111111111111",
        query: "prazo para recolhimento do ISS",
        limit: 6,
      }),
    }))).resolves.toEqual({
      municipalityId: "11111111-1111-4111-8111-111111111111",
      query: "prazo para recolhimento do ISS",
      limit: 6,
    });
  });

  it("declares Portuguese lexical retrieval and the semantic limitation honestly", () => {
    expect(SEARCH_RETRIEVAL_MODE).toBe("lexical_portuguese");
    expect(SEARCH_LEXICAL_LANGUAGE).toBe("pt-BR");
    expect(SEARCH_SEMANTIC_STATUS).toBe("unsupported_language");
  });

  it("allows the live alias and never reflects an arbitrary origin", () => {
    const live = knowledgeSearchCorsHeaders("https://ia-fiscal-homologacao.vercel.app");
    const arbitrary = knowledgeSearchCorsHeaders("https://attacker.invalid");

    expect(live["access-control-allow-origin"]).toBe(
      "https://ia-fiscal-homologacao.vercel.app",
    );
    expect(live["access-control-allow-methods"]).toContain("OPTIONS");
    expect(arbitrary).not.toHaveProperty("access-control-allow-origin");
  });
});
