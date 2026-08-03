import { Link } from "@tanstack/react-router";
import { ArrowLeft, Construction } from "lucide-react";

import { HomologationBanner } from "@/components/layout/HomologationBanner";
import { Button } from "@/components/ui/button";

interface PagePlaceholderProps {
  title: string;
  description: string;
  upcoming: string[];
}

export function PagePlaceholder({ title, description, upcoming }: PagePlaceholderProps) {
  return (
    <div className="mx-auto max-w-3xl space-y-6 py-4">
      <HomologationBanner />
      <div className="surface-card p-6 sm:p-8">
        <div className="grid size-11 place-items-center rounded-md bg-primary-soft text-primary">
          <Construction className="size-5" aria-hidden />
        </div>
        <h1 className="mt-4 text-2xl font-semibold">{title}</h1>
        <p className="mt-2 text-sm text-muted-foreground">{description}</p>

        <h2 className="mt-6 text-sm font-semibold">Previsto para esta área</h2>
        <ul className="mt-2 space-y-2 text-sm text-muted-foreground">
          {upcoming.map((item) => (
            <li key={item} className="flex gap-2">
              <span className="mt-1.5 size-1.5 shrink-0 rounded-full bg-accent" aria-hidden />
              {item}
            </li>
          ))}
        </ul>

        <Button asChild variant="outline" className="mt-6">
          <Link to="/">
            <ArrowLeft className="size-4" aria-hidden />
            Voltar à Visão Geral
          </Link>
        </Button>
      </div>
    </div>
  );
}
