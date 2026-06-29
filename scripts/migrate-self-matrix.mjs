// One-shot migration: re-home the stale `presentation_skills.*` self-matrix onto
// clean per-area subfeatures under the `use-cases-plugin` identity, dropping the
// old namespace. Faithful: rewrites use_case + scenario ids deterministically and
// fixes product-name prose, without disturbing any other content. The 12 existing
// clean rows (matrix.core, evidence.core, hosts.projections, mcp.wrapper, ...) are
// referenced by capsules/tests/showcase-runs and are left untouched.
//
// Usage: node scripts/migrate-self-matrix.mjs
import { readFileSync, writeFileSync, mkdirSync, rmSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { parse, stringify } from "yaml";

const ROOT = process.cwd();
const SRC_DIR = join(ROOT, "use-cases", "presentation-skills");

// area (presentation_skills.<area>) -> { feature id, name, summary, file }
const MAP = {
  matrix:      { id: "matrix.product",        file: "matrix/product.yml" },
  evidence:    { id: "evidence.ledger",       file: "evidence/ledger.yml" },
  hosts:       { id: "hosts.profiles",        file: "hosts/profiles.yml" },
  mcp:         { id: "mcp.surface",           file: "mcp/surface.yml" },
  capsules:    { id: "capsule.demos",         file: "capsule/demos.yml" },
  migration:   { id: "migration.importer",    file: "migration/importer.yml" },
  release:     { id: "release.proof",         file: "release/proof.yml" },
  showcase:    { id: "showcase.flow",         file: "showcase/flow.yml" },
  planning:    { id: "planning.cards",        file: "planning/cards.yml" },
  lifecycle:   { id: "lifecycle.loop",        file: "lifecycle/loop.yml" },
  diagnostics: { id: "diagnostics.contracts", file: "diagnostics/contracts.yml" },
  skills:      { id: "skills.assets",         file: "skills/assets.yml" }
};
// future.yml rows are deferred ideas already tagged with a target area in their id;
// they all collapse into one roadmap feature.
const ROADMAP = { id: "roadmap.deferred", file: "roadmap/deferred.yml" };

// Source file -> { area key in MAP } (the feature.id second segment after presentation_skills.)
const FILES = {
  "matrix.yml": "matrix",
  "evidence.yml": "evidence",
  "hosts.yml": "hosts",
  "mcp.yml": "mcp",
  "capsules.yml": "capsules",
  "migration.yml": "migration",
  "release.yml": "release",
  "showcase.yml": "showcase",
  "planning.yml": "planning",
  "lifecycle.yml": "lifecycle",
  "diagnostics.yml": "diagnostics",
  "skills.yml": "skills"
};

// Product-name prose fixes. Applied ONLY to string values that are NOT id fields,
// and never to dotted-identifier tokens (those are handled by id remap).
function fixProse(s) {
  return s
    .replaceAll("Presentation Skills", "Use Cases Plugin")
    .replaceAll("presentation skills", "use cases plugin")
    .replaceAll("presentation_skills rows", "use-cases-plugin rows")
    .replaceAll("presentation_skills component", "use-cases-plugin component");
}

// Remap an id by replacing its `presentation_skills.<area>` prefix with the new feature id.
function remapId(id, area, newFeatureId) {
  const prefix = `presentation_skills.${area}`;
  if (!id.startsWith(prefix)) return id;
  return newFeatureId + id.slice(prefix.length);
}

// For roadmap rows, id is presentation_skills.<somearea>.<case>; collapse to roadmap.deferred.<case>
function remapRoadmapId(id) {
  const parts = id.split(".");
  // presentation_skills . area . case [. scenario...]
  const tail = parts.slice(2).join(".");
  return tail ? `${ROADMAP.id}.${tail}` : ROADMAP.id;
}

// Deep transform: clone, remap ids on use_case + nested scenarios, fix prose on other strings.
function transformUseCase(uc, remap) {
  const out = {};
  for (const [k, v] of Object.entries(uc)) {
    if (k === "id") {
      out[k] = remap(v);
    } else if (k === "scenarios" && Array.isArray(v)) {
      out[k] = v.map((sc) => {
        const scOut = {};
        for (const [sk, sv] of Object.entries(sc)) {
          scOut[sk] = sk === "id" ? remap(sv) : walkProse(sv);
        }
        return scOut;
      });
    } else {
      out[k] = walkProse(v);
    }
  }
  return out;
}

// Recursively apply prose fixes to all strings in a value (no id keys reach here).
function walkProse(v) {
  if (typeof v === "string") return fixProse(v);
  if (Array.isArray(v)) return v.map(walkProse);
  if (v && typeof v === "object") {
    const o = {};
    for (const [k, val] of Object.entries(v)) o[k] = walkProse(val);
    return o;
  }
  return v;
}

function writeDoc(relFile, feature, useCases) {
  const full = join(ROOT, "use-cases", relFile);
  mkdirSync(dirname(full), { recursive: true });
  const doc = { schema_version: 1, feature, use_cases: useCases };
  writeFileSync(full, stringify(doc, { lineWidth: 0 }));
  console.log(`wrote ${relFile.padEnd(28)} feature=${feature.id.padEnd(22)} rows=${useCases.length}`);
}

let totalRows = 0;

// 1. Per-area feature files
for (const [srcName, area] of Object.entries(FILES)) {
  const srcPath = join(SRC_DIR, srcName);
  if (!existsSync(srcPath)) { console.warn(`SKIP missing ${srcName}`); continue; }
  const src = parse(readFileSync(srcPath, "utf8"));
  const target = MAP[area];
  const feature = {
    id: target.id,
    name: fixProse(src.feature.name),
    summary: fixProse(src.feature.summary)
  };
  const useCases = src.use_cases.map((uc) =>
    transformUseCase(uc, (id) => remapId(id, area, target.id))
  );
  writeDoc(target.file, feature, useCases);
  totalRows += useCases.length;
}

// 2. Roadmap (future.yml)
{
  const srcPath = join(SRC_DIR, "future.yml");
  const src = parse(readFileSync(srcPath, "utf8"));
  const feature = {
    id: ROADMAP.id,
    name: fixProse(src.feature.name),
    summary: fixProse(src.feature.summary)
  };
  const useCases = src.use_cases.map((uc) => transformUseCase(uc, remapRoadmapId));
  writeDoc(ROADMAP.file, feature, useCases);
  totalRows += useCases.length;
}

// 3. Drop the old namespace dir
rmSync(SRC_DIR, { recursive: true, force: true });
console.log(`\nremoved use-cases/presentation-skills/`);
console.log(`migrated ${totalRows} rows into ${Object.keys(MAP).length + 1} feature files`);
