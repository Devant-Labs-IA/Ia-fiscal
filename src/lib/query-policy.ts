export const FISCAL_QUERY_STALE_TIME_MS = 30_000;
export const FISCAL_QUERY_GC_TIME_MS = 5 * 60_000;
// PostgREST already enforces an 8 s statement timeout for authenticated
// requests. Stop the browser first so a failed read always leaves the loading
// state with a useful retry action.
export const FISCAL_READ_TIMEOUT_MS = 7_500;

function errorCode(error: unknown): string {
  if (error && typeof error === "object" && "code" in error) {
    return String(error.code).toLocaleLowerCase("pt-BR");
  }
  return "";
}

function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message.toLocaleLowerCase("pt-BR");
  return String(error ?? "").toLocaleLowerCase("pt-BR");
}

export function shouldRetryFiscalQuery(failureCount: number, error: unknown): boolean {
  if (failureCount >= 1) return false;
  const code = errorCode(error);
  const message = errorMessage(error);
  return (
    error instanceof TypeError ||
    ["408", "425", "429", "502", "503", "504", "econnreset", "etimedout"].includes(code) ||
    /network|fetch failed|temporar|timeout|timed out|rate limit/.test(message)
  );
}

export function isFiscalQueryTimeout(error: unknown): boolean {
  const code = errorCode(error);
  const message = errorMessage(error);
  return code === "query_timeout" || /abort|timeout|timed out/.test(message);
}

export function fiscalQueryErrorMessage(error: unknown, fallback: string): string {
  return isFiscalQueryTimeout(error)
    ? "A consulta demorou mais do que o esperado. Tente novamente."
    : fallback;
}