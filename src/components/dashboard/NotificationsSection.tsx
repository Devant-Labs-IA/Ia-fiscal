import { CheckCircle2, Mail, MessageCircle, ShieldAlert, type LucideIcon } from "lucide-react";
import { toast } from "sonner";

import { EmptyState, SectionCard, SectionSkeleton } from "@/components/common/SectionCard";
import { StatusBadge } from "@/components/common/StatusBadges";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { maskCnpj } from "@/lib/format";
import type { NotificationCandidate } from "@/types/fiscal";

const channelIcons: Record<NotificationCandidate["channel"], LucideIcon> = {
  "e-mail": Mail,
  whatsapp: MessageCircle,
  portal: ShieldAlert,
};

interface NotificationsSectionProps {
  items: NotificationCandidate[] | undefined;
  isLoading: boolean;
}

export function NotificationsSection({ items, isLoading }: NotificationsSectionProps) {
  return (
    <SectionCard
      title="Notificações para validar"
      description="86 destinatários preparados. Nenhum liberado para envio."
      action={
        <Badge
          variant="outline"
          className="border-warning/50 bg-warning-soft text-warning-foreground"
        >
          Envio bloqueado
        </Badge>
      }
    >
      {isLoading ? (
        <SectionSkeleton rows={3} />
      ) : (items ?? []).length === 0 ? (
        <EmptyState message="Nenhuma notificação aguardando validação." />
      ) : (
        <ul className="space-y-3">
          {(items ?? []).map((item) => {
            const ChannelIcon = channelIcons[item.channel];
            return (
              <li key={item.id} className="space-y-2.5 rounded-md border border-border p-3">
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-medium">{item.taxpayerName}</span>
                    <span className="text-xs tabular-nums text-muted-foreground">
                      {maskCnpj(item.cnpj)}
                    </span>
                    <StatusBadge status={item.status} />
                  </div>
                  <p className="mt-1 text-sm text-muted-foreground">{item.templateName}</p>
                  <div className="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
                    <span className="inline-flex items-center gap-1">
                      <ChannelIcon className="size-3.5" aria-hidden />
                      {item.channel}: {item.contact}
                    </span>
                    {item.contactValidated ? (
                      <span className="inline-flex items-center gap-1 text-success">
                        <CheckCircle2 className="size-3.5" aria-hidden />
                        contato validado
                      </span>
                    ) : (
                      <span className="text-warning-foreground">contato não validado</span>
                    )}
                  </div>
                  <p className="mt-1.5 text-xs text-muted-foreground">
                    Bloqueio: {item.blockedReason}
                  </p>
                </div>

                <div className="flex flex-wrap items-start gap-2">
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() =>
                      toast.info("Mensagem aberta para revisão", {
                        description: item.draftMessage,
                      })
                    }
                  >
                    Revisar mensagem
                  </Button>
                  <Button
                    size="sm"
                    onClick={() =>
                      toast.success("Validação de contato registrada", {
                        description: "Ambiente de homologação — nenhum envio externo autorizado.",
                      })
                    }
                  >
                    Validar contato
                  </Button>
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </SectionCard>
  );
}
