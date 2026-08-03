export interface PortalQuestionSubmission {
  caseId: string;
  body: string;
  clientRequestId: string;
}

type RequestKeyFactory = () => string;

function defaultRequestKey(): string {
  return `portal:${crypto.randomUUID()}`;
}

/**
 * Keeps one idempotency key for one logical submission. A transport retry or
 * rapid second confirmation receives the same object; changing case or the
 * normalized question starts a new logical submission.
 */
export function preparePortalQuestionSubmission(
  previous: PortalQuestionSubmission | null,
  caseId: string,
  body: string,
  createRequestKey: RequestKeyFactory = defaultRequestKey,
): PortalQuestionSubmission {
  const normalizedBody = body.trim();
  if (previous?.caseId === caseId && previous.body === normalizedBody) {
    return previous;
  }

  return {
    caseId,
    body: normalizedBody,
    clientRequestId: createRequestKey(),
  };
}
