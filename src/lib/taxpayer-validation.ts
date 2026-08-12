import type { CreateTaxpayerInput } from "@/types/fiscal";

export type TaxpayerField = keyof CreateTaxpayerInput;
export type TaxpayerValidationErrors = Partial<Record<TaxpayerField, string>>;

export interface TaxpayerValidationResult {
  data: CreateTaxpayerInput;
  errors: TaxpayerValidationErrors;
  valid: boolean;
}

/** Normaliza apenas representação; nenhuma informação fiscal é inferida. */
export function validateTaxpayerInput(input: CreateTaxpayerInput): TaxpayerValidationResult {
  const data: CreateTaxpayerInput = {
    municipalRegistration: input.municipalRegistration.trim(),
    taxId: input.taxId.replace(/\D/g, ""),
    legalName: input.legalName.trim(),
    tradeName: input.tradeName.trim(),
    taxpayerType: input.taxpayerType,
  };
  const errors: TaxpayerValidationErrors = {};

  if (!data.municipalRegistration) {
    errors.municipalRegistration = "Informe a inscrição municipal.";
  } else if (data.municipalRegistration.length > 50) {
    errors.municipalRegistration = "Use no máximo 50 caracteres.";
  }

  if (data.taxId.length !== 11 && data.taxId.length !== 14) {
    errors.taxId = "Informe um CPF com 11 dígitos ou CNPJ com 14 dígitos.";
  }

  if (data.legalName.length < 3) {
    errors.legalName = "Informe a razão social ou o nome completo.";
  } else if (data.legalName.length > 180) {
    errors.legalName = "Use no máximo 180 caracteres.";
  }

  if (data.tradeName.length > 180) {
    errors.tradeName = "Use no máximo 180 caracteres.";
  }

  if (!["company", "individual", "other"].includes(data.taxpayerType)) {
    errors.taxpayerType = "Selecione um tipo de contribuinte.";
  }

  return { data, errors, valid: Object.keys(errors).length === 0 };
}

export function maskTaxpayerTaxId(value: string): string {
  const digits = value.replace(/\D/g, "");
  if (digits.length === 11) {
    return `${digits.slice(0, 3)}.***.***-${digits.slice(-2)}`;
  }
  if (digits.length === 14) {
    return `${digits.slice(0, 2)}.${digits.slice(2, 5)}.***/****-${digits.slice(-2)}`;
  }
  return "Identificador não informado";
}