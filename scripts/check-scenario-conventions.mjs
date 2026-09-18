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

// `agent` and `user` are verifier KINDS, not ids a `verifiers:` block defines —
// an agent observation or a person's sign-off has no command behind it by
// design. Counting them as dangling would bury the 22 rows that really do name
// a `script` verifier nobody wrote, which is a bug rather than a decision.
const BUILT_IN_VERIFIERS = new Set(["agent", "user"]);

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
  let inVerifiers = false;
  let inRequired = false;
  for (const line of lines) {
    const id = /^ {2}- id: (\S+)$/.exec(line);
    if (id) {
      row = {
        id: id[1],
        lifecycle: null,
        tags: [],
        scenarios: [],
        definedVerifiers: [],
        requiredVerifiers: [],
        file: path
      };
      rows.push(row);
      inVerifiers = false;
      inRequired = false;
      continue;
    }
    if (!row) continue;

    const lifecycle = /^ {4}lifecycle: (\S+)$/.exec(line);
    if (lifecycle) row.lifecycle = lifecycle[1];

    const tag = /^ {6}- (\S+)$/.exec(line);
    if (tag && /^(no-bad-path|no-edge-path)$/.test(tag[1])) row.tags.push(tag[1]);

    const scenario = /^ {6}- id: (\S+)$/.exec(line);
    if (scenario) row.scenarios.push(scenario[1]);

    // `verifiers:` sits at 6 spaces under verification_policy; each verifier id
    // at 8. Any other 6-space key ends the block.
    if (/^ {6}verifiers:$/.test(line)) { inVerifiers = true; continue; }
    if (/^ {0,6}[a-z_]+:/.test(line) && !/^ {8}/.test(line)) inVerifiers = false;
    if (inVerifiers) {
      const defined = /^ {8}([a-z_]+):$/.exec(line);
      if (defined) row.definedVerifiers.push(defined[1]);
    }

    // `required_verifiers:` sits at 10 spaces inside a requirements entry; its
    // items at 12.
    if (/^ {10}required_verifiers:$/.test(line)) { inRequired = true; continue; }
    if (inRequired) {
      const required = /^ {12}- (\S+)$/.exec(line);
      if (required) row.requiredVerifiers.push(required[1]);
      else inRequired = false;
    }
  }
  return rows;
}

const findings = [];
const verifierFindings = [];
let active = 0;
for (const file of yamlFiles(matrixDir)) {
  for (const row of rowsOf(file)) {
    if (row.lifecycle !== "active") continue;
    active += 1;
    const rel = file.slice(repoRoot.length + 1);

    // Row 2 needs something to RUN. A row whose required_verifiers names an id
    // its verifiers block never defines is a dangling reference, and it reads
    // exactly like a healthy row: `use-cases matrix validate` passes it with zero
    // diagnostics, the same way it passed the dead source_refs. Counting it
    // here is what makes row 2 start with a target instead of a surprise.
    if (row.requiredVerifiers.length > 0) {
      const undefinedIds = row.requiredVerifiers.filter(
        (id) => !row.definedVerifiers.includes(id) && !BUILT_IN_VERIFIERS.has(id)
      );
      if (undefinedIds.length > 0) {
        verifierFindings.push(
          `${rel}: ${row.id} — required_verifiers names ${undefinedIds.join(", ")}, which no verifiers block defines`
        );
      }
    } else if (row.definedVerifiers.length === 0) {
      verifierFindings.push(`${rel}: ${row.id} — no verifier at all; nothing can run for this row`);
    }
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

console.log(
  findings.length === 0
    ? `scenario conventions: OK (${active} active rows)`
    : `scenario conventions: ${findings.length} finding(s) across ${active} active rows`
);
for (const f of findings) console.log(`  ${f}`);

console.log(
  verifierFindings.length === 0
    ? `runnable verifiers: OK (${active} active rows)`
    : `runnable verifiers: ${verifierFindings.length} row(s) with nothing to run — this is row 2's target`
);
for (const f of verifierFindings) console.log(`  ${f}`);

process.exit(strict && (findings.length > 0 || verifierFindings.length > 0) ? 1 : 0);
