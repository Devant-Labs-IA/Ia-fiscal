/** Formatações brasileiras (moeda, data, CNPJ). */

const currencyFormatter = new Intl.NumberFormat("pt-BR", {
  style: "currency",
  currency: "BRL",
});

const numberFormatter = new Intl.NumberFormat("pt-BR");

export function formatCurrency(value: number): string {
  return currencyFormatter.format(value);
}

export function formatNumber(value: number): string {
  return numberFormatter.format(value);
}

export function formatDate(value: string): string {
  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  }).format(new Date(value));
}

export function formatDateTime(value: string): string {
  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(value));
}

/** Aplica a máscara 00.000.000/0000-00. */
export function formatCnpj(cnpj: string): string {
  const digits = cnpj.replace(/\D/g, "").padStart(14, "0");
  return digits.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5");
}

/** Máscara parcial para exibição pública: 12.345.***\/**01-90 */
export function maskCnpj(cnpj: string): string {
  const digits = cnpj.replace(/\D/g, "").padStart(14, "0");
  return `${digits.slice(0, 2)}.${digits.slice(2, 5)}.***/**${digits.slice(10, 12)}-${digits.slice(12)}`;
}
