import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";

const result = spawnSync("npm", ["run", "typecheck"], {
  cwd: process.cwd(),
  encoding: "utf8",
  env: process.env,
  maxBuffer: 20 * 1024 * 1024,
});

const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
const probe = process.env.GAUNTLET_TYPE_PROBE ?? "src/";
const expression = new RegExp(probe, "i");
const matchedLines = output
  .split(/\r?\n/)
  .filter((line) => expression.test(line))
  .slice(0, 100);

mkdirSync("dist", { recursive: true });
writeFileSync(
  "dist/index.html",
  matchedLines.length > 0 ? `probe-match:${probe}` : `probe-clear:${probe}`,
);

if (matchedLines.length > 0) {
  console.error(`TypeScript probe matched ${matchedLines.length} line(s) for ${probe}.`);
  process.exit(1);
}

console.log(`TypeScript probe found no diagnostics for ${probe}.`);
