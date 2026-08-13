import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";

import { OnboardingDialog } from "@/components/onboarding/OnboardingDialog";
import { ONBOARDING_VERSION, onboardingStepsForRole } from "@/config/onboarding";
import {
  createPersistenceQueue,
  onboardingService,
  type PersistenceQueue,
} from "@/services/onboarding-service";
import type { AppRole } from "@/types/read-models";

interface OnboardingControls {
  openTutorial(): void;
}

interface OnboardingGateProps {
  userId: string;
  role: AppRole;
  onSignOut(): void;
  children(controls: OnboardingControls): ReactNode;
}

type GatePhase = "loading" | "error" | "ready";

export function OnboardingGate({ userId, role, onSignOut, children }: OnboardingGateProps) {
  const steps = useMemo(() => onboardingStepsForRole(role), [role]);
  const queueRef = useRef<PersistenceQueue>(createPersistenceQueue());
  const requestRef = useRef(0);
  const [phase, setPhase] = useState<GatePhase>("loading");
  const [open, setOpen] = useState(true);
  const [mandatory, setMandatory] = useState(true);
  const [stepIndex, setStepIndex] = useState(0);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const requestId = ++requestRef.current;
    setPhase("loading");
    setOpen(true);
    setMandatory(true);
    setSaveError(null);

    try {
      const progress = await onboardingService.load(userId, role);
      if (requestId !== requestRef.current) return;
      const isCurrent = progress?.onboardingVersion === ONBOARDING_VERSION;
      const completed = Boolean(isCurrent && progress?.completedAt);
      const resumableStep = isCurrent ? (progress?.currentStep ?? 0) : 0;

      setStepIndex(Math.min(Math.max(resumableStep, 0), Math.max(steps.length - 1, 0)));
      setMandatory(!completed);
      setOpen(!completed);
      setPhase("ready");
    } catch {
      if (requestId !== requestRef.current) return;
      setPhase("error");
      setOpen(true);
      setMandatory(true);
    }
  }, [role, steps.length, userId]);

  useEffect(() => {
    queueRef.current = createPersistenceQueue();
    void load();
    return () => {
      requestRef.current += 1;
    };
  }, [load]);

  function persistStep(nextStep: number): void {
    setStepIndex(nextStep);
    setSaveError(null);
    if (!mandatory) return;
    void queueRef.current
      .enqueue(() =>
        onboardingService.save({
          userId,
          role,
          currentStep: nextStep,
          completed: false,
        }),
      )
      .then((result) => {
        if (!result.ok) {
          setSaveError(
            "Não foi possível salvar esta etapa. Você pode continuar e tentar concluir novamente.",
          );
        }
      });
  }

  async function finish(): Promise<void> {
    setSaving(true);
    setSaveError(null);
    const result = await queueRef.current.enqueue(() =>
      onboardingService.save({
        userId,
        role,
        currentStep: Math.max(steps.length - 1, 0),
        completed: true,
      }),
    );
    setSaving(false);

    if (!result.ok) {
      setSaveError(
        "O treinamento foi concluído, mas o progresso não pôde ser salvo. Tente concluir novamente.",
      );
      return;
    }

    setMandatory(false);
    setOpen(false);
  }

  const openTutorial = useCallback(() => {
    setStepIndex(0);
    setSaveError(null);
    setMandatory(false);
    setPhase("ready");
    setOpen(true);
  }, []);

  return (
    <>
      {children({ openTutorial })}
      <OnboardingDialog
        open={open}
        mandatory={mandatory}
        phase={phase}
        step={steps[stepIndex] ?? null}
        stepIndex={stepIndex}
        stepCount={steps.length}
        saving={saving}
        saveError={saveError}
        onBack={() => persistStep(Math.max(stepIndex - 1, 0))}
        onNext={() => persistStep(Math.min(stepIndex + 1, steps.length - 1))}
        onFinish={() => void finish()}
        onRetry={() => void load()}
        onClose={() => setOpen(false)}
        onSignOut={onSignOut}
      />
    </>
  );
}
