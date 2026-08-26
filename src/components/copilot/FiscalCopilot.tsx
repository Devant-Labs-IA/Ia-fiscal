import { useMutation } from "@tanstack/react-query";
import { useRouterState } from "@tanstack/react-router";
import { Bot, Database, LoaderCircle, Send, ShieldCheck, Sparkles } from "lucide-react";
import { useMemo, useState, type FormEvent } from "react";
import { toast } from "sonner";

import { useAuth } from "@/auth/AuthContext";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import { extractTaxpayerIdFromPath } from "@/lib/homologation-policy";
import { homologationService } from "@/services/homologation-service";

const FISCAL_EXAMPLES = [
  "Resuma o histórico do contribuinte que estou visualizando.",
  "Quais divergências e procedimentos precisam de conferência?",
  "Explique esta tela e indique o próximo passo operacional.",
];

const PORTAL_EXAMPLES = [
  "Quais informações estão disponíveis no meu atendimento?",
  "Existe registro de pergunta ou resposta neste processo?",
  "Explique em linguagem simples o que preciso conferir.",
];

export function FiscalCopilot() {
  const auth = useAuth();
  const pathname = useRouterState({ select: (state) => state.location.pathname });
  const [open, setOpen] = useState(false);
  const [question, setQuestion] = useState("");
  const municipalityId = auth.access?.municipalityId ?? "";
  const role = auth.access?.role ?? "support_readonly";
  const taxpayerId = useMemo(() => extractTaxpayerIdFromPath(pathname), [pathname]);
  const isPortal = role === "taxpayer" || role === "accountant";
  const examples = isPortal ? PORTAL_EXAMPLES : FISCAL_EXAMPLES;
  const normalizedQuestion = question.trim();

  const ask = useMutation({
    mutationFn: () =>
      homologationService.askCopilot(normalizedQuestion, {
        municipalityId,
        role,
        pathname,
        taxpayerId,
        caseId: null,
      }),
    onError: () =>
      toast.error("O copiloto não conseguiu concluir a consulta", {
        description:
          "Nenhuma resposta foi inventada. Verifique a conexão do backend ou tente novamente.",
      }),
  });

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (normalizedQuestion.length < 4 || ask.isPending) return;
    ask.mutate();
  }

  function setDialogOpen(nextOpen: boolean) {
    setOpen(nextOpen);
    if (!nextOpen) {
      setQuestion("");
      ask.reset();
    }
  }

  if (!auth.access || auth.demo) return null;

  return (
    <Dialog open={open} onOpenChange={setDialogOpen}>
      <DialogTrigger asChild>
        <Button
          type="button"
          size="lg"
          className="fixed bottom-5 right-5 z-50 gap-2 rounded-full shadow-lg"
          aria-label="Abrir Copiloto IA Fiscal"
        >
          <Sparkles className="size-4" aria-hidden />
          <span className="hidden sm:inline">Copiloto IA</span>
        </Button>
      </DialogTrigger>
      <DialogContent className="max-h-[92vh] overflow-y-auto sm:max-w-2xl">
        <DialogHeader>
          <div className="flex flex-wrap items-center gap-2">
            <DialogTitle>Copiloto IA Fiscal</DialogTitle>
            <Badge variant="outline" className="border-primary/30 bg-primary-soft text-primary">
              Somente leitura
            </Badge>
          </div>
          <DialogDescription>
            Consulta apenas dados autorizados para sua sessão. Não altera processos, não envia
            notificações e não substitui a decisão fiscal.
          </DialogDescription>
        </DialogHeader>

        <div className="rounded-md border border-border bg-muted/40 p-3 text-xs text-muted-foreground">
          <p className="flex items-start gap-2">
            <ShieldCheck className="mt-0.5 size-4 shrink-0 text-success" aria-hidden />
            Contexto atual: {pathname}
            {taxpayerId ? ` · contribuinte ${taxpayerId.slice(0, 8)}…` : ""}
          </p>
        </div>

        <div className="flex flex-wrap gap-2">
          {examples.map((example) => (
            <Button
              key={example}
              type="button"
              variant="outline"
              size="sm"
              className="h-auto whitespace-normal text-left"
              disabled={ask.isPending}
              onClick={() => setQuestion(example)}
            >
              {example}
            </Button>
          ))}
        </div>

        <form className="space-y-3" onSubmit={submit}>
          <label htmlFor="copilot-question" className="text-sm font-medium">
            Pergunta
          </label>
          <Textarea
            id="copilot-question"
            value={question}
            onChange={(event) => {
              setQuestion(event.target.value);
              if (ask.data) ask.reset();
            }}
            minLength={4}
            maxLength={1_000}
            rows={5}
            disabled={ask.isPending}
            placeholder="Ex.: traga o histórico e as pendências deste contribuinte."
          />
          <Button
            type="submit"
            className="w-full"
            disabled={normalizedQuestion.length < 4 || ask.isPending}
          >
            {ask.isPending ? (
              <LoaderCircle className="size-4 animate-spin" aria-hidden />
            ) : (
              <Send className="size-4" aria-hidden />
            )}
            {ask.isPending ? "Consultando fontes autorizadas…" : "Consultar copiloto"}
          </Button>
        </form>

        {ask.data ? (
          <section className="space-y-4 rounded-lg border border-border p-4" aria-live="polite">
            <div className="flex flex-wrap items-center gap-2">
              <Bot className="size-5 text-primary" aria-hidden />
              <h2 className="font-semibold">Resposta informativa</h2>
              <Badge variant="secondary">
                {ask.data.mode === "ai" ? "Síntese por IA" : "Síntese determinística"}
              </Badge>
            </div>
            <p className="whitespace-pre-wrap text-sm leading-relaxed">{ask.data.answer}</p>

            {ask.data.dataPoints.length > 0 ? (
              <div>
                <h3 className="text-sm font-semibold">Dados consultados</h3>
                <ul className="mt-2 space-y-1 text-sm text-muted-foreground">
                  {ask.data.dataPoints.map((point) => (
                    <li key={point}>• {point}</li>
                  ))}
                </ul>
              </div>
            ) : null}

            {ask.data.sources.length > 0 ? (
              <div>
                <h3 className="flex items-center gap-2 text-sm font-semibold">
                  <Database className="size-4" aria-hidden />
                  Fontes
                </h3>
                <ul className="mt-2 space-y-2">
                  {ask.data.sources.map((source, index) => (
                    <li
                      key={`${source.reference}-${index}`}
                      className="rounded-md bg-muted/40 px-3 py-2 text-xs"
                    >
                      <span className="block font-medium">{source.title}</span>
                      <span className="text-muted-foreground">{source.reference}</span>
                    </li>
                  ))}
                </ul>
              </div>
            ) : null}

            {ask.data.limitations.length > 0 ? (
              <div className="rounded-md border border-warning/40 bg-warning-soft p-3">
                <h3 className="text-sm font-semibold text-warning-foreground">Limitações</h3>
                <ul className="mt-1 space-y-1 text-xs text-warning-foreground">
                  {ask.data.limitations.map((limitation) => (
                    <li key={limitation}>• {limitation}</li>
                  ))}
                </ul>
              </div>
            ) : null}

            <p className="text-[11px] text-muted-foreground">
              Correlação: {ask.data.correlationId}
            </p>
          </section>
        ) : null}
      </DialogContent>
    </Dialog>
  );
}
