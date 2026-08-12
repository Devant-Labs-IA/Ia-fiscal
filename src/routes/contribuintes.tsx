import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Link, createFileRoute } from "@tanstack/react-router";
import { Archive, ArrowRight, Building2, Pencil, Plus, Search } from "lucide-react";
import { useId, useMemo, useState, type FormEvent, type ReactNode } from "react";
import { toast } from "sonner";

import { useAuth } from "@/auth/AuthContext";
import {
  EmptyState,
  ErrorState,
  SectionCard,
  SectionSkeleton,
} from "@/components/common/SectionCard";
import { StatusBadge } from "@/components/common/StatusBadges";
import { HomologationBanner } from "@/components/layout/HomologationBanner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { formatCurrency } from "@/lib/format";
import {
  maskTaxpayerTaxId,
  validateTaxpayerInput,
  type TaxpayerValidationErrors,
} from "@/lib/taxpayer-validation";
import { fiscalKeys, fiscalService } from "@/services/fiscal-service";
import type { CreateTaxpayerInput } from "@/types/fiscal";
import type { Taxpayer360Summary } from "@/types/read-models";

export const Route = createFileRoute("/contribuintes")({
  head: () => ({
    meta: [
      { title: "Contribuintes — IA Fiscal" },
      {
        name: "description",
        content: "Visão operacional dos contribuintes autorizados para a sessão atual.",
      },
      { property: "og:title", content: "Contribuintes — IA Fiscal" },
      {
        property: "og:description",
        content: "Visão operacional dos contribuintes autorizados para a sessão atual.",
      },
    ],
  }),
  component: TaxpayersPage,
});

type AttentionFilter = "todos" | "com_atencao" | "sem_atencao";
type TaxpayerEditor = { mode: "create" } | { mode: "edit"; taxpayer: Taxpayer360Summary };

const MANAGER_ROLES = new Set([
  "platform_admin",
  "municipal_admin",
  "supervisor",
]);

function TaxpayersPage() {
  const auth = useAuth();
  const queryClient = useQueryClient();
  const municipalityId = auth.access?.municipalityId ?? "";
  const [query, setQuery] = useState("");
  const [attention, setAttention] = useState<AttentionFilter>("todos");
  const [editor, setEditor] = useState<TaxpayerEditor | null>(null);
  const [archiveCandidate, setArchiveCandidate] = useState<Taxpayer360Summary | null>(null);
  const canManage =
    Boolean(auth.access?.platformAdmin) || MANAGER_ROLES.has(auth.access?.role ?? "");
  const taxpayers = useQuery({
    queryKey: fiscalKeys.taxpayers(municipalityId),
    queryFn: () => fiscalService.listTaxpayerSummaries(municipalityId),
    enabled: Boolean(municipalityId),
  });
  const saveTaxpayer = useMutation({
    mutationFn: async ({
      taxpayerId,
      input,
    }: {
      taxpayerId?: string;
      input: CreateTaxpayerInput;
    }) => {
      if (taxpayerId) {
        await fiscalService.updateTaxpayer(municipalityId, taxpayerId, input);
        return "updated" as const;
      }
      await fiscalService.createTaxpayer(municipalityId, input);
      return "created" as const;
    },
    onSuccess: async (operation) => {
      await queryClient.invalidateQueries({ queryKey: ["municipality", municipalityId] });
      setEditor(null);
      toast.success(
        operation === "created"
          ? "Contribuinte cadastrado com sucesso."
          : "Cadastro do contribuinte atualizado.",
      );
    },
    onError: (error) => toast.error(taxpayerWriteErrorMessage(error)),
  });
  const archiveTaxpayer = useMutation({
    mutationFn: (taxpayerId: string) => fiscalService.archiveTaxpayer(municipalityId, taxpayerId),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["municipality", municipalityId] });
      setArchiveCandidate(null);
      toast.success("Contribuinte arquivado. O histórico e a auditoria foram preservados.");
    },
    onError: (error) => toast.error(taxpayerWriteErrorMessage(error)),
  });

  const filtered = useMemo(() => {
    const term = query.trim().toLocaleLowerCase("pt-BR");
    const digits = query.replace(/\D/g, "");

    return (taxpayers.data ?? []).filter((item) => {
      const needsAttention =
        item.openBalanceTotal > 0 ||
        item.activeDivergenceCount > 0 ||
        item.blockedCalculationCount > 0 ||
        item.waitingQuestionCount > 0;
      const matchesAttention =
        attention === "todos" || (attention === "com_atencao" ? needsAttention : !needsAttention);
      const matchesTerm =
        term.length === 0 ||
        item.legalName.toLocaleLowerCase("pt-BR").includes(term) ||
        item.tradeName.toLocaleLowerCase("pt-BR").includes(term) ||
        item.municipalRegistration.toLocaleLowerCase("pt-BR").includes(term) ||
        (digits.length > 0 && item.taxId.replace(/\D/g, "").includes(digits));

      return matchesAttention && matchesTerm;
    });
  }, [attention, query, taxpayers.data]);

  const openBalance = (taxpayers.data ?? []).reduce(
    (total, item) => total + item.openBalanceTotal,
    0,
  );
  const activeCases = (taxpayers.data ?? []).reduce(
    (total, item) => total + item.activeCaseCount,
    0,
  );

  return (
    <div className="space-y-5 py-4">
      <HomologationBanner />

      <header className="flex flex-col justify-between gap-3 sm:flex-row sm:items-start">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">Contribuintes</h1>
          <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
            Consulte, cadastre e mantenha os contribuintes do município atual. Abra a ficha para
            visualizar os dados fiscais consolidados.
          </p>
        </div>
        {canManage && (
          <Button onClick={() => setEditor({ mode: "create" })}>
            <Plus aria-hidden />
            Cadastrar contribuinte
          </Button>
        )}
      </header>

      {taxpayers.isLoading ? (
        <SectionSkeleton rows={3} />
      ) : taxpayers.isError ? (
        <ErrorState
          message="Não foi possível carregar os contribuintes autorizados."
          error={taxpayers.error}
          onRetry={() => void taxpayers.refetch()}
          retrying={taxpayers.isFetching}
        />
      ) : (
        <div className="grid gap-3 sm:grid-cols-3">
          <SummaryMetric
            label="Contribuintes visíveis"
            value={String((taxpayers.data ?? []).length)}
          />
          <SummaryMetric label="Saldo em aberto" value={formatCurrency(openBalance)} />
          <SummaryMetric label="Casos ativos" value={String(activeCases)} />
        </div>
      )}

      <SectionCard
        title="Cadastro fiscal"
        description="Alterações são restritas ao município atual e registradas pelo backend."
        action={
          <Badge variant="secondary" className="tabular-nums">
            {filtered.length} registro{filtered.length === 1 ? "" : "s"}
          </Badge>
        }
      >
        <div className="mb-4 flex flex-col gap-2 sm:flex-row">
          <div className="relative min-w-0 flex-1">
            <Search
              className="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"
              aria-hidden
            />
            <Input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Razão social, CNPJ ou inscrição municipal"
              aria-label="Pesquisar contribuinte"
              className="pl-8"
            />
          </div>
          <Select
            value={attention}
            onValueChange={(value) => setAttention(value as AttentionFilter)}
          >
            <SelectTrigger className="w-full sm:w-52" aria-label="Filtrar necessidade de atenção">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="todos">Todos</SelectItem>
              <SelectItem value="com_atencao">Com atenção operacional</SelectItem>
              <SelectItem value="sem_atencao">Sem atenção pendente</SelectItem>
            </SelectContent>
          </Select>
        </div>

        {taxpayers.isLoading ? (
          <SectionSkeleton rows={6} />
        ) : taxpayers.isError ? (
          <ErrorState
            message="A listagem de contribuintes está temporariamente indisponível."
            error={taxpayers.error}
            onRetry={() => void taxpayers.refetch()}
            retrying={taxpayers.isFetching}
          />
        ) : (taxpayers.data ?? []).length === 0 ? (
          <div className="rounded-md border border-dashed border-border px-4 py-8 text-center">
            <p className="text-sm text-muted-foreground">
              Este município ainda não possui contribuintes cadastrados.
            </p>
            {canManage && (
              <Button className="mt-4" size="sm" onClick={() => setEditor({ mode: "create" })}>
                <Plus aria-hidden />
                Fazer primeiro cadastro
              </Button>
            )}
          </div>
        ) : filtered.length === 0 ? (
          <EmptyState message="Nenhum contribuinte corresponde aos filtros aplicados." />
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Contribuinte</TableHead>
                  <TableHead>Inscrição municipal</TableHead>
                  <TableHead>Situação</TableHead>
                  <TableHead className="text-right">Saldo em aberto</TableHead>
                  <TableHead className="text-right">Divergências ativas</TableHead>
                  <TableHead>Ação prioritária</TableHead>
                  <TableHead className="text-right">Ações</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filtered.map((item) => (
                  <TableRow key={item.taxpayerId}>
                    <TableCell className="min-w-64">
                      <span className="block font-medium">{item.legalName}</span>
                      <span className="block text-xs tabular-nums text-muted-foreground">
                        {maskTaxpayerTaxId(item.taxId)}
                      </span>
                    </TableCell>
                    <TableCell className="tabular-nums">{item.municipalRegistration}</TableCell>
                    <TableCell>
                      <StatusBadge status={item.taxpayerStatus} />
                    </TableCell>
                    <TableCell className="text-right font-medium tabular-nums">
                      {formatCurrency(item.openBalanceTotal)}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">
                      {item.activeDivergenceCount}
                    </TableCell>
                    <TableCell className="max-w-72 text-sm text-muted-foreground">
                      {item.primaryActionLabel ?? "Sem ação prioritária registrada"}
                    </TableCell>
                    <TableCell>
                      <div className="flex min-w-max justify-end gap-1.5">
                        {canManage && (
                          <>
                            <Button
                              variant="outline"
                              size="icon"
                              aria-label={`Editar ${item.legalName}`}
                              title="Editar cadastro"
                              onClick={() => setEditor({ mode: "edit", taxpayer: item })}
                            >
                              <Pencil aria-hidden />
                            </Button>
                            <Button
                              variant="outline"
                              size="icon"
                              aria-label={`Arquivar ${item.legalName}`}
                              title={
                                item.taxpayerStatus === "inactive"
                                  ? "Contribuinte já arquivado"
                                  : "Arquivar contribuinte"
                              }
                              disabled={item.taxpayerStatus === "inactive"}
                              onClick={() => setArchiveCandidate(item)}
                            >
                              <Archive aria-hidden />
                            </Button>
                          </>
                        )}
                        <Button asChild variant="outline" size="sm">
                          <Link
                            to="/contribuintes/$taxpayerId"
                            params={{ taxpayerId: item.taxpayerId }}
                          >
                            Abrir 360
                            <ArrowRight className="size-4" aria-hidden />
                          </Link>
                        </Button>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
      </SectionCard>

      {editor && (
        <TaxpayerEditorDialog
          key={editor.mode === "create" ? "new" : editor.taxpayer.taxpayerId}
          editor={editor}
          municipalityLabel={auth.access?.municipalityLabel ?? "município atual"}
          pending={saveTaxpayer.isPending}
          onClose={() => setEditor(null)}
          onSave={(input) => {
            saveTaxpayer.mutate(
              editor.mode === "edit"
                ? { taxpayerId: editor.taxpayer.taxpayerId, input }
                : { input },
            );
          }}
        />
      )}

      <AlertDialog
        open={Boolean(archiveCandidate)}
        onOpenChange={(open) => !open && setArchiveCandidate(null)}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Arquivar contribuinte?</AlertDialogTitle>
            <AlertDialogDescription>
              {archiveCandidate?.legalName} deixará de ser um cadastro ativo. Nenhum registro será
              apagado: dados fiscais, vínculos e trilha de auditoria serão preservados.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={archiveTaxpayer.isPending}>Cancelar</AlertDialogCancel>
            <AlertDialogAction
              disabled={archiveTaxpayer.isPending}
              onClick={() =>
                archiveCandidate && archiveTaxpayer.mutate(archiveCandidate.taxpayerId)
              }
            >
              {archiveTaxpayer.isPending ? "Arquivando…" : "Arquivar com segurança"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

function TaxpayerEditorDialog({
  editor,
  municipalityLabel,
  pending,
  onClose,
  onSave,
}: {
  editor: TaxpayerEditor;
  municipalityLabel: string;
  pending: boolean;
  onClose(): void;
  onSave(input: CreateTaxpayerInput): void;
}) {
  const formId = useId();
  const initial = editor.mode === "edit" ? editor.taxpayer : null;
  const [form, setForm] = useState<CreateTaxpayerInput>({
    municipalRegistration: initial?.municipalRegistration ?? "",
    taxId: initial?.taxId ?? "",
    legalName: initial?.legalName ?? "",
    tradeName: initial?.tradeName ?? "",
    taxpayerType:
      initial?.taxpayerType === "individual" || initial?.taxpayerType === "other"
        ? initial.taxpayerType
        : "company",
  });
  const [errors, setErrors] = useState<TaxpayerValidationErrors>({});

  function updateField<Field extends keyof CreateTaxpayerInput>(
    field: Field,
    value: CreateTaxpayerInput[Field],
  ) {
    setForm((current) => ({ ...current, [field]: value }));
    setErrors((current) => ({ ...current, [field]: undefined }));
  }

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const validation = validateTaxpayerInput(form);
    if (!validation.valid) {
      setErrors(validation.errors);
      return;
    }
    onSave(validation.data);
  }

  return (
    <Dialog open onOpenChange={(open) => !open && !pending && onClose()}>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle>
            {editor.mode === "create" ? "Cadastrar contribuinte" : "Editar contribuinte"}
          </DialogTitle>
          <DialogDescription>
            O cadastro será mantido exclusivamente em {municipalityLabel}. Campos marcados com * são
            obrigatórios.
          </DialogDescription>
        </DialogHeader>

        <form id={formId} className="grid gap-4 sm:grid-cols-2" onSubmit={submit} noValidate>
          <TaxpayerField
            id={`${formId}-registration`}
            label="Inscrição municipal *"
            error={errors.municipalRegistration}
          >
            <Input
              id={`${formId}-registration`}
              value={form.municipalRegistration}
              maxLength={50}
              aria-invalid={Boolean(errors.municipalRegistration)}
              aria-describedby={
                errors.municipalRegistration ? `${formId}-registration-error` : undefined
              }
              onChange={(event) => updateField("municipalRegistration", event.target.value)}
            />
          </TaxpayerField>

          <TaxpayerField id={`${formId}-tax-id`} label="CPF ou CNPJ *" error={errors.taxId}>
            <Input
              id={`${formId}-tax-id`}
              value={form.taxId}
              inputMode="numeric"
              maxLength={18}
              placeholder="Somente 11 ou 14 dígitos"
              aria-invalid={Boolean(errors.taxId)}
              aria-describedby={errors.taxId ? `${formId}-tax-id-error` : undefined}
              onChange={(event) => updateField("taxId", event.target.value)}
            />
          </TaxpayerField>

          <TaxpayerField
            id={`${formId}-legal-name`}
            label="Razão social ou nome completo *"
            error={errors.legalName}
            className="sm:col-span-2"
          >
            <Input
              id={`${formId}-legal-name`}
              value={form.legalName}
              maxLength={180}
              aria-invalid={Boolean(errors.legalName)}
              aria-describedby={errors.legalName ? `${formId}-legal-name-error` : undefined}
              onChange={(event) => updateField("legalName", event.target.value)}
            />
          </TaxpayerField>

          <TaxpayerField id={`${formId}-trade-name`} label="Nome fantasia" error={errors.tradeName}>
            <Input
              id={`${formId}-trade-name`}
              value={form.tradeName}
              maxLength={180}
              aria-invalid={Boolean(errors.tradeName)}
              aria-describedby={errors.tradeName ? `${formId}-trade-name-error` : undefined}
              onChange={(event) => updateField("tradeName", event.target.value)}
            />
          </TaxpayerField>

          <TaxpayerField id={`${formId}-type`} label="Tipo de pessoa *" error={errors.taxpayerType}>
            <Select
              value={form.taxpayerType}
              onValueChange={(value) =>
                updateField("taxpayerType", value as CreateTaxpayerInput["taxpayerType"])
              }
            >
              <SelectTrigger
                id={`${formId}-type`}
                aria-invalid={Boolean(errors.taxpayerType)}
                aria-describedby={errors.taxpayerType ? `${formId}-type-error` : undefined}
              >
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="company">Pessoa jurídica</SelectItem>
                <SelectItem value="individual">Pessoa física</SelectItem>
                <SelectItem value="other">Outro tipo</SelectItem>
              </SelectContent>
            </Select>
          </TaxpayerField>
        </form>

        <p className="text-xs text-muted-foreground">
          Para excluir da operação, use “Arquivar”. O sistema nunca apaga o histórico fiscal pelo
          cadastro.
        </p>
        <DialogFooter>
          <DialogClose asChild>
            <Button type="button" variant="outline" disabled={pending}>
              Cancelar
            </Button>
          </DialogClose>
          <Button type="submit" form={formId} disabled={pending}>
            {pending ? "Salvando…" : editor.mode === "create" ? "Cadastrar" : "Salvar alterações"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function TaxpayerField({
  id,
  label,
  error,
  className,
  children,
}: {
  id: string;
  label: string;
  error: string | undefined;
  className?: string | undefined;
  children: ReactNode;
}) {
  return (
    <div className={className}>
      <Label htmlFor={id}>{label}</Label>
      <div className="mt-2">{children}</div>
      {error && (
        <p id={`${id}-error`} role="alert" className="mt-1.5 text-xs text-destructive">
          {error}
        </p>
      )}
    </div>
  );
}

function taxpayerWriteErrorMessage(error: unknown): string {
  const code = error instanceof Error ? error.message : "";
  if (code.includes("23505")) {
    return "Já existe um contribuinte com este CPF/CNPJ ou inscrição municipal neste município.";
  }
  if (code.includes("42501")) {
    return "Seu perfil não possui permissão para alterar contribuintes.";
  }
  if (code.includes("invalid_taxpayer_input")) {
    return "Revise os dados do contribuinte e tente novamente.";
  }
  return "Não foi possível salvar o cadastro. Tente novamente ou revise suas permissões.";
}

function SummaryMetric({ label, value }: { label: string; value: string }) {
  return (
    <div className="surface-card p-4">
      <Building2 className="size-4 text-primary" aria-hidden />
      <p className="mt-3 text-xl font-semibold tabular-nums">{value}</p>
      <p className="mt-0.5 text-xs text-muted-foreground">{label}</p>
    </div>
  );
}