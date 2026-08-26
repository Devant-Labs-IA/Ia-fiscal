import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";

const commands = [
  ["Formatting", ["run", "format:check"]],
  ["Lint", ["run", "lint"]],
  ["TypeScript", ["run", "typecheck"]],
  ["Tests", ["test"]],
  ["Build", ["run", "build"]],
];

const reports = [];

for (const [name, args] of commands) {
  const startedAt = Date.now();
  const result = spawnSync("npm", args, {
    cwd: process.cwd(),
    encoding: "utf8",
    env: process.env,
    maxBuffer: 20 * 1024 * 1024,
  });
  const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`.trim();
  reports.push({
    name,
    command: `npm ${args.join(" ")}`,
    status: result.status ?? 1,
    durationMs: Date.now() - startedAt,
    output: output.slice(-120_000),
  });
}

mkdirSync("dist", { recursive: true });
const payload = JSON.stringify(
  {
    generatedAt: new Date().toISOString(),
    node: process.version,
    reports,
  },
  null,
  2,
);
writeFileSync("dist/diagnostics.json", payload);

const escapeHtml = (value) =>
  value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");

writeFileSync(
  "dist/index.html",
  `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Gauntlet Diagnostics</title><style>body{font-family:ui-monospace,monospace;max-width:1200px;margin:40px auto;padding:0 20px;background:#0b1020;color:#e5e7eb}section{border:1px solid #374151;border-radius:10px;padding:16px;margin:18px 0}.ok{color:#34d399}.fail{color:#f87171}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#111827;padding:14px;border-radius:8px}</style></head><body><h1>Gauntlet Diagnostics</h1><p>Gerado em ${escapeHtml(new Date().toISOString())}</p>${reports
    .map(
      (report) =>
        `<section><h2 class="${report.status === 0 ? "ok" : "fail"}">${escapeHtml(report.name)} — ${report.status === 0 ? "PASS" : `FAIL (${report.status})`}</h2><p>${escapeHtml(report.command)} · ${report.durationMs} ms</p><pre>${escapeHtml(report.output || "Sem saída")}</pre></section>`,
    )
    .join("")}</body></html>`,
);

console.log("Gauntlet diagnostics generated in dist/. The diagnostic deployment intentionally exits 0.");
