import { assert, assertEquals } from "jsr:@std/assert@1";

import {
  buildDeterministicChunks,
  EXTERNAL_OCR_V1_MAX_PAGES,
  ExternalOcrPdfError,
  extractLegalBodyText,
  isExternalOcrEligiblePdfFailure,
} from "../extraction.ts";
import { IngestPolicyError, MAX_PDF_IMAGE_PIXELS, MAX_PDF_PAGES } from "../policy.ts";

function singlePagePdfFixture(text: string): Uint8Array {
  const safeText = text.replace(/[()\\]/g, (value) => `\\${value}`);
  const content = `BT /F1 12 Tf 72 720 Td (${safeText}) Tj ET`;
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    `<< /Length ${new TextEncoder().encode(content).byteLength} >>\nstream\n${content}\nendstream`,
  ];
  let pdf = "%PDF-1.4\n";
  const offsets = [0];
  for (let index = 0; index < objects.length; index += 1) {
    offsets.push(new TextEncoder().encode(pdf).byteLength);
    pdf += `${index + 1} 0 obj\n${objects[index]}\nendobj\n`;
  }
  const xrefOffset = new TextEncoder().encode(pdf).byteLength;
  pdf += `xref\n0 ${objects.length + 1}\n`;
  pdf += "0000000000 65535 f \n";
  for (const offset of offsets.slice(1)) {
    pdf += `${String(offset).padStart(10, "0")} 00000 n \n`;
  }
  pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n`;
  pdf += `startxref\n${xrefOffset}\n%%EOF\n`;
  return new TextEncoder().encode(pdf);
}

Deno.test("unpdf extracts the complete legal fixture and releases its loading task", async () => {
  const expected = "Lei Complementar 399 Artigo 1 instituicao do codigo tributario municipal";
  const result = await extractLegalBodyText({
    bytes: singlePagePdfFixture(expected),
    mimeType: "application/pdf",
    contentType: "application/pdf",
  });

  assertEquals(result.parser, "unpdf-1.8.0");
  assertEquals(result.pageCount, 1);
  assert(result.text.includes("Lei Complementar 399"));
  assert(result.text.includes("codigo tributario municipal"));
});

Deno.test("invalid PDF input is classified at the document-open stage", async () => {
  let observed: unknown;
  try {
    await extractLegalBodyText({
      bytes: new TextEncoder().encode("%PDF-1.4\ninvalid official artifact"),
      mimeType: "application/pdf",
      contentType: "application/pdf",
    });
  } catch (error) {
    observed = error;
  }

  assert(observed instanceof IngestPolicyError);
  assertEquals(observed.code, "source_pdf_open_failed");
  assertEquals(observed.responseStatus, 422);
});

Deno.test("a PDF without a text layer fails closed for governed OCR", async () => {
  let observed: unknown;
  try {
    await extractLegalBodyText({
      bytes: singlePagePdfFixture(""),
      mimeType: "application/pdf",
      contentType: "application/pdf",
    });
  } catch (error) {
    observed = error;
  }

  assert(observed instanceof IngestPolicyError);
  assertEquals(observed.code, "source_pdf_text_missing");
  assertEquals(observed.responseStatus, 422);
  assert(observed instanceof ExternalOcrPdfError);
  assertEquals(observed.pageCount, 1);
});

Deno.test("only reparable PDF extraction failures are eligible for external OCR", () => {
  for (const code of [
    "source_pdf_extraction_failed",
    "source_pdf_text_missing",
  ]) {
    assertEquals(isExternalOcrEligiblePdfFailure(new ExternalOcrPdfError(code, 81)), true);
  }
  for (const code of [
    "source_pdf_open_failed",
    "source_pdf_page_limit_exceeded",
    "source_pdf_extraction_incomplete",
    "source_pdf_image_limit_exceeded",
    "source_too_large",
  ]) {
    assertEquals(isExternalOcrEligiblePdfFailure(new IngestPolicyError(code, 422)), false);
  }
  assertEquals(isExternalOcrEligiblePdfFailure(new Error("source_pdf_text_missing")), false);
  assertEquals(
    isExternalOcrEligiblePdfFailure(new IngestPolicyError("source_pdf_text_missing", 422)),
    false,
  );
});

Deno.test("chunking is deterministic, bounded and exactly derived", () => {
  const paragraph = "Artigo 1 O tributo municipal observa a legalidade e a vigencia.\n";
  const integral = paragraph.repeat(180);
  const first = buildDeterministicChunks(integral);
  const second = buildDeterministicChunks(integral);

  assertEquals(first, second);
  assert(first.length > 1);
  for (const chunk of first) {
    assert(chunk.content_text.length <= 6_000);
    assert(integral.includes(chunk.content_text));
  }
});

Deno.test("untrusted PDF resource limits stay explicit", () => {
  assertEquals(EXTERNAL_OCR_V1_MAX_PAGES, 120);
  assertEquals(MAX_PDF_PAGES, 500);
  assertEquals(MAX_PDF_IMAGE_PIXELS, 16_777_216);
});
