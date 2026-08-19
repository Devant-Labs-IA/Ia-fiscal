from __future__ import annotations

import json
import unittest
from urllib.error import HTTPError, URLError
from unittest.mock import patch

from scripts.knowledge_ocr import CONTRACT_VERSION
from scripts.knowledge_ocr.edge_client import (
    ArtifactReference,
    ClaimedJob,
    EdgeClient,
    JobLimits,
    SourceDescriptor,
    EXPECTED_EDGE_URL,
)
from scripts.knowledge_ocr.errors import WorkerError


class FakeOidc:
    def __init__(self, values: list[str]) -> None:
        self.values = iter(values)
        self.calls = 0

    def token(self) -> str:
        self.calls += 1
        return next(self.values)


class FakeResponse:
    status = 200

    def __init__(self, payload: dict[str, object]) -> None:
        self.raw = json.dumps(payload).encode()

    def __enter__(self) -> "FakeResponse":
        return self

    def __exit__(self, *_args: object) -> None:
        return None

    def read(self, _maximum: int) -> bytes:
        return self.raw


class ReplayRejectingEdge:
    def __init__(self) -> None:
        self.tokens: set[str] = set()

    def __call__(self, request, timeout: int):  # type: ignore[no-untyped-def]
        del timeout
        token = request.get_header("Authorization")
        if token in self.tokens:
            raise HTTPError(request.full_url, 403, "replay", {}, None)
        self.tokens.add(token)
        return FakeResponse({"contract_version": CONTRACT_VERSION, "status": "empty"})


class EdgeClientTests(unittest.TestCase):
    def make_client(self, tokens: list[str]) -> EdgeClient:
        return EdgeClient(
            EXPECTED_EDGE_URL,
            FakeOidc(tokens),  # type: ignore[arg-type]
            {"qvgenxcrdrqyiyozxtdt.supabase.co"},
        )

    def test_multicall_flow_uses_distinct_tokens(self) -> None:
        edge = ReplayRejectingEdge()
        client = self.make_client(["jwt-jti-1", "jwt-jti-2"])
        with patch("scripts.knowledge_ocr.edge_client.urlopen", side_effect=edge):
            self.assertIsNone(client.claim(run_id="1", run_attempt="1", claim_number=1))
            self.assertIsNone(client.claim(run_id="2", run_attempt="1", claim_number=1))
        self.assertEqual(client.oidc.calls, 2)

    def test_replayed_jti_is_rejected_as_403(self) -> None:
        edge = ReplayRejectingEdge()
        client = self.make_client(["jwt-same", "jwt-same"])
        with patch("scripts.knowledge_ocr.edge_client.urlopen", side_effect=edge):
            self.assertIsNone(client.claim(run_id="1", run_attempt="1", claim_number=1))
            with self.assertRaises(WorkerError) as captured:
                client.claim(run_id="2", run_attempt="1", claim_number=1)
        self.assertEqual(captured.exception.code, "edge_request_rejected")

    def test_contract_version_mismatch_fails_closed(self) -> None:
        client = self.make_client(["jwt-jti-1"])
        with patch(
            "scripts.knowledge_ocr.edge_client.urlopen",
            return_value=FakeResponse({"contract_version": "wrong", "status": "empty"}),
        ):
            with self.assertRaises(WorkerError) as captured:
                client.claim(run_id="1", run_attempt="1", claim_number=1)
        self.assertEqual(captured.exception.code, "edge_response_invalid")

    def test_claim_rejects_server_page_limit_above_v1_cap(self) -> None:
        client = self.make_client(["jwt-jti-1"])
        payload = {
            "contract_version": CONTRACT_VERSION,
            "job": {
                "id": "job-1",
                "attempt": 1,
                "max_attempts": 3,
                "lease_token": "l" * 32,
                "lease_expires_at": "2026-08-19T12:00:00Z",
            },
            "source": {
                "url": "https://qvgenxcrdrqyiyozxtdt.supabase.co/storage/source",
                "sha256": "0" * 64,
                "byte_size": 100,
                "mime_type": "application/pdf",
            },
            "limits": {
                "max_pages": 121,
                "max_page_characters": 100_000,
                "max_total_characters": 1_000_000,
                "max_part_bytes": 1_000_000,
            },
        }
        with patch(
            "scripts.knowledge_ocr.edge_client.urlopen", return_value=FakeResponse(payload)
        ):
            with self.assertRaises(WorkerError) as captured:
                client.claim(run_id="1", run_attempt="1", claim_number=1)
        self.assertEqual(captured.exception.code, "contract_invalid")

    def test_claim_parses_canonical_sql_limit_field_names(self) -> None:
        client = self.make_client(["jwt-jti-1"])
        payload = {
            "contract_version": CONTRACT_VERSION,
            "job": {
                "id": "job-1",
                "attempt": 1,
                "max_attempts": 3,
                "lease_token": "l" * 32,
                "lease_expires_at": "2026-08-19T12:00:00Z",
            },
            "source": {
                "url": "https://qvgenxcrdrqyiyozxtdt.supabase.co/storage/source",
                "sha256": "0" * 64,
                "byte_size": 100,
                "mime_type": "application/pdf",
            },
            "limits": {
                "max_pages": 120,
                "max_page_characters": 100_000,
                "max_total_characters": 1_000_000,
                "max_part_bytes": 1_000_000,
            },
        }
        with patch(
            "scripts.knowledge_ocr.edge_client.urlopen", return_value=FakeResponse(payload)
        ):
            job = client.claim(run_id="1", run_attempt="1", claim_number=1)
        self.assertIsNotNone(job)
        assert job is not None
        self.assertEqual(job.limits.max_page_chars, 100_000)
        self.assertEqual(job.limits.max_total_chars, 1_000_000)

    def test_complete_retries_response_loss_with_new_jti_and_refs_only(self) -> None:
        client = self.make_client(["jwt-jti-1", "jwt-jti-2"])
        job = ClaimedJob(
            job_id="job-1",
            lease_token="l" * 32,
            attempt=1,
            max_attempts=3,
            source=SourceDescriptor(
                url="https://qvgenxcrdrqyiyozxtdt.supabase.co/storage/source",
                sha256="0" * 64,
                byte_count=100,
                media_type="application/pdf",
            ),
            limits=JobLimits(
                max_pages=120,
                max_page_chars=100_000,
                max_total_chars=1_000_000,
                max_part_bytes=1_000_000,
            ),
        )
        artifact = ArtifactReference("ocr/job/manifest.json", "1" * 64, 123)
        requests = []
        response = FakeResponse(
            {
                "contract_version": CONTRACT_VERSION,
                "status": "already_completed",
                "job_id": "job-1",
                "content_sha256": "3" * 64,
                "page_count": 1,
                "publication_status": "not_published",
            }
        )

        def invoke(request, timeout):  # type: ignore[no-untyped-def]
            del timeout
            requests.append(request)
            if len(requests) == 1:
                raise URLError("response lost")
            return response

        pages = [
            {
                "page_number": 1,
                "artifact": {
                    "storage_ref": "ocr/job/page-1.json",
                    "sha256": "2" * 64,
                    "byte_size": 456,
                },
            }
        ]
        with patch("scripts.knowledge_ocr.edge_client.urlopen", side_effect=invoke):
            client.complete(
                job,
                engine_version="5.3.4",
                manifest=artifact,
                content_sha256="3" * 64,
                pages=pages,
            )
        self.assertEqual(client.oidc.calls, 2)
        self.assertEqual(len(requests), 2)
        first_body = json.loads(requests[0].data)
        second_body = json.loads(requests[1].data)
        self.assertEqual(first_body, second_body)
        self.assertEqual(first_body["pages"], pages)
        self.assertNotIn("content_text", json.dumps(first_body))
        first_key = requests[0].get_header("Idempotency-key")
        second_key = requests[1].get_header("Idempotency-key")
        self.assertEqual(first_key, second_key)

    def test_complete_unknown_success_status_never_becomes_reportable_failure(self) -> None:
        client = self.make_client(["jwt-jti-1"])
        job = ClaimedJob(
            job_id="job-1",
            lease_token="l" * 32,
            attempt=1,
            max_attempts=3,
            source=SourceDescriptor(
                url="https://qvgenxcrdrqyiyozxtdt.supabase.co/storage/source",
                sha256="0" * 64,
                byte_count=100,
                media_type="application/pdf",
            ),
            limits=JobLimits(
                max_pages=120,
                max_page_chars=100_000,
                max_total_chars=1_000_000,
                max_part_bytes=1_000_000,
            ),
        )
        artifact = ArtifactReference("ocr/job/manifest.json", "1" * 64, 123)
        with patch(
            "scripts.knowledge_ocr.edge_client.urlopen",
            return_value=FakeResponse(
                {
                    "contract_version": CONTRACT_VERSION,
                    "status": "unexpected_terminal_alias",
                    "job_id": "job-1",
                    "content_sha256": "3" * 64,
                    "page_count": 0,
                    "publication_status": "not_published",
                }
            ),
        ):
            with self.assertRaises(WorkerError) as captured:
                client.complete(
                    job,
                    engine_version="5.3.4",
                    manifest=artifact,
                    content_sha256="3" * 64,
                    pages=[],
                )
        self.assertEqual(captured.exception.code, "complete_outcome_unknown")
        self.assertTrue(captured.exception.retryable)

    def test_complete_refuses_any_response_that_claims_publication(self) -> None:
        client = self.make_client(["jwt-jti-1"])
        job = ClaimedJob(
            job_id="job-1",
            lease_token="l" * 32,
            attempt=1,
            max_attempts=3,
            source=SourceDescriptor(
                url="https://qvgenxcrdrqyiyozxtdt.supabase.co/storage/source",
                sha256="0" * 64,
                byte_count=100,
                media_type="application/pdf",
            ),
            limits=JobLimits(120, 100_000, 1_000_000, 1_000_000),
        )
        artifact = ArtifactReference("ocr/job/manifest.json", "1" * 64, 123)
        with patch(
            "scripts.knowledge_ocr.edge_client.urlopen",
            return_value=FakeResponse(
                {
                    "contract_version": CONTRACT_VERSION,
                    "status": "under_review",
                    "job_id": "job-1",
                    "content_sha256": "3" * 64,
                    "page_count": 0,
                    "publication_status": "published",
                }
            ),
        ):
            with self.assertRaises(WorkerError) as captured:
                client.complete(
                    job,
                    engine_version="5.3.4",
                    manifest=artifact,
                    content_sha256="3" * 64,
                    pages=[],
                )
        self.assertEqual(captured.exception.code, "complete_outcome_unknown")


if __name__ == "__main__":
    unittest.main()
