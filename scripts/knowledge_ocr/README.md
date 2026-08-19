# Governed legal OCR worker

This worker turns an immutable, officially captured PDF artifact into page-level OCR evidence. It does not publish legal content. The Edge backend verifies every hash and creates an `under_review` candidate for a human legal reviewer.

## Execution and identity

`.github/workflows/knowledge-ocr.yml` runs hourly or by manual dispatch, one job per run. It has only `contents: read` and `id-token: write`; it does not use a Supabase service-role key or a long-lived GitHub secret.

Every Edge request obtains a new GitHub OIDC token. The Edge allowlist and the worker's local sanity check use:

- audience `ia-fiscal-knowledge-ocr-qvgenxcrdrqyiyozxtdt`;
- repository `AlmoreContabilidade/Ia-fiscal`, ID `1320619695`;
- owner ID `296187202`;
- immutable subject `repo:AlmoreContabilidade@296187202/Ia-fiscal@1320619695:environment:knowledge-ocr`;
- workflow ref `AlmoreContabilidade/Ia-fiscal/.github/workflows/knowledge-ocr.yml@refs/heads/main`;
- environment `knowledge-ocr`, ref `refs/heads/main`, and a GitHub-hosted runner.

The local JWT claim inspection is only a fail-closed configuration check. The Edge function remains the trust boundary and must verify the token signature, issuer, audience, claims, expiry, and one-time `jti` against GitHub's JWKS.

Before activation, repository administrators must restrict the `knowledge-ocr` environment to the `main` branch. The worker and Edge still reject any other ref even if that environment setting is accidentally relaxed.

## Processing contract

The v1 worker:

1. claims one PDF job and starts an independent 30-second lease keeper;
2. downloads only from the exact Supabase hostname and verifies declared byte count and SHA-256;
3. normalizes PDFs with qpdf using an empty password, which decrypts empty-password PDFs and rejects sources requiring another password;
4. checks the normalized PDF and rejects more than 120 pages before OCR;
5. renders and OCRs each page in Portuguese at 300 DPI;
6. uploads each canonical page JSON immediately as a WORM checkpoint;
7. enforces total/page limits, at least 90% text-bearing page coverage, and mean confidence of at least 0.55;
8. uploads a deterministic manifest and completes using artifact references only.

Page text is never printed or placed in the GitHub artifact. The uploaded run artifact contains only counts, confidence/coverage metrics, safe error codes, and a hashed job reference.

The workflow has a 45-minute process timeout and a 40-minute per-job deadline. A lease failure, cancellation, output overflow, dependency mismatch, page gap, integrity mismatch, or quality failure stops native parsing and prevents finalization.

## Native parser isolation and supply chain

qpdf, pdfinfo, pdftoppm, Tesseract, and unrtf run inside bubblewrap with all namespaces unshared, no network, a fresh `/proc`, a minimal read-only filesystem, one writable work directory, no capabilities, and a cleared environment. If this sandbox cannot be established, the workflow fails closed.

Actions use 40-character commit pins. Python and all Ubuntu packages have exact versions in `toolchain.lock.json`. The workflow verifies that lock before claiming a job. The manifest records package versions plus SHA-256/byte counts for every native binary and the Portuguese Tesseract language data.

## DOCX and RTF auxiliaries

`extraction.py` contains bounded, tested DOCX and RTF extractors. They are intentionally not connected to the v1 queue: the backend accepts only a governed PDF artifact and rejects non-empty `auxiliary_sources`. A DOCX or RTF must first be captured as its own official immutable artifact with source/hash provenance before a later contract version can ingest it. This prevents unrelated documents from being silently mixed into a legal source.

## Local tests

Run without generating bytecode artifacts:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/knowledge_ocr/tests -v
```

The tests cover deterministic manifests, page hashes, DOCX/RTF extraction, URL and source integrity, immutable OIDC claims, one-time JTIs, replay rejection, response-loss completion retry, parser sandboxing, bounded subprocess output, lease loss, hard page caps, exact workflow pins, and metadata-only logs.
