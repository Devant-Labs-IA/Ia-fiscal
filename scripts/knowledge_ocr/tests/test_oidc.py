from __future__ import annotations

import base64
import json
import time
import unittest
from unittest.mock import patch

from scripts.knowledge_ocr.errors import WorkerError
from scripts.knowledge_ocr.oidc import GitHubOidcProvider, validate_expected_claims

AUDIENCE = "ia-fiscal-knowledge-ocr-qvgenxcrdrqyiyozxtdt"
REPOSITORY = "AlmoreContabilidade/Ia-fiscal"
REPOSITORY_ID = "1320619695"
REPOSITORY_OWNER_ID = "296187202"
REF = "refs/heads/main"
ENVIRONMENT = "knowledge-ocr"
WORKFLOW_REF = "AlmoreContabilidade/Ia-fiscal/.github/workflows/knowledge-ocr.yml@refs/heads/main"


def token_with_claims(claims: dict[str, object]) -> str:
    def segment(value: dict[str, object]) -> str:
        return base64.urlsafe_b64encode(json.dumps(value).encode()).rstrip(b"=").decode()

    return f"{segment({'alg': 'RS256'})}.{segment(claims)}.signature"


def valid_claims(**overrides: object) -> dict[str, object]:
    claims: dict[str, object] = {
        "aud": AUDIENCE,
        "iss": "https://token.actions.githubusercontent.com",
        "repository": REPOSITORY,
        "ref": REF,
        "environment": ENVIRONMENT,
        "sub": (
            f"repo:AlmoreContabilidade@{REPOSITORY_OWNER_ID}/"
            f"Ia-fiscal@{REPOSITORY_ID}:environment:{ENVIRONMENT}"
        ),
        "repository_id": REPOSITORY_ID,
        "repository_owner_id": REPOSITORY_OWNER_ID,
        "runner_environment": "github-hosted",
        "workflow_ref": WORKFLOW_REF,
        "event_name": "schedule",
        "exp": int(time.time()) + 300,
        "nbf": int(time.time()) - 10,
        "jti": "unique-jti",
    }
    claims.update(overrides)
    return claims


class FakeResponse:
    def __init__(self, token: str) -> None:
        self.raw = json.dumps({"value": token}).encode()

    def __enter__(self) -> "FakeResponse":
        return self

    def __exit__(self, *_args: object) -> None:
        return None

    def read(self, _maximum: int) -> bytes:
        return self.raw


class OidcTests(unittest.TestCase):
    def test_claims_require_exact_direct_workflow_ref(self) -> None:
        validate_expected_claims(
            valid_claims(),
            audience=AUDIENCE,
            repository=REPOSITORY,
            repository_id=REPOSITORY_ID,
            repository_owner_id=REPOSITORY_OWNER_ID,
            ref=REF,
            environment=ENVIRONMENT,
            workflow_ref=WORKFLOW_REF,
        )
        with self.assertRaisesRegex(WorkerError, "workflow"):
            validate_expected_claims(
                valid_claims(workflow_ref=None, job_workflow_ref=WORKFLOW_REF),
                audience=AUDIENCE,
                repository=REPOSITORY,
                repository_id=REPOSITORY_ID,
                repository_owner_id=REPOSITORY_OWNER_ID,
                ref=REF,
                environment=ENVIRONMENT,
                workflow_ref=WORKFLOW_REF,
            )

    def test_provider_requests_a_fresh_jti_for_every_call(self) -> None:
        tokens = [
            token_with_claims(valid_claims(jti="jti-1")),
            token_with_claims(valid_claims(jti="jti-2")),
        ]
        responses = [FakeResponse(token) for token in tokens]
        provider = GitHubOidcProvider(
            audience=AUDIENCE,
            repository=REPOSITORY,
            repository_id=REPOSITORY_ID,
            repository_owner_id=REPOSITORY_OWNER_ID,
            ref=REF,
            environment=ENVIRONMENT,
            workflow_ref=WORKFLOW_REF,
            request_url="https://actions.example.test/id-token",
            request_token="runner-request-token",
        )
        with patch("scripts.knowledge_ocr.oidc.urlopen", side_effect=responses) as request:
            self.assertEqual(provider.token(), tokens[0])
            self.assertEqual(provider.token(), tokens[1])
        self.assertEqual(request.call_count, 2)

    def test_wrong_audience_repository_or_ref_fails_closed(self) -> None:
        for override in (
            {"aud": "wrong"},
            {"repository": "someone/else"},
            {"repository_id": "999"},
            {"repository_owner_id": "999"},
            {"sub": f"repo:{REPOSITORY}:environment:{ENVIRONMENT}"},
            {"runner_environment": "self-hosted"},
            {"ref": "refs/heads/feature"},
            {"environment": "other"},
        ):
            with self.subTest(override=override), self.assertRaises(WorkerError):
                validate_expected_claims(
                    valid_claims(**override),
                    audience=AUDIENCE,
                    repository=REPOSITORY,
                    repository_id=REPOSITORY_ID,
                    repository_owner_id=REPOSITORY_OWNER_ID,
                    ref=REF,
                    environment=ENVIRONMENT,
                    workflow_ref=WORKFLOW_REF,
                )


if __name__ == "__main__":
    unittest.main()
