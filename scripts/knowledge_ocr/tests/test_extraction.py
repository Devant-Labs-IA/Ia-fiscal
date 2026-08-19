from __future__ import annotations

import os
import subprocess
import tempfile
import time
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch
from unittest.mock import Mock

from scripts.knowledge_ocr.errors import WorkerError
from scripts.knowledge_ocr.extraction import (
    _sandbox_command,
    _run,
    _KEEPALIVE_INTERVAL_SECONDS,
    _toolchain_metadata,
    extract_docx,
    extract_rtf,
    process_pdf,
)


class ExtractionTests(unittest.TestCase):
    def test_toolchain_manifest_has_exact_backend_schema(self) -> None:
        binary = {
            "version": "tool 1.0.0",
            "canonical_version": "1.0.0",
            "binary_sha256": "a" * 64,
            "binary_bytes": 10,
        }
        package_result = subprocess.CompletedProcess([], 0, "locked-version", "")
        with patch(
            "scripts.knowledge_ocr.extraction._require_tool",
            side_effect=lambda name: f"/usr/bin/{name}",
        ), patch(
            "scripts.knowledge_ocr.extraction._require_locked_bwrap",
            return_value="/usr/bin/bwrap",
        ), patch(
            "scripts.knowledge_ocr.extraction._binary_metadata", return_value=binary
        ), patch(
            "scripts.knowledge_ocr.extraction.subprocess.run", return_value=package_result
        ), patch(
            "scripts.knowledge_ocr.extraction.Path.glob",
            return_value=[Path("/usr/share/tesseract-ocr/5/tessdata/por.traineddata")],
        ), patch(
            "scripts.knowledge_ocr.extraction.sha256_file", return_value=("b" * 64, 20)
        ):
            tools = _toolchain_metadata(
                qpdf="/usr/bin/qpdf",
                pdfinfo="/usr/bin/pdfinfo",
                pdftoppm="/usr/bin/pdftoppm",
                tesseract="/usr/bin/tesseract",
            )
        self.assertEqual(
            set(tools),
            {
                "bubblewrap",
                "qpdf",
                "pdfinfo",
                "pdftoppm",
                "tesseract",
                "unrtf",
                "python",
                "packages",
                "tesseract_por",
            },
        )
        for name in ("bubblewrap", "qpdf", "pdfinfo", "pdftoppm", "tesseract", "unrtf", "python"):
            self.assertEqual(
                set(tools[name]),
                {"version", "canonical_version", "binary_sha256", "binary_bytes"},
            )

    def test_subprocess_keepalive_starts_immediately_and_interval_is_below_lease_margin(self) -> None:
        keepalive = Mock()
        with tempfile.TemporaryDirectory() as temporary, patch(
            "scripts.knowledge_ocr.extraction._sandbox_command",
            return_value=["/usr/bin/true"],
        ):
            result = _run(
                ["/usr/bin/true"],
                timeout=5,
                code="probe_failed",
                sandbox_root=Path(temporary),
                keepalive=keepalive,
            )
        self.assertEqual(result.returncode, 0)
        keepalive.assert_called_once_with()
        self.assertLessEqual(_KEEPALIVE_INTERVAL_SECONDS, 30)

    def test_subprocess_output_is_bounded(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, patch(
            "scripts.knowledge_ocr.extraction._sandbox_command",
            return_value=["/usr/bin/python3", "-c", "print('x' * 4096)"],
        ):
            with self.assertRaises(WorkerError) as captured:
                _run(
                    ["/usr/bin/python3"],
                    timeout=5,
                    code="probe_failed",
                    sandbox_root=Path(temporary),
                    max_stdout_bytes=128,
                )
        self.assertEqual(captured.exception.code, "worker_output_limit_exceeded")

    def test_keepalive_loss_terminates_native_parser(self) -> None:
        calls = 0

        def keepalive() -> None:
            nonlocal calls
            calls += 1
            if calls >= 2:
                raise WorkerError("lease_heartbeat_failed", "lease lost")

        started = time.monotonic()
        with tempfile.TemporaryDirectory() as temporary, patch(
            "scripts.knowledge_ocr.extraction._sandbox_command",
            return_value=["/usr/bin/python3", "-c", "import time; time.sleep(2)"],
        ), patch("scripts.knowledge_ocr.extraction._KEEPALIVE_INTERVAL_SECONDS", 0.01):
            with self.assertRaises(WorkerError) as captured:
                _run(
                    ["/usr/bin/python3"],
                    timeout=5,
                    code="probe_failed",
                    sandbox_root=Path(temporary),
                    keepalive=keepalive,
                )
        self.assertEqual(captured.exception.code, "lease_heartbeat_failed")
        self.assertLess(time.monotonic() - started, 1)

    def test_docx_extracts_body_and_header_deterministically(self) -> None:
        document = (
            b'<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
            b"<w:body><w:p><w:r><w:t>Lei municipal</w:t></w:r></w:p></w:body></w:document>"
        )
        header = (
            b'<w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
            b"<w:p><w:r><w:t>Diario Oficial</w:t></w:r></w:p></w:hdr>"
        )
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "source.docx"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("word/header1.xml", header)
                archive.writestr("word/document.xml", document)
            self.assertEqual(extract_docx(path), "Lei municipal\n\nDiario Oficial")

    def test_docx_rejects_zip_slip_even_if_body_is_valid(self) -> None:
        document = (
            b'<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
            b"<w:body><w:p><w:r><w:t>Lei</w:t></w:r></w:p></w:body></w:document>"
        )
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "source.docx"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("word/document.xml", document)
                archive.writestr("../escape", b"x")
            with self.assertRaisesRegex(WorkerError, "unsafe"):
                extract_docx(path)

    def test_rtf_extraction_normalizes_sandboxed_tool_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "source.rtf"
            path.write_bytes(b"{\\rtf1 Lei}")
            output = subprocess.CompletedProcess(["unrtf"], 0, "banner\n-----------------\nLei\r\n", "")
            with patch("scripts.knowledge_ocr.extraction._require_tool", return_value="/usr/bin/unrtf"), patch(
                "scripts.knowledge_ocr.extraction._run", return_value=output
            ):
                self.assertEqual(extract_rtf(path), "Lei")

    def test_pdf_normalization_failure_is_classified(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.pdf"
            source.write_bytes(b"%PDF-1.7\n")
            with patch("scripts.knowledge_ocr.extraction._require_tool", return_value="/usr/bin/tool"), patch(
                "scripts.knowledge_ocr.extraction._run",
                side_effect=WorkerError("pdf_normalization_failed", "failed"),
            ):
                with self.assertRaisesRegex(WorkerError, "failed") as captured:
                    process_pdf(source, root, language="por", dpi=300, max_pages=10)
            self.assertEqual(captured.exception.code, "pdf_normalization_failed")

    def test_pdf_processing_reaches_toolchain_manifest_with_pdfinfo(self) -> None:
        tsv = (
            "level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n"
            "5\t1\t1\t1\t1\t1\t0\t0\t1\t1\t90\tLei\n"
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.pdf"
            source.write_bytes(b"%PDF-1.7\n")

            def fake_run(_command, *, code, **_kwargs):  # type: ignore[no-untyped-def]
                if code == "pdf_normalization_failed":
                    (root / "normalized.pdf").write_bytes(b"%PDF-1.7 normalized")
                    return subprocess.CompletedProcess([], 0, "", "")
                if code == "pdf_inspection_failed":
                    return subprocess.CompletedProcess([], 0, "Pages: 1\n", "")
                if code == "pdf_page_render_failed":
                    (root / "page-000001.png").write_bytes(b"png data")
                    return subprocess.CompletedProcess([], 0, "", "")
                if code == "ocr_page_failed":
                    return subprocess.CompletedProcess([], 0, tsv, "")
                return subprocess.CompletedProcess([], 0, "", "")

            on_page = Mock()
            with patch(
                "scripts.knowledge_ocr.extraction._require_tool",
                side_effect=lambda name: f"/usr/bin/{name}",
            ), patch("scripts.knowledge_ocr.extraction._run", side_effect=fake_run), patch(
                "scripts.knowledge_ocr.extraction._toolchain_metadata",
                return_value={"tesseract": {"canonical_version": "5.3.4"}},
            ) as toolchain:
                result = process_pdf(
                    source,
                    root,
                    language="por",
                    dpi=300,
                    max_pages=120,
                    on_page=on_page,
                )
        self.assertEqual(result.page_count, 1)
        self.assertEqual(result.pages[0].text, "Lei")
        on_page.assert_called_once()
        toolchain.assert_called_once_with(
            qpdf="/usr/bin/qpdf",
            pdfinfo="/usr/bin/pdfinfo",
            pdftoppm="/usr/bin/pdftoppm",
            tesseract="/usr/bin/tesseract",
        )

    def test_pdf_above_approved_page_cap_fails_non_retryable_before_ocr(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.pdf"
            source.write_bytes(b"%PDF-1.7\n")

            def fake_run(_command, *, code, **_kwargs):  # type: ignore[no-untyped-def]
                if code == "pdf_normalization_failed":
                    (root / "normalized.pdf").write_bytes(b"%PDF-1.7 normalized")
                    return subprocess.CompletedProcess([], 0, "", "")
                if code == "pdf_validation_failed":
                    return subprocess.CompletedProcess([], 0, "", "")
                if code == "pdf_inspection_failed":
                    return subprocess.CompletedProcess([], 0, "Pages: 121\n", "")
                self.fail(f"unexpected expensive stage after page-cap check: {code}")

            with patch(
                "scripts.knowledge_ocr.extraction._require_tool",
                side_effect=lambda name: f"/usr/bin/{name}",
            ), patch("scripts.knowledge_ocr.extraction._run", side_effect=fake_run):
                with self.assertRaises(WorkerError) as captured:
                    process_pdf(source, root, language="por", dpi=300, max_pages=120)
        self.assertEqual(captured.exception.code, "pdf_page_limit_exceeded")
        self.assertFalse(captured.exception.retryable)

    def test_native_parser_sandbox_has_no_network_parent_proc_or_inherited_env(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, patch(
            "scripts.knowledge_ocr.extraction._require_locked_bwrap",
            return_value="/usr/bin/bwrap",
        ):
            source = Path(temporary) / "source.pdf"
            source.write_bytes(b"%PDF")
            command = _sandbox_command(
                ["/usr/bin/qpdf", "--check", str(source)], Path(temporary)
            )
        self.assertIn("--unshare-all", command)
        self.assertIn("--clearenv", command)
        self.assertIn("--proc", command)
        self.assertNotIn("ACTIONS_ID_TOKEN_REQUEST_TOKEN", command)
        self.assertEqual(command[0], "/usr/bin/bwrap")
        self.assertEqual(command[-3:], ["/usr/bin/qpdf", "--check", "/work/source.pdf"])

    def test_native_parser_sandbox_rejects_path_shadowed_bwrap(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            shadow_bin = root / "shadow-bin"
            shadow_bin.mkdir()
            shadow = shadow_bin / "bwrap"
            shadow.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            shadow.chmod(0o755)
            work = root / "work"
            work.mkdir()

            with patch.dict(
                os.environ,
                {"PATH": f"{shadow_bin}:/usr/bin:/bin"},
            ):
                with self.assertRaises(WorkerError) as captured:
                    _sandbox_command(["/usr/bin/true"], work)

        self.assertEqual(captured.exception.code, "worker_dependency_mismatch")


if __name__ == "__main__":
    unittest.main()
