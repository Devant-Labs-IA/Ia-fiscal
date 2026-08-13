import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { CheckCircle2, LockKeyhole, RefreshCw, ShieldAlert, UserPlus, Users } from "lucide-react";
import { useEffect, useState, type FormEvent } from "react";
import { toast } from "sonner";

import { useAuth } from "@/auth/AuthContext";
import {
  EmptyState,
  ErrorState,
  SectionCard,
  SectionSkeleton,
} from "@/components/common/SectionCard";
import { HomologationBanner } from "@/components/layout/HomologationBanner";
import { ExternalDeliveryReadinessPanel } from "@/components/notifications/ExternalDeliveryReadinessPanel";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
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
import { runtimeConfig } from "@/config/runtime";
import { environmentLabel } from "@/lib/fiscal-labels";
import { fiscalKeys, fiscalService } from "@/services/fiscal-service";
import type {
  MunicipalityMembershipStatus,
  MunicipalityUser,
  MunicipalityUserRole,
} from "@/types/read-models";

export const Route = createFileRoute("/configuracoes")({
  head: () => ({ meta: [{ title: "Configurações e acessos — IA Fiscal" }] }),
  component: SettingsPage,
});

const ROLE_OPTIONS: Array<{ value: MunicipalityUserRole; label: string }> = [
  { value: "municipal_admin", label: "Administrador municipal" },
  { value: "supervisor", label: "Supervisor fiscal" },
  { value: "fiscal_auditor", label: "Auditor fiscal" },
  { value: "legal_reviewer", label: "Revisor jurídico" },
  { value: "support_readonly", label: "Suporte — somente leitura" },
];

const STATUS_OPTIONS: Array<{ value: MunicipalityMembershipStatus; label: string }> = [
  { value: "active", label: "Ativo" },
  { value: "suspended", label: "Suspenso" },
  { value: "revoked", label: "Revogado" },
];

function roleLabel(role: MunicipalityUserRole): string {
  return ROLE_OPTIONS.find((option) => option.value === role)?.label ?? role;
}

function statusLabel(status: MunicipalityMembershipStatus): string {
  return STATUS_OPTIONS.find((option) => option.value === status)?.label ?? status;
}

function errorMessage(error: unknown): string {
  const code = error instanceof Error ? error.message.split(":").at(-1) : "";
  if (code === "P0002") {
    return "Conta não encontrada. A pessoa precisa ter uma conta autenticada antes de receber acesso municipal.";
  }
  if (code === "23514") return "O município precisa manter ao menos um administrador ativo.";
  if (code === "42501") return "Seu acesso não permite realizar esta alteração.";
  if (code === "22023") return "Revise o e-mail, o papel e a situação informados.";
  return "Não foi possível concluir a alteração. Tente novamente.";
}

function formattedDate(value: string | null): string {
  if (!value) return "Nunca";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Não informado";
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
  }).format(date);
}

interface MembershipEditorProps {
  user: MunicipalityUser;
  currentUserId: string | undefined;
  pending: boolean;
  onConfirm(
    user: MunicipalityUser,
    role: MunicipalityUserRole,
    status: MunicipalityMembershipStatus,
  ): void;
}

function MembershipEditor({ user, currentUserId, pending, onConfirm }: MembershipEditorProps) {
  const [role, setRole] = useState<MunicipalityUserRole>(user.role);
  const [status, setStatus] = useState<MunicipalityMembershipStatus>(user.status);
  const isOwnAccess = user.userId === currentUserId;
  const changed = role !== user.role || status !== user.status;

  useEffect(() => {
    setRole(user.role);
    setStatus(user.status);
  }, [user.role, user.status]);

  return (
    <TableRow>
      <TableCell className="min-w-56">
        <p className="font-medium">
          {user.fullName}
          {isOwnAccess && <span className="ml-1 text-xs text-muted-foreground">(você)</span>}
        </p>
        <p className="text-xs text-muted-foreground">{user.email || "E-mail não informado"}</p>
      </TableCell>
      <TableCell className="min-w-52">
        <Select
          value={role}
          onValueChange={(value) => setRole(value as MunicipalityUserRole)}
          disabled={isOwnAccess || pending}
        >
          <SelectTrigger aria-label={`Papel de ${user.fullName}`}>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {ROLE_OPTIONS.map((option) => (
              <SelectItem key={option.value} value={option.value}>
                {option.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </TableCell>
      <TableCell className="min-w-36">
        <Select
          value={status}
          onValueChange={(value) => setStatus(value as MunicipalityMembershipStatus)}
          disabled={isOwnAccess || pending}
        >
          <SelectTrigger aria-label={`Situação de ${user.fullName}`}>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {STATUS_OPTIONS.map((option) => (
              <SelectItem key={option.value} value={option.value}>
                {option.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </TableCell>
      <TableCell className="whitespace-nowrap text-xs text-muted-foreground">
        {formattedDate(user.lastSeenAt)}
      </TableCell>
      <TableCell className="text-right">
        {isOwnAccess ? (
          <Badge variant="outline">Acesso protegido</Badge>
        ) : (
          <AlertDialog>
            <AlertDialogTrigger asChild>
              <Button variant="outline" size="sm" disabled={!changed || pending}>
                Revisar alteração
              </Button>
            </AlertDialogTrigger>
            <AlertDialogContent>
              <AlertDialogHeader>
                <AlertDialogTitle>Confirmar alteração de acesso?</AlertDialogTitle>
                <AlertDialogDescription>
                  {user.fullName} ficará como {roleLabel(role).toLocaleLowerCase("pt-BR")}, com
                  situação {statusLabel(status).toLocaleLowerCase("pt-BR")}. A alteração vale apenas
                  dentro deste município e não envia nenhuma mensagem.
                </AlertDialogDescription>
              </AlertDialogHeader>
              <AlertDialogFooter>
                <AlertDialogCancel disabled={pending}>Cancelar</AlertDialogCancel>
                <AlertDialogAction disabled={pending} onClick={() => onConfirm(user, role, status)}>
                  {pending ? "Salvando…" : "Confirmar alteração"}
                </AlertDialogAction>
              </AlertDialogFooter>
            </AlertDialogContent>
          </AlertDialog>
        )}
      </TableCell>
    </TableRow>
  );
}

function SettingsPage() {
  const auth = useAuth();
  const queryClient = useQueryClient();
  const municipalityId = auth.access?.municipalityId ?? "";
  const canManageUsers = auth.access?.role === "municipal_admin";
  const [email, setEmail] = useState("");
  const [newRole, setNewRole] = useState<MunicipalityUserRole>("fiscal_auditor");

  const usersQuery = useQuery({
    queryKey: fiscalKeys.municipalityUsers(municipalityId),
    queryFn: () => fiscalService.listMunicipalityUsers(municipalityId),
    enabled: canManageUsers && Boolean(municipalityId),
  });

  const addUser = useMutation({
    mutationFn: () => fiscalService.addExistingMunicipalityUser(municipalityId, email, newRole),
    onSuccess: async () => {
      setEmail("");
      await queryClient.invalidateQueries({
        queryKey: fiscalKeys.municipalityUsers(municipalityId),
      });
      toast.success("Acesso municipal adicionado", {
        description:
          "A conta existente já pode trabalhar neste município. Nenhum e-mail foi enviado.",
      });
    },
    onError: (error) =>
      toast.error("Não foi possível adicionar o acesso", { description: errorMessage(error) }),
  });

  const updateMembership = useMutation({
    mutationFn: ({
      membershipId,
      role,
      status,
    }: {
      membershipId: string;
      role: MunicipalityUserRole;
      status: MunicipalityMembershipStatus;
    }) => fiscalService.updateMunicipalityMembership(municipalityId, membershipId, role, status),
    onSuccess: async () => {
      await queryClient.invalidateQueries({
        queryKey: fiscalKeys.municipalityUsers(municipalityId),
      });
      toast.success("Acesso atualizado");
    },
    onError: (error) =>
      toast.error("Não foi possível atualizar o acesso", { description: errorMessage(error) }),
  });

  if (!canManageUsers) {
    return (
      <div className="py-4">
        <SectionCard title="Acesso administrativo necessário">
          <p className="flex gap-2 text-sm text-muted-foreground">
            <LockKeyhole className="size-5 shrink-0" aria-hidden />
            Somente um administrador municipal pode configurar usuários e permissões.
          </p>
        </SectionCard>
      </div>
    );
  }

  const activeMunicipality = auth.municipalityContexts.find(
    (municipality) => municipality.id === municipalityId,
  );

  function submitExistingUser(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!email.trim() || addUser.isPending) return;
    addUser.mutate();
  }

  return (
    <div className="space-y-5 py-4">
      <HomologationBanner />
      <header>
        <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">
          Configurações e acessos
        </h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Gerencie quem pode trabalhar no município e mantenha a operação assistida sob controle.
        </p>
      </header>

      <ExternalDeliveryReadinessPanel municipalityId={municipalityId} />

      <div className="grid gap-5 lg:grid-cols-2">
        <SectionCard
          title="Ambiente"
          action={<Badge variant="outline">{environmentLabel(runtimeConfig.environment)}</Badge>}
        >
          <dl className="space-y-3 text-sm">
            <div className="flex justify-between gap-4">
              <dt className="text-muted-foreground">Município</dt>
              <dd className="text-right font-medium">
                {auth.access?.municipalityLabel ?? runtimeConfig.municipalityLabel}
              </dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-muted-foreground">Código IBGE</dt>
              <dd className="font-mono">
                {activeMunicipality?.ibgeCode ?? runtimeConfig.municipalityIbge}
              </dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-muted-foreground">Dados exibidos</dt>
              <dd className="text-right font-medium">
                {auth.demo ? "Demonstração fictícia" : "Base municipal em operação assistida"}
              </dd>
            </div>
          </dl>
        </SectionCard>

        <SectionCard title="Controles ativos">
          <ul className="space-y-3 text-sm">
            <li className="flex gap-2">
              <CheckCircle2 className="size-5 shrink-0 text-success" aria-hidden />
              Segundo fator de autenticação obrigatório para a equipe interna
            </li>
            <li className="flex gap-2">
              <CheckCircle2 className="size-5 shrink-0 text-success" aria-hidden />
              Acesso separado por município e por função de trabalho
            </li>
            <li className="flex gap-2">
              <ShieldAlert className="size-5 shrink-0 text-warning" aria-hidden />
              Produção e comunicação externa permanecem bloqueadas
            </li>
          </ul>
        </SectionCard>
      </div>

      <SectionCard
        title="Adicionar conta existente"
        description="Vincule ao município uma pessoa que já possui conta autenticada no sistema."
        action={<UserPlus className="size-5 text-primary" aria-hidden />}
      >
        <form
          className="grid gap-4 md:grid-cols-[minmax(0,1fr)_16rem_auto] md:items-end"
          onSubmit={submitExistingUser}
        >
          <div className="space-y-2">
            <Label htmlFor="existing-user-email">E-mail da conta</Label>
            <Input
              id="existing-user-email"
              type="email"
              autoComplete="off"
              placeholder="usuario@prefeitura.gov.br"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              required
              disabled={addUser.isPending}
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="existing-user-role">Papel no município</Label>
            <Select
              value={newRole}
              onValueChange={(value) => setNewRole(value as MunicipalityUserRole)}
              disabled={addUser.isPending}
            >
              <SelectTrigger id="existing-user-role">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {ROLE_OPTIONS.map((option) => (
                  <SelectItem key={option.value} value={option.value}>
                    {option.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <Button type="submit" disabled={!email.trim() || addUser.isPending}>
            {addUser.isPending ? "Adicionando…" : "Adicionar acesso"}
          </Button>
        </form>
        <p className="mt-3 text-xs text-muted-foreground">
          Esta ação não cria conta, não envia convite e não dispara nenhum e-mail. Se a conta ainda
          não existe, a própria pessoa deve primeiro concluir o cadastro e a autenticação.
        </p>
      </SectionCard>

      <SectionCard
        title="Usuários do município"
        description="Altere o papel ou suspenda, reative e revogue acessos internos."
        action={
          <Button
            type="button"
            size="sm"
            variant="outline"
            disabled={usersQuery.isFetching}
            onClick={() => void usersQuery.refetch()}
          >
            <RefreshCw
              className={`mr-2 size-4 ${usersQuery.isFetching ? "animate-spin" : ""}`}
              aria-hidden
            />
            Atualizar
          </Button>
        }
      >
        {usersQuery.isPending ? (
          <SectionSkeleton rows={3} />
        ) : usersQuery.isError ? (
          <ErrorState message="Não foi possível carregar os usuários deste município." />
        ) : usersQuery.data.length === 0 ? (
          <EmptyState message="Nenhum acesso municipal foi encontrado." />
        ) : (
          <>
            <div className="mb-3 flex items-center gap-2 text-sm text-muted-foreground">
              <Users className="size-4" aria-hidden />
              {usersQuery.data.length} acesso(s) cadastrado(s)
            </div>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Usuário</TableHead>
                  <TableHead>Papel</TableHead>
                  <TableHead>Situação</TableHead>
                  <TableHead>Último acesso</TableHead>
                  <TableHead className="text-right">Ação</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {usersQuery.data.map((user) => (
                  <MembershipEditor
                    key={user.membershipId}
                    user={user}
                    currentUserId={auth.user?.id}
                    pending={
                      updateMembership.isPending &&
                      updateMembership.variables?.membershipId === user.membershipId
                    }
                    onConfirm={(selectedUser, role, status) =>
                      updateMembership.mutate({
                        membershipId: selectedUser.membershipId,
                        role,
                        status,
                      })
                    }
                  />
                ))}
              </TableBody>
            </Table>
          </>
        )}
      </SectionCard>
    </div>
  );
}
