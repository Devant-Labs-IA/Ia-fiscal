import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: process.cwd(),
    encoding: "utf8",
    stdio: "inherit",
    env: process.env,
    ...options,
  });
  if ((result.status ?? 1) !== 0) process.exit(result.status ?? 1);
}

run("npm", ["run", "format"]);
run("git", ["config", "user.name", "vercel-gauntlet"]);
run("git", ["config", "user.email", "vercel-gauntlet@users.noreply.github.com"]);
run("git", ["add", "."]);

const staged = spawnSync("git", ["diff", "--cached", "--quiet"], {
  cwd: process.cwd(),
  stdio: "inherit",
});
if ((staged.status ?? 0) !== 0) {
  run("git", ["commit", "-m", "style: aplicar formatação do Gauntlet"]);
}
run("git", ["push", "origin", "HEAD:feat/homologacao-realista-gauntlet"]);

mkdirSync("dist", { recursive: true });
writeFileSync("dist/index.html", "format-persisted");
