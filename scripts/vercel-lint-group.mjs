import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";

const groups = {
  core: [
    "src/types/homologation.ts",
    "src/lib/homologation-policy.ts",
    "src/lib/homologation-policy.test.ts",
    "src/services/homologation-service.ts",
  ],
  "core-policy": [
    "src/types/homologation.ts",
    "src/lib/homologation-policy.ts",
    "src/lib/homologation-policy.test.ts",
  ],
  types: ["src/types/homologation.ts"],
  policy: ["src/lib/homologation-policy.ts"],
  "policy-test": ["src/lib/homologation-policy.test.ts"],
  "core-service": ["src/services/homologation-service.ts"],
  ui: [
    "src/components/copilot/FiscalCopilot.tsx",
    "src/components/notifications/NotificationDossierDialog.tsx",
    "src/components/layout/AppShell.tsx",
  ],
  routes: [
    "src/routes/notificacoes.tsx",
    "src/routes/portal.tsx",
    "src/routes/contribuintes_.$taxpayerId.tsx",
    "src/routes/debitos.tsx",
  ],
};

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: process.cwd(),
    encoding: "utf8",
    stdio: "inherit",
    env: process.env,
  });
  if ((result.status ?? 1) !== 0) process.exit(result.status ?? 1);
}

const groupName = process.env.GAUNTLET_LINT_GROUP ?? "core";
const files = groups[groupName];
if (!files) throw new Error(`unknown_lint_group:${groupName}`);

run("npm", ["exec", "--", "prettier", "--write", ...files]);
run("npm", ["exec", "--", "eslint", ...files]);

mkdirSync("dist", { recursive: true });
writeFileSync("dist/index.html", `lint-${groupName}-pass`);
