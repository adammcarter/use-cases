// Regenerates `Tests/UseCasesCoreTests/Markers/Commands/MarkerCommandsGoldenCorpus.swift`
// by running every case below through the REAL TypeScript command cores in
// `packages/core/dist/markers/cli` and recording exactly what they return and
// exactly what they leave on disk.
//
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-marker-commands-corpus.mjs
//
// This is the oracle for bind, unbind, rebind and validate-ledger (row 3d4a).
// Each command case builds a real workspace in a temporary directory, runs a
// sequence of commands against it with a fixed clock and id factory, and
// records the result objects plus every file's bytes and mode afterwards.
// The script refuses to run against a `dist` older than its `src`.
//
// THIS SCRIPT WRITES MARKERS FOR A LIVING. No line of this file, and no line of
// the file it generates, may begin with a marker: marker text is built at
// runtime below, and the corpus is emitted as ONE line of escaped JSON.
import { execFileSync } from "node:child_process";
import {
  chmodSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  readlinkSync,
  realpathSync,
  rmSync,
  statSync,
  symlinkSync,
  writeFileSync
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const packageRoot = dirname(scriptDirectory);
const repositoryRoot = dirname(packageRoot);
const sourceDirectory = join(repositoryRoot, "packages/core/src");
const distDirectory = join(repositoryRoot, "packages/core/dist");
const targetPath = join(
  packageRoot,
  "Tests/UseCasesCoreTests/Markers/Commands/MarkerCommandsGoldenCorpus.swift"
);

const PORTED = [
  "markers/cli/io",
  "markers/cli/shared",
  "markers/cli/bindingLifecycle",
  "markers/cli/bind",
  "markers/cli/unbind",
  "markers/cli/rebind",
  "markers/cli/validateLedger",
  "markers/scanner",
  "markers/registry",
  "markers/markerLine",
  "markers/commentPrefix",
  "markers/evidenceLedger",
  "markers/appendOnly",
  "roots",
  "useCases/loadUseCaseMatrix",
  "version"
];

for (const name of PORTED) {
  const source = statSync(join(sourceDirectory, `${name}.ts`)).mtimeMs;
  const built = statSync(join(distDirectory, `${name}.js`)).mtimeMs;
  if (built < source) {
    throw new Error(`dist/${name}.js is older than src; rebuild packages/core first`);
  }
}

const core = await import(join(distDirectory, "index.js"));
const {
  resolveWorkspaceContext,
  runBindCommand,
  runUnbindCommand,
  runRebindCommand,
  runValidateLedgerCommand,
  insertMarkerLines,
  locateMarkerLines,
  removeMarkerLines,
  bindingRegisteredEvent,
  bindingReleasedEvent,
  appendJsonlLine,
  nodeMarkerFs,
  collectSourceInputs,
  loadMarkerRows,
  rowVariants,
  toPosix,
  resolveUnderRoot
} = core;

// A marker line, built at runtime so this file never carries one literally.
const token = (prefix) => `${prefix}: @use-` + "case:";
const startMarker = (prefix, slug) => `${token(prefix)}${slug}`;
const endMarker = (prefix, slug) => `${token(prefix)}end ${slug}`;

// Every JavaScript value the corpus records goes through this, so `undefined`
// members disappear exactly as JSON.stringify drops them.
const plain = (value) => (value === undefined ? null : JSON.parse(JSON.stringify(value)));

const umask = process.umask();

// ---------------------------------------------------------------------------
// Workspaces. Entries are relative to a temporary root; the workspace itself is
// always `workspace/`, so a symlink can point OUTSIDE it at `outside/`.

const ROW_A = "checkout.apply_coupon";
const ROW_B = "checkout.remove_coupon";

const CONFIG_YAML = `schema_version: 1
workspace_id: commands.fixture
data_root: .
use_cases_dir: use-cases
evidence_dir: evidence
demo_capsules_dir: demo-capsules
showcase_runs_dir: showcase-runs
component_id: commands-fixture
default_workflow_mode: continuous
`;

function rowYaml(rowId, title, extra = "") {
  return `  - id: ${rowId}
    title: ${title}
    lifecycle: active
    value_tier: critical
    journey_role: golden
    usage_frequency: common
    actor: shopper
    intent: ${title}.
    preconditions:
      - A cart exists.
    trigger: The shopper submits a coupon code.
    scenarios:
      - id: ${rowId}.web
        kind: steps
        steps:
          - The shopper submits a coupon code.
    observable_outcomes:
      - The cart total reflects the change.
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: requirements
      verifiers:
        contract_check:
          kind: script
          evidence_kind: test_result
          command: [echo, contract-ok]
          inputs: []
      requirements:
        - evidence_kind: test_result
          required_verifiers: [contract_check]
          minimum_count: 1
    approval_policy:
      mode: predefined
      requirements:
        - approver_type: user
          minimum_count: 1
      statement: Final acceptance requires user-visible proof.
${extra}`;
}

function useCaseYaml(rows) {
  return `schema_version: 1
feature:
  id: checkout
  name: Checkout
  summary: Shoppers can apply coupons during checkout.
metadata:
  owner: product
  lifecycle: active
use_cases:
${rows.join("")}`;
}

const BOTH_ROWS = useCaseYaml([
  rowYaml(ROW_A, "Apply a valid coupon"),
  rowYaml(ROW_B, "Remove a coupon")
]);
const ONLY_ROW_B = useCaseYaml([rowYaml(ROW_B, "Remove a coupon")]);

const CHECKOUT_SWIFT = [
  "import Foundation",
  "",
  "struct Checkout {",
  "  func applyCoupon(_ code: String) -> Bool {",
  "    return !code.isEmpty",
  "  }",
  "",
  "  func removeCoupon() -> Bool {",
  "    return true",
  "  }",
  "}",
  ""
].join("\n");

const COUPON_PY = ["def apply(code):", "    total = 10", "    return total - len(code)", ""].join("\n");

const baseEntries = (yaml = BOTH_ROWS) => [
  ["file", "workspace/use-cases.yml", CONFIG_YAML, 0o644],
  ["file", "workspace/use-cases/checkout.yml", yaml, 0o644]
];

const fileEntry = (path, contents, mode = 0o644) => ["file", `workspace/${path}`, contents, mode];

function materialize(root, entries) {
  for (const entry of entries) {
    const [kind, path] = entry;
    const full = join(root, path);
    if (kind === "directory") {
      mkdirSync(full, { recursive: true });
    } else if (kind === "file") {
      mkdirSync(dirname(full), { recursive: true });
      writeFileSync(full, entry[2]);
      chmodSync(full, entry[3]);
    } else if (kind === "symlink") {
      mkdirSync(dirname(full), { recursive: true });
      symlinkSync(entry[2], full);
    } else if (kind === "chmod") {
      chmodSync(full, entry[2]);
    } else {
      throw new Error(`unknown entry kind ${kind}`);
    }
  }
}

const jsLess = (left, right) => (left < right ? -1 : left > right ? 1 : 0);

// Every entry under root, never following a symlink, skipping `.git`
// internals, sorted by path with JavaScript `<`.
function snapshot(root) {
  const out = [];
  const walk = (relative) => {
    const full = relative === "" ? root : join(root, relative);
    for (const name of readdirSync(full)) {
      const childRelative = relative === "" ? name : `${relative}/${name}`;
      const childFull = join(root, childRelative);
      const status = lstatSync(childFull);
      if (status.isSymbolicLink()) {
        out.push(["symlink", childRelative, readlinkSync(childFull)]);
      } else if (status.isDirectory()) {
        if (name === ".git") {
          continue;
        }
        out.push(["directory", childRelative]);
        walk(childRelative);
      } else {
        out.push(["file", childRelative, readFileSync(childFull, "utf8"), status.mode & 0o7777]);
      }
    }
  };
  walk("");
  return out.sort((left, right) => jsLess(left[1], right[1]));
}

const gitIdentity = [
  "-c",
  "user.name=Use Cases",
  "-c",
  "user.email=use-cases@example.com",
  "-c",
  "commit.gpgsign=false"
];

// ---------------------------------------------------------------------------
// Command cases: a workspace, then steps. The clock and the id factory share
// one counter, so the order they are read in is part of what is recorded.

function runCommandCase(testCase) {
  const temporary = realpathSync(mkdtempSync(join(tmpdir(), "uc-commands-")));
  try {
    materialize(temporary, testCase.entries);
    const workspace = join(temporary, "workspace");
    let tick = 0;
    const clock = () => `2026-09-17T10:00:${String(tick++).padStart(2, "0")}.000Z`;
    const idFactory = () => `event-${String(tick++).padStart(4, "0")}`;
    const steps = [];
    for (const step of testCase.steps) {
      const recorded = { ...step };
      if (step.kind === "write") {
        materialize(temporary, [["file", `workspace/${step.path}`, step.contents, step.mode ?? 0o644]]);
      } else if (step.kind === "git") {
        execFileSync("git", step.arguments, { cwd: workspace, stdio: "pipe" });
      } else {
        const context = resolveWorkspaceContext({ workspaceRoot: workspace });
        const option = step.options ?? {};
        const common = {
          context,
          productRoot: context.workspace_root,
          bindingsPath: join(context.data_root, ".use-cases", "bindings.jsonl"),
          clock,
          idFactory,
          version: option.version,
          commentConfig: option.comment_config
        };
        const placement = {
          rowId: option.row_id,
          suffix: option.suffix,
          file: option.file,
          mode: option.mode,
          line: option.line,
          startLine: option.start_line,
          endLine: option.end_line,
          commentPrefix: option.comment_prefix,
          dryRun: option.dry_run,
          reason: option.reason
        };
        let result;
        if (step.kind === "bind") {
          result = runBindCommand({ ...common, ...placement, registerExisting: option.register_existing });
        } else if (step.kind === "unbind") {
          result = runUnbindCommand({ ...common, ...placement });
        } else if (step.kind === "rebind") {
          result = runRebindCommand({ ...common, ...placement });
        } else if (step.kind === "validate_ledger") {
          result = runValidateLedgerCommand({
            context,
            evidencePath: join(context.data_root, ".use-cases", "proofs.jsonl"),
            bindingsPath: join(context.data_root, ".use-cases", "bindings.jsonl"),
            publicKeyResolver: () => undefined,
            baseRef: option.base_ref,
            repoCwd: workspace,
            // A scripted git: answers `show <ref>:<path>` from base_texts by the
            // path's basename, and fails as a missing path fails otherwise.
            gitRunner: option.base_texts
              ? (args) => {
                  const spec = args[1];
                  const base = spec.slice(spec.lastIndexOf("/") + 1);
                  if (base in option.base_texts) {
                    return option.base_texts[base];
                  }
                  const error = new Error("scripted");
                  error.stderr = `fatal: path '${base}' does not exist in 'HEAD'`;
                  throw error;
                }
              : undefined
          });
        } else {
          throw new Error(`unknown step ${step.kind}`);
        }
        recorded.result = plain(result);
      }
      steps.push(recorded);
    }
    return { name: testCase.name, entries: testCase.entries, steps, tree: snapshot(temporary) };
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
}

const bindStep = (options) => ({ kind: "bind", options });
const unbindStep = (options) => ({ kind: "unbind", options });
const rebindStep = (options) => ({ kind: "rebind", options });
const validateStep = (options = {}) => ({ kind: "validate_ledger", options });

// A registry line written as the tool writes it, for workspaces that start
// already bound.
const registeredLine = (rowId, slug, eventId) =>
  JSON.stringify(
    bindingRegisteredEvent({
      command: "bind",
      rowId,
      bindingSlug: slug,
      reason: "initial_bind",
      eventId,
      createdAt: "2026-09-01T00:00:00.000Z",
      version: "0.7.0"
    })
  );

const ledgerEntry = (lines) => fileEntry(".use-cases/bindings.jsonl", lines.map((line) => `${line}\n`).join(""));

const SKIP_DIRECTORIES = [
  ".git",
  ".claude",
  "node_modules",
  ".use-cases",
  "dist",
  "dist-ts",
  "build",
  "out",
  "coverage",
  ".next",
  ".turbo",
  ".svelte-kit"
];

const markedSwift = (slug) => [startMarker("//", slug), "func marked() -> Bool {", "  return true", "}", ""].join("\n");

const commandCases = [
  {
    name: "swift_func_bind",
    entries: [...baseEntries(), fileEntry("Sources/Checkout.swift", CHECKOUT_SWIFT)],
    steps: [
      bindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "swift-func", line: 4 }),
      validateStep()
    ]
  },
  {
    name: "explicit_bind",
    entries: [...baseEntries(), fileEntry("tools/coupon.py", COUPON_PY)],
    steps: [bindStep({ row_id: ROW_A, file: "tools/coupon.py", mode: "explicit", start_line: 2, end_line: 3 })]
  },
  {
    name: "bind_dry_run_and_explicit_version",
    entries: [...baseEntries(), fileEntry("tools/coupon.py", COUPON_PY)],
    steps: [
      bindStep({ row_id: ROW_A, file: "tools/coupon.py", mode: "explicit", start_line: 1, end_line: 3, dry_run: true }),
      bindStep({ row_id: ROW_A, file: "tools/coupon.py", mode: "explicit", start_line: 1, end_line: 3, version: "9.9.9" })
    ]
  },
  {
    name: "bind_suffix_onto_file_already_binding_another_row",
    entries: [...baseEntries(), fileEntry("Sources/Checkout.swift", CHECKOUT_SWIFT)],
    steps: [
      bindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "swift-func", line: 4 }),
      bindStep({ row_id: ROW_B, suffix: "second", file: "Sources/Checkout.swift", mode: "swift-func", line: 9 }),
      bindStep({ row_id: ROW_B, suffix: "", file: "Sources/Checkout.swift", mode: "swift-func", line: 10 }),
      validateStep()
    ]
  },
  {
    name: "bind_refused_on_invalid_registry",
    entries: [
      ...baseEntries(),
      fileEntry("Sources/Checkout.swift", CHECKOUT_SWIFT),
      ledgerEntry([registeredLine("ghost.row", "ghost.row", "event-ghost"), '{"schema":"not-a-registry-event"}'])
    ],
    steps: [
      bindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "swift-func", line: 4 }),
      rebindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "swift-func", line: 4 }),
      unbindStep({ row_id: ROW_A }),
      validateStep()
    ]
  },
  {
    name: "bind_refusals",
    entries: [
      ...baseEntries(),
      fileEntry("Sources/Checkout.swift", CHECKOUT_SWIFT),
      fileEntry("README.md", "# Readme\n\nText.\n")
    ],
    steps: [
      bindStep({ row_id: "checkout.unknown_row", file: "Sources/Checkout.swift", mode: "swift-func", line: 4 }),
      bindStep({ row_id: ROW_A, suffix: "Bad Suffix", file: "Sources/Checkout.swift", mode: "swift-func", line: 4 }),
      bindStep({ row_id: ROW_A, file: "Sources/Missing.swift", mode: "swift-func", line: 4 }),
      bindStep({ row_id: ROW_A, file: "README.md", mode: "explicit", start_line: 1, end_line: 2 }),
      bindStep({ row_id: ROW_A, file: "README.md", mode: "explicit", start_line: 1, end_line: 2, comment_prefix: "#" }),
      bindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "swift-func" }),
      bindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "swift-func", line: 0 }),
      bindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "swift-func", line: 13 }),
      bindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "swift-func", line: 1 }),
      bindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "explicit", start_line: 2 }),
      bindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "explicit", start_line: 3, end_line: 2 }),
      bindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "explicit", start_line: 1, end_line: 13 }),
      bindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "swift-func", line: 4, register_existing: true }),
      bindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "swift-func", line: 4 }),
      bindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "swift-func", line: 9 })
    ]
  },
  {
    name: "register_existing",
    entries: [
      ...baseEntries(),
      fileEntry(
        "tools/coupon.py",
        [startMarker("#", ROW_A), "def apply(code):", "    return len(code)", endMarker("#", ROW_A), ""].join("\n")
      )
    ],
    steps: [
      bindStep({ row_id: ROW_A, file: "tools/coupon.py", mode: "explicit", register_existing: true }),
      validateStep()
    ]
  },
  {
    name: "rebind_within_file",
    entries: [...baseEntries(), fileEntry("Sources/Checkout.swift", CHECKOUT_SWIFT)],
    steps: [
      bindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "swift-func", line: 4 }),
      rebindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "swift-func", line: 8, reason: "wrong_declaration" }),
      rebindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "explicit", start_line: 4, end_line: 6 }),
      validateStep()
    ]
  },
  {
    name: "rebind_to_another_file",
    entries: [
      ...baseEntries(),
      fileEntry("Sources/Checkout.swift", CHECKOUT_SWIFT),
      fileEntry("tools/coupon.py", COUPON_PY)
    ],
    steps: [
      bindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "swift-func", line: 4 }),
      rebindStep({ row_id: ROW_A, file: "tools/coupon.py", mode: "explicit", start_line: 2, end_line: 3, dry_run: true }),
      rebindStep({ row_id: ROW_A, file: "tools/coupon.py", mode: "explicit", start_line: 2, end_line: 3 })
    ]
  },
  {
    name: "rebind_refusals",
    entries: [
      ...baseEntries(),
      fileEntry("Sources/Checkout.swift", CHECKOUT_SWIFT),
      fileEntry("README.md", "# Readme\n")
    ],
    steps: [
      rebindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "swift-func", line: 4 }),
      bindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "swift-func", line: 4 }),
      rebindStep({ row_id: "checkout.unknown_row", file: "Sources/Checkout.swift", mode: "swift-func", line: 4 }),
      rebindStep({ row_id: ROW_A, suffix: "No Good", file: "Sources/Checkout.swift", mode: "swift-func", line: 4 }),
      rebindStep({ row_id: ROW_A, file: "Sources/Missing.swift", mode: "swift-func", line: 4 }),
      rebindStep({ row_id: ROW_A, file: "README.md", mode: "explicit", start_line: 1, end_line: 1 }),
      rebindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "swift-func", line: 40 }),
      rebindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "swift-func", line: 1 })
    ]
  },
  {
    name: "rebind_when_marker_already_gone",
    entries: [
      ...baseEntries(),
      fileEntry("Sources/Checkout.swift", CHECKOUT_SWIFT),
      ledgerEntry([registeredLine(ROW_A, ROW_A, "event-seed")])
    ],
    steps: [rebindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "swift-func", line: 8 })]
  },
  {
    name: "unbind_row_retired",
    entries: [...baseEntries(), fileEntry("tools/coupon.py", COUPON_PY)],
    steps: [
      bindStep({ row_id: ROW_A, file: "tools/coupon.py", mode: "explicit", start_line: 1, end_line: 3 }),
      { kind: "write", path: "use-cases/checkout.yml", contents: ONLY_ROW_B },
      validateStep(),
      unbindStep({ row_id: ROW_A, reason: "row_retired" }),
      validateStep()
    ]
  },
  {
    name: "unbind_refusals_and_dry_run",
    entries: [...baseEntries(), fileEntry("Sources/Checkout.swift", CHECKOUT_SWIFT)],
    steps: [
      unbindStep({ row_id: ROW_A }),
      unbindStep({ row_id: ROW_A, suffix: "Not Valid" }),
      bindStep({ row_id: ROW_A, file: "Sources/Checkout.swift", mode: "swift-func", line: 4 }),
      unbindStep({ row_id: ROW_A, dry_run: true }),
      { kind: "write", path: ".use-cases/bindings.jsonl", contents: "[]\n" },
      unbindStep({ row_id: ROW_A })
    ]
  },
  {
    name: "unbind_when_marker_already_gone",
    entries: [
      ...baseEntries(),
      fileEntry("Sources/Checkout.swift", CHECKOUT_SWIFT),
      ledgerEntry([registeredLine(ROW_A, `${ROW_A}#kept`, "event-seed")])
    ],
    steps: [unbindStep({ row_id: ROW_A, suffix: "kept" }), bindStep({ row_id: ROW_A, suffix: "kept", file: "Sources/Checkout.swift", mode: "swift-func", line: 4 })]
  },
  {
    name: "crlf_source",
    entries: [
      ...baseEntries(),
      fileEntry("Sources/Crlf.swift", CHECKOUT_SWIFT.split("\n").join("\r\n")),
      fileEntry("tools/crlf.py", COUPON_PY.split("\n").join("\r\n"))
    ],
    steps: [
      bindStep({ row_id: ROW_A, file: "Sources/Crlf.swift", mode: "swift-func", line: 4 }),
      bindStep({ row_id: ROW_B, file: "tools/crlf.py", mode: "explicit", start_line: 2, end_line: 3 }),
      rebindStep({ row_id: ROW_B, file: "tools/crlf.py", mode: "explicit", start_line: 1, end_line: 2 }),
      unbindStep({ row_id: ROW_B })
    ]
  },
  {
    name: "source_without_trailing_newline",
    entries: [...baseEntries(), fileEntry("tools/coupon.py", COUPON_PY.slice(0, -1))],
    steps: [
      bindStep({ row_id: ROW_A, file: "tools/coupon.py", mode: "explicit", start_line: 2, end_line: 3 }),
      rebindStep({ row_id: ROW_A, file: "tools/coupon.py", mode: "explicit", start_line: 3, end_line: 3 }),
      unbindStep({ row_id: ROW_A })
    ]
  },
  {
    name: "shebang_script_keeps_its_executable_bit",
    entries: [
      ...baseEntries(),
      fileEntry("bin/deploy", "#!/bin/sh\necho one\necho two\n", 0o755),
      fileEntry("tools/private.sh", "echo secret\necho more\n", 0o600)
    ],
    steps: [
      bindStep({ row_id: ROW_A, file: "bin/deploy", mode: "explicit", start_line: 2, end_line: 3 }),
      bindStep({ row_id: ROW_B, file: "tools/private.sh", mode: "explicit", start_line: 1, end_line: 2 }),
      rebindStep({ row_id: ROW_A, file: "bin/deploy", mode: "explicit", start_line: 2, end_line: 2 }),
      rebindStep({ row_id: ROW_B, file: "bin/deploy", mode: "explicit", start_line: 5, end_line: 5 }),
      unbindStep({ row_id: ROW_A })
    ]
  },
  {
    name: "nested_workspace_skipped",
    entries: [
      ...baseEntries(),
      fileEntry("vendor/sample/use-cases.yml", CONFIG_YAML),
      fileEntry("vendor/sample/Sources/Pkg.swift", markedSwift(ROW_A)),
      fileEntry("fixtures/other/use-cases.yaml", CONFIG_YAML),
      fileEntry("fixtures/other/tool.py", [startMarker("#", ROW_B), "x = 1", endMarker("#", ROW_B), ""].join("\n")),
      ledgerEntry([registeredLine(ROW_A, ROW_A, "event-a"), registeredLine(ROW_B, ROW_B, "event-b")])
    ],
    steps: [unbindStep({ row_id: ROW_A }), unbindStep({ row_id: ROW_B })]
  },
  {
    name: "symlinked_source_skipped",
    entries: [
      ...baseEntries(),
      ["file", "outside/Linked.swift", markedSwift(ROW_A), 0o644],
      ["file", "outside/dir/tool.py", [startMarker("#", ROW_B), "x = 1", endMarker("#", ROW_B), ""].join("\n"), 0o644],
      ["symlink", "workspace/Sources/Link.swift", "../../outside/Linked.swift"],
      ["symlink", "workspace/linked", "../outside/dir"],
      ledgerEntry([registeredLine(ROW_A, ROW_A, "event-a"), registeredLine(ROW_B, ROW_B, "event-b")])
    ],
    steps: [unbindStep({ row_id: ROW_A }), unbindStep({ row_id: ROW_B })]
  },
  {
    name: "skip_directory_contents_ignored",
    entries: [
      ...baseEntries(),
      ...SKIP_DIRECTORIES.map((directory) => fileEntry(`${directory}/Stray.swift`, markedSwift(ROW_A))),
      fileEntry("zz/.build/Gen.swift", markedSwift(ROW_A)),
      ledgerEntry([registeredLine(ROW_A, ROW_A, "event-a")])
    ],
    steps: [unbindStep({ row_id: ROW_A, dry_run: true })]
  },
  {
    name: "validate_ledger_reports",
    entries: [
      ...baseEntries(),
      ledgerEntry([registeredLine(ROW_A, ROW_A, "event-a"), registeredLine(ROW_B, ROW_A, "event-b"), "", "[1]"]),
      fileEntry(".use-cases/proofs.jsonl", '{"schema":"ucase-proof-event-v1"}\n\n"text"\n{"entry_index":0,"previous_entry_hash":"sha256:00"}\n')
    ],
    steps: [validateStep()]
  },
  {
    name: "validate_ledger_against_base_ref",
    entries: [
      ...baseEntries(),
      ledgerEntry([registeredLine(ROW_A, ROW_A, "event-a"), registeredLine(ROW_B, ROW_B, "event-b")])
    ],
    steps: [
      { kind: "git", arguments: ["init", "-q", "-b", "main"] },
      { kind: "git", arguments: ["add", "-A"] },
      { kind: "git", arguments: [...gitIdentity, "commit", "-q", "-m", "base"] },
      validateStep({ base_ref: "HEAD" }),
      {
        kind: "write",
        path: ".use-cases/bindings.jsonl",
        contents: `${registeredLine(ROW_B, ROW_B, "event-b")}\n`
      },
      validateStep({ base_ref: "HEAD" })
    ]
  },
  {
    name: "validate_ledger_against_scripted_base_texts",
    entries: [
      ...baseEntries(),
      ledgerEntry([registeredLine(ROW_B, ROW_B, "event-b")]),
      fileEntry(".use-cases/proofs.jsonl", "")
    ],
    steps: [
      validateStep({
        base_ref: "main",
        base_texts: {
          "bindings.jsonl": `${registeredLine(ROW_A, ROW_A, "event-a")}\n${registeredLine(ROW_B, ROW_B, "event-b")}\n`,
          "proofs.jsonl": '{"x":1}\n'
        }
      }),
      validateStep({
        base_ref: "main",
        base_texts: { "bindings.jsonl": `${registeredLine(ROW_B, ROW_B, "event-b")}\n` }
      })
    ]
  }
];

// ---------------------------------------------------------------------------
// Direct cases for the building blocks.

const insertCases = [];
const addInsert = (name, source, prefix, slug, placement) => {
  insertCases.push({ name, source, prefix, slug, placement, result: plain(insertMarkerLines(source, prefix, slug, placement)) });
};
const THREE = "one\ntwo\nthree\n";
addInsert("swift_func_first_line", THREE, "//", ROW_A, { mode: "swift-func", line: 1 });
addInsert("swift_func_middle", THREE, "//", ROW_A, { mode: "swift-func", line: 2 });
addInsert("swift_func_one_past_the_last_line", THREE, "//", ROW_A, { mode: "swift-func", line: 4 });
addInsert("swift_func_two_past_the_last_line", THREE, "//", ROW_A, { mode: "swift-func", line: 5 });
addInsert("swift_func_line_zero", THREE, "//", ROW_A, { mode: "swift-func", line: 0 });
addInsert("swift_func_negative_line", THREE, "//", ROW_A, { mode: "swift-func", line: -3 });
addInsert("swift_func_missing_line", THREE, "//", ROW_A, { mode: "swift-func", startLine: 1, endLine: 2 });
addInsert("swift_func_empty_source", "", "//", ROW_A, { mode: "swift-func", line: 1 });
addInsert("swift_func_empty_source_line_two", "", "//", ROW_A, { mode: "swift-func", line: 2 });
addInsert("swift_func_single_newline", "\n", "//", ROW_A, { mode: "swift-func", line: 2 });
addInsert("swift_func_crlf", "one\r\ntwo\r\nthree\r\n", "//", ROW_A, { mode: "swift-func", line: 2 });
addInsert("swift_func_without_trailing_newline", "one\ntwo", "//", ROW_A, { mode: "swift-func", line: 3 });
addInsert("swift_func_indented_declaration_marker_not_indented", "struct S {\n    func f() {}\n}\n", "//", ROW_A, { mode: "swift-func", line: 2 });
addInsert("explicit_single_line", THREE, "#", `${ROW_A}#part`, { mode: "explicit", startLine: 2, endLine: 2 });
addInsert("explicit_whole_file", THREE, "#", ROW_A, { mode: "explicit", startLine: 1, endLine: 3 });
addInsert("explicit_end_past_the_last_line", THREE, "#", ROW_A, { mode: "explicit", startLine: 1, endLine: 4 });
addInsert("explicit_start_zero", THREE, "#", ROW_A, { mode: "explicit", startLine: 0, endLine: 2 });
addInsert("explicit_end_before_start", THREE, "#", ROW_A, { mode: "explicit", startLine: 3, endLine: 2 });
addInsert("explicit_missing_start", THREE, "#", ROW_A, { mode: "explicit", endLine: 2 });
addInsert("explicit_missing_end", THREE, "#", ROW_A, { mode: "explicit", startLine: 2, line: 2 });
addInsert("explicit_crlf", "one\r\ntwo\r\nthree\r\n", "#", ROW_A, { mode: "explicit", startLine: 2, endLine: 3 });
addInsert("explicit_without_trailing_newline", "one\ntwo\nthree", "#", ROW_A, { mode: "explicit", startLine: 2, endLine: 3 });
addInsert("explicit_empty_source", "", "#", ROW_A, { mode: "explicit", startLine: 1, endLine: 1 });
addInsert("explicit_blank_lines", "\n\n\n", "#", ROW_A, { mode: "explicit", startLine: 1, endLine: 3 });
addInsert("explicit_lone_carriage_returns", "a\rb\rc", "#", ROW_A, { mode: "explicit", startLine: 1, endLine: 1 });

const locateCases = [];
const addLocate = (name, contents, prefix, slug) => {
  locateCases.push({ name, contents, prefix, slug, result: plain(locateMarkerLines("src/File.swift", contents, prefix, slug)) });
};
const S = startMarker("//", ROW_A);
const E = endMarker("//", ROW_A);
addLocate("start_only", ["a", S, "func f() {}", ""].join("\n"), "//", ROW_A);
addLocate("start_and_end", ["a", S, "b", E, ""].join("\n"), "//", ROW_A);
addLocate("end_before_start_is_ignored", [E, S, "b", ""].join("\n"), "//", ROW_A);
addLocate("second_start_ignored_first_end_kept", [S, "x", E, S, E, ""].join("\n"), "//", ROW_A);
addLocate("other_slug_end_ignored", [S, endMarker("//", ROW_B), "x", E].join("\n"), "//", ROW_A);
addLocate("absent", "a\nb\n", "//", ROW_A);
addLocate("indented", ["  " + S, "\t" + E].join("\n"), "//", ROW_A);
addLocate("crlf_start_does_not_parse", [S, "x", E, ""].join("\r\n"), "//", ROW_A);
addLocate("crlf_last_line_without_terminator", [S, "x", E].join("\r\n"), "//", ROW_A);
addLocate("other_prefix", [startMarker("#", ROW_A), "x"].join("\n"), "//", ROW_A);
addLocate("explicit_begin_form", [`${token("//")}begin ${ROW_A}`, "x", E].join("\n"), "//", ROW_A);
addLocate("suffixed_slug_is_distinct", [startMarker("//", `${ROW_A}#two`), S].join("\n"), "//", ROW_A);

const removeCases = [];
const addRemove = (name, contents, location) => {
  removeCases.push({ name, contents, location, result: removeMarkerLines(contents, location) });
};
addRemove("start_only", "a\nb\nc\n", { file_path: "f", start_line: 2, end_line: null });
addRemove("start_and_end", "a\nb\nc\nd\n", { file_path: "f", start_line: 1, end_line: 4 });
addRemove("without_trailing_newline", "a\nb\nc", { file_path: "f", start_line: 3, end_line: null });
addRemove("crlf", "a\r\nb\r\nc\r\n", { file_path: "f", start_line: 1, end_line: 2 });
addRemove("out_of_range_is_a_no_op", "a\nb\n", { file_path: "f", start_line: 9, end_line: 10 });
addRemove("everything", "a\n", { file_path: "f", start_line: 1, end_line: null });
addRemove("empty_source", "", { file_path: "f", start_line: 1, end_line: null });

const eventInput = {
  command: "rebind",
  rowId: ROW_A,
  bindingSlug: `${ROW_A}#two`,
  reason: "wrong_declaration",
  eventId: "event-0001",
  createdAt: "2026-09-17T10:00:00.000Z"
};
const registryEventCases = [
  { name: "registered_default_version", kind: "registered", input: eventInput, json: JSON.stringify(bindingRegisteredEvent(eventInput)) },
  { name: "released_explicit_version", kind: "released", input: { ...eventInput, version: "1.2.3" }, json: JSON.stringify(bindingReleasedEvent({ ...eventInput, version: "1.2.3" })) }
];

const appendCases = [];
for (const [name, before] of [
  ["missing_file", null],
  ["missing_parent_directory", null],
  ["empty_file", ""],
  ["with_trailing_newline", '{"a":1}\n'],
  ["without_trailing_newline", '{"a":1}'],
  ["blank_last_line", '{"a":1}\n\n'],
  ["crlf_last_line", '{"a":1}\r\n'],
  ["only_a_carriage_return", "\r"]
]) {
  const temporary = realpathSync(mkdtempSync(join(tmpdir(), "uc-append-")));
  try {
    const path = name === "missing_parent_directory" ? join(temporary, "deep/er/ledger.jsonl") : join(temporary, "ledger.jsonl");
    if (before !== null) {
      writeFileSync(path, before);
      chmodSync(path, 0o640);
    }
    appendJsonlLine(nodeMarkerFs, path, '{"b":2}');
    appendCases.push({
      name,
      nested: name === "missing_parent_directory",
      before,
      line: '{"b":2}',
      after: readFileSync(path, "utf8"),
      mode: statSync(path).mode & 0o7777
    });
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
}

const writeTextCases = [];
for (const [name, initialMode, preserveMode] of [
  ["preserve_executable", 0o755, true],
  ["preserve_owner_only", 0o600, true],
  ["preserve_setuid_bits", 0o4755, true],
  ["no_preserve_drops_executable", 0o755, false],
  ["preserve_on_a_new_file", null, true],
  ["no_preserve_on_a_new_file", null, false]
]) {
  const temporary = realpathSync(mkdtempSync(join(tmpdir(), "uc-write-")));
  try {
    const path = join(temporary, "tool.sh");
    if (initialMode !== null) {
      writeFileSync(path, "old\n");
      chmodSync(path, initialMode);
    }
    nodeMarkerFs.writeText(path, "new\n", { preserveMode });
    writeTextCases.push({
      name,
      initial_mode: initialMode,
      preserve_mode: preserveMode,
      contents: readFileSync(path, "utf8"),
      mode: statSync(path).mode & 0o7777,
      directory_entries: readdirSync(temporary).sort()
    });
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
}

const collectCases = [];
const addCollect = (name, entries, options = {}) => {
  const temporary = realpathSync(mkdtempSync(join(tmpdir(), "uc-collect-")));
  try {
    materialize(temporary, entries);
    const workspace = join(temporary, "workspace");
    let result;
    try {
      result = {
        inputs: plain(
          collectSourceInputs(workspace, {
            config: options.config,
            skipPaths: options.skip_paths?.map((path) => join(temporary, path))
          })
        )
      };
    } catch (error) {
      result = { throws: error.code };
    }
    collectCases.push({ name, entries, options, result });
  } finally {
    for (const entry of entries) {
      if (entry[0] === "chmod") {
        chmodSync(join(temporary, entry[1]), 0o755);
      }
    }
    rmSync(temporary, { recursive: true, force: true });
  }
};

addCollect("walk_rules", [
  ...baseEntries(),
  fileEntry("Sources/App.swift", "let a = 1\n"),
  fileEntry("Sources/README.md", "# not a source\n"),
  fileEntry("Z.swift", "z\n"),
  fileEntry("a.swift", "a\n"),
  fileEntry("_.swift", "_\n"),
  fileEntry("\u{1F600}.swift", "emoji\n"),
  fileEntry("\u{FF5E}.swift", "tilde\n"),
  fileEntry("bin/hook", "#!/usr/bin/env bash\necho hi\n", 0o755),
  fileEntry("bin/notes", "plain text\n"),
  fileEntry("bin/UPPER.PY", "x = 1\n"),
  fileEntry(".gitignore", "dist\n"),
  ...SKIP_DIRECTORIES.map((directory) => fileEntry(`${directory}/Inside.swift`, "skipped\n")),
  ...SKIP_DIRECTORIES.map((directory) => fileEntry(`deeper/${directory}/Inside.swift`, "skipped too\n")),
  fileEntry(".build/checkouts/Dep.swift", "kept\n"),
  fileEntry("DerivedData/Build/Gen.swift", "kept\n"),
  fileEntry("vendor/sample/use-cases.yml", CONFIG_YAML),
  fileEntry("vendor/sample/Pkg.swift", "nested\n"),
  fileEntry("vendor/other/use-cases.yaml", CONFIG_YAML),
  fileEntry("vendor/other/Pkg.swift", "nested\n"),
  fileEntry("vendor/kept/use-cases.json", "{}\n"),
  fileEntry("vendor/kept/Pkg.swift", "kept\n"),
  ["file", "outside/Linked.swift", "outside\n", 0o644],
  ["symlink", "workspace/Link.swift", "../outside/Linked.swift"],
  ["symlink", "workspace/linked-dir", "../outside"],
  ["symlink", "workspace/dangling.swift", "nowhere.swift"],
  fileEntry("custom-data/Data.swift", "skipped by skip path\n"),
  fileEntry("custom-data-extra/Data.swift", "kept: prefix only\n"),
  ["directory", "workspace/empty"]
], { skip_paths: ["workspace/custom-data"] });

addCollect("comment_config_override", [
  fileEntry("README.md", "# readme\n"),
  fileEntry("App.swift", "let a = 1\n"),
  fileEntry("script.py", "x = 1\n")
], { config: { extensions: { ".md": "<!--", ".swift": "#" } } });

addCollect("directory_named_like_a_workspace_config_throws", [
  fileEntry("App.swift", "let a = 1\n"),
  ["directory", "workspace/child/use-cases.yml"]
]);

addCollect("unreadable_child_directory_throws_from_the_nested_check", [
  fileEntry("App.swift", "let a = 1\n"),
  fileEntry("locked/Inside.swift", "x\n"),
  ["chmod", "workspace/locked", 0o000]
]);

addCollect("unlistable_but_searchable_directory_is_swallowed", [
  fileEntry("App.swift", "let a = 1\n"),
  fileEntry("locked/Inside.swift", "x\n"),
  ["chmod", "workspace/locked", 0o311]
]);

addCollect("missing_product_root_is_swallowed", []);

const rowsCases = [];
{
  const temporary = realpathSync(mkdtempSync(join(tmpdir(), "uc-rows-")));
  try {
    // Keys chosen so code-unit order ("-" < "1" < "_" < "a") differs from
    // locale order. The loader refuses a duplicate key, so stability cannot be
    // observed through a loaded row.
    const variantsExtra = `    variants:
      - key: zeta
        title: Zeta
      - key: alpha
        title: First alpha
      - key: _under
      - key: 1digit
      - key: a-b
`;
    const plannedRow = `  - id: checkout.later
    title: A planned row without policies
    lifecycle: planned
    value_tier: supporting
    journey_role: edge
    usage_frequency: rare
`;
    const entries = [
      ["file", "workspace/use-cases.yml", CONFIG_YAML, 0o644],
      [
        "file",
        "workspace/use-cases/checkout.yml",
        useCaseYaml([rowYaml(ROW_B, "Remove a coupon", variantsExtra), rowYaml(ROW_A, "Apply a valid coupon"), plannedRow]),
        0o644
      ]
    ];
    materialize(temporary, entries);
    const context = resolveWorkspaceContext({ workspaceRoot: join(temporary, "workspace") });
    const loaded = loadMarkerRows(context);
    if (loaded.rows.length !== 3) {
      throw new Error(`load_marker_rows fixture loaded ${loaded.rows.length} rows, expected 3`);
    }
    rowsCases.push({
      name: "two_rows_one_family",
      entries,
      rows: plain(loaded.rows),
      row_ids: [...loaded.rowIds],
      variants: loaded.rows.map((row) => plain(rowVariants(row)))
    });
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
}

const pathCases = {
  to_posix: ["a\\b\\c", "", "/x/y", "\\\\server\\share", "mixed/a\\b"].map((input) => ({ input, output: toPosix(input) })),
  resolve_under_root: [
    ["/root", "/abs/file.swift"],
    ["/root", "rel/file.swift"],
    ["/root", "../up/file.swift"],
    ["/root", ""],
    ["/root/", "./a//b/"],
    ["/root", "a\\b.swift"]
  ].map(([root, value]) => ({ root, value, output: resolveUnderRoot(root, value) }))
};

const corpus = {
  umask,
  command_cases: commandCases.map(runCommandCase),
  insert_marker_lines: insertCases,
  locate_marker_lines: locateCases,
  remove_marker_lines: removeCases,
  registry_events: registryEventCases,
  append_jsonl_line: appendCases,
  write_text: writeTextCases,
  collect_source_inputs: collectCases,
  load_marker_rows: rowsCases,
  paths: pathCases
};

// Every non-ASCII code unit (including each half of a surrogate pair) becomes
// a \uXXXX escape, so the emitted Swift file is pure ASCII and ONE line.
const asciiJson = JSON.stringify(corpus).replace(
  /[-￿]/g,
  (character) => `\\u${character.charCodeAt(0).toString(16).padStart(4, "0")}`
);

let pounds = "#";
while (asciiJson.includes(`\\${pounds}`) || asciiJson.includes(`"""${pounds}`)) {
  pounds += "#";
}

const names = (cases) => cases.map((entry) => `    ${JSON.stringify(entry.name)},`).join("\n");
const nameList = (label, cases) => `  static let ${label}: [String] = [\n${names(cases)}\n  ]\n`;

const swift = `// swiftlint:disable single_line_closure_body line_length
// A generated data file: the corpus below is one JSON literal.
// Generated from the TypeScript marker command cores. DO NOT EDIT BY HAND.
//
// Every expected value is what packages/core/dist/markers/cli returned, or left
// on disk, for the input beside it.
//
// Regenerate with:
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-marker-commands-corpus.mjs
enum MarkerCommandsGoldenCorpus {
${nameList("commandCaseNames", commandCases)}
${nameList("insertCaseNames", insertCases)}
${nameList("locateCaseNames", locateCases)}
${nameList("removeCaseNames", removeCases)}
${nameList("appendCaseNames", appendCases)}
${nameList("writeTextCaseNames", writeTextCases)}
${nameList("collectCaseNames", collectCases)}
  /// The corpus itself: one JSON object, ASCII only, on one line.
  static let json = ${pounds}"""
  ${asciiJson}
  """${pounds}
}

// swiftlint:enable single_line_closure_body line_length
`;

mkdirSync(dirname(targetPath), { recursive: true });
writeFileSync(targetPath, swift);
const written = readFileSync(targetPath, "utf8");
if (!/^[\x00-\x7f]*$/.test(written)) {
  throw new Error("corpus file is not ASCII");
}
if (/^[ \t]*(\/\/|#): @use-case:/m.test(written)) {
  throw new Error("corpus file carries a marker line");
}
console.log(
  `wrote ${targetPath}: ${commandCases.length} command, ${insertCases.length} insert, ` +
    `${locateCases.length} locate, ${removeCases.length} remove, ${appendCases.length} append, ` +
    `${writeTextCases.length} write, ${collectCases.length} collect cases`
);
