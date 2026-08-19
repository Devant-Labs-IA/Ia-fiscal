// Manual pre-activation smoke. It performs no database or Storage mutation.
// Run with: deno run --allow-net official-pdf.smoke.ts

import { extractLegalBodyText } from "./extraction.ts";
import { fetchOfficialArtifact, IngestPolicyError, type MunicipalitySlug } from "./policy.ts";

type OfficialPdfFixture = {
  name: string;
  url: string;
  municipalitySlug: MunicipalitySlug;
  hosts: string[];
} & (
  | {
      expectedOutcome: "extracted";
      expectedPages: number;
      marker: RegExp;
    }
  | {
      expectedOutcome: "blocked_missing_text";
      expectedSafeCode: "source_pdf_text_missing";
    }
);

const fixtures: OfficialPdfFixture[] = [
  {
    name: "Cordeirópolis LC 399/2024 — Jornal do Município 1645",
    url: "https://www.cordeiropolis.sp.gov.br/wp-content/uploads/2024/12/Edicao-1645-_C.pdf",
    municipalitySlug: "cordeiropolis-sp",
    hosts: ["www.cordeiropolis.sp.gov.br"],
    expectedOutcome: "extracted",
    expectedPages: 32,
    marker: /LEI COMPLEMENTAR\s+(?:N[º°.]?\s*)?399/i,
  },
  {
    name: "Araras Lei 3.362/2001 — anexo PDF 43123",
    url: "https://araras.siscam.com.br/arquivo?Id=43123",
    municipalitySlug: "araras-sp",
    hosts: ["araras.siscam.com.br"],
    expectedOutcome: "blocked_missing_text",
    expectedSafeCode: "source_pdf_text_missing",
  },
];

for (const fixture of fixtures) {
  const artifact = await fetchOfficialArtifact(fixture.url, {
    municipalitySlug: fixture.municipalitySlug,
    endpointAllowedHosts: fixture.hosts,
    expectedContentTypes: ["application/pdf", "application/octet-stream"],
  });
  if (artifact.mimeType !== "application/pdf") {
    throw new Error(`${fixture.name}: resposta não é PDF`);
  }

  if (fixture.expectedOutcome === "blocked_missing_text") {
    let observed: unknown;
    try {
      await extractLegalBodyText(artifact);
    } catch (error) {
      observed = error;
    }
    if (
      !(observed instanceof IngestPolicyError) ||
      observed.code !== fixture.expectedSafeCode ||
      observed.responseStatus !== 422
    ) {
      throw new Error(`${fixture.name}: bloqueio fail-closed inesperado`);
    }
    console.log(JSON.stringify({
      name: fixture.name,
      status: "blocked",
      safe_error_code: observed.code,
      bytes: artifact.byteSize,
    }));
    continue;
  }

  const extraction = await extractLegalBodyText(artifact);
  if (extraction.pageCount !== fixture.expectedPages) {
    throw new Error(
      `${fixture.name}: esperadas ${fixture.expectedPages} páginas, obtidas ${extraction.pageCount}`,
    );
  }
  if (!fixture.marker.test(extraction.text)) {
    throw new Error(`${fixture.name}: dispositivo-chave não localizado`);
  }
  console.log(JSON.stringify({
    name: fixture.name,
    status: "ok",
    pages: extraction.pageCount,
    bytes: artifact.byteSize,
    extracted_characters: [...extraction.text].length,
  }));
}
