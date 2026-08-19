import { describe, expect, it } from "vitest";

import {
  assertCompletionTextHashes,
  assertGithubOidcClaims,
  buildOidcContext,
  buildPartStoragePath,
  GITHUB_OIDC_POLICY,
  MAX_TOTAL_CHARACTERS,
  OCR_CONTRACT_VERSION,
  OcrPolicyError,
  parseCompletionPageReferences,
  parseEnvelope,
  type CompletionPage,
} from "./policy";

const now = 1_787_000_000;

function validClaims(): Record<string, unknown> {
  return {
    aud: GITHUB_OIDC_POLICY.audience,
    iss: GITHUB_OIDC_POLICY.issuer,
    sub: GITHUB_OIDC_POLICY.subject,
    repository: GITHUB_OIDC_POLICY.repository,
    repository_id: GITHUB_OIDC_POLICY.repositoryId,
    repository_owner: GITHUB_OIDC_POLICY.repositoryOwner,
    repository_owner_id: GITHUB_OIDC_POLICY.repositoryOwnerId,
    repository_visibility: "private",
    runner_environment: "github-hosted",
    ref: GITHUB_OIDC_POLICY.ref,
    ref_type: "branch",
    environment: GITHUB_OIDC_POLICY.environment,
    workflow_ref: GITHUB_OIDC_POLICY.workflowRef,
    workflow_sha: "a".repeat(40),
    event_name: "workflow_dispatch",
    run_id: "123456789",
    run_attempt: "2",
    jti: "unique-jti-value",
    iat: now - 30,
    nbf: now - 30,
    exp: now + 300,
  };
}

describe("GitHub OIDC policy", () => {
  it("accepts only the immutable repository subject and IDs", async () => {
    const identity = assertGithubOidcClaims(validClaims(), { alg: "RS256", typ: "JWT" }, now);
    expect(identity.subject).toBe(
      "repo:AlmoreContabilidade@296187202/Ia-fiscal@1320619695:environment:knowledge-ocr",
    );
    const context = await buildOidcContext(identity, "complete");
    expect(context).toMatchObject({
      action: "complete",
      repository_id: "1320619695",
      repository_owner_id: "296187202",
      runner_environment: "github-hosted",
    });
    expect(context.subject_sha256).toBe(
      "6458d6e7ba5d2430f62ac326d74561853af077abeddc00eb96763a08b78fd005",
    );
  });

  it.each([
    ["aud", "wrong-audience"],
    ["repository", "attacker/repository"],
    ["repository_id", "1"],
    ["repository_owner", "attacker"],
    ["repository_owner_id", "1"],
    ["repository_visibility", "public"],
    ["runner_environment", "self-hosted"],
    ["ref", "refs/heads/feature"],
    ["environment", "production"],
    ["workflow_ref", "AlmoreContabilidade/Ia-fiscal/.github/workflows/other.yml@refs/heads/main"],
    ["workflow_sha", "b".repeat(39)],
    ["event_name", "pull_request"],
    ["sub", "repo:AlmoreContabilidade/Ia-fiscal:environment:knowledge-ocr"],
  ])("rejects a mismatched %s claim", (claim, value) => {
    expect(() =>
      assertGithubOidcClaims({ ...validClaims(), [claim]: value }, { alg: "RS256" }, now),
    ).toThrowError(new OcrPolicyError("github_oidc_claims_rejected", 403));
  });
});

describe("OCR completion references", () => {
  const jobId = "123e4567-e89b-42d3-a456-426614174000";
  const artifactSha = "b".repeat(64);
  const storageRef = buildPartStoragePath(jobId, 2, "page", 1, artifactSha);

  it("accepts references only and rejects duplicated page text in the request", () => {
    const references = parseCompletionPageReferences(
      [
        {
          page_number: 1,
          artifact: { storage_ref: storageRef, sha256: artifactSha, byte_size: 100 },
        },
      ],
      jobId,
      2,
    );
    expect(references[0]?.storage_path).toBe(storageRef);
    expect(() =>
      parseCompletionPageReferences(
        [
          {
            page_number: 1,
            content_text: "must not cross the gateway",
            artifact: { storage_ref: storageRef, sha256: artifactSha, byte_size: 100 },
          },
        ],
        jobId,
        2,
      ),
    ).toThrowError(/ocr_page_reference_invalid/);
  });

  it("recomputes the consolidated content hash from server-derived pages", async () => {
    const text = "Lei municipal integral";
    const textHash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
    const sha = Array.from(new Uint8Array(textHash), (byte) =>
      byte.toString(16).padStart(2, "0"),
    ).join("");
    const pages: CompletionPage[] = [
      {
        page_number: 1,
        content_text: text,
        text_sha256: sha,
        confidence_milli: 800,
        confidence_samples: 4,
        character_count: text.length,
        utf8_bytes: text.length,
        word_count: 3,
        storage_path: storageRef,
        artifact_sha256: artifactSha,
        artifact_byte_size: 100,
      },
    ];
    expect(await assertCompletionTextHashes(pages)).toBe(sha);
    expect(MAX_TOTAL_CHARACTERS).toBe(8_000_000);
  });
});

describe("request envelope", () => {
  it("maps only the frozen v1 action set", () => {
    expect(parseEnvelope({ contract_version: OCR_CONTRACT_VERSION, action: "claim" }).action).toBe(
      "claim",
    );
    expect(() =>
      parseEnvelope({ contract_version: OCR_CONTRACT_VERSION, action: "publish" }),
    ).toThrowError(/ocr_action_invalid/);
  });
});
