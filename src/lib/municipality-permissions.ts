const TAXPAYER_MANAGER_ROLES = new Set(["municipal_admin", "supervisor"]);

export function canManageMunicipalTaxpayers(role: string | null | undefined): boolean {
  return TAXPAYER_MANAGER_ROLES.has(role ?? "");
}
