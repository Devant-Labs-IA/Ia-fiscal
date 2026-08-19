from __future__ import annotations

import base64
import json
import os
import threading
import time
from dataclasses import dataclass, field
from typing import Any
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen

from .errors import WorkerError
from .integrity import validate_https_url


def _decode_segment(segment: str) -> dict[str, Any]:
    padding = "=" * (-len(segment) % 4)
    try:
        decoded = base64.urlsafe_b64decode(segment + padding)
        value = json.loads(decoded)
    except (ValueError, json.JSONDecodeError) as error:
        raise WorkerError("oidc_token_invalid", "OIDC token payload is malformed") from error
    if not isinstance(value, dict):
        raise WorkerError("oidc_token_invalid", "OIDC token payload is malformed")
    return value


def unverified_claims(token: str) -> dict[str, Any]:
    parts = token.split(".")
    if len(parts) != 3:
        raise WorkerError("oidc_token_invalid", "OIDC token is not a JWT")
    return _decode_segment(parts[1])


def validate_expected_claims(
    claims: dict[str, Any],
    *,
    audience: str,
    repository: str,
    repository_id: str,
    repository_owner_id: str,
    ref: str,
    environment: str,
    workflow_ref: str,
    now: int | None = None,
) -> int:
    current_time = int(time.time()) if now is None else now
    aud = claims.get("aud")
    audience_matches = aud == audience or (isinstance(aud, list) and audience in aud)
    if not audience_matches:
        raise WorkerError("oidc_claim_mismatch", "OIDC audience does not match")
    if claims.get("iss") != "https://token.actions.githubusercontent.com":
        raise WorkerError("oidc_claim_mismatch", "OIDC issuer does not match")
    if claims.get("repository") != repository:
        raise WorkerError("oidc_claim_mismatch", "OIDC repository does not match")
    if claims.get("ref") != ref:
        raise WorkerError("oidc_claim_mismatch", "OIDC ref does not match")
    if claims.get("environment") != environment:
        raise WorkerError("oidc_claim_mismatch", "OIDC environment does not match")
    try:
        owner, repository_name = repository.split("/", 1)
    except ValueError as error:
        raise WorkerError("configuration_invalid", "OIDC repository configuration is invalid") from error
    expected_subject = (
        f"repo:{owner}@{repository_owner_id}/"
        f"{repository_name}@{repository_id}:environment:{environment}"
    )
    if claims.get("sub") != expected_subject:
        raise WorkerError("oidc_claim_mismatch", "OIDC subject does not match")
    if claims.get("repository_id") != repository_id:
        raise WorkerError("oidc_claim_mismatch", "OIDC repository ID does not match")
    if claims.get("repository_owner_id") != repository_owner_id:
        raise WorkerError("oidc_claim_mismatch", "OIDC repository owner ID does not match")
    if claims.get("runner_environment") != "github-hosted":
        raise WorkerError("oidc_claim_mismatch", "OIDC runner environment does not match")
    if claims.get("workflow_ref") != workflow_ref:
        raise WorkerError("oidc_claim_mismatch", "OIDC workflow ref does not match")
    event_name = claims.get("event_name")
    if event_name not in {"schedule", "workflow_dispatch"}:
        raise WorkerError("oidc_claim_mismatch", "OIDC event is not permitted")
    exp = claims.get("exp")
    nbf = claims.get("nbf", current_time - 1)
    if not isinstance(exp, int) or not isinstance(nbf, int) or exp <= current_time + 30 or nbf > current_time + 30:
        raise WorkerError("oidc_token_invalid", "OIDC token lifetime is invalid")
    return exp


@dataclass
class GitHubOidcProvider:
    audience: str
    repository: str
    repository_id: str
    repository_owner_id: str
    ref: str
    environment: str
    workflow_ref: str
    request_url: str
    request_token: str
    _request_lock: threading.Lock = field(default_factory=threading.Lock, init=False, repr=False)

    @classmethod
    def from_environment(cls) -> "GitHubOidcProvider":
        required = {
            "OCR_OIDC_AUDIENCE": os.environ.get("OCR_OIDC_AUDIENCE"),
            "OCR_ALLOWED_REPOSITORY": os.environ.get("OCR_ALLOWED_REPOSITORY"),
            "OCR_ALLOWED_REPOSITORY_ID": os.environ.get("OCR_ALLOWED_REPOSITORY_ID"),
            "OCR_ALLOWED_REPOSITORY_OWNER_ID": os.environ.get("OCR_ALLOWED_REPOSITORY_OWNER_ID"),
            "OCR_ALLOWED_REF": os.environ.get("OCR_ALLOWED_REF"),
            "OCR_GITHUB_ENVIRONMENT": os.environ.get("OCR_GITHUB_ENVIRONMENT"),
            "OCR_ALLOWED_WORKFLOW_REF": os.environ.get("OCR_ALLOWED_WORKFLOW_REF"),
            "ACTIONS_ID_TOKEN_REQUEST_URL": os.environ.get("ACTIONS_ID_TOKEN_REQUEST_URL"),
            "ACTIONS_ID_TOKEN_REQUEST_TOKEN": os.environ.get("ACTIONS_ID_TOKEN_REQUEST_TOKEN"),
        }
        missing = [key for key, value in required.items() if not value]
        if missing:
            raise WorkerError("configuration_invalid", f"Missing OIDC configuration: {','.join(missing)}")
        assert all(isinstance(value, str) for value in required.values())
        request_url = str(required["ACTIONS_ID_TOKEN_REQUEST_URL"])
        request_host = urlsplit(request_url).hostname
        if not request_host or not request_host.endswith(".actions.githubusercontent.com"):
            raise WorkerError("configuration_invalid", "OIDC request URL is invalid")
        validate_https_url(request_url, {request_host}, field="ACTIONS_ID_TOKEN_REQUEST_URL")
        return cls(
            audience=str(required["OCR_OIDC_AUDIENCE"]),
            repository=str(required["OCR_ALLOWED_REPOSITORY"]),
            repository_id=str(required["OCR_ALLOWED_REPOSITORY_ID"]),
            repository_owner_id=str(required["OCR_ALLOWED_REPOSITORY_OWNER_ID"]),
            ref=str(required["OCR_ALLOWED_REF"]),
            environment=str(required["OCR_GITHUB_ENVIRONMENT"]),
            workflow_ref=str(required["OCR_ALLOWED_WORKFLOW_REF"]),
            request_url=request_url,
            request_token=str(required["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]),
        )

    def token(self) -> str:
        # The Edge audit ledger consumes each JWT `jti` exactly once. Never cache,
        # persist, retry, or reuse an ID token across Edge actions.
        with self._request_lock:
            return self._fresh_token()

    def _fresh_token(self) -> str:
        parsed = urlsplit(self.request_url)
        query = dict(parse_qsl(parsed.query, keep_blank_values=True))
        query["audience"] = self.audience
        url = urlunsplit((parsed.scheme, parsed.netloc, parsed.path, urlencode(query), parsed.fragment))
        request = Request(
            url,
            headers={"Authorization": f"Bearer {self.request_token}", "Accept": "application/json"},
            method="GET",
        )
        try:
            with urlopen(request, timeout=20) as response:  # noqa: S310 - URL is validated above.
                raw = response.read(256 * 1024 + 1)
        except OSError as error:
            raise WorkerError("oidc_request_failed", "GitHub OIDC token request failed", retryable=True) from error
        if len(raw) > 256 * 1024:
            raise WorkerError("oidc_response_invalid", "GitHub OIDC response is too large")
        try:
            payload = json.loads(raw)
            token = payload["value"]
        except (json.JSONDecodeError, KeyError, TypeError) as error:
            raise WorkerError("oidc_response_invalid", "GitHub OIDC response is malformed") from error
        if not isinstance(token, str) or len(token) > 16_384:
            raise WorkerError("oidc_response_invalid", "GitHub OIDC response is malformed")
        validate_expected_claims(
            unverified_claims(token),
            audience=self.audience,
            repository=self.repository,
            repository_id=self.repository_id,
            repository_owner_id=self.repository_owner_id,
            ref=self.ref,
            environment=self.environment,
            workflow_ref=self.workflow_ref,
        )
        return token
