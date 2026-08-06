import {
  KeyRound,
  LockKeyhole,
  Mail,
  QrCode,
  RefreshCw,
  ShieldCheck,
  UserPlus,
} from "lucide-react";
import { useState, type FormEvent, type ReactNode } from "react";
import { toast } from "sonner";

import { AppShell } from "@/components/layout/AppShell";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { runtimeConfig } from "@/config/runtime";
import { useAuth } from "@/auth/AuthContext";

function FullPage({ children }: { children: ReactNode }) {
  return (
    <main className="grid min-h-screen place-items-center bg-background px-4 py-10">
      {children}
    </main>
  );
}

function LoadingScreen() {
  return (
    <FullPage>
      <div className="text-center" role="status" aria-live="polite">
        <ShieldCheck className="mx-auto size-9 animate-pulse text-primary" aria-hidden />
        <p className="mt-3 text-sm text-muted-foreground">Validando sessão e permissões…</p>
      </div>
    </FullPage>
  );
}

function LoginScreen() {
  const auth = useAuth();
  const [mode, setMode] = useState<"login" | "signup" | "recovery">("login");
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);

  function changeMode(nextMode: "login" | "signup" | "recovery") {
    if (busy) return;
    setMode(nextMode);
    setPassword("");
    setConfirmation("");
    setNotice(null);
  }

  async function submitLogin(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    try {
      await auth.signIn(email.trim(), password);
    } catch {
      toast.error("Não foi possível entrar", {
        description: "Confira o e-mail e a senha ou solicite a recuperação de acesso.",
      });
    } finally {
      setBusy(false);
    }
  }

  async function submitSignup(event: FormEvent) {
    event.preventDefault();
    if (password !== confirmation) {
      toast.error("As senhas não coincidem.");
      return;
    }
    if (password.length < 12) {
      toast.error("A senha precisa ter pelo menos 12 caracteres.");
      return;
    }
    setBusy(true);
    try {
      await auth.signUp(fullName.trim(), email.trim(), password);
      setPassword("");
      setConfirmation("");
      setNotice(
        "Confira seu e-mail para confirmar a conta. O acesso aos dados só é liberado após a aprovação do vínculo.",
      );
      toast.success("Cadastro recebido", {
        description: "Confirme o endereço pelo e-mail enviado antes de entrar.",
      });
    } catch {
      toast.error("O cadastro não pôde ser concluído", {
        description: "Revise os dados ou aguarde antes de tentar novamente.",
      });
    } finally {
      setBusy(false);
    }
  }

  async function submitRecovery(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    try {
      await auth.requestPasswordReset(email.trim());
      setNotice(
        "Se esse e-mail estiver cadastrado, você receberá um link para definir uma nova senha.",
      );
      toast.success("Solicitação registrada");
    } catch {
      toast.error("A recuperação não pôde ser iniciada.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <FullPage>
      <section className="w-full max-w-md surface-card p-6 sm:p-8" aria-labelledby="login-title">
        <div className="flex items-center gap-3">
          <div className="grid size-11 place-items-center rounded-lg bg-primary text-primary-foreground">
            <ShieldCheck className="size-6" aria-hidden />
          </div>
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.16em] text-primary">
              Ambiente de homologação
            </p>
            <h1 id="login-title" className="text-2xl font-semibold">
              IA Fiscal
            </h1>
          </div>
        </div>

        <p className="mt-5 text-sm text-muted-foreground">
          Entre, cadastre uma conta ou recupere sua senha. Todo acesso a dados exige vínculo
          aprovado e verificação em duas etapas.
        </p>

        <div
          className="mt-5 grid grid-cols-3 gap-1 rounded-lg bg-muted p-1"
          role="tablist"
          aria-label="Opções de acesso"
        >
          <Button
            id="access-tab-login"
            type="button"
            size="sm"
            variant={mode === "login" ? "secondary" : "ghost"}
            role="tab"
            aria-selected={mode === "login"}
            aria-controls="access-panel-login"
            disabled={busy}
            onClick={() => changeMode("login")}
          >
            Entrar
          </Button>
          <Button
            id="access-tab-signup"
            type="button"
            size="sm"
            variant={mode === "signup" ? "secondary" : "ghost"}
            role="tab"
            aria-selected={mode === "signup"}
            aria-controls="access-panel-signup"
            disabled={busy || !runtimeConfig.allowSignup}
            onClick={() => changeMode("signup")}
          >
            Cadastrar
          </Button>
          <Button
            id="access-tab-recovery"
            type="button"
            size="sm"
            variant={mode === "recovery" ? "secondary" : "ghost"}
            role="tab"
            aria-selected={mode === "recovery"}
            aria-controls="access-panel-recovery"
            disabled={busy}
            onClick={() => changeMode("recovery")}
          >
            Recuperar
          </Button>
        </div>

        {notice ? (
          <p
            className="mt-4 rounded-md border border-border bg-primary-soft px-3 py-3 text-sm"
            role="status"
            aria-live="polite"
          >
            {notice}
          </p>
        ) : null}

        {mode === "login" ? (
          <form
            id="access-panel-login"
            className="mt-6 space-y-4"
            role="tabpanel"
            aria-labelledby="access-tab-login"
            onSubmit={submitLogin}
          >
            <div className="space-y-2">
              <Label htmlFor="login-email">E-mail</Label>
              <Input
                id="login-email"
                type="email"
                autoComplete="username"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="login-password">Senha</Label>
              <Input
                id="login-password"
                type="password"
                autoComplete="current-password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                required
              />
            </div>
            <Button className="w-full" type="submit" disabled={busy}>
              <LockKeyhole className="size-4" aria-hidden />
              {busy ? "Validando…" : "Entrar com segurança"}
            </Button>
          </form>
        ) : null}

        {mode === "signup" ? (
          <form
            id="access-panel-signup"
            className="mt-6 space-y-4"
            role="tabpanel"
            aria-labelledby="access-tab-signup"
            onSubmit={submitSignup}
          >
            <div className="space-y-2">
              <Label htmlFor="signup-name">Nome completo</Label>
              <Input
                id="signup-name"
                autoComplete="name"
                value={fullName}
                onChange={(event) => setFullName(event.target.value)}
                minLength={3}
                maxLength={120}
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="signup-email">E-mail</Label>
              <Input
                id="signup-email"
                type="email"
                autoComplete="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="signup-password">Crie uma senha</Label>
              <Input
                id="signup-password"
                type="password"
                autoComplete="new-password"
                minLength={12}
                maxLength={128}
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="signup-confirmation">Confirme a senha</Label>
              <Input
                id="signup-confirmation"
                type="password"
                autoComplete="new-password"
                minLength={12}
                maxLength={128}
                value={confirmation}
                onChange={(event) => setConfirmation(event.target.value)}
                required
              />
            </div>
            <Button className="w-full" type="submit" disabled={busy}>
              <UserPlus className="size-4" aria-hidden />
              {busy ? "Cadastrando…" : "Criar meu acesso"}
            </Button>
            <p className="text-xs text-muted-foreground">
              O cadastro cria somente a identidade. Permissões fiscais ou administrativas dependem
              de aprovação separada.
            </p>
          </form>
        ) : null}

        {mode === "recovery" ? (
          <form
            id="access-panel-recovery"
            className="mt-6 space-y-4"
            role="tabpanel"
            aria-labelledby="access-tab-recovery"
            onSubmit={submitRecovery}
          >
            <div className="space-y-2">
              <Label htmlFor="recovery-email">E-mail cadastrado</Label>
              <Input
                id="recovery-email"
                type="email"
                autoComplete="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                required
              />
            </div>
            <Button className="w-full" type="submit" disabled={busy}>
              <Mail className="size-4" aria-hidden />
              {busy ? "Solicitando…" : "Enviar link de recuperação"}
            </Button>
            <p className="text-xs text-muted-foreground">
              Por segurança, a tela não informa se um endereço existe na base.
            </p>
          </form>
        ) : null}

        {runtimeConfig.allowDemo && (
          <div className="mt-5 border-t border-border pt-5">
            <Button className="w-full" variant="outline" onClick={auth.enterDemo}>
              Abrir demonstração com dados fictícios
            </Button>
            <p className="mt-2 text-center text-xs text-muted-foreground">
              A demonstração não consulta dados protegidos e não executa ações externas.
            </p>
          </div>
        )}
      </section>
    </FullPage>
  );
}

function MfaEnrollmentScreen() {
  const auth = useAuth();
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);

  async function startEnrollment() {
    setBusy(true);
    try {
      await auth.startMfaEnrollment();
    } catch {
      toast.error("Não foi possível iniciar a proteção em duas etapas.");
    } finally {
      setBusy(false);
    }
  }

  async function verify(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    try {
      await auth.verifyMfa(code);
      toast.success("Autenticador confirmado.");
    } catch {
      toast.error("Código não confirmado", {
        description: "Use o código atual de seis dígitos exibido no seu autenticador.",
      });
    } finally {
      setBusy(false);
    }
  }

  return (
    <FullPage>
      <section className="w-full max-w-lg surface-card p-6 sm:p-8" aria-labelledby="mfa-title">
        <div className="grid size-11 place-items-center rounded-lg bg-primary text-primary-foreground">
          <QrCode className="size-6" aria-hidden />
        </div>
        <h1 id="mfa-title" className="mt-4 text-2xl font-semibold">
          Proteja seu acesso
        </h1>
        <p className="mt-2 text-sm text-muted-foreground">
          O IA Fiscal exige verificação em duas etapas. Use um aplicativo autenticador para que
          dados fiscais não fiquem protegidos apenas pela senha.
        </p>

        {!auth.mfaEnrollment ? (
          <div className="mt-6 space-y-3">
            <Button className="w-full" disabled={busy} onClick={() => void startEnrollment()}>
              <QrCode className="size-4" aria-hidden />
              {busy ? "Preparando…" : "Configurar aplicativo autenticador"}
            </Button>
            <Button className="w-full" variant="outline" onClick={() => void auth.signOut()}>
              Encerrar sessão
            </Button>
          </div>
        ) : (
          <form className="mt-6 space-y-5" onSubmit={verify}>
            <div className="rounded-lg border border-border bg-white p-4 text-center">
              <img
                className="mx-auto size-52 max-w-full"
                src={auth.mfaEnrollment.qrCode}
                alt="QR code para cadastrar o IA Fiscal no aplicativo autenticador"
              />
            </div>
            <div className="space-y-2">
              <p className="text-sm font-medium">Não consegue ler o QR code?</p>
              <p className="text-xs text-muted-foreground">
                Digite esta chave manualmente no autenticador. Não compartilhe nem fotografe esta
                tela.
              </p>
              <code className="block break-all rounded-md bg-muted px-3 py-2 text-xs">
                {auth.mfaEnrollment.secret}
              </code>
            </div>
            <div className="space-y-2">
              <Label htmlFor="mfa-enrollment-code">Código de seis dígitos</Label>
              <Input
                id="mfa-enrollment-code"
                inputMode="numeric"
                autoComplete="one-time-code"
                pattern="[0-9]{6}"
                maxLength={6}
                value={code}
                onChange={(event) => setCode(event.target.value.replace(/\D/g, "").slice(0, 6))}
                required
              />
            </div>
            <Button className="w-full" type="submit" disabled={busy || code.length !== 6}>
              <ShieldCheck className="size-4" aria-hidden />
              {busy ? "Confirmando…" : "Confirmar e continuar"}
            </Button>
            <Button
              className="w-full"
              type="button"
              variant="outline"
              disabled={busy}
              onClick={() => void auth.signOut()}
            >
              Encerrar sessão
            </Button>
          </form>
        )}

        {auth.errorCode && (
          <p className="mt-4 rounded-md bg-muted px-3 py-2 font-mono text-xs">
            Referência: {auth.errorCode}
          </p>
        )}
      </section>
    </FullPage>
  );
}

function MfaChallengeScreen() {
  const auth = useAuth();
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);

  async function verify(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    try {
      await auth.verifyMfa(code);
    } catch {
      toast.error("Código não confirmado", {
        description: "Confira o código atual no seu aplicativo autenticador.",
      });
    } finally {
      setBusy(false);
    }
  }

  return (
    <FullPage>
      <section className="w-full max-w-md surface-card p-6 sm:p-8" aria-labelledby="mfa-code-title">
        <div className="grid size-11 place-items-center rounded-lg bg-primary text-primary-foreground">
          <KeyRound className="size-6" aria-hidden />
        </div>
        <h1 id="mfa-code-title" className="mt-4 text-2xl font-semibold">
          Confirme que é você
        </h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Informe o código atual de seis dígitos do aplicativo autenticador.
        </p>
        <form className="mt-6 space-y-4" onSubmit={verify}>
          <div className="space-y-2">
            <Label htmlFor="mfa-code">Código de verificação</Label>
            <Input
              id="mfa-code"
              inputMode="numeric"
              autoComplete="one-time-code"
              pattern="[0-9]{6}"
              maxLength={6}
              autoFocus
              value={code}
              onChange={(event) => setCode(event.target.value.replace(/\D/g, "").slice(0, 6))}
              required
            />
          </div>
          <Button className="w-full" type="submit" disabled={busy || code.length !== 6}>
            <ShieldCheck className="size-4" aria-hidden />
            {busy ? "Verificando…" : "Verificar e entrar"}
          </Button>
          <Button
            className="w-full"
            type="button"
            variant="outline"
            disabled={busy}
            onClick={() => void auth.signOut()}
          >
            Encerrar sessão
          </Button>
        </form>
        {auth.errorCode && (
          <p className="mt-4 rounded-md bg-muted px-3 py-2 font-mono text-xs">
            Referência: {auth.errorCode}
          </p>
        )}
      </section>
    </FullPage>
  );
}

function PasswordRecoveryScreen() {
  const auth = useAuth();
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [busy, setBusy] = useState(false);

  async function updatePassword(event: FormEvent) {
    event.preventDefault();
    if (password !== confirmation) {
      toast.error("As senhas não coincidem.");
      return;
    }
    if (password.length < 12) {
      toast.error("A nova senha precisa ter pelo menos 12 caracteres.");
      return;
    }

    setBusy(true);
    try {
      const allSessionsEnded = await auth.updateRecoveredPassword(password);
      if (allSessionsEnded) {
        toast.success("Senha atualizada", {
          description: "As sessões foram encerradas. Entre novamente com a nova senha.",
        });
      } else {
        toast.warning("Senha atualizada", {
          description:
            "A sessão atual foi encerrada, mas não foi possível confirmar o encerramento de todas as sessões anteriores.",
        });
      }
    } catch {
      toast.error("A senha não pôde ser atualizada", {
        description: "Solicite um novo link de recuperação e tente novamente.",
      });
    } finally {
      setBusy(false);
    }
  }

  return (
    <FullPage>
      <section className="w-full max-w-md surface-card p-6 sm:p-8" aria-labelledby="recovery-title">
        <div className="grid size-11 place-items-center rounded-lg bg-primary text-primary-foreground">
          <KeyRound className="size-6" aria-hidden />
        </div>
        <h1 id="recovery-title" className="mt-4 text-2xl font-semibold">
          Defina uma nova senha
        </h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Use entre 12 e 128 caracteres. Após a alteração, todas as sessões serão encerradas por
          segurança.
        </p>
        <form className="mt-6 space-y-4" onSubmit={updatePassword}>
          <div className="space-y-2">
            <Label htmlFor="new-password">Nova senha</Label>
            <Input
              id="new-password"
              type="password"
              autoComplete="new-password"
              minLength={12}
              maxLength={128}
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              required
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="confirm-password">Confirme a nova senha</Label>
            <Input
              id="confirm-password"
              type="password"
              autoComplete="new-password"
              minLength={12}
              maxLength={128}
              value={confirmation}
              onChange={(event) => setConfirmation(event.target.value)}
              required
            />
          </div>
          <Button
            className="w-full"
            type="submit"
            disabled={busy || password.length < 12 || confirmation.length < 12}
          >
            <ShieldCheck className="size-4" aria-hidden />
            {busy ? "Atualizando…" : "Atualizar senha e encerrar sessões"}
          </Button>
          <Button
            className="w-full"
            type="button"
            variant="outline"
            disabled={busy}
            onClick={() => void auth.signOut()}
          >
            Cancelar e encerrar sessão
          </Button>
        </form>
        {auth.errorCode && (
          <p className="mt-4 rounded-md bg-muted px-3 py-2 font-mono text-xs">
            Referência: {auth.errorCode}
          </p>
        )}
      </section>
    </FullPage>
  );
}

function AccessPendingScreen() {
  const auth = useAuth();
  const [busy, setBusy] = useState(false);

  return (
    <FullPage>
      <section className="w-full max-w-lg surface-card p-6 sm:p-8">
        <div className="grid size-11 place-items-center rounded-lg bg-warning-soft text-warning-foreground">
          <LockKeyhole className="size-5" aria-hidden />
        </div>
        <h1 className="mt-4 text-2xl font-semibold">Acesso ainda não vinculado</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          A autenticação foi aceita, mas o usuário não possui vínculo municipal, de contribuinte ou
          de contador ativo. Isso impede qualquer leitura por segurança.
        </p>
        {auth.errorCode && (
          <p className="mt-3 rounded-md bg-muted px-3 py-2 font-mono text-xs">
            Referência: {auth.errorCode}
          </p>
        )}
        <div className="mt-6 flex flex-wrap gap-2">
          <Button
            disabled={busy}
            onClick={async () => {
              setBusy(true);
              try {
                await auth.reloadAccess();
              } finally {
                setBusy(false);
              }
            }}
          >
            <RefreshCw className="size-4" aria-hidden />
            Verificar novamente
          </Button>
          <Button variant="outline" onClick={() => void auth.signOut()}>
            Encerrar sessão
          </Button>
          {runtimeConfig.allowDemo && (
            <Button variant="outline" onClick={auth.enterDemo}>
              Ver demonstração
            </Button>
          )}
        </div>
      </section>
    </FullPage>
  );
}

export function AuthBoundary({ children }: { children: ReactNode }) {
  const auth = useAuth();
  if (auth.status === "loading") return <LoadingScreen />;
  if (auth.status === "unauthenticated") return <LoginScreen />;
  if (auth.status === "mfa_enrollment_required") return <MfaEnrollmentScreen />;
  if (auth.status === "mfa_required") return <MfaChallengeScreen />;
  if (auth.status === "password_recovery") return <PasswordRecoveryScreen />;
  if (auth.status === "access_pending") return <AccessPendingScreen />;
  return <AppShell>{children}</AppShell>;
}
