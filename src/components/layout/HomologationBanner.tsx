import { AlertTriangle } from "lucide-react";

import { HOMOLOGATION_NOTICE } from "@/data/mocks";
import { cn } from "@/lib/utils";

export function HomologationBanner({ className }: { className?: string }) {
  return (
    <div
      role="status"
      className={cn(
        "flex items-start gap-2 rounded-lg border border-warning/40 bg-warning-soft px-4 py-2.5 text-sm font-medium text-warning-foreground",
        className,
      )}
    >
      <AlertTriangle className="mt-0.5 size-4 shrink-0" aria-hidden />
      <span>{HOMOLOGATION_NOTICE}</span>
    </div>
  );
}
