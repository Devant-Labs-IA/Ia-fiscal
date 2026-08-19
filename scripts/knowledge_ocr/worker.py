from __future__ import annotations

import json
import os
import signal
import sys
import tempfile
import threading
import time
from pathlib import Path
from typing import Any

from .edge_client import ClaimedJob, EdgeClient
from .errors import WorkerError
from .extraction import PageOutput, process_pdf
from .integrity import (
    canonical_json_bytes,
    parse_host_allowlist,
    redact_identifier,
    verify_file,
)
from .manifest import build_manifest, enforce_quality_and_limits, page_artifact_bytes
from .oidc import GitHubOidcProvider

_STOP_REQUESTED = False


class LeaseKeeper:
    """Maintains a lease independently while untrusted native parsers run."""

    def __init__(self, client: EdgeClient, job: ClaimedJob, *, interval_seconds: float = 30.0) -> None:
        self.client = client
        self.job = job
        self.interval_seconds = interval_seconds
        self._stop = threading.Event()
        self._started = threading.Event()
        self._lock = threading.Lock()
        self._error: WorkerError | None = None
        self._terminal = False
        self._sequence = 0
        self._thread = threading.Thread(
            target=self._run,
            name=f"ocr-lease-{redact_identifier(job.job_id)}",
            daemon=False,
        )

    def start(self) -> None:
        self._thread.start()
        if not self._started.wait(timeout=50):
            self._stop.set()
            raise WorkerError("lease_heartbeat_timeout", "Initial lease heartbeat timed out", retryable=True)
        self.raise_if_failed()

    def raise_if_failed(self) -> None:
        with self._lock:
            error = self._error
        if error is not None:
            raise WorkerError(
                "lease_heartbeat_failed",
                "OCR lease heartbeat failed; processing was cancelled",
                retryable=error.retryable,
            )

    def mark_terminal(self) -> None:
        with self._lock:
            self._terminal = True

    def stop(self) -> None:
        self._stop.set()
        if self._thread.ident is None:
            return
        self._thread.join(timeout=50)
        if self._thread.is_alive():
            raise WorkerError("lease_heartbeat_stop_failed", "OCR lease heartbeat did not stop")

    def _run(self) -> None:
        while not self._stop.is_set():
            self._sequence += 1
            try:
                self.client.heartbeat(self.job, sequence=self._sequence)
            except WorkerError as error:
                with self._lock:
                    if not self._terminal:
                        self._error = error
                self._started.set()
                return
            except Exception:
                with self._lock:
                    if not self._terminal:
                        self._error = WorkerError(
                            "lease_heartbeat_unclassified",
                            "OCR lease heartbeat failed unexpectedly",
                            retryable=False,
                        )
                self._started.set()
                return
            self._started.set()
            if self._stop.wait(self.interval_seconds):
                return


def _request_stop(_signum: int, _frame: Any) -> None:
    global _STOP_REQUESTED
    _STOP_REQUESTED = True


def main() -> int:
    signal.signal(signal.SIGTERM, _request_stop)
    signal.signal(signal.SIGINT, _request_stop)
    summary_path = Path(os.environ.get("OCR_SUMMARY_PATH", "knowledge-ocr-summary.json"))
    summary: dict[str, Any] = {
        "schema_version": "ia-fiscal-knowledge-ocr-run-summary/v1",
        "jobs_claimed": 0,
        "jobs_completed": 0,
        "jobs_failed": 0,
        "jobs": [],
        "result": "running",
    }
    _write_summary(summary_path, summary)
    try:
        edge_url = _required_environment("OCR_EDGE_URL")
        oidc = GitHubOidcProvider.from_environment()
        hosts = parse_host_allowlist(os.environ.get("OCR_ALLOWED_DOWNLOAD_HOSTS"), edge_url=edge_url)
        client = EdgeClient(edge_url, oidc, hosts)
        max_jobs = _bounded_environment_int("OCR_MAX_JOBS", default=1, minimum=1, maximum=1)
        run_id = _required_environment("GITHUB_RUN_ID")
        run_attempt = _required_environment("GITHUB_RUN_ATTEMPT")
        for claim_number in range(1, max_jobs + 1):
            if _STOP_REQUESTED:
                break
            job = client.claim(
                run_id=run_id,
                run_attempt=run_attempt,
                claim_number=claim_number,
            )
            if job is None:
                break
            summary["jobs_claimed"] += 1
            job_summary = {"job_ref": redact_identifier(job.job_id), "result": "running"}
            summary["jobs"].append(job_summary)
            _write_summary(summary_path, summary)
            lease_keeper = LeaseKeeper(client, job)
            try:
                lease_keeper.start()
                metrics = _process_job(client, job, lease_keeper)
                job_summary.update({"result": "completed", **metrics})
                summary["jobs_completed"] += 1
            except WorkerError as error:
                job_summary.update({"result": "failed", "error_code": error.code, "retryable": error.retryable})
                summary["jobs_failed"] += 1
                if error.code != "complete_outcome_unknown":
                    try:
                        client.fail(job, error)
                        lease_keeper.mark_terminal()
                    except WorkerError as report_error:
                        job_summary["failure_report_code"] = report_error.code
                _safe_log("job_failed", job=job, code=error.code)
            except Exception:  # Defensive boundary: never report exception text or source data.
                classified = WorkerError("worker_unclassified_failure", "Worker failed unexpectedly", retryable=False)
                job_summary.update({"result": "failed", "error_code": classified.code, "retryable": False})
                summary["jobs_failed"] += 1
                try:
                    client.fail(job, classified)
                    lease_keeper.mark_terminal()
                except WorkerError as report_error:
                    job_summary["failure_report_code"] = report_error.code
                _safe_log("job_failed", job=job, code=classified.code)
            finally:
                lease_keeper.stop()
            _write_summary(summary_path, summary)
        summary["result"] = "failed" if summary["jobs_failed"] else "completed"
        _write_summary(summary_path, summary)
        return 1 if summary["jobs_failed"] else 0
    except WorkerError as error:
        summary.update({"result": "failed", "fatal_error_code": error.code})
        _write_summary(summary_path, summary)
        print(json.dumps({"event": "worker_failed", "code": error.code}, separators=(",", ":")))
        return 1


def _process_job(client: EdgeClient, job: ClaimedJob, lease_keeper: LeaseKeeper) -> dict[str, int]:
    with tempfile.TemporaryDirectory(prefix="ia-fiscal-ocr-") as temporary:
        work_dir = Path(temporary)
        os.chmod(work_dir, 0o700)
        source = work_dir / "source.pdf"
        client.download(job.source, source)
        verify_file(source, job.source.sha256, job.source.byte_count)

        dpi = _bounded_environment_int("OCR_DPI", default=300, minimum=200, maximum=600)
        min_coverage_bps = _bounded_environment_int(
            "OCR_MIN_PAGE_COVERAGE_BPS", default=9_000, minimum=0, maximum=10_000
        )
        min_confidence_milli = _bounded_environment_int(
            "OCR_MIN_MEAN_CONFIDENCE_MILLI", default=550, minimum=0, maximum=1_000
        )

        deadline = time.monotonic() + _bounded_environment_int(
            "OCR_JOB_DEADLINE_SECONDS", default=2_400, minimum=300, maximum=2_520
        )

        def guard() -> None:
            if _STOP_REQUESTED:
                raise WorkerError("worker_cancelled", "Worker cancellation was requested", retryable=True)
            lease_keeper.raise_if_failed()
            if time.monotonic() >= deadline:
                raise WorkerError("job_deadline_exceeded", "OCR job exceeded its processing deadline", retryable=True)

        completed_pages: list[dict[str, Any]] = []

        def upload_page(page: PageOutput) -> None:
            guard()
            artifact = client.upload_part(
                job,
                part_kind="page",
                part_number=page.page_number,
                body=page_artifact_bytes(page),
            )
            completed_pages.append(
                {
                    "page_number": page.page_number,
                    "artifact": artifact.payload(),
                }
            )

        pdf = process_pdf(
            source,
            work_dir,
            language="por",
            dpi=dpi,
            max_pages=job.limits.max_pages,
            heartbeat=guard,
            on_page=upload_page,
        )
        manifest, manifest_body, _manifest_sha256, content_sha256 = build_manifest(
            job_id=job.job_id,
            attempt=job.attempt,
            source_sha256=job.source.sha256,
            source_bytes=job.source.byte_count,
            pdf=pdf,
            language="por",
            dpi=dpi,
        )
        enforce_quality_and_limits(
            manifest,
            pdf.pages,
            max_page_chars=job.limits.max_page_chars,
            max_total_chars=job.limits.max_total_chars,
            min_coverage_bps=min_coverage_bps,
            min_confidence_milli=min_confidence_milli,
        )
        guard()
        manifest_artifact = client.upload_part(
            job,
            part_kind="manifest",
            part_number=pdf.page_count + 1,
            body=manifest_body,
        )
        tesseract_metadata = pdf.tools.get("tesseract", {})
        engine_version = (
            tesseract_metadata.get("canonical_version", "unavailable")
            if isinstance(tesseract_metadata, dict)
            else "unavailable"
        )
        client.complete(
            job,
            engine_version=engine_version,
            manifest=manifest_artifact,
            content_sha256=content_sha256,
            pages=completed_pages,
        )
        lease_keeper.mark_terminal()
        metrics = manifest["metrics"]
        _safe_log("job_completed", job=job, pages=metrics["processed_pages"])
        return {
            "pages": metrics["processed_pages"],
            "pages_with_text": metrics["pages_with_text"],
            "page_coverage_bps": metrics["page_coverage_bps"],
            "mean_confidence_milli": metrics["mean_confidence_milli"],
        }


def _safe_log(event: str, *, job: ClaimedJob, code: str | None = None, pages: int | None = None) -> None:
    value: dict[str, Any] = {"event": event, "job_ref": redact_identifier(job.job_id)}
    if code:
        value["code"] = code
    if pages is not None:
        value["pages"] = pages
    print(json.dumps(value, separators=(",", ":"), sort_keys=True))


def _write_summary(path: Path, summary: dict[str, Any]) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_bytes(canonical_json_bytes(summary) + b"\n")
    os.chmod(temporary, 0o600)
    temporary.replace(path)


def _required_environment(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise WorkerError("configuration_invalid", f"Required environment variable is missing: {name}")
    return value


def _bounded_environment_int(name: str, *, default: int, minimum: int, maximum: int) -> int:
    value = os.environ.get(name, str(default))
    try:
        parsed = int(value)
    except ValueError as error:
        raise WorkerError("configuration_invalid", f"{name} must be an integer") from error
    if parsed < minimum or parsed > maximum:
        raise WorkerError("configuration_invalid", f"{name} is outside the accepted range")
    return parsed


if __name__ == "__main__":
    sys.exit(main())
