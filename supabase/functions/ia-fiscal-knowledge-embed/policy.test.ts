import { describe, expect, it } from "vitest";

import {
  EMBEDDING_DIMENSIONS,
  EMBEDDING_MODEL_REVISION,
  normalizeEmbedding,
  parseEmbedRequest,
} from "./policy.ts";

describe("knowledge embedding contract", () => {
  it("pins the model revision and exactly 384 values", () => {
    expect(EMBEDDING_MODEL_REVISION).toBe("gte-small-384-v1");
    expect(EMBEDDING_DIMENSIONS).toBe(384);
    expect(normalizeEmbedding(Array.from({ length: 384 }, () => 0.25))).toHaveLength(384);
    expect(() => normalizeEmbedding([0.1, 0.2])).toThrowError(
      expect.objectContaining({ code: "embedding_contract_invalid" }),
    );
  });

  it("accepts only a bounded batch size", async () => {
    await expect(parseEmbedRequest(new Request("https://edge.invalid", {
      method: "POST",
      body: JSON.stringify({ batch_size: 8 }),
    }))).resolves.toEqual({ batchSize: 8 });
    await expect(parseEmbedRequest(new Request("https://edge.invalid", {
      method: "POST",
      body: JSON.stringify({ batch_size: 33 }),
    }))).rejects.toMatchObject({ code: "invalid_batch_size" });
  });
});
