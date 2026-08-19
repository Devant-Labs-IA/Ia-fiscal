from __future__ import annotations

import json
import unittest

from scripts.knowledge_ocr.errors import WorkerError
from scripts.knowledge_ocr.extraction import PageOutput, PdfOutput, _page_from_tsv
from scripts.knowledge_ocr.integrity import canonical_json_bytes, sha256_bytes
from scripts.knowledge_ocr.manifest import (
    CONTENT_PAGE_SEPARATOR,
    build_manifest,
    enforce_quality_and_limits,
    page_artifact_bytes,
    POLICY_VERSION,
    TOOLCHAIN_LOCK_SHA256,
)


def make_page(number: int, text: str, confidence: int | None = 900) -> PageOutput:
    encoded = text.encode()
    return PageOutput(
        page_number=number,
        text=text,
        text_sha256=sha256_bytes(encoded),
        utf8_bytes=len(encoded),
        character_count=len(text),
        word_count=len(text.split()),
        confidence_milli=confidence,
        confidence_samples=3 if confidence is not None else 0,
    )


def make_pdf(pages: tuple[PageOutput, ...]) -> PdfOutput:
    return PdfOutput(
        normalized_sha256="1" * 64,
        normalized_bytes=123,
        page_count=len(pages),
        pages=pages,
        tools={
            "tesseract": {
                "version": "tesseract 5.3.4",
                "canonical_version": "5.3.4",
                "binary_sha256": "2" * 64,
            }
        },
    )


class ManifestTests(unittest.TestCase):
    def test_manifest_and_content_hash_are_deterministic(self) -> None:
        pages = (make_page(1, "Art. 1º"), make_page(2, "Art. 2º", 800))
        arguments = {
            "job_id": "job-1",
            "attempt": 1,
            "source_sha256": "0" * 64,
            "source_bytes": 99,
            "pdf": make_pdf(pages),
            "language": "por",
            "dpi": 300,
        }
        first = build_manifest(**arguments)
        second = build_manifest(**arguments)
        self.assertEqual(first, second)
        manifest, body, manifest_hash, content_hash = first
        self.assertEqual(body, canonical_json_bytes(manifest))
        self.assertEqual(manifest_hash, sha256_bytes(body))
        expected_content = CONTENT_PAGE_SEPARATOR.join(page.text for page in pages).encode()
        self.assertEqual(content_hash, sha256_bytes(expected_content))
        self.assertEqual(manifest["auxiliary_sources"], [])
        self.assertEqual(manifest["policy_version"], POLICY_VERSION)
        self.assertEqual(manifest["toolchain_lock_sha256"], TOOLCHAIN_LOCK_SHA256)
        self.assertNotIn("created_at", manifest)

    def test_page_artifact_contains_exact_canonical_contract(self) -> None:
        page = make_page(1, "Lei")
        value = json.loads(page_artifact_bytes(page))
        self.assertEqual(
            set(value),
            {
                "schema_version",
                "page_number",
                "text",
                "text_sha256",
                "confidence_milli",
                "confidence_samples",
                "character_count",
                "utf8_bytes",
                "word_count",
            },
        )
        self.assertEqual(value["text_sha256"], sha256_bytes(b"Lei"))

    def test_quality_and_limits_fail_closed(self) -> None:
        pages = (make_page(1, "", None), make_page(2, "texto", 400))
        manifest, *_ = build_manifest(
            job_id="job-1",
            attempt=1,
            source_sha256="0" * 64,
            source_bytes=99,
            pdf=make_pdf(pages),
            language="por",
            dpi=300,
        )
        with self.assertRaisesRegex(WorkerError, "coverage"):
            enforce_quality_and_limits(
                manifest,
                pages,
                max_page_chars=100,
                max_total_chars=100,
                min_coverage_bps=9_000,
                min_confidence_milli=0,
            )
        with self.assertRaisesRegex(WorkerError, "confidence"):
            enforce_quality_and_limits(
                manifest,
                pages,
                max_page_chars=100,
                max_total_chars=100,
                min_coverage_bps=0,
                min_confidence_milli=500,
            )

    def test_tesseract_confidence_uses_zero_to_one_thousand_scale(self) -> None:
        raw = (
            "level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n"
            "5\t1\t1\t1\t1\t1\t0\t0\t1\t1\t75.5\tLei\n"
        )
        page = _page_from_tsv(1, raw)
        self.assertEqual(page.confidence_milli, 755)
        self.assertEqual(page.text, "Lei")

    def test_page_gap_is_rejected(self) -> None:
        pdf = PdfOutput(
            normalized_sha256="1" * 64,
            normalized_bytes=123,
            page_count=2,
            pages=(make_page(1, "a"), make_page(3, "b")),
            tools={},
        )
        with self.assertRaisesRegex(WorkerError, "contiguous"):
            build_manifest(
                job_id="job-1",
                attempt=1,
                source_sha256="0" * 64,
                source_bytes=99,
                pdf=pdf,
                language="por",
                dpi=300,
            )


if __name__ == "__main__":
    unittest.main()
