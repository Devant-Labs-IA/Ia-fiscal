from __future__ import annotations

import hashlib
import ipaddress
import json
import os
import re
import unicodedata
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

from .errors import WorkerError

_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path, *, chunk_size: int = 1024 * 1024) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as handle:
        while chunk := handle.read(chunk_size):
            digest.update(chunk)
            size += len(chunk)
    return digest.hexdigest(), size


def require_sha256(value: Any, field: str) -> str:
    if not isinstance(value, str) or not _SHA256_RE.fullmatch(value):
        raise WorkerError("contract_invalid", f"{field} must be a lowercase SHA-256")
    return value


def require_positive_int(value: Any, field: str, *, maximum: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 1 or value > maximum:
        raise WorkerError("contract_invalid", f"{field} is outside the accepted range")
    return value


def verify_file(path: Path, expected_sha256: str, expected_bytes: int) -> None:
    actual_sha256, actual_bytes = sha256_file(path)
    if actual_bytes != expected_bytes:
        raise WorkerError("source_size_mismatch", "Downloaded source byte count does not match")
    if not _constant_time_text_equal(actual_sha256, expected_sha256):
        raise WorkerError("source_sha256_mismatch", "Downloaded source SHA-256 does not match")


def normalize_text(value: str) -> str:
    normalized = unicodedata.normalize("NFC", value.replace("\r\n", "\n").replace("\r", "\n"))
    cleaned = "".join(
        character
        for character in normalized
        if character in {"\n", "\t"} or unicodedata.category(character) != "Cc"
    )
    lines = [line.rstrip() for line in cleaned.split("\n")]
    while lines and not lines[0]:
        lines.pop(0)
    while lines and not lines[-1]:
        lines.pop()
    return "\n".join(lines)


def validate_https_url(url: str, allowed_hosts: set[str], *, field: str) -> str:
    try:
        parsed = urlsplit(url)
        port = parsed.port
    except ValueError as error:
        raise WorkerError("contract_invalid", f"{field} is not a valid URL") from error

    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise WorkerError("url_not_allowed", f"{field} must be an HTTPS URL without credentials")
    if port not in (None, 443):
        raise WorkerError("url_not_allowed", f"{field} uses a disallowed port")

    hostname = parsed.hostname.rstrip(".").lower()
    try:
        address = ipaddress.ip_address(hostname)
    except ValueError:
        address = None
    if address is not None and not address.is_global:
        raise WorkerError("url_not_allowed", f"{field} resolves to a non-public address literal")

    normalized_hosts = {host.rstrip(".").lower() for host in allowed_hosts if host.strip()}
    if hostname not in normalized_hosts:
        raise WorkerError("url_not_allowed", f"{field} host is outside the configured allowlist")
    return url


def parse_host_allowlist(value: str | None, *, edge_url: str) -> set[str]:
    hosts = {item.strip().lower() for item in (value or "").split(",") if item.strip()}
    edge_host = urlsplit(edge_url).hostname
    if edge_host:
        hosts.add(edge_host.lower())
    if not hosts:
        raise WorkerError("configuration_invalid", "No download host is allowlisted")
    return hosts


def safe_identifier(value: Any, field: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9._:-]{1,160}", value):
        raise WorkerError("contract_invalid", f"{field} is invalid")
    return value


def redact_identifier(value: str) -> str:
    return sha256_bytes(value.encode("utf-8"))[:16]


def _constant_time_text_equal(left: str, right: str) -> bool:
    if len(left) != len(right):
        return False
    result = 0
    for left_byte, right_byte in zip(left.encode(), right.encode(), strict=True):
        result |= left_byte ^ right_byte
    return result == 0


def assert_private_file(path: Path) -> None:
    mode = os.stat(path).st_mode & 0o777
    if mode & 0o077:
        raise WorkerError("workspace_permissions_invalid", "Worker file permissions are too broad")

