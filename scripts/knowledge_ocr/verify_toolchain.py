from __future__ import annotations

import json
import platform
import subprocess
import sys
import tempfile
from pathlib import Path

from .errors import WorkerError
from .extraction import _parser_environment, _sandbox_command


def verify(lock_path: Path) -> dict[str, str]:
    try:
        lock = json.loads(lock_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise WorkerError("toolchain_lock_invalid", "OCR toolchain lock could not be read") from error
    if lock.get("schema_version") != "ia-fiscal-knowledge-ocr-toolchain/v1":
        raise WorkerError("toolchain_lock_invalid", "OCR toolchain lock version does not match")
    if lock.get("architecture") != platform.machine().replace("x86_64", "amd64"):
        raise WorkerError("toolchain_mismatch", "OCR runner architecture does not match the lock")
    if platform.python_version() != lock.get("python"):
        raise WorkerError("toolchain_mismatch", "Python version does not match the OCR toolchain lock")
    packages = lock.get("packages")
    if not isinstance(packages, dict) or not packages:
        raise WorkerError("toolchain_lock_invalid", "OCR package lock is empty")
    installed: dict[str, str] = {}
    for package, expected_version in sorted(packages.items()):
        if not isinstance(package, str) or not isinstance(expected_version, str):
            raise WorkerError("toolchain_lock_invalid", "OCR package lock entry is invalid")
        result = subprocess.run(
            ["dpkg-query", "-W", "-f=${Version}", package],
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
        actual_version = result.stdout.strip() if result.returncode == 0 else ""
        if actual_version != expected_version:
            raise WorkerError("toolchain_mismatch", f"Installed package does not match lock: {package}")
        installed[package] = actual_version
    languages = subprocess.run(
        ["tesseract", "--list-langs"],
        check=False,
        capture_output=True,
        text=True,
        timeout=15,
    )
    if languages.returncode != 0 or "por" not in languages.stdout.splitlines():
        raise WorkerError("toolchain_mismatch", "Portuguese OCR language data is unavailable")
    _verify_parser_sandbox()
    return installed


def _verify_parser_sandbox() -> None:
    probe = (
        "import pathlib,socket,sys;"
        "env=pathlib.Path('/proc/1/environ').read_bytes();"
        "secret=b'ACTIONS_ID_TOKEN_REQUEST_TOKEN' in env;"
        "sock=socket.socket();sock.settimeout(0.2);"
        "network=sock.connect_ex(('1.1.1.1',443))==0;"
        "sys.exit(1 if secret or network else 0)"
    )
    with tempfile.TemporaryDirectory(prefix="ia-fiscal-ocr-sandbox-probe-") as temporary:
        command = _sandbox_command(["/usr/bin/python3", "-c", probe], Path(temporary))
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
            env=_parser_environment(),
        )
    if result.returncode != 0:
        raise WorkerError("toolchain_sandbox_failed", "Native parser sandbox verification failed")


def main() -> int:
    lock_path = Path(__file__).with_name("toolchain.lock.json")
    try:
        installed = verify(lock_path)
    except WorkerError as error:
        print(json.dumps({"event": "toolchain_rejected", "code": error.code}, separators=(",", ":")))
        return 1
    print(
        json.dumps(
            {"event": "toolchain_verified", "package_count": len(installed)},
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
