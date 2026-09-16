#!/usr/bin/env node
// Holds the matrix to the conventions in docs/rewrite/scenario-conventions.md.
//
// The gap audit of 2026-09-16 had to KEYWORD-CLASSIFY scenario ids to report how
// many rows lacked a bad or edge path, because nothing in the matrix recorded a
// scenario's role. The naming convention replaced that heuristic — but a
// convention nothing enforces is just a heuristic with better manners, and drift
// would be invisible again within a dozen feature files. This is the enforcement.
//
//   node scripts/check-scenario-conventions.mjs            report, exit 0
//   node scripts/check-scenario-conventions.mjs --strict    exit 1 on any finding
//
// Parked roadmap rows and non-active rows are not held to it.
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, resolve } from "node:path";

const repoRoot = resolve(import.meta.dirname, "..");
const matrixDir = join(repoRoot, "use-cases");
const strict = process.argv.includes("--strict");

function yamlFiles(dir) {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) out.push(...yamlFiles(path));
    else if (entry.endsWith(".yml") || entry.endsWith(".yaml")) out.push(path);
  }
  return out;
}

// A deliberately small line reader rather than a YAML dependency: this runs in a
// git hook, where a parse of the whole matrix is slower than the check is worth.
function rowsOf(path) {
  const lines = readFileSync(path, "utf8").split("\n");
  const rows = [];
  let row = null;
  for (const line of lines) {
    const id = /^ {2}- id: (\S+)$/.exec(line);
    if (id) {
      row = { id: id[1], lifecycle: null, tags: [], scenarios: [], file: path };
      rows.push(row);
      continue;
    }
    if (!row) continue;
    const lifecycle = /^ {4}lifecycle: (\S+)$/.exec(line);
    if (lifecycle) row.lifecycle = lifecycle[1];
    const tag = /^ {6}- (\S+)$/.exec(line);
    if (tag && /^(no-bad-path|no-edge-path)$/.test(tag[1])) row.tags.push(tag[1]);
    const scenario = /^ {6}- id: (\S+)$/.exec(line);
    if (scenario) row.scenarios.push(scenario[1]);
  }
  return rows;
}

const findings = [];
let active = 0;
for (const file of yamlFiles(matrixDir)) {
  for (const row of rowsOf(file)) {
    if (row.lifecycle !== "active") continue;
    active += 1;
    const rel = file.slice(repoRoot.length + 1);
    const suffixes = row.scenarios.map((s) => s.slice(row.id.length + 1));
    const unconventional = suffixes.filter((s) => !/^(golden|bad|edge|stress)(_|$)/.test(s));
    const has = (kind) => suffixes.some((s) => s === kind || s.startsWith(`${kind}_`));

    if (row.scenarios.length === 0) {
      findings.push(`${rel}: ${row.id} — active with no scenarios`);
      continue;
    }
    for (const s of unconventional) {
      findings.push(`${rel}: ${row.id}.${s} — scenario id does not start golden/bad/edge/stress`);
    }
    if (!has("golden")) findings.push(`${rel}: ${row.id} — no golden scenario`);
    if (!has("bad") && !row.tags.includes("no-bad-path")) {
      findings.push(`${rel}: ${row.id} — no bad scenario, and no no-bad-path tag saying why`);
    }
    if (!has("edge") && !row.tags.includes("no-edge-path")) {
      findings.push(`${rel}: ${row.id} — no edge scenario, and no no-edge-path tag saying why`);
    }
  }
}

if (findings.length === 0) {
  console.log(`scenario conventions: OK (${active} active rows)`);
  process.exit(0);
}
console.log(`scenario conventions: ${findings.length} finding(s) across ${active} active rows`);
for (const f of findings) console.log(`  ${f}`);
process.exit(strict ? 1 : 0);
