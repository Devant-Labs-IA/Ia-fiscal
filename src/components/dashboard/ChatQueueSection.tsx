import { useState } from "react";
import { Clock, Sparkles } from "lucide-react";
import { toast } from "sonner";

import { EmptyState, SectionCard, SectionSkeleton } from "@/components/common/SectionCard";
import { RiskBadge } from "@/components/common/StatusBadges";
import { HomologationBanner } from "@/components/layout/HomologationBanner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { Textarea } from "@/components/ui/textarea";
import { maskCnpj } from "@/lib/format";
import type { ChatQueueItem } from "@/types/fiscal";

interface ChatQueueSectionProps {
  items: ChatQueueItem[] | undefined;
  isLoading: boolean;
}

export function ChatQueueSection({ items, isLoading }: ChatQueueSectionProps) {
  const [draftFor, setDraftFor] = useState<ChatQueueItem | null>(null);

  return (
    <>
      <SectionCard
        title="Atendimentos aguardando ação"
        description="Fila de contribuintes com resposta pendente do fiscal."
      >
        {isLoading ? (
          <SectionSkeleton rows={3} />
        ) : (items ?? []).length === 0 ? (
          <EmptyState message="Nenhum atendimento aguardando ação." />
        ) : (
          <ul className="divide-y divide-border">
            {(items ?? []).map((item) => (
              <li key={item.id} className="space-y-2.5 py-3">
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-medium">{item.taxpayerName}</span>
                    <span className="text-xs tabular-nums text-muted-foreground">
                      {maskCnpj(item.cnpj)}
                    </span>
                    <RiskBadge risk={item.priority} />
                  </div>
                  <p className="mt-1 text-sm text-muted-foreground">{item.lastMessage}</p>
                  <div className="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
                    <span className="inline-flex items-center gap-1">
                      <Clock className="size-3.5" aria-hidden />
                      {item.waitingLabel}
                    </span>
                    <Badge variant="outline" className="font-normal">
                      Origem: {item.origin}
                    </Badge>
                  </div>
                </div>

                <div className="flex flex-wrap items-start gap-2">
                  <Button
                    size="sm"
                    onClick={() =>
                      toast.success("Atendimento assumido", {
                        description: `${item.taxpayerName} — registro apenas em homologação.`,
                      })
                    }
                  >
                    Assumir atendimento
                  </Button>
                  <Button size="sm" variant="outline" onClick={() => setDraftFor(item)}>
                    <Sparkles className="size-4" aria-hidden />
                    Responder com IA
                  </Button>
                </div>
              </li>
            ))}
          </ul>
        )}
      </SectionCard>

      <Sheet open={Boolean(draftFor)} onOpenChange={(open) => !open && setDraftFor(null)}>
        <SheetContent className="w-full overflow-y-auto sm:max-w-lg">
          {draftFor && (
            <>
              <SheetHeader className="text-left">
                <SheetTitle>Sugestão de resposta</SheetTitle>
                <SheetDescription>
                  {draftFor.taxpayerName} · origem {draftFor.origin}
                </SheetDescription>
              </SheetHeader>

              <div className="space-y-4 px-4 pb-8">
                <HomologationBanner />

                <div className="rounded-md border border-border bg-muted/60 p-3">
                  <p className="text-xs font-medium text-muted-foreground">
                    Mensagem do contribuinte
                  </p>
                  <p className="mt-1 text-sm">{draftFor.lastMessage}</p>
                </div>

                <div>
                  <div className="flex items-center justify-between gap-2">
                    <label htmlFor="rascunho-ia" className="text-sm font-medium">
                      Rascunho gerado pela IA
                    </label>
                    <Badge
                      variant="outline"
                      className="border-warning/50 bg-warning-soft text-warning-foreground"
                    >
                      Rascunho não enviado
                    </Badge>
                  </div>
                  <Textarea
                    id="rascunho-ia"
                    defaultValue={draftFor.suggestedReply}
                    rows={8}
                    className="mt-2 bg-card"
                  />
                  <p className="mt-1.5 text-xs text-muted-foreground">
                    Nenhum conteúdo é enviado ao contribuinte neste ambiente. A revisão do fiscal é
                    obrigatória antes de qualquer disparo.
                  </p>
                </div>

                <div className="flex flex-wrap gap-2">
                  <Button
                    onClick={() =>
                      toast.success("Rascunho salvo", {
                        description: "Permanece retido — nenhum envio externo autorizado.",
                      })
                    }
                  >
                    Salvar rascunho
                  </Button>
                  <Button
                    variant="outline"
                    onClick={() =>
                      toast.info("Nova sugestão gerada", {
                        description: "Conteúdo de demonstração, sem consulta externa.",
                      })
                    }
                  >
                    Gerar outra sugestão
                  </Button>
                </div>
              </div>
            </>
          )}
        </SheetContent>
      </Sheet>
    </>
  );
}
