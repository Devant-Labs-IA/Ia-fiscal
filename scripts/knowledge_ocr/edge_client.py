from __future__ import annotations

import base64
import json
import os
import re
import socket
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

from . import CONTRACT_VERSION
from .errors import WorkerError
from .integrity import (
    canonical_json_bytes,
    require_positive_int,
    require_sha256,
    safe_identifier,
    sha256_bytes,
    validate_https_url,
)
from .oidc import GitHubOidcProvider

_MAX_RESPONSE_BYTES = 1024 * 1024
_MAX_SOURCE_BYTES = 512 * 1024 * 1024
EXPECTED_EDGE_URL = (
    "https://qvgenxcrdrqyiyozxtdt.supabase.co/functions/v1/ia-fiscal-knowledge-ocr"
)


@dataclass(frozen=True)
class SourceDescriptor:
    url: str
    sha256: str
    byte_count: int
    media_type: str


@dataclass(frozen=True)
class JobLimits:
    max_pages: int
    max_page_chars: int
    max_total_chars: int
    max_part_bytes: int


@dataclass(frozen=True)
class ClaimedJob:
    job_id: str
    lease_token: str
    attempt: int
    max_attempts: int
    source: SourceDescriptor
    limits: JobLimits


@dataclass(frozen=True)
class ArtifactReference:
    storage_ref: str
    sha256: str
    byte_count: int

    def payload(self) -> dict[str, Any]:
        return {
            "storage_ref": self.storage_ref,
            "sha256": self.sha256,
            "byte_size": self.byte_count,
        }


class EdgeClient:
    def __init__(self, endpoint: str, oidc: GitHubOidcProvider, allowed_download_hosts: set[str]) -> None:
        if endpoint != EXPECTED_EDGE_URL:
            raise WorkerError("configuration_invalid", "OCR edge endpoint does not match the production contract")
        endpoint_host = urlsplit(endpoint).hostname
        if not endpoint_host:
            raise WorkerError("configuration_invalid", "OCR edge endpoint is invalid")
        self.endpoint = validate_https_url(endpoint, {endpoint_host}, field="OCR_EDGE_URL")
        self.oidc = oidc
        self.allowed_download_hosts = allowed_download_hosts

    def claim(self, *, run_id: str, run_attempt: str, claim_number: int) -> ClaimedJob | None:
        payload = self._request(
            "claim",
            {},
            idempotency_key=f"claim:{run_id}:{run_attempt}:{claim_number}",
            allowed_statuses={200},
        )
        if payload.get("status") == "empty":
            return None
        return self._parse_job(payload)

    def heartbeat(self, job: ClaimedJob, *, sequence: int) -> None:
        self._request(
            "heartbeat",
            {"job_id": job.job_id, "lease_token": job.lease_token},
            idempotency_key=f"heartbeat:{job.job_id}:{job.attempt}:{sequence}",
            allowed_statuses={200},
        )

    def upload_part(
        self,
        job: ClaimedJob,
        *,
        part_kind: str,
        part_number: int,
        body: bytes,
    ) -> ArtifactReference:
        if part_kind not in {"page", "manifest"} or part_number < 1:
            raise WorkerError("internal_contract_invalid", "OCR upload part metadata is invalid")
        if len(body) > job.limits.max_part_bytes:
            raise WorkerError("ocr_part_limit_exceeded", "OCR upload part exceeded its approved size")
        digest = sha256_bytes(body)
        payload = self._request(
            "upload-part",
            {
                "job_id": job.job_id,
                "lease_token": job.lease_token,
                "part_kind": part_kind,
                "part_number": part_number,
                "sha256": digest,
                "content_type": "application/json",
                "body_base64": base64.b64encode(body).decode("ascii"),
            },
            idempotency_key=f"part:{job.job_id}:{job.attempt}:{part_kind}:{part_number}:{digest}",
            allowed_statuses={200, 201},
        )
        return self._parse_artifact(payload, expected_sha256=digest, expected_bytes=len(body))

    def complete(
        self,
        job: ClaimedJob,
        *,
        engine_version: str,
        manifest: ArtifactReference,
        content_sha256: str,
        pages: list[dict[str, Any]],
    ) -> None:
        body = {
            "job_id": job.job_id,
            "lease_token": job.lease_token,
            "engine": {"name": "tesseract", "version": engine_version},
            "manifest": manifest.payload(),
            "content_sha256": content_sha256,
            "pages": pages,
        }
        idempotency_key = f"complete:{job.job_id}:{job.attempt}:{content_sha256}"
        try:
            payload = self._request(
                "complete",
                body,
                idempotency_key=idempotency_key,
                allowed_statuses={200, 201},
            )
        except WorkerError as first_error:
            if not first_error.retryable:
                raise
            try:
                # A lost response may follow a committed transaction. Retry once
                # with a fresh JWT/JTI and the same idempotency key.
                payload = self._request(
                    "complete",
                    body,
                    idempotency_key=idempotency_key,
                    allowed_statuses={200, 201},
                )
            except WorkerError as retry_error:
                raise WorkerError(
                    "complete_outcome_unknown",
                    "OCR completion outcome is unknown; terminal failure must not be written",
                    retryable=True,
                ) from retry_error
        if (
            payload.get("status") not in {"already_completed", "under_review"}
            or payload.get("publication_status") != "not_published"
            or payload.get("job_id") != job.job_id
            or payload.get("content_sha256") != content_sha256
            or payload.get("page_count") != len(pages)
        ):
            # A 2xx response can arrive after the terminal transaction committed.
            # Treat an unrecognized completion status as outcome-unknown so the
            # caller never writes a contradictory failure over a terminal job.
            raise WorkerError(
                "complete_outcome_unknown",
                "OCR completion outcome is unknown; terminal failure must not be written",
                retryable=True,
            )

    def fail(self, job: ClaimedJob, error: WorkerError) -> None:
        self._request(
            "fail",
            {
                "job_id": job.job_id,
                "lease_token": job.lease_token,
                "error_code": error.code,
                "error_detail": error.public_message[:240],
                "retryable": error.retryable,
            },
            idempotency_key=f"fail:{job.job_id}:{job.attempt}:{error.code}",
            allowed_statuses={200},
        )

    def download(self, source: SourceDescriptor, target: Path) -> None:
        validate_https_url(source.url, self.allowed_download_hosts, field="source.url")
        request = Request(source.url, headers={"Accept": "application/octet-stream"}, method="GET")
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        received = 0
        try:
            with urlopen(request, timeout=45) as response:  # noqa: S310 - URL is allowlisted above.
                validate_https_url(response.geturl(), self.allowed_download_hosts, field="source.redirect_url")
                with target.open("xb") as handle:
                    os.chmod(target, 0o600)
                    while chunk := response.read(1024 * 1024):
                        received += len(chunk)
                        if received > _MAX_SOURCE_BYTES or received > source.byte_count:
                            raise WorkerError("source_too_large", "Downloaded source exceeded the declared limit")
                        handle.write(chunk)
        except WorkerError:
            target.unlink(missing_ok=True)
            raise
        except (HTTPError, URLError, OSError, socket.timeout) as error:
            target.unlink(missing_ok=True)
            raise WorkerError("source_download_failed", "Source download failed", retryable=True) from error

    def _request(
        self,
        action: str,
        body: dict[str, Any],
        *,
        idempotency_key: str,
        allowed_statuses: set[int],
    ) -> dict[str, Any]:
        request_body = canonical_json_bytes({"contract_version": CONTRACT_VERSION, "action": action, **body})
        request = Request(
            self.endpoint,
            data=request_body,
            headers={
                # token() deliberately obtains a new JWT for every request; jti replay is rejected.
                "Authorization": f"Bearer {self.oidc.token()}",
                "Content-Type": "application/json",
                "Accept": "application/json",
                "Idempotency-Key": idempotency_key,
                "User-Agent": "ia-fiscal-knowledge-ocr/1",
            },
            method="POST",
        )
        try:
            with urlopen(request, timeout=45) as response:  # noqa: S310 - endpoint is validated above.
                status = response.status
                raw = response.read(_MAX_RESPONSE_BYTES + 1)
        except HTTPError as error:
            error.read(_MAX_RESPONSE_BYTES)
            if error.code in {408, 425, 429, 500, 502, 503, 504}:
                raise WorkerError("edge_transient_failure", f"Edge action {action} failed", retryable=True) from error
            raise WorkerError("edge_request_rejected", f"Edge action {action} was rejected") from error
        except (URLError, OSError, socket.timeout) as error:
            raise WorkerError("edge_request_failed", f"Edge action {action} failed", retryable=True) from error
        if status not in allowed_statuses:
            raise WorkerError("edge_response_invalid", f"Edge action {action} returned an invalid status")
        if len(raw) > _MAX_RESPONSE_BYTES:
            raise WorkerError("edge_response_invalid", "Edge response exceeded the size limit")
        try:
            value = json.loads(raw)
        except json.JSONDecodeError as error:
            raise WorkerError("edge_response_invalid", "Edge response was not valid JSON") from error
        if not isinstance(value, dict) or value.get("contract_version") != CONTRACT_VERSION:
            raise WorkerError("edge_response_invalid", "Edge response contract version does not match")
        return value

    def _parse_job(self, payload: dict[str, Any]) -> ClaimedJob:
        raw_job = payload.get("job")
        raw_source = payload.get("source")
        raw_limits = payload.get("limits")
        if not isinstance(raw_job, dict) or not isinstance(raw_source, dict) or not isinstance(raw_limits, dict):
            raise WorkerError("edge_response_invalid", "Claim response is incomplete")
        lease_token = raw_job.get("lease_token")
        if not isinstance(lease_token, str) or not 20 <= len(lease_token) <= 4_096:
            raise WorkerError("edge_response_invalid", "Claim lease token is invalid")
        source_url = raw_source.get("url")
        if not isinstance(source_url, str) or len(source_url) > 8_192:
            raise WorkerError("edge_response_invalid", "Claim source URL is invalid")
        validate_https_url(source_url, self.allowed_download_hosts, field="source.url")
        media_type = raw_source.get("mime_type")
        if media_type != "application/pdf":
            raise WorkerError("unsupported_media_type", "OCR v1 only accepts PDF source artifacts")
        source = SourceDescriptor(
            url=source_url,
            sha256=require_sha256(raw_source.get("sha256"), "source.sha256"),
            byte_count=require_positive_int(raw_source.get("byte_size"), "source.byte_size", maximum=_MAX_SOURCE_BYTES),
            media_type=media_type,
        )
        limits = JobLimits(
            max_pages=require_positive_int(raw_limits.get("max_pages"), "limits.max_pages", maximum=120),
            max_page_chars=require_positive_int(
                raw_limits.get("max_page_characters"),
                "limits.max_page_characters",
                maximum=10_000_000,
            ),
            max_total_chars=require_positive_int(
                raw_limits.get("max_total_characters"),
                "limits.max_total_characters",
                maximum=100_000_000,
            ),
            max_part_bytes=require_positive_int(
                raw_limits.get("max_part_bytes"), "limits.max_part_bytes", maximum=16 * 1024 * 1024
            ),
        )
        attempt = require_positive_int(raw_job.get("attempt"), "job.attempt", maximum=100)
        max_attempts = require_positive_int(raw_job.get("max_attempts"), "job.max_attempts", maximum=100)
        if attempt > max_attempts:
            raise WorkerError("edge_response_invalid", "Claim attempt exceeds max attempts")
        lease_expires_at = raw_job.get("lease_expires_at")
        if not isinstance(lease_expires_at, str) or len(lease_expires_at) > 64:
            raise WorkerError("edge_response_invalid", "Claim lease expiry is invalid")
        return ClaimedJob(
            job_id=safe_identifier(raw_job.get("id"), "job.id"),
            lease_token=lease_token,
            attempt=attempt,
            max_attempts=max_attempts,
            source=source,
            limits=limits,
        )

    def _parse_artifact(
        self, payload: dict[str, Any], *, expected_sha256: str, expected_bytes: int
    ) -> ArtifactReference:
        storage_ref = payload.get("storage_ref")
        sha256 = require_sha256(payload.get("sha256"), "upload.sha256")
        byte_count = require_positive_int(payload.get("byte_size"), "upload.byte_size", maximum=16 * 1024 * 1024)
        if sha256 != expected_sha256 or byte_count != expected_bytes:
            raise WorkerError("edge_artifact_mismatch", "Uploaded artifact acknowledgement does not match")
        if (
            not isinstance(storage_ref, str)
            or not re.fullmatch(r"[A-Za-z0-9._:/-]{1,1024}", storage_ref)
            or ".." in storage_ref.split("/")
        ):
            raise WorkerError("edge_response_invalid", "Uploaded artifact reference is invalid")
        return ArtifactReference(storage_ref=storage_ref, sha256=sha256, byte_count=byte_count)
