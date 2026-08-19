from __future__ import annotations

import json
import hashlib
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]


class WorkflowContractTests(unittest.TestCase):
    def test_workflow_uses_oidc_without_administrative_secret(self) -> None:
        workflow = (ROOT / ".github/workflows/knowledge-ocr.yml").read_text(encoding="utf-8")
        self.assertIn("id-token: write", workflow)
        self.assertIn("environment: knowledge-ocr", workflow)
        self.assertIn("OCR_ALLOWED_WORKFLOW_REF:", workflow)
        self.assertNotIn("SERVICE_ROLE", workflow)
        self.assertNotIn("SUPABASE_ACCESS_TOKEN", workflow)

    def test_actions_and_packages_are_immutable_or_exactly_pinned(self) -> None:
        workflow = (ROOT / ".github/workflows/knowledge-ocr.yml").read_text(encoding="utf-8")
        lock = json.loads(
            (ROOT / "scripts/knowledge_ocr/toolchain.lock.json").read_text(encoding="utf-8")
        )
        action_uses = re.findall(r"uses:\s*([^\s#]+)", workflow)
        self.assertGreaterEqual(len(action_uses), 3)
        for action in action_uses:
            self.assertRegex(action, r"@[0-9a-f]{40}$")
        for package, version in lock["packages"].items():
            self.assertIn(f"{package}={version}", workflow)
        lock_bytes = (ROOT / "scripts/knowledge_ocr/toolchain.lock.json").read_bytes()
        self.assertEqual(
            hashlib.sha256(lock_bytes).hexdigest(),
            "6bb5c3a93dad84e38ea05cedb47e1aeee13c8a22899f0cb9f693e114e5e5cd60",
        )

    def test_workflow_has_timeouts_and_metadata_only_artifact(self) -> None:
        workflow = (ROOT / ".github/workflows/knowledge-ocr.yml").read_text(encoding="utf-8")
        self.assertIn("timeout-minutes: 65", workflow)
        self.assertIn("timeout --signal=TERM --kill-after=60s 45m", workflow)
        self.assertIn('OCR_MAX_JOBS: "1"', workflow)
        self.assertIn('OCR_ALLOWED_REPOSITORY_ID: "1320619695"', workflow)
        self.assertIn('OCR_ALLOWED_REPOSITORY_OWNER_ID: "296187202"', workflow)
        self.assertIn("knowledge-ocr-summary.json", workflow)
        self.assertIn("sensitive summary field rejected", workflow)

    def test_apt_install_is_bounded_and_has_official_ubuntu_fallback(self) -> None:
        workflow = (ROOT / ".github/workflows/knowledge-ocr.yml").read_text(encoding="utf-8")
        install_step = workflow[
            workflow.index("- name: Install the locked OCR toolchain") : workflow.index(
                "- name: Verify toolchain and fail-closed unit tests"
            )
        ]

        self.assertIn("timeout-minutes: 6", install_step)
        self.assertIn('test "$os_version" = "24.04"', install_step)
        self.assertIn('test "$(dpkg --print-architecture)" = "amd64"', install_step)
        self.assertIn("Acquire::Retries=1", install_step)
        self.assertIn("Acquire::http::Timeout=10", install_step)
        self.assertIn("Acquire::https::Timeout=10", install_step)
        self.assertIn("DPkg::Lock::Timeout=30", install_step)
        self.assertIn(
            'timeout --signal=TERM --kill-after=15s "$budget"', install_step
        )
        self.assertIn(
            'apt_update "$primary_sources" "$primary_lists" 45s', install_step
        )
        self.assertIn(
            'apt_update "$fallback_sources" "$fallback_lists" 75s', install_step
        )
        self.assertIn("timeout --signal=TERM --kill-after=15s 150s", install_step)
        self.assertIn("http://azure.archive.ubuntu.com/ubuntu/", install_step)
        self.assertIn("http://archive.ubuntu.com/ubuntu/", install_step)
        self.assertGreaterEqual(
            install_step.count("http://security.ubuntu.com/ubuntu/"),
            2,
        )
        self.assertEqual(
            install_step.count(
                "Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg"
            ),
            4,
        )
        self.assertIn('Dir::Etc::sourceparts="-"', install_step)
        self.assertNotRegex(install_step, r"\b(?:curl|wget)\b")
        self.assertNotIn("trusted=yes", install_step)
        self.assertNotIn("--allow-unauthenticated", install_step)
        self.assertNotIn("Acquire::AllowInsecureRepositories", install_step)

        job_match = re.search(r"(?m)^    timeout-minutes: (\d+)$", workflow)
        deadline_match = re.search(
            r'(?m)^      OCR_JOB_DEADLINE_SECONDS: "(\d+)"$', workflow
        )
        self.assertIsNotNone(job_match)
        self.assertIsNotNone(deadline_match)
        assert job_match is not None
        assert deadline_match is not None
        job_minutes = int(job_match.group(1))
        deadline_seconds = int(deadline_match.group(1))
        self.assertGreaterEqual(
            (job_minutes - 6) * 60 - deadline_seconds,
            9 * 60,
        )
        self.assertLessEqual(
            (45 + 15) + (75 + 15) + (150 + 15),
            6 * 60,
        )

    def test_job_environment_does_not_use_runner_context(self) -> None:
        workflow = (ROOT / ".github/workflows/knowledge-ocr.yml").read_text(encoding="utf-8")
        lines = workflow.splitlines()
        job_env_start = lines.index("    env:")
        job_env_lines: list[str] = []
        for line in lines[job_env_start + 1 :]:
            indentation = len(line) - len(line.lstrip())
            if line.strip() and indentation < 6:
                break
            job_env_lines.append(line)

        job_environment = "\n".join(job_env_lines)
        self.assertNotIn("${{ runner.", job_environment)
        self.assertNotIn("OCR_SUMMARY_PATH:", job_environment)
        self.assertIn(': "${RUNNER_TEMP:?RUNNER_TEMP is required}"', workflow)
        self.assertIn(
            '"$RUNNER_TEMP/knowledge-ocr-summary.json" >> "$GITHUB_ENV"',
            workflow,
        )


if __name__ == "__main__":
    unittest.main()
