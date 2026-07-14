// Capture the CLI's JSON contract as a version-comparable snapshot.
//
// Drives a fixed, hermetic workspace through the full daily loop (validate ->
// bind -> scan -> verify -> scan) against a GIVEN cli binary, and records, for
// every step: the process exit code, and every JSON key path with its type and
// value. That snapshot IS the contract a consumer integrates against.
//
// Committed once from the published 0.4.0 binary, it becomes the mechanical
// proof that a later version removed nothing, retyped nothing, and changed no
// exit code — and that every VALUE that did change was declared on purpose.
//
//   node scripts/capture-cli-contract.mjs <path-to-cli.js> > snapshot.json
//
// Deterministic by construction: volatile values (timestamps, ULIDs, absolute
// paths, the version string) are redacted, so two runs of the same binary
// produce byte-identical output.
import { spawnSync } from "node:child_process";
import { cpSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const fixtureDir = resolve(here, "../tests/fixtures/backcompat");

const cliPath = process.argv[2];
if (!cliPath) {
  console.error("usage: node scripts/capture-cli-contract.mjs <path-to-cli/dist/index.js>");
  process.exit(2);
}

// Values that legitimately differ between two runs of the SAME binary. Redacting
// them is what makes the snapshot a contract rather than a recording.
const VOLATILE = [
  /\.generated_at$/,
  /\.created_at$/,
  /\.event_id$/,
  /\.tool\.version$/,
  /\.version$/,
  /\.product_root$/,
  /\.out_path$/,
  /\.workspace_root$/,
  /\.data_root$/,
  /\.source_path$/,
  /\.repo_root$/,
  /_path$/,
  /\.path$/
];

function isVolatile(path) {
  return VOLATILE.some((pattern) => pattern.test(path));
}

// Flatten to `path -> {type, value}`. Array indices are preserved (the fixture is
// fixed, so they are stable), which means a REORDERED array is caught too.
function flatten(value, path, out) {
  if (value === null) {
    out[path] = { type: "null", value: null };
    return;
  }
  if (Array.isArray(value)) {
    out[path] = { type: "array", value: `len:${value.length}` };
    value.forEach((item, index) => flatten(item, `${path}[${index}]`, out));
    return;
  }
  if (typeof value === "object") {
    out[path] = { type: "object", value: Object.keys(value).sort().join(",") };
    for (const key of Object.keys(value).sort()) {
      flatten(value[key], `${path}.${key}`, out);
    }
    return;
  }
  out[path] = {
    type: typeof value,
    value: isVolatile(path) ? "<redacted>" : value
  };
}

const workspace = mkdtempSync(join(tmpdir(), "uc-contract-"));
cpSync(fixtureDir, workspace, { recursive: true });

function git(...args) {
  spawnSync("git", args, { cwd: workspace, encoding: "utf8" });
}
// `impact` needs a git baseline.
git("init", "-q");
git("config", "user.email", "t@example.com");
git("config", "user.name", "t");
git("add", "-A");
git("commit", "-qm", "baseline");

function run(label, args) {
  const result = spawnSync("node", [cliPath, ...args, "--repo", workspace], {
    cwd: workspace,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });

  const entry = { label, argv: args, exit_code: result.status };
  const stdout = (result.stdout ?? "").trim();
  if (stdout === "") {
    entry.keys = {};
    entry.note = "no stdout";
    return entry;
  }
  let parsed;
  try {
    parsed = JSON.parse(stdout);
  } catch {
    entry.keys = {};
    entry.note = "non-json stdout";
    return entry;
  }
  const flat = {};
  flatten(parsed, "$", flat);
  entry.keys = flat;
  return entry;
}

// The daily loop, in order. Each step's state feeds the next, so the snapshot
// covers unbound, bound-unverified, verified, and single-row-verified states.
const steps = [
  ["matrix.validate", ["matrix", "validate", "--json"]],
  ["matrix.list", ["matrix", "list", "--json"]],
  ["matrix.status", ["matrix", "status", "--json"]],
  ["scan.unbound", ["scan", "--json"]],
  ["scan.unbound.gate", ["scan", "--gate", "--json"]],
  ["impact.clean", ["impact", "--json"]],
  ["bind.coupon", ["bind", "--row", "checkout.apply_coupon", "--file", "src/coupon.js", "--mode", "explicit", "--register-existing", "--json"]],
  ["bind.refund", ["bind", "--row", "checkout.refund_order", "--file", "src/refund.js", "--mode", "explicit", "--register-existing", "--json"]],
  ["scan.bound", ["scan", "--json"]],
  ["verify.all", ["verify", "--all", "--json"]],
  ["scan.verified", ["scan", "--json"]],
  ["scan.verified.gate", ["scan", "--gate", "--json"]],
  ["verify.single_row", ["verify", "--row", "checkout.apply_coupon", "--json"]],
  ["scan.after_single_row", ["scan", "--json"]],
  ["matrix.status.verified", ["matrix", "status", "--json"]],
  ["verify.unbound_row", ["verify", "--row", "checkout.never_bound", "--json"]]
];

const snapshot = { steps: steps.map(([label, args]) => run(label, args)) };
rmSync(workspace, { recursive: true, force: true });
process.stdout.write(`${JSON.stringify(snapshot, null, 2)}\n`);
