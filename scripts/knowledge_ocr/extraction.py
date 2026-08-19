from __future__ import annotations

import csv
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Callable
from xml.etree import ElementTree

from .errors import WorkerError
from .integrity import normalize_text, sha256_bytes, sha256_file

_WORD_NAMESPACE = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
_KEEPALIVE_INTERVAL_SECONDS = 20


@dataclass(frozen=True)
class PageOutput:
    page_number: int
    text: str
    text_sha256: str
    utf8_bytes: int
    character_count: int
    word_count: int
    confidence_milli: int | None
    confidence_samples: int


@dataclass(frozen=True)
class AuxiliaryOutput:
    index: int
    kind: str
    source_sha256: str
    text: str
    text_sha256: str
    utf8_bytes: int
    character_count: int
    word_count: int


@dataclass(frozen=True)
class PdfOutput:
    normalized_sha256: str
    normalized_bytes: int
    page_count: int
    pages: tuple[PageOutput, ...]
    tools: dict[str, Any]


def process_pdf(
    source: Path,
    work_dir: Path,
    *,
    language: str,
    dpi: int,
    max_pages: int,
    heartbeat: Callable[[], None] | None = None,
    on_page: Callable[[PageOutput], None] | None = None,
) -> PdfOutput:
    _require_magic(source, b"%PDF-", "source_pdf_magic_invalid")
    qpdf = _require_tool("qpdf")
    pdfinfo = _require_tool("pdfinfo")
    pdftoppm = _require_tool("pdftoppm")
    tesseract = _require_tool("tesseract")
    normalized = work_dir / "normalized.pdf"
    _run(
        [
            qpdf,
            "--password=",
            "--decrypt",
            "--deterministic-id",
            "--object-streams=generate",
            "--",
            str(source),
            str(normalized),
        ],
        timeout=180,
        code="pdf_normalization_failed",
        sandbox_root=work_dir,
        keepalive=heartbeat,
        max_stdout_bytes=1024 * 1024,
    )
    os.chmod(normalized, 0o600)
    _run(
        [qpdf, "--check", str(normalized)],
        timeout=120,
        code="pdf_validation_failed",
        sandbox_root=work_dir,
        keepalive=heartbeat,
        max_stdout_bytes=1024 * 1024,
    )
    info = _run(
        [pdfinfo, str(normalized)],
        timeout=120,
        code="pdf_inspection_failed",
        sandbox_root=work_dir,
        keepalive=heartbeat,
        max_stdout_bytes=1024 * 1024,
    ).stdout
    page_match = re.search(r"(?mi)^Pages:\s*(\d+)\s*$", info)
    if not page_match:
        raise WorkerError("pdf_inspection_failed", "PDF page count could not be determined")
    page_count = int(page_match.group(1))
    if page_count < 1 or page_count > max_pages:
        raise WorkerError("pdf_page_limit_exceeded", "PDF page count is outside the approved limit")

    pages: list[PageOutput] = []
    for page_number in range(1, page_count + 1):
        prefix = work_dir / f"page-{page_number:06d}"
        _run(
            [
                pdftoppm,
                "-f",
                str(page_number),
                "-l",
                str(page_number),
                "-singlefile",
                "-r",
                str(dpi),
                "-png",
                str(normalized),
                str(prefix),
            ],
            timeout=240,
            code="pdf_page_render_failed",
            sandbox_root=work_dir,
            keepalive=heartbeat,
            max_stdout_bytes=1024 * 1024,
        )
        image = prefix.with_suffix(".png")
        if not image.is_file() or image.stat().st_size < 8:
            raise WorkerError("pdf_page_render_failed", "Rendered PDF page is missing")
        if image.stat().st_size > 128 * 1024 * 1024:
            raise WorkerError("pdf_page_render_too_large", "Rendered PDF page exceeded the size limit")
        tsv = _run(
            [tesseract, str(image), "stdout", "-l", language, "--oem", "1", "--psm", "6", "tsv"],
            timeout=300,
            code="ocr_page_failed",
            sandbox_root=work_dir,
            keepalive=heartbeat,
            max_stdout_bytes=32 * 1024 * 1024,
        ).stdout
        page = _page_from_tsv(page_number, tsv)
        if on_page:
            on_page(page)
        pages.append(page)
        image.unlink(missing_ok=True)
        if heartbeat:
            heartbeat()

    normalized_sha256, normalized_bytes = sha256_file(normalized)
    return PdfOutput(
        normalized_sha256=normalized_sha256,
        normalized_bytes=normalized_bytes,
        page_count=page_count,
        pages=tuple(pages),
        tools=_toolchain_metadata(
            qpdf=qpdf,
            pdfinfo=pdfinfo,
            pdftoppm=pdftoppm,
            tesseract=tesseract,
        ),
    )


def extract_auxiliary(path: Path, *, index: int, kind: str, source_sha256: str) -> AuxiliaryOutput:
    if kind == "docx":
        text = extract_docx(path)
    elif kind == "rtf":
        text = extract_rtf(path)
    else:
        raise WorkerError("unsupported_auxiliary_type", "Auxiliary source type is unsupported")
    text = normalize_text(text)
    if not text:
        raise WorkerError("auxiliary_text_missing", "Auxiliary source did not yield text")
    encoded = text.encode("utf-8")
    return AuxiliaryOutput(
        index=index,
        kind=kind,
        source_sha256=source_sha256,
        text=text,
        text_sha256=sha256_bytes(encoded),
        utf8_bytes=len(encoded),
        character_count=len(text),
        word_count=len(text.split()),
    )


def extract_docx(path: Path) -> str:
    _require_magic(path, b"PK", "source_docx_magic_invalid")
    try:
        with zipfile.ZipFile(path) as archive:
            infos = archive.infolist()
            if len(infos) > 10_000:
                raise WorkerError("docx_archive_limit_exceeded", "DOCX contains too many entries")
            expanded_size = 0
            for info in infos:
                pure_name = PurePosixPath(info.filename)
                if pure_name.is_absolute() or ".." in pure_name.parts:
                    raise WorkerError("docx_archive_invalid", "DOCX contains an unsafe entry")
                expanded_size += info.file_size
                if expanded_size > 256 * 1024 * 1024:
                    raise WorkerError("docx_archive_limit_exceeded", "DOCX expanded size exceeded the limit")
            names = set(archive.namelist())
            ordered = ["word/document.xml", "word/footnotes.xml", "word/endnotes.xml"]
            ordered.extend(sorted(name for name in names if re.fullmatch(r"word/header\d+\.xml", name)))
            ordered.extend(sorted(name for name in names if re.fullmatch(r"word/footer\d+\.xml", name)))
            if "word/document.xml" not in names:
                raise WorkerError("docx_document_missing", "DOCX document body is missing")
            sections = [_extract_word_xml(archive.read(name)) for name in ordered if name in names]
    except WorkerError:
        raise
    except (zipfile.BadZipFile, KeyError, ElementTree.ParseError, OSError) as error:
        raise WorkerError("docx_extraction_failed", "DOCX extraction failed") from error
    return normalize_text("\n\n".join(section for section in sections if section))


def extract_rtf(path: Path) -> str:
    _require_magic(path, b"{\\rtf", "source_rtf_magic_invalid")
    unrtf = _require_tool("unrtf")
    result = _run(
        [unrtf, "--text", "--nopict", str(path)],
        timeout=120,
        code="rtf_extraction_failed",
        sandbox_root=path.parent,
        max_stdout_bytes=16 * 1024 * 1024,
    )
    text = result.stdout
    # GNU unrtf emits a fixed conversion banner before the first blank line.
    if "-----------------" in text[:1_000]:
        text = text.split("-----------------", 1)[1]
    return normalize_text(text)


def _extract_word_xml(raw: bytes) -> str:
    if b"<!DOCTYPE" in raw.upper() or b"<!ENTITY" in raw.upper():
        raise WorkerError("docx_xml_unsafe", "DOCX XML contains a forbidden declaration")
    root = ElementTree.fromstring(raw)
    paragraphs: list[str] = []
    for paragraph in root.iter(f"{_WORD_NAMESPACE}p"):
        parts: list[str] = []
        for element in paragraph.iter():
            if element.tag == f"{_WORD_NAMESPACE}t" and element.text:
                parts.append(element.text)
            elif element.tag == f"{_WORD_NAMESPACE}tab":
                parts.append("\t")
            elif element.tag in {f"{_WORD_NAMESPACE}br", f"{_WORD_NAMESPACE}cr"}:
                parts.append("\n")
        paragraphs.append("".join(parts))
    return normalize_text("\n".join(paragraphs))


def _page_from_tsv(page_number: int, raw: str) -> PageOutput:
    try:
        reader = csv.DictReader(io.StringIO(raw), delimiter="\t")
        lines: dict[tuple[str, str, str], list[str]] = {}
        confidences: list[int] = []
        for row in reader:
            word = normalize_text(row.get("text", "")).replace("\n", " ").strip()
            if not word:
                continue
            key = (row.get("block_num", "0"), row.get("par_num", "0"), row.get("line_num", "0"))
            lines.setdefault(key, []).append(word)
            try:
                confidence = float(row.get("conf", "-1"))
            except ValueError:
                confidence = -1
            if 0 <= confidence <= 100:
                # Canonical confidence unit: 0..1000 maps to numeric 0..1 server-side.
                confidences.append(round(confidence * 10))
    except (csv.Error, TypeError) as error:
        raise WorkerError("ocr_output_invalid", "OCR engine output was invalid") from error
    text = normalize_text("\n".join(" ".join(words) for words in lines.values()))
    encoded = text.encode("utf-8")
    confidence_milli = round(sum(confidences) / len(confidences)) if confidences else None
    return PageOutput(
        page_number=page_number,
        text=text,
        text_sha256=sha256_bytes(encoded),
        utf8_bytes=len(encoded),
        character_count=len(text),
        word_count=len(text.split()),
        confidence_milli=confidence_milli,
        confidence_samples=len(confidences),
    )


def _require_magic(path: Path, expected: bytes, code: str) -> None:
    try:
        with path.open("rb") as handle:
            actual = handle.read(len(expected))
    except OSError as error:
        raise WorkerError("source_read_failed", "Source could not be read") from error
    if actual != expected:
        raise WorkerError(code, "Source signature does not match its declared type")


def _require_tool(name: str) -> str:
    path = shutil.which(name)
    if not path:
        raise WorkerError("worker_dependency_missing", f"Required worker dependency is missing: {name}")
    return path


def _run(
    command: list[str],
    *,
    timeout: int,
    code: str,
    sandbox_root: Path,
    keepalive: Callable[[], None] | None = None,
    max_stdout_bytes: int = 1024 * 1024,
    max_stderr_bytes: int = 1024 * 1024,
) -> subprocess.CompletedProcess[str]:
    sandboxed_command = _sandbox_command(command, sandbox_root)
    process: subprocess.Popen[str] | None = None
    try:
        with tempfile.TemporaryFile() as stdout_file, tempfile.TemporaryFile() as stderr_file:
            if keepalive:
                keepalive()
            process = subprocess.Popen(
                sandboxed_command,
                stdout=stdout_file,
                stderr=stderr_file,
                env=_parser_environment(),
            )
            deadline = time.monotonic() + timeout
            next_keepalive = time.monotonic() + _KEEPALIVE_INTERVAL_SECONDS
            while True:
                now = time.monotonic()
                if now >= deadline:
                    process.kill()
                    process.wait(timeout=10)
                    raise WorkerError(code, f"Sandboxed worker command timed out: {Path(command[0]).name}")
                if keepalive and now >= next_keepalive:
                    keepalive()
                    next_keepalive = time.monotonic() + _KEEPALIVE_INTERVAL_SECONDS
                stdout_size = os.fstat(stdout_file.fileno()).st_size
                stderr_size = os.fstat(stderr_file.fileno()).st_size
                if stdout_size > max_stdout_bytes or stderr_size > max_stderr_bytes:
                    process.kill()
                    process.wait(timeout=10)
                    raise WorkerError(
                        "worker_output_limit_exceeded",
                        f"Sandboxed worker output exceeded its limit: {Path(command[0]).name}",
                    )
                try:
                    return_code = process.wait(timeout=min(0.25, max(0.05, deadline - now)))
                    break
                except subprocess.TimeoutExpired:
                    continue
            if return_code != 0:
                raise WorkerError(code, f"Sandboxed worker command failed: {Path(command[0]).name}")
            stdout_file.seek(0)
            stderr_file.seek(0)
            try:
                stdout = stdout_file.read(max_stdout_bytes + 1).decode("utf-8")
                stderr = stderr_file.read(max_stderr_bytes + 1).decode("utf-8")
            except UnicodeDecodeError as error:
                raise WorkerError("worker_output_invalid", "Sandboxed worker output is not UTF-8") from error
            if len(stdout.encode("utf-8")) > max_stdout_bytes or len(stderr.encode("utf-8")) > max_stderr_bytes:
                raise WorkerError("worker_output_limit_exceeded", "Sandboxed worker output exceeded its limit")
            return subprocess.CompletedProcess(command, return_code, stdout, stderr)
    except WorkerError:
        if process and process.poll() is None:
            process.kill()
            process.wait(timeout=10)
        raise
    except (subprocess.SubprocessError, OSError) as error:
        if process and process.poll() is None:
            process.kill()
            process.wait(timeout=10)
        raise WorkerError(code, f"Sandboxed worker command failed: {Path(command[0]).name}") from error


def _tool_version(command: list[str]) -> str:
    try:
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
            env=_parser_environment(),
        )
    except (subprocess.SubprocessError, OSError):
        return "unavailable"
    output = normalize_text(f"{result.stdout}\n{result.stderr}").split("\n", 1)[0]
    return output[:160] or "unavailable"


def _toolchain_metadata(
    *, qpdf: str, pdfinfo: str, pdftoppm: str, tesseract: str
) -> dict[str, Any]:
    bubblewrap = _require_tool("bwrap")
    unrtf = _require_tool("unrtf")
    metadata: dict[str, Any] = {
        "bubblewrap": _binary_metadata(bubblewrap, [bubblewrap, "--version"]),
        "qpdf": _binary_metadata(qpdf, [qpdf, "--version"]),
        "pdfinfo": _binary_metadata(pdfinfo, [pdfinfo, "-v"]),
        "pdftoppm": _binary_metadata(pdftoppm, [pdftoppm, "-v"]),
        "tesseract": _binary_metadata(tesseract, [tesseract, "--version"]),
        "unrtf": _binary_metadata(unrtf, [unrtf, "--version"]),
        "python": _binary_metadata(sys.executable, [sys.executable, "--version"]),
        "packages": {},
    }
    for package in (
        "bubblewrap",
        "qpdf",
        "poppler-utils",
        "tesseract-ocr",
        "tesseract-ocr-por",
        "unrtf",
    ):
        result = subprocess.run(
            ["dpkg-query", "-W", "-f=${Version}", package],
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
            env=_parser_environment(),
        )
        metadata["packages"][package] = normalize_text(result.stdout) if result.returncode == 0 else "unavailable"
    tessdata_candidates = sorted(Path("/usr/share/tesseract-ocr").glob("**/por.traineddata"))
    if not tessdata_candidates:
        raise WorkerError("worker_dependency_missing", "Portuguese Tesseract language data is missing")
    tessdata_sha256, tessdata_bytes = sha256_file(tessdata_candidates[0])
    metadata["tesseract_por"] = {
        "traineddata_sha256": tessdata_sha256,
        "traineddata_bytes": tessdata_bytes,
    }
    return metadata


def _binary_metadata(path: str, version_command: list[str]) -> dict[str, Any]:
    binary_sha256, binary_bytes = sha256_file(Path(path))
    version = _tool_version(version_command)
    version_match = re.search(r"\d+(?:\.\d+){1,3}(?:[-+][A-Za-z0-9.-]+)?", version)
    return {
        "version": version,
        "canonical_version": version_match.group(0)[:80] if version_match else "unavailable",
        "binary_sha256": binary_sha256,
        "binary_bytes": binary_bytes,
    }


def _parser_environment() -> dict[str, str]:
    """Do not expose GitHub OIDC or workflow configuration to native parsers."""
    environment = {
        "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "LC_ALL": "C.UTF-8",
        "LANG": "C.UTF-8",
        "HOME": "/tmp/ia-fiscal-ocr-home",
    }
    tessdata_prefix = os.environ.get("TESSDATA_PREFIX")
    if tessdata_prefix and Path(tessdata_prefix).is_absolute() and str(tessdata_prefix).startswith("/usr/share/"):
        environment["TESSDATA_PREFIX"] = tessdata_prefix
    return environment


def _sandbox_command(command: list[str], sandbox_root: Path) -> list[str]:
    bubblewrap = _require_tool("bwrap")
    root = sandbox_root.resolve(strict=True)
    if not root.is_dir() or root == Path("/"):
        raise WorkerError("worker_sandbox_invalid", "Parser sandbox root is invalid")
    base = [
        bubblewrap,
        "--die-with-parent",
        "--new-session",
        "--unshare-all",
        "--cap-drop",
        "ALL",
        "--clearenv",
        "--setenv",
        "PATH",
        "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "--setenv",
        "LC_ALL",
        "C.UTF-8",
        "--setenv",
        "LANG",
        "C.UTF-8",
        "--setenv",
        "HOME",
        "/tmp/home",
        "--ro-bind",
        "/usr",
        "/usr",
        "--ro-bind-try",
        "/bin",
        "/bin",
        "--ro-bind-try",
        "/sbin",
        "/sbin",
        "--ro-bind-try",
        "/lib",
        "/lib",
        "--ro-bind-try",
        "/lib64",
        "/lib64",
        "--ro-bind-try",
        "/etc/fonts",
        "/etc/fonts",
        "--ro-bind-try",
        "/etc/ld.so.cache",
        "/etc/ld.so.cache",
        "--ro-bind-try",
        "/etc/tesseract-ocr",
        "/etc/tesseract-ocr",
        "--proc",
        "/proc",
        "--dev",
        "/dev",
        "--tmpfs",
        "/tmp",
        "--bind",
        str(root),
        "/work",
        "--dir",
        "/tmp/home",
        "--chdir",
        "/work",
        "--",
    ]
    translated: list[str] = []
    for argument in command:
        try:
            relative = Path(argument).relative_to(root)
        except (ValueError, TypeError):
            translated.append(argument)
        else:
            translated.append(str(Path("/work") / relative))
    return [*base, *translated]
