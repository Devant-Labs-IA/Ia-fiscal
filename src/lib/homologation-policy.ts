export const DEFAULT_HOMOLOGATION_EMAIL_SUBJECT =
  "Aviso informativo para conferência no CIGIS";

export function buildDefaultHomologationEmailBody(): string {
  return [
    "Olá,",
    "",
    "Identificamos informações fiscais que precisam ser conferidas no ambiente autenticado.",
    "",
    "Acesse normalmente o CIGIS e consulte a área de débitos e divergências. Caso precise de esclarecimentos, utilize o menu Atendimento Online.",
    "",
    "Esta mensagem é exclusivamente informativa. A análise e qualquer decisão permanecem sob responsabilidade da fiscalização competente.",
  ].join("\n");
}

export function homologationEmailBlockers(subject: string, body: string): string[] {
  const content = `${subject}\n${body}`;
  const blockers: string[] = [];

  if (/(https?:\/\/|www\.|href\s*=|<a(?:\s|>))/i.test(content)) {
    blockers.push("A mensagem de homologação não pode conter links.");
  }
  if (/(?:r\$|\bbrl\b|(?:^|\s)\d{1,3}(?:\.\d{3})*,\d{2}(?:\s|$))/i.test(content)) {
    blockers.push("A mensagem de homologação não pode conter valores monetários.");
  }
  if (/\b(anexo|anexos|anexa|anexado|attachment|attachments)\b/i.test(content)) {
    blockers.push("A mensagem de homologação não pode mencionar ou incluir anexos.");
  }
  if (subject.trim().length < 5 || subject.trim().length > 180) {
    blockers.push("O assunto precisa ter entre 5 e 180 caracteres.");
  }
  if (body.trim().length < 40 || body.trim().length > 5_000) {
    blockers.push("O corpo precisa ter entre 40 e 5.000 caracteres.");
  }

  return blockers;
}

export function extractTaxpayerIdFromPath(pathname: string): string | null {
  const match = /^\/contribuintes\/([^/?#]+)/.exec(pathname);
  if (!match?.[1]) return null;
  try {
    return decodeURIComponent(match[1]);
  } catch {
    return match[1];
  }
}
