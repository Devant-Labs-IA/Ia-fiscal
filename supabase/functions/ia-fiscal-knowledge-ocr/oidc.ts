import { createRemoteJWKSet, jwtVerify } from "jose";

import {
  assertGithubOidcClaims,
  GITHUB_OIDC_POLICY,
  type GithubOidcIdentity,
  OcrPolicyError,
} from "./policy.ts";

const githubJwks = createRemoteJWKSet(new URL(GITHUB_OIDC_POLICY.jwksUrl), {
  timeoutDuration: 5_000,
  cooldownDuration: 30_000,
  cacheMaxAge: 10 * 60_000,
});

export async function authenticateGithubOidc(request: Request): Promise<GithubOidcIdentity> {
  const authorization = request.headers.get("authorization")?.trim() ?? "";
  if (!authorization.startsWith("Bearer ")) {
    throw new OcrPolicyError("github_oidc_required", 401);
  }
  const token = authorization.slice("Bearer ".length).trim();
  if (!token || token.length > 16_384) {
    throw new OcrPolicyError("github_oidc_invalid", 401);
  }
  try {
    const result = await jwtVerify(token, githubJwks, {
      issuer: GITHUB_OIDC_POLICY.issuer,
      audience: GITHUB_OIDC_POLICY.audience,
      algorithms: ["RS256"],
      clockTolerance: 30,
      maxTokenAge: "10 minutes",
    });
    return assertGithubOidcClaims(
      result.payload as Record<string, unknown>,
      result.protectedHeader as Record<string, unknown>,
    );
  } catch (error) {
    if (error instanceof OcrPolicyError) throw error;
    throw new OcrPolicyError("github_oidc_invalid", 401);
  }
}
