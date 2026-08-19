import { extractText, getDocumentProxy } from "npm:unpdf@1.8.0";

import {
  extractUntrustedHtmlText,
  IngestPolicyError,
  MAX_PDF_IMAGE_PIXELS,
  MAX_PDF_PAGES,
  normalizeExtractedText,
  type FetchedArtifact,
} from "./policy.ts";

export type ExtractionResult = {
  text: string;
  parser: "html-v2" | "plain-text-v1" | "unpdf-1.8.0";
  pageCount: number | null;
};

export type StagedChunk = {
  chunk_index: number;
  content_text: string;
  token_count: number;
};

const EXTERNAL_OCR_ELIGIBLE_PDF_ERRORS = new Set([
  "source_pdf_extraction_failed",
  "source_pdf_text_missing",
]);
export const EXTERNAL_OCR_V1_MAX_PAGES = 120;

export class ExternalOcrPdfError extends IngestPolicyError {
  constructor(
    code: "source_pdf_extraction_failed" | "source_pdf_text_missing",
    readonly pageCount: number,
  ) {
    super(code, 422);
    this.name = "ExternalOcrPdfError";
  }
}

/**
 * A validly fetched official PDF may still need a separately isolated OCR
 * worker. These failures are not evidence that the official bytes are
 * invalid, so a non-dry-run ingestion may preserve the raw artifact and
 * enqueue governed OCR. Policy, size and page-limit failures remain closed.
 */
export function isExternalOcrEligiblePdfFailure(
  error: unknown,
): error is ExternalOcrPdfError {
  return (
    error instanceof ExternalOcrPdfError &&
    Number.isSafeInteger(error.pageCount) &&
    error.pageCount >= 1 &&
    error.pageCount <= MAX_PDF_PAGES &&
    EXTERNAL_OCR_ELIGIBLE_PDF_ERRORS.has(error.code)
  );
}

async function extractPdf(bytes: Uint8Array): Promise<ExtractionResult> {
  let pdf: Awaited<ReturnType<typeof getDocumentProxy>>;
  try {
    pdf = await getDocumentProxy(bytes, {
      maxImageSize: MAX_PDF_IMAGE_PIXELS,
      isEvalSupported: false,
      useSystemFonts: false,
      disableAutoFetch: true,
    });
  } catch {
    throw new IngestPolicyError("source_pdf_open_failed", 422);
  }
  try {
    if (pdf.numPages < 1 || pdf.numPages > MAX_PDF_PAGES) {
      throw new IngestPolicyError("source_pdf_page_limit_exceeded", 413);
    }
    let extracted: Awaited<ReturnType<typeof extractText>>;
    try {
      extracted = await extractText(pdf, { mergePages: true });
    } catch {
      throw new ExternalOcrPdfError("source_pdf_extraction_failed", pdf.numPages);
    }
    if (extracted.totalPages !== pdf.numPages || typeof extracted.text !== "string") {
      throw new IngestPolicyError("source_pdf_extraction_incomplete", 422);
    }
    const text = normalizeExtractedText(extracted.text);
    if (!text || text.length < 40) {
      throw new ExternalOcrPdfError("source_pdf_text_missing", pdf.numPages);
    }
    return { text, parser: "unpdf-1.8.0", pageCount: pdf.numPages };
  } finally {
    await pdf.loadingTask.destroy().catch(() => undefined);
  }
}

export async function extractLegalBodyText(
  artifact: Pick<FetchedArtifact, "bytes" | "mimeType" | "contentType">,
): Promise<ExtractionResult> {
  switch (artifact.mimeType) {
    case "text/html":
    case "application/xhtml+xml": {
      const text = extractUntrustedHtmlText(artifact.bytes, artifact.contentType);
      if (!text || text.length < 40) {
        throw new IngestPolicyError("source_html_text_missing", 422);
      }
      return { text, parser: "html-v2", pageCount: null };
    }
    case "text/plain": {
      const text = normalizeExtractedText(new TextDecoder().decode(artifact.bytes));
      if (!text || text.length < 40) {
        throw new IngestPolicyError("source_plain_text_missing", 422);
      }
      return { text, parser: "plain-text-v1", pageCount: null };
    }
    case "application/pdf":
      return extractPdf(artifact.bytes);
  }
  throw new IngestPolicyError("unsupported_source_mime", 415);
}

export function buildDeterministicChunks(
  text: string,
  maximumCharacters = 6_000,
  overlapCharacters = 500,
): StagedChunk[] {
  if (maximumCharacters < 1_000 || maximumCharacters > 8_000) {
    throw new IngestPolicyError("chunk_size_invalid", 500);
  }
  if (overlapCharacters < 0 || overlapCharacters >= maximumCharacters / 2) {
    throw new IngestPolicyError("chunk_overlap_invalid", 500);
  }
  if (text.length <= 8_000) return [];

  const chunks: StagedChunk[] = [];
  let start = 0;
  while (start < text.length) {
    let end = Math.min(text.length, start + maximumCharacters);
    if (end < text.length) {
      const minimumEnd = start + Math.floor(maximumCharacters * 0.65);
      const newline = text.lastIndexOf("\n", end);
      const space = text.lastIndexOf(" ", end);
      const boundary = Math.max(newline, space);
      if (boundary >= minimumEnd) end = boundary;
    }
    const content = text.slice(start, end).trim();
    if (content) {
      chunks.push({
        chunk_index: chunks.length + 1,
        content_text: content,
        token_count: Math.max(1, content.split(/\s+/u).length),
      });
    }
    if (end >= text.length) break;
    let nextStart = Math.max(start + 1, end - overlapCharacters);
    const nextBoundary = text.indexOf(" ", nextStart);
    if (nextBoundary >= nextStart && nextBoundary < end) nextStart = nextBoundary + 1;
    start = nextStart;
  }
  if (chunks.length > 5_000) {
    throw new IngestPolicyError("chunk_count_limit_exceeded", 413);
  }
  return chunks;
}
