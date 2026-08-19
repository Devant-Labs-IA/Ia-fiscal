import { crc32, deflateRawSync, inflateRawSync } from "node:zlib";

import { describe, expect, it, vi } from "vitest";

import {
  DOCX_DISABLED_CODE,
  DOCX_MIME_TYPE,
  fetchOfficialArtifact,
  parseKnowledgeEndpoint,
} from "./policy.ts";

const endpointId = "11111111-1111-4111-8111-111111111111";
const sourceId = "22222222-2222-4222-8222-222222222222";
const municipalityId = "33333333-3333-4333-8333-333333333333";
const REPORTED_EXPANDED_BYTES = 67_109_921;
const FORGED_DECLARED_BYTES = 1_032;
const MAX_SAFE_EXPANSION_BYTES = 64 * 1024 * 1024;

type ZipFixtureEntry = {
  name: string;
  method: 0 | 8;
  compressed: Uint8Array;
  crc32: number;
  declaredUncompressedBytes: number;
};

function forgedDocxExpansionBomb(): {
  bytes: Uint8Array;
  deflatedDocument: Uint8Array;
  declaredDocumentBytes: number;
} {
  const encoder = new TextEncoder();
  const expandedDocument = Buffer.alloc(REPORTED_EXPANDED_BYTES);
  const deflatedDocument = deflateRawSync(expandedDocument, {
    level: 9,
  });
  const contentTypes = encoder.encode(
    '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>',
  );
  const entries: ZipFixtureEntry[] = [
    {
      name: "[Content_Types].xml",
      method: 0,
      compressed: contentTypes,
      crc32: crc32(contentTypes),
      declaredUncompressedBytes: contentTypes.byteLength,
    },
    {
      name: "word/document.xml",
      method: 8,
      compressed: deflatedDocument,
      crc32: crc32(expandedDocument),
      declaredUncompressedBytes: FORGED_DECLARED_BYTES,
    },
  ];
  const encoded = entries.map((entry) => ({ ...entry, nameBytes: encoder.encode(entry.name) }));
  const localBytes = encoded.reduce(
    (total, entry) => total + 30 + entry.nameBytes.byteLength + entry.compressed.byteLength,
    0,
  );
  const centralBytes = encoded.reduce((total, entry) => total + 46 + entry.nameBytes.byteLength, 0);
  const bytes = new Uint8Array(localBytes + centralBytes + 22);
  const view = new DataView(bytes.buffer);
  const localOffsets: number[] = [];
  let cursor = 0;

  for (const entry of encoded) {
    localOffsets.push(cursor);
    view.setUint32(cursor, 0x04034b50, true);
    view.setUint16(cursor + 4, 20, true);
    view.setUint16(cursor + 8, entry.method, true);
    view.setUint32(cursor + 14, entry.crc32, true);
    view.setUint32(cursor + 18, entry.compressed.byteLength, true);
    view.setUint32(cursor + 22, entry.declaredUncompressedBytes, true);
    view.setUint16(cursor + 26, entry.nameBytes.byteLength, true);
    bytes.set(entry.nameBytes, cursor + 30);
    bytes.set(entry.compressed, cursor + 30 + entry.nameBytes.byteLength);
    cursor += 30 + entry.nameBytes.byteLength + entry.compressed.byteLength;
  }

  const centralOffset = cursor;
  for (let index = 0; index < encoded.length; index += 1) {
    const entry = encoded[index];
    view.setUint32(cursor, 0x02014b50, true);
    view.setUint16(cursor + 4, 20, true);
    view.setUint16(cursor + 6, 20, true);
    view.setUint16(cursor + 10, entry.method, true);
    view.setUint32(cursor + 16, entry.crc32, true);
    view.setUint32(cursor + 20, entry.compressed.byteLength, true);
    view.setUint32(cursor + 24, entry.declaredUncompressedBytes, true);
    view.setUint16(cursor + 28, entry.nameBytes.byteLength, true);
    view.setUint32(cursor + 42, localOffsets[index], true);
    bytes.set(entry.nameBytes, cursor + 46);
    cursor += 46 + entry.nameBytes.byteLength;
  }

  view.setUint32(cursor, 0x06054b50, true);
  view.setUint16(cursor + 8, encoded.length, true);
  view.setUint16(cursor + 10, encoded.length, true);
  view.setUint32(cursor + 12, centralBytes, true);
  view.setUint32(cursor + 16, centralOffset, true);

  return {
    bytes,
    deflatedDocument,
    declaredDocumentBytes: FORGED_DECLARED_BYTES,
  };
}

function endpointFixture(expectedContentTypes: string[]): Record<string, unknown> {
  return {
    endpoint_id: endpointId,
    municipality_id: municipalityId,
    municipality_slug: "cordeiropolis-sp",
    source_id: sourceId,
    source_title: "Fonte oficial sintética",
    requested_url: "https://cordeiropolis.siscam.com.br/arquivo?Id=121730",
    trust_tier: "primary_publication",
    endpoint_kind: "document_file",
    endpoint_status: "active",
    content_mode: "legal_body",
    citable_body: true,
    activation_blocker: null,
    parser_hint: "official_attachment",
    expected_content_types: expectedContentTypes,
    allowed_hosts: ["cordeiropolis.siscam.com.br"],
  };
}

describe("DOCX fail-closed release policy", () => {
  it("rejects the forged-size DEFLATE PoC without passing it to a ZIP/DOCX parser", async () => {
    const { bytes, deflatedDocument, declaredDocumentBytes } = forgedDocxExpansionBomb();

    expect(bytes.byteLength).toBeGreaterThan(65_000);
    expect(bytes.byteLength).toBeLessThan(66_000);
    expect(declaredDocumentBytes).toBe(1_032);
    expect(inflateRawSync(deflatedDocument).byteLength).toBe(REPORTED_EXPANDED_BYTES);
    expect(REPORTED_EXPANDED_BYTES).toBeGreaterThan(MAX_SAFE_EXPANSION_BYTES);

    const fetchImpl = vi.fn(
      async () =>
        new Response(bytes, {
          status: 200,
          headers: { "content-type": "application/octet-stream" },
        }),
    ) as unknown as typeof fetch;

    await expect(
      fetchOfficialArtifact("https://cordeiropolis.siscam.com.br/arquivo?Id=121730", {
        municipalitySlug: "cordeiropolis-sp",
        endpointAllowedHosts: ["cordeiropolis.siscam.com.br"],
        expectedContentTypes: ["application/octet-stream"],
        fetchImpl,
      }),
    ).rejects.toMatchObject({ code: DOCX_DISABLED_CODE, responseStatus: 415 });
  });

  it("cancels a declared DOCX response before reading its body", async () => {
    const cancel = vi.fn();
    const body = new ReadableStream<Uint8Array>({
      cancel,
    });
    const fetchImpl = vi.fn(
      async () =>
        new Response(body, {
          status: 200,
          headers: { "content-type": DOCX_MIME_TYPE },
        }),
    ) as unknown as typeof fetch;

    await expect(
      fetchOfficialArtifact("https://cordeiropolis.siscam.com.br/arquivo?Id=121730", {
        municipalitySlug: "cordeiropolis-sp",
        endpointAllowedHosts: ["cordeiropolis.siscam.com.br"],
        expectedContentTypes: [DOCX_MIME_TYPE],
        fetchImpl,
      }),
    ).rejects.toMatchObject({ code: DOCX_DISABLED_CODE, responseStatus: 415 });
    expect(cancel).toHaveBeenCalledWith("source_mime_rejected");
  });

  it("removes DOCX from a mixed endpoint interface and blocks a DOCX-only endpoint", () => {
    const mixed = parseKnowledgeEndpoint(
      endpointFixture(["application/pdf", "application/octet-stream", DOCX_MIME_TYPE]),
    );
    expect(mixed.expected_content_types).toEqual(["application/pdf", "application/octet-stream"]);
    expect(() => parseKnowledgeEndpoint(endpointFixture([DOCX_MIME_TYPE]))).toThrowError(
      expect.objectContaining({ code: DOCX_DISABLED_CODE, responseStatus: 503 }),
    );
  });
});
