// One-shot dedup: remove migrated rows that genuinely duplicate an externally
// referenced clean row, folding the migrated row's distinct outcomes into the
// surviving clean row. Survivors keep their own verification/approval policies
// (those drive CI/capsule behaviour and external references target the row id).
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { parse, stringify } from "yaml";

const ROOT = process.cwd();
const r = (p) => join(ROOT, "use-cases", p);

// Rows to delete (migrated duplicates)
const DELETE = {
  "hosts/profiles.yml": ["hosts.profiles.conformance_status_truth"],
  "mcp/surface.yml": ["mcp.surface.safe_matrix_mutation_workflow"],
  "release/proof.yml": ["release.proof.installable_artifact_provenance", "release.proof.sequential_gate_story"]
};

// Distinct outcomes to fold into the surviving clean row
const ENRICH = {
  "hosts/projections.yml": {
    "hosts.projections.static_conformance": [
      "Missing Copilot or OpenCode executables are reported as not_run rather than passed."
    ]
  },
  "mcp/wrapper.yml": {
    "mcp.use_case_mutation.safe": [
      "Damaged input or a path escape prevents mutation."
    ]
  },
  "release/package.yml": {
    "release.package.installable_artifact": [
      "The release claim points at the artifact users will install, and package contents match documented and manifest claims."
    ],
    "release.ci_gate.sequential": [
      "The gate proves frozen install, typecheck, build, full tests, package doctor, and matrix checks in one deterministic sequence."
    ]
  }
};

function load(p) { return parse(readFileSync(r(p), "utf8")); }
function save(p, doc) { writeFileSync(r(p), stringify(doc, { lineWidth: 0 })); }

for (const [file, ids] of Object.entries(DELETE)) {
  const doc = load(file);
  const before = doc.use_cases.length;
  doc.use_cases = doc.use_cases.filter((u) => !ids.includes(u.id));
  save(file, doc);
  console.log(`deleted ${before - doc.use_cases.length} row(s) from ${file}: ${ids.join(", ")}`);
}

for (const [file, byId] of Object.entries(ENRICH)) {
  const doc = load(file);
  for (const [id, extra] of Object.entries(byId)) {
    const uc = doc.use_cases.find((u) => u.id === id);
    if (!uc) { console.warn(`  WARN: ${id} not found in ${file}`); continue; }
    uc.observable_outcomes = [...(uc.observable_outcomes || []), ...extra];
    console.log(`enriched ${id} (+${extra.length} outcome)`);
  }
  save(file, doc);
}
