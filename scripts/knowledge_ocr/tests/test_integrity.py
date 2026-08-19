from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from scripts.knowledge_ocr.errors import WorkerError
from scripts.knowledge_ocr.integrity import (
    canonical_json_bytes,
    normalize_text,
    sha256_bytes,
    validate_https_url,
    verify_file,
)


class IntegrityTests(unittest.TestCase):
    def test_canonical_json_is_order_independent_and_unicode_preserving(self) -> None:
        left = canonical_json_bytes({"z": 1, "á": [True, None]})
        right = canonical_json_bytes({"á": [True, None], "z": 1})
        self.assertEqual(left, right)
        self.assertIn("á".encode(), left)

    def test_file_integrity_fails_closed_for_size_and_hash(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "source.bin"
            path.write_bytes(b"official")
            verify_file(path, sha256_bytes(b"official"), 8)
            with self.assertRaisesRegex(WorkerError, "byte count"):
                verify_file(path, sha256_bytes(b"official"), 9)
            with self.assertRaisesRegex(WorkerError, "SHA-256"):
                verify_file(path, "0" * 64, 8)

    def test_url_allowlist_rejects_scheme_credentials_port_and_other_host(self) -> None:
        allowed = {"project.supabase.co"}
        self.assertEqual(
            validate_https_url(
                "https://project.supabase.co/storage/v1/object/sign/x", allowed, field="source"
            ),
            "https://project.supabase.co/storage/v1/object/sign/x",
        )
        rejected = (
            "http://project.supabase.co/x",
            "https://user@project.supabase.co/x",
            "https://project.supabase.co:8443/x",
            "https://evil-project.supabase.co/x",
            "https://127.0.0.1/x",
        )
        for url in rejected:
            with self.subTest(url=url), self.assertRaises(WorkerError):
                validate_https_url(url, allowed, field="source")

    def test_text_normalization_is_stable(self) -> None:
        self.assertEqual(normalize_text("\r\n  Lei  \x00\r\n\r\n"), "  Lei")


if __name__ == "__main__":
    unittest.main()

