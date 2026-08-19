import { describe, expect, it } from "vitest";

import {
  knowledgeSearchCorsHeaders,
  normalizeSearchEmbedding,
  parseKnowledgeSearchRequest,
  SEARCH_EMBEDDING_DIMENSIONS,
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

  it("requires exactly 384 finite query-vector values", () => {
    expect(SEARCH_EMBEDDING_DIMENSIONS).toBe(384);
    expect(normalizeSearchEmbedding(new Float32Array(384))).toHaveLength(384);
    expect(() => normalizeSearchEmbedding([Number.NaN, ...Array(383).fill(0)])).toThrow();
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
