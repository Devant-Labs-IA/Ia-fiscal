from __future__ import annotations

import time
import unittest

from scripts.knowledge_ocr.edge_client import ClaimedJob, JobLimits, SourceDescriptor
from scripts.knowledge_ocr.errors import WorkerError
from scripts.knowledge_ocr.worker import LeaseKeeper


def make_job() -> ClaimedJob:
    return ClaimedJob(
        job_id="job-1",
        lease_token="l" * 32,
        attempt=1,
        max_attempts=3,
        source=SourceDescriptor(
            url="https://project.supabase.co/source",
            sha256="0" * 64,
            byte_count=10,
            media_type="application/pdf",
        ),
        limits=JobLimits(
            max_pages=120,
            max_page_chars=100_000,
            max_total_chars=1_000_000,
            max_part_bytes=1_000_000,
        ),
    )


class HeartbeatClient:
    def __init__(self, fail_at: int | None = None) -> None:
        self.sequences: list[int] = []
        self.fail_at = fail_at

    def heartbeat(self, _job: ClaimedJob, *, sequence: int) -> None:
        self.sequences.append(sequence)
        if self.fail_at == sequence:
            raise WorkerError("edge_request_rejected", "lease lost")


class LeaseKeeperTests(unittest.TestCase):
    def test_heartbeat_starts_immediately_repeats_and_joins(self) -> None:
        client = HeartbeatClient()
        keeper = LeaseKeeper(client, make_job(), interval_seconds=0.01)  # type: ignore[arg-type]
        keeper.start()
        time.sleep(0.035)
        keeper.stop()
        self.assertGreaterEqual(len(client.sequences), 2)
        self.assertEqual(client.sequences, list(range(1, len(client.sequences) + 1)))
        self.assertFalse(keeper._thread.is_alive())

    def test_lease_loss_fails_closed_before_processing(self) -> None:
        keeper = LeaseKeeper(HeartbeatClient(fail_at=1), make_job(), interval_seconds=0.01)  # type: ignore[arg-type]
        with self.assertRaises(WorkerError) as captured:
            keeper.start()
        keeper.stop()
        self.assertEqual(captured.exception.code, "lease_heartbeat_failed")


if __name__ == "__main__":
    unittest.main()
