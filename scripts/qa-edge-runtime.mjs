import { createHmac } from "node:crypto";
import { createInterface } from "node:readline";

import { createClient } from "@supabase/supabase-js";

function decodeBase32(value) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits = "";
  for (const character of value.replace(/=+$/u, "").toUpperCase()) {
    const index = alphabet.indexOf(character);
    if (index < 0) throw new Error("invalid_totp_secret");
    bits += index.toString(2).padStart(5, "0");
  }
  const bytes = [];
  for (let offset = 0; offset + 8 <= bits.length; offset += 8) {
    bytes.push(Number.parseInt(bits.slice(offset, offset + 8), 2));
  }
  return Buffer.from(bytes);
}

function totp(secret, timestamp = Date.now()) {
  const counter = Math.floor(timestamp / 30_000);
  const message = Buffer.alloc(8);
  message.writeBigUInt64BE(BigInt(counter));
  const digest = createHmac("sha1", decodeBase32(secret)).update(message).digest();
  const offset = digest.at(-1) & 0x0f;
  const binary =
    ((digest[offset] & 0x7f) << 24) |
    ((digest[offset + 1] & 0xff) << 16) |
    ((digest[offset + 2] & 0xff) << 8) |
    (digest[offset + 3] & 0xff);
  return String(binary % 1_000_000).padStart(6, "0");
}

async function readConfiguration() {
  const reader = createInterface({ input: process.stdin, terminal: false });
  const [line] = await new Promise((resolve, reject) => {
    reader.once("line", (...args) => resolve(args));
    reader.once("error", reject);
  });
  reader.close();
  return JSON.parse(line);
}

async function invoke(functionUrl, publishableKey, token, municipalityId) {
  const response = await fetch(functionUrl, {
    method: "POST",
    headers: {
      apikey: publishableKey,
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      "content-type": "application/json",
    },
    body: JSON.stringify({ municipality_id: municipalityId, query: "ISS", limit: 5 }),
  });
  const payload = await response.json().catch(() => ({}));
  return {
    status: response.status,
    error: typeof payload.error === "string" ? payload.error : null,
    contractVersion: typeof payload.contract_version === "string" ? payload.contract_version : null,
    resultCount: Array.isArray(payload.data) ? payload.data.length : null,
  };
}

function expectResult(actual, expectedStatus, expectedError = null) {
  if (actual.status !== expectedStatus || actual.error !== expectedError) {
    throw new Error(
      `unexpected_edge_result:${JSON.stringify({ actual, expectedStatus, expectedError })}`,
    );
  }
}

const config = await readConfiguration();
const client = createClient(config.supabaseUrl, config.publishableKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const noToken = await invoke(
  config.functionUrl,
  config.publishableKey,
  null,
  config.authorizedMunicipalityId,
);
if (noToken.status !== 401) throw new Error(`missing_token_not_denied:${noToken.status}`);

const signedIn = await client.auth.signInWithPassword({
  email: config.email,
  password: config.password,
});
if (signedIn.error || !signedIn.data.session) {
  throw new Error(`password_login_failed:${signedIn.error?.code ?? "no_session"}`);
}
const aal1Token = signedIn.data.session.access_token;

const tokenParts = aal1Token.split(".");
if (tokenParts.length !== 3 || tokenParts[2].length < 2) throw new Error("unexpected_jwt_shape");
tokenParts[2] = `${tokenParts[2][0] === "a" ? "b" : "a"}${tokenParts[2].slice(1)}`;
const invalidToken = tokenParts.join(".");
const altered = await invoke(
  config.functionUrl,
  config.publishableKey,
  invalidToken,
  config.authorizedMunicipalityId,
);
if (altered.status !== 401) throw new Error(`altered_token_not_denied:${altered.status}`);

const aal1 = await invoke(
  config.functionUrl,
  config.publishableKey,
  aal1Token,
  config.authorizedMunicipalityId,
);
expectResult(aal1, 403, "aal2_required");

const factors = await client.auth.mfa.listFactors();
if (factors.error) throw new Error(`factor_list_failed:${factors.error.code}`);
const factor = factors.data.totp.find(({ status }) => status === "verified");
if (!factor) throw new Error("verified_totp_factor_missing");

const challenge = await client.auth.mfa.challenge({ factorId: factor.id });
if (challenge.error) throw new Error(`mfa_challenge_failed:${challenge.error.code}`);
const verified = await client.auth.mfa.verify({
  factorId: factor.id,
  challengeId: challenge.data.id,
  code: totp(config.totpSecret),
});
if (verified.error || !verified.data.access_token) {
  throw new Error(`mfa_verify_failed:${verified.error?.code ?? "no_token"}`);
}
const aal2Token = verified.data.access_token;

const authorized = await invoke(
  config.functionUrl,
  config.publishableKey,
  aal2Token,
  config.authorizedMunicipalityId,
);
expectResult(authorized, 200);

const wrongTenant = await invoke(
  config.functionUrl,
  config.publishableKey,
  aal2Token,
  config.deniedMunicipalityId,
);
expectResult(wrongTenant, 403, "search_access_denied");

console.log(
  JSON.stringify({
    missing_token: noToken.status,
    altered_token: altered.status,
    aal1,
    aal2_authorized: authorized,
    aal2_wrong_tenant: wrongTenant,
  }),
);
