from __future__ import annotations


class WorkerError(RuntimeError):
    """A classified error that is safe to report without source text."""

    def __init__(self, code: str, message: str, *, retryable: bool = False) -> None:
        super().__init__(message)
        self.code = code
        self.public_message = message
        self.retryable = retryable

