from __future__ import annotations

from dataclasses import asdict
from typing import Any

from . import CONTRACT_VERSION, MANIFEST_VERSION
from .errors import WorkerError
from .extraction import PageOutput, PdfOutput
from .integrity import canonical_json_bytes, sha256_bytes

PAGE_ARTIFACT_VERSION = "ia-fiscal-knowledge-ocr-page/v1"
POLICY_VERSION = "ia-fiscal-knowledge-ocr-policy/v1"
TOOLCHAIN_LOCK_SHA256 = "6bb5c3a93dad84e38ea05cedb47e1aeee13c8a22899f0cb9f693e114e5e5cd60"
CONTENT_PAGE_SEPARATOR = "\n\f\n"


def page_artifact_bytes(page: PageOutput) -> bytes:
    return canonical_json_bytes(
        {
            "schema_version": PAGE_ARTIFACT_VERSION,
            "page_number": page.page_number,
            "text": page.text,
            "text_sha256": page.text_sha256,
            "confidence_milli": page.confidence_milli,
            "confidence_samples": page.confidence_samples,
            "character_count": page.character_count,
            "utf8_bytes": page.utf8_bytes,
            "word_count": page.word_count,
        }
    )


def build_manifest(
    *,
    job_id: str,
    attempt: int,
    source_sha256: str,
    source_bytes: int,
    pdf: PdfOutput,
    language: str,
    dpi: int,
) -> tuple[dict[str, Any], bytes, str, str]:
    if not pdf.pages or [page.page_number for page in pdf.pages] != list(range(1, pdf.page_count + 1)):
        raise WorkerError("ocr_page_sequence_invalid", "OCR pages are not contiguous")
    pages_with_text = sum(bool(page.text) for page in pdf.pages)
    confidence_values = [
        page.confidence_milli for page in pdf.pages if page.confidence_milli is not None
    ]
    metrics = {
        "requested_pages": pdf.page_count,
        "processed_pages": len(pdf.pages),
        "pages_with_text": pages_with_text,
        "page_coverage_bps": round(pages_with_text * 10_000 / pdf.page_count),
        "mean_confidence_milli": (
            round(sum(confidence_values) / len(confidence_values)) if confidence_values else 0
        ),
        "minimum_confidence_milli": min(confidence_values) if confidence_values else 0,
        "confidence_page_samples": len(confidence_values),
        "total_characters": sum(page.character_count for page in pdf.pages),
        "total_utf8_bytes": sum(page.utf8_bytes for page in pdf.pages),
        "total_words": sum(page.word_count for page in pdf.pages),
    }
    content_text = CONTENT_PAGE_SEPARATOR.join(page.text for page in pdf.pages)
    content_sha256 = sha256_bytes(content_text.encode("utf-8"))
    manifest: dict[str, Any] = {
        "schema_version": MANIFEST_VERSION,
        "contract_version": CONTRACT_VERSION,
        "policy_version": POLICY_VERSION,
        "toolchain_lock_sha256": TOOLCHAIN_LOCK_SHA256,
        "job_id": job_id,
        "attempt": attempt,
        "source": {
            "sha256": source_sha256,
            "bytes": source_bytes,
            "normalized_sha256": pdf.normalized_sha256,
            "normalized_bytes": pdf.normalized_bytes,
            "page_count": pdf.page_count,
        },
        "ocr": {
            "language": language,
            "dpi": dpi,
            "content_page_separator": CONTENT_PAGE_SEPARATOR,
            "content_sha256": content_sha256,
            "tools": pdf.tools,
            "pages": [_page_manifest(page) for page in pdf.pages],
        },
        # V1 intentionally rejects auxiliary content not captured as its own governed artifact.
        "auxiliary_sources": [],
        "metrics": metrics,
    }
    encoded = canonical_json_bytes(manifest)
    return manifest, encoded, sha256_bytes(encoded), content_sha256


def enforce_quality_and_limits(
    manifest: dict[str, Any],
    pages: tuple[PageOutput, ...],
    *,
    max_page_chars: int,
    max_total_chars: int,
    min_coverage_bps: int,
    min_confidence_milli: int,
) -> None:
    metrics = manifest.get("metrics", {})
    if metrics.get("processed_pages") != metrics.get("requested_pages"):
        raise WorkerError("ocr_page_coverage_incomplete", "Not every PDF page was processed")
    if any(page.character_count > max_page_chars for page in pages):
        raise WorkerError("ocr_page_character_limit_exceeded", "An OCR page exceeded its approved character limit")
    content_chars = sum(page.character_count for page in pages) + max(0, len(pages) - 1) * len(
        CONTENT_PAGE_SEPARATOR
    )
    if content_chars > max_total_chars:
        raise WorkerError("ocr_total_character_limit_exceeded", "OCR content exceeded its approved character limit")
    if metrics.get("page_coverage_bps", 0) < min_coverage_bps:
        raise WorkerError("ocr_text_coverage_below_threshold", "OCR text coverage is below the approved threshold")
    if metrics.get("mean_confidence_milli", 0) < min_confidence_milli:
        raise WorkerError("ocr_confidence_below_threshold", "OCR confidence is below the approved threshold")


def _page_manifest(page: PageOutput) -> dict[str, Any]:
    value = asdict(page)
    value.pop("text")
    value["has_text"] = bool(page.text)
    value["artifact_sha256"] = sha256_bytes(page_artifact_bytes(page))
    return value
