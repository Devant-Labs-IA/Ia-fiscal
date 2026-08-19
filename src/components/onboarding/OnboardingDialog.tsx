import { ArrowLeft, ArrowRight, CircleHelp, LoaderCircle, LogOut } from "lucide-react";

import {
  ONBOARDING_CAPABILITY_LABELS,
  type OnboardingCapability,
  type OnboardingStep,
} from "@/config/onboarding";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { cn } from "@/lib/utils";

type DialogPhase = "loading" | "error" | "ready";

const capabilityStyles: Record<OnboardingCapability, string> = {
  available: "border-success/40 bg-success-soft text-success",
  simulation: "border-primary/30 bg-primary-soft text-primary",
  blocked: "border-critical/35 bg-critical-soft text-critical",
  guidance: "border-border bg-muted text-foreground",
};

interface OnboardingDialogProps {
  open: boolean;
  mandatory: boolean;
  phase: DialogPhase;
  step: OnboardingStep | null;
  stepIndex: number;
  stepCount: number;
  saving: boolean;
  saveError: string | null;
  onBack(): void;
  onNext(): void;
  onFinish(): void;
  onRetry(): void;
  onClose(): void;
  onSignOut(): void;
}

export function OnboardingDialog({
  open,
  mandatory,
  phase,
  step,
  stepIndex,
  stepCount,
  saving,
  saveError,
  onBack,
  onNext,
  onFinish,
  onRetry,
  onClose,
  onSignOut,
}: OnboardingDialogProps) {
  const dismissible = phase === "ready" && !mandatory && !saving;

  return (
    <Dialog
      open={open}
      onOpenChange={(nextOpen) => {
        if (!nextOpen && dismissible) onClose();
      }}
    >
      <DialogContent
        showCloseButton={dismissible}
        className="flex max-h-[calc(100dvh-1rem)] w-[calc(100vw-1rem)] max-w-3xl flex-col gap-0 overflow-hidden p-0 sm:max-h-[calc(100dvh-2rem)]"
        onEscapeKeyDown={(event) => {
          if (!dismissible) event.preventDefault();
        }}
        onPointerDownOutside={(event) => {
          if (!dismissible) event.preventDefault();
        }}
        onInteractOutside={(event) => {
          if (!dismissible) event.preventDefault();
        }}
      >
        {phase === "loading" ? (
          <div className="grid min-h-64 place-items-center p-8 text-center">
            <div role="status" aria-live="polite">
              <LoaderCircle
                className="mx-auto size-8 animate-spin text-primary motion-reduce:animate-none"
                aria-hidden
              />
              <DialogTitle className="mt-4">Preparando seu treinamento</DialogTitle>
              <DialogDescription className="mt-2">
                Estamos verificando onde você parou antes de liberar a navegação.
              </DialogDescription>
            </div>
          </div>
        ) : phase === "error" ? (
          <div className="grid min-h-64 place-items-center p-6 text-center sm:p-8">
            <div className="max-w-lg">
              <CircleHelp className="mx-auto size-8 text-warning" aria-hidden />
              <DialogTitle className="mt-4">O treinamento não pôde ser carregado</DialogTitle>
              <DialogDescription className="mt-2">
                O primeiro acesso permanece protegido. Tente novamente para carregar e salvar seu
                progresso.
              </DialogDescription>
              <div className="mt-6 flex flex-col justify-center gap-2 sm:flex-row">
                <Button onClick={onRetry}>Tentar novamente</Button>
                <Button variant="outline" onClick={onSignOut}>
                  <LogOut className="size-4" aria-hidden />
                  Encerrar sessão
                </Button>
              </div>
            </div>
          </div>
        ) : step ? (
          <>
            <div className="shrink-0 border-b border-border bg-muted/35 px-5 py-4 sm:px-7">
              <DialogHeader className="pr-7 text-left">
                <div className="flex flex-wrap items-center gap-2">
                  <Badge variant="outline" className={cn(capabilityStyles[step.capability])}>
                    {ONBOARDING_CAPABILITY_LABELS[step.capability]}
                  </Badge>
                  <span className="text-xs font-medium text-muted-foreground">{step.section}</span>
                </div>
                <DialogTitle className="pt-2 text-xl leading-tight sm:text-2xl">
                  {step.title}
                </DialogTitle>
                <DialogDescription className="leading-relaxed">{step.summary}</DialogDescription>
              </DialogHeader>

              <div
                className="mt-4"
                role="progressbar"
                aria-label={`Progresso: etapa ${stepIndex + 1} de ${stepCount}`}
                aria-valuemin={1}
                aria-valuemax={stepCount}
                aria-valuenow={stepIndex + 1}
              >
                <div className="mb-1.5 flex items-center justify-between text-xs text-muted-foreground">
                  <span aria-live="polite">
                    Etapa {stepIndex + 1} de {stepCount}
                  </span>
                  <span>{Math.round(((stepIndex + 1) / stepCount) * 100)}%</span>
                </div>
                <div className="h-1.5 overflow-hidden rounded-full bg-primary/15">
                  <div
                    className="h-full rounded-full bg-primary transition-[width] motion-reduce:transition-none"
                    style={{ width: `${((stepIndex + 1) / stepCount) * 100}%` }}
                  />
                </div>
              </div>
            </div>

            <div
              className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-5 py-5 outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring sm:px-7"
              role="region"
              aria-label={`Instruções da etapa ${stepIndex + 1}: ${step.title}`}
              tabIndex={0}
            >
              {step.routeLabel ? (
                <p className="mb-4 rounded-md border border-border bg-background px-3 py-2 text-sm">
                  <span className="font-medium">Onde encontrar:</span> menu {step.routeLabel}
                </p>
              ) : null}

              <h3 className="text-sm font-semibold">O que fazer</h3>
              <ol className="mt-3 space-y-3">
                {step.actions.map((action, index) => (
                  <li key={action} className="flex gap-3 text-sm leading-relaxed">
                    <span
                      className="grid size-6 shrink-0 place-items-center rounded-full bg-primary-soft text-xs font-semibold text-primary"
                      aria-hidden
                    >
                      {index + 1}
                    </span>
                    <span>{action}</span>
                  </li>
                ))}
              </ol>

              {saveError ? (
                <p
                  className="mt-5 rounded-md border border-critical/30 bg-critical-soft px-3 py-2 text-sm text-critical"
                  role="alert"
                >
                  {saveError}
                </p>
              ) : null}
            </div>

            <DialogFooter className="shrink-0 gap-2 border-t border-border bg-background px-5 py-4 sm:px-7">
              {mandatory ? (
                <Button type="button" variant="ghost" disabled={saving} onClick={onSignOut}>
                  Encerrar sessão
                </Button>
              ) : (
                <Button type="button" variant="ghost" disabled={saving} onClick={onClose}>
                  Fechar treinamento
                </Button>
              )}
              <div className="flex flex-1 flex-wrap justify-end gap-2">
                <Button
                  type="button"
                  variant="outline"
                  disabled={stepIndex === 0 || saving}
                  onClick={onBack}
                >
                  <ArrowLeft className="size-4" aria-hidden />
                  Voltar
                </Button>
                {stepIndex === stepCount - 1 ? (
                  <Button type="button" disabled={saving} onClick={onFinish}>
                    {saving ? "Salvando…" : "Concluir treinamento"}
                  </Button>
                ) : (
                  <Button type="button" disabled={saving} onClick={onNext}>
                    Próxima etapa
                    <ArrowRight className="size-4" aria-hidden />
                  </Button>
                )}
              </div>
            </DialogFooter>
          </>
        ) : null}
      </DialogContent>
    </Dialog>
  );
}
