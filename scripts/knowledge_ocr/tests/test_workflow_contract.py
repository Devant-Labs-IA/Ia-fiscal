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
        self.assertIn("timeout-minutes: 55", workflow)
        self.assertIn("timeout --signal=TERM --kill-after=60s 45m", workflow)
        self.assertIn('OCR_MAX_JOBS: "1"', workflow)
        self.assertIn('OCR_ALLOWED_REPOSITORY_ID: "1320619695"', workflow)
        self.assertIn('OCR_ALLOWED_REPOSITORY_OWNER_ID: "296187202"', workflow)
        self.assertIn("knowledge-ocr-summary.json", workflow)
        self.assertIn("sensitive summary field rejected", workflow)

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
