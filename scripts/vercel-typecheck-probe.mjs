import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";

const result = spawnSync("npm", ["run", "typecheck"], {
  cwd: process.cwd(),
  encoding: "utf8",
  env: process.env,
  maxBuffer: 20 * 1024 * 1024,
});

const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
const lines = output.split(/\r?\n/);
const fileProbe = process.env.GAUNTLET_TYPE_FILE;
const minimumLine = Number.parseInt(process.env.GAUNTLET_TYPE_LINE_MIN ?? "1", 10);
const maximumLine = Number.parseInt(process.env.GAUNTLET_TYPE_LINE_MAX ?? "999999", 10);
const expression = new RegExp(process.env.GAUNTLET_TYPE_PROBE ?? "src/", "i");

const matchedLines = fileProbe
  ? lines.filter((line) => {
      const match = /^(.*)\((\d+),(\d+)\): error TS\d+:/.exec(line);
      if (!match) return false;
      const [, fileName, rawLine] = match;
      const lineNumber = Number.parseInt(rawLine, 10);
      return (
        fileName === fileProbe &&
        lineNumber >= minimumLine &&
        lineNumber <= maximumLine
      );
    })
  : lines.filter((line) => expression.test(line));

mkdirSync("dist", { recursive: true });
writeFileSync(
  "dist/index.html",
  matchedLines.length > 0
    ? `probe-match:${fileProbe ?? expression.source}:${minimumLine}-${maximumLine}`
    : `probe-clear:${fileProbe ?? expression.source}:${minimumLine}-${maximumLine}`,
);

if (matchedLines.length > 0) {
  console.error(
    `TypeScript probe matched ${matchedLines.length} line(s) for ${fileProbe ?? expression.source}.`,
  );
  process.exit(1);
}

console.log(`TypeScript probe found no matching diagnostics.`);
