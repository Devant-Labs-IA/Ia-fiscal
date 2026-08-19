import { describe, expect, it } from "vitest";

import {
  parseEmbedRequest,
  RETIRED_MODEL_REVISION,
} from "./policy.ts";

describe("knowledge embedding contract", () => {
  it("identifies the model revision retained only as audit history", () => {
    expect(RETIRED_MODEL_REVISION).toBe("gte-small-384-v1");
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

  it("preserves the legacy HTTP batch range without turning it into work", async () => {
    const { batchSize } = await parseEmbedRequest(new Request("https://edge.invalid", {
      method: "POST",
      body: JSON.stringify({ batch_size: 32 }),
    }));

    expect(batchSize).toBe(32);
  });
});
