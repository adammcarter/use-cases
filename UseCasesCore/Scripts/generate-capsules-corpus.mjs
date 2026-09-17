// Regenerates the demo capsule corpus by running every case below through the
// REAL TypeScript, and recording exactly what it returns, throws and writes.
//
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-capsules-corpus.mjs
//
// Written:
//
//   Tests/UseCasesCoreTests/Capsules/CapsulesGoldenCorpus.swift
//     `loadDemoCapsules`, `planDemoCapsule` and `runDemoCapsule` over real
//     workspaces: capsule files of every extension, parse and schema failures,
//     duplicate ids, symlinks, FIFOs, ICU-ordered names, and runs that execute
//     real commands -- passing, failing, timing out, killed, unstartable,
//     overflowing node's maxBuffer, escaping the workspace -- with the result
//     or error, and every file the workspace holds afterwards.
//
// The script refuses to run when the dist is older than its src. Absolute
// paths become `<workspace>`. Nondeterminism is pinned the way the Swift side
// injects it: `Date.now()` reads the case's clock, and `process.env` is
// replaced by the case's environment for the duration of a run, so the
// allowlisted command environment is the same on both sides. Every command is
// a /bin/sh or /usr/bin program found through that fixed PATH.
import { chmodSync, lstatSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, readlinkSync, realpathSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const packageRoot = dirname(scriptDirectory);
const repositoryRoot = dirname(packageRoot);
const coreRoot = join(repositoryRoot, "packages/core");
const testsDirectory = join(packageRoot, "Tests/UseCasesCoreTests/Capsules");

for (const name of ["capsules/types", "capsules/loadCapsule", "capsules/runCapsule", "redact"]) {
  if (statSync(join(coreRoot, "dist", `${name}.js`)).mtimeMs < statSync(join(coreRoot, "src", `${name}.ts`)).mtimeMs) {
    throw new Error(`dist/${name}.js is older than src; rebuild packages/core first`);
  }
}

const core = await import(join(coreRoot, "dist/index.js"));
const { loadDemoCapsules, planDemoCapsule, runDemoCapsule, resolveWorkspaceContext } = core;

const FIXTURE = join(repositoryRoot, "tests/fixtures/workspaces/evidence-basic");
const PATH = "/usr/bin:/bin:/usr/sbin:/sbin";
const ENVIRONMENT = { PATH, HOME: "/corpus-home", TMPDIR: "/corpus-tmp/", UC_CORPUS_SECRET: "must-not-reach-the-command" };

// ---------------------------------------------------------------------------
// Trees

const file = (path, text) => ({ kind: "file", path, text });
const bytes = (path, buffer) => ({ kind: "file", path, base64: Buffer.from(buffer).toString("base64") });
const directory = (path) => ({ kind: "directory", path });
const symlink = (path, target) => ({ kind: "symlink", path, target });
const fifo = (path) => ({ kind: "fifo", path });
const mode = (path, value) => ({ kind: "mode", path, mode: value });

function fixtureTree() {
  const out = [];
  const walk = (current) => {
    for (const name of readdirSync(current).sort()) {
      const full = join(current, name);
      if (lstatSync(full).isDirectory()) {
        walk(full);
      } else {
        out.push(file(relative(FIXTURE, full), readFileSync(full, "utf8")));
      }
    }
  };
  walk(FIXTURE);
  return out;
}

const BASE = fixtureTree();
const withoutCapsules = () => BASE.filter((entry) => !entry.path.startsWith("demo-capsules/"));

function capsule(id, overrides = {}) {
  return {
    schema_version: 1,
    capsule_id: id,
    title: `Capsule ${id}`,
    mode: "showcase",
    description: "Demonstrate the live showcase.",
    audience: "reviewer",
    timebox_seconds: 600,
    items: [
      {
        use_case_id: "showcase.live.golden",
        runbook: [{ kind: "instruction", text: "Start the live showcase." }]
      }
    ],
    permissions: { command_execution: false },
    ...overrides
  };
}

const jsonCapsule = (path, value) => file(path, `${JSON.stringify(value, null, 2)}\n`);
const command = (argv, extra = {}) => ({
  kind: "command",
  executable: "/bin/sh",
  argv: ["-c", ...argv],
  working_directory: ".",
  expected_exit_codes: [0],
  ...extra
});
function commandCapsule(id, steps, overrides = {}) {
  return jsonCapsule(`demo-capsules/${id}.json`, capsule(id, {
    items: [{ use_case_id: "showcase.live.golden", runbook: steps }],
    permissions: { command_execution: true },
    ...overrides
  }));
}

function buildWorkspace(tree) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "use-cases-capsules-corpus-")));
  for (const entry of tree) {
    const target = join(root, entry.path);
    if (entry.kind !== "mode") {
      mkdirSync(dirname(target), { recursive: true });
    }
    switch (entry.kind) {
      case "file":
        writeFileSync(target, entry.base64 !== undefined ? Buffer.from(entry.base64, "base64") : entry.text);
        break;
      case "directory":
        mkdirSync(target, { recursive: true });
        break;
      case "symlink":
        symlinkSync(entry.target, target);
        break;
      case "fifo":
        spawnSync("mkfifo", [target]);
        break;
      case "mode":
        chmodSync(target, entry.mode);
        break;
      default:
        throw new Error(`unknown entry ${entry.kind}`);
    }
  }
  return root;
}

function restoreModes(root, tree) {
  for (const entry of tree) {
    if (entry.kind === "mode") {
      chmodSync(join(root, entry.path), 0o755);
    }
  }
}

// Every file and symlink under the workspace after the case, in code-unit
// order; directories are implied by their files.
function listTree(root, current = root) {
  const out = [];
  for (const name of readdirSync(current).sort()) {
    const full = join(current, name);
    const stats = lstatSync(full);
    const path = relative(root, full);
    if (stats.isSymbolicLink()) {
      out.push({ path, symlink: readlinkSync(full) });
    } else if (stats.isDirectory()) {
      out.push(...listTree(root, full));
    } else if (stats.isFIFO()) {
      out.push({ path, fifo: true });
    } else {
      out.push({ path, text: readFileSync(full, "utf8") });
    }
  }
  return out;
}

function tokenized(value, workspace) {
  if (value === undefined) {
    return null;
  }
  return JSON.parse(JSON.stringify(value).split(workspace).join("<workspace>"));
}

function thrown(error) {
  return { code: error.code ?? null, message: error.message };
}

// ---------------------------------------------------------------------------
// Loading

const valid = (path, id, extra = {}) => jsonCapsule(path, capsule(id, extra));
const yamlCapsule = (path, id) => file(path, [
  "schema_version: 1",
  `capsule_id: ${id}`,
  "title: YAML capsule",
  "mode: walkthrough",
  "description: A capsule written as YAML.",
  "audience: reviewer",
  "timebox_seconds: 900",
  "items:",
  "  - use_case_id: showcase.live.golden",
  "    scenario_ids: [showcase.live.golden.cli]",
  "    runbook:",
  "      - kind: observation",
  "        text: Confirm it.",
  "permissions:",
  "  command_execution: false",
  ""
].join("\n"));

const loadCases = [
  { name: "no_demo_capsules_directory", tree: withoutCapsules() },
  { name: "empty_demo_capsules_directory", tree: [...withoutCapsules(), directory("demo-capsules")] },
  { name: "fixture_capsule_loads", tree: BASE },
  {
    name: "every_extension_and_ignored_files",
    tree: [
      ...withoutCapsules(),
      yamlCapsule("demo-capsules/a.yml", "capsule.a"),
      yamlCapsule("demo-capsules/b.yaml", "capsule.b"),
      valid("demo-capsules/c.json", "capsule.c"),
      valid("demo-capsules/d.txt", "capsule.d"),
      valid("demo-capsules/e.JSON", "capsule.e"),
      valid("demo-capsules/f.yml.bak", "capsule.f"),
      valid("demo-capsules/.json", "capsule.g"),
      file("demo-capsules/README", "not a capsule")
    ]
  },
  {
    name: "names_in_locale_order",
    tree: [
      ...withoutCapsules(),
      ...["B.yml", "a.yml", "_c.yml", "-d.yml", "10.yml", "9.yml", "\u00e9.yml", "e.yml", "Z.yml", "zz.yml", ".hidden.yml", "a b.yml", "a-b.yml", "a_b.yml", "a.b.yml"].map(
        (name, index) => yamlCapsule(`demo-capsules/${name}`, `capsule.order_${index}`)
      )
    ]
  },
  {
    name: "nested_directories_are_walked_depth_first",
    tree: [
      ...withoutCapsules(),
      yamlCapsule("demo-capsules/b/inner.yml", "capsule.inner"),
      yamlCapsule("demo-capsules/a.yml", "capsule.a"),
      yamlCapsule("demo-capsules/b/deeper/leaf.yml", "capsule.leaf"),
      yamlCapsule("demo-capsules/c.yml", "capsule.c")
    ]
  },
  {
    name: "parse_errors",
    tree: [
      ...withoutCapsules(),
      file("demo-capsules/broken.json", "{\"schema_version\": 1,"),
      file("demo-capsules/broken.yml", "items: [unclosed\n"),
      file("demo-capsules/empty.json", ""),
      yamlCapsule("demo-capsules/good.yml", "capsule.good")
    ]
  },
  {
    name: "schema_errors",
    tree: [
      ...withoutCapsules(),
      jsonCapsule("demo-capsules/missing-items.json", { ...capsule("capsule.missing"), items: undefined }),
      jsonCapsule("demo-capsules/bad-command.json", capsule("capsule.bad_command", {
        items: [{ use_case_id: "showcase.live.golden", runbook: [{ kind: "command", executable: "", argv: [], working_directory: ".", expected_exit_codes: [0] }] }]
      })),
      jsonCapsule("demo-capsules/extra.json", { ...capsule("capsule.extra"), surprise: true }),
      file("demo-capsules/empty.yml", ""),
      file("demo-capsules/list.yml", "- one\n- two\n"),
      jsonCapsule("demo-capsules/fraction.json", capsule("capsule.fraction", { timebox_seconds: 1.5 }))
    ]
  },
  {
    name: "duplicate_capsule_ids",
    tree: [
      ...withoutCapsules(),
      valid("demo-capsules/a.json", "capsule.same"),
      yamlCapsule("demo-capsules/b.yml", "capsule.same"),
      valid("demo-capsules/c.json", "capsule.other"),
      valid("demo-capsules/d/e.json", "capsule.same")
    ]
  },
  {
    name: "invalid_file_does_not_claim_an_id",
    tree: [
      ...withoutCapsules(),
      jsonCapsule("demo-capsules/a.json", { ...capsule("capsule.same"), title: "" }),
      valid("demo-capsules/b.json", "capsule.same")
    ]
  },
  {
    name: "rejected_entries_are_listed_before_loaded_files",
    tree: [
      ...withoutCapsules(),
      valid("demo-capsules/a.json", "capsule.a"),
      symlink("demo-capsules/b.json", "a.json"),
      valid("demo-capsules/c.json", "capsule.c"),
      fifo("demo-capsules/d.json"),
      directory("demo-capsules/e"),
      symlink("demo-capsules/e/link-dir", ".."),
      fifo("demo-capsules/f.txt"),
      file("demo-capsules/..escape.json", `${JSON.stringify(capsule("capsule.dots"))}\n`),
      symlink("demo-capsules/g.yml", "missing-target.yml")
    ]
  },
  {
    name: "demo_capsules_root_is_a_symlink",
    tree: [
      ...withoutCapsules(),
      valid("elsewhere/a.json", "capsule.elsewhere"),
      symlink("demo-capsules", "elsewhere")
    ]
  },
  {
    name: "configured_data_root",
    tree: [
      file("use-cases.yml", readFileSync(join(FIXTURE, "use-cases.yml"), "utf8").replace("data_root: .\n", "data_root: data\n")),
      valid("data/demo-capsules/a.json", "capsule.data"),
      valid("demo-capsules/ignored.json", "capsule.ignored")
    ]
  },
  {
    name: "byte_order_marks_and_invalid_utf8",
    tree: [
      ...withoutCapsules(),
      file("demo-capsules/bom.json", `\ufeff${JSON.stringify(capsule("capsule.bom_json"))}`),
      file("demo-capsules/bom.yml", `\ufeff${JSON.stringify(capsule("capsule.bom_yaml"))}`),
      bytes("demo-capsules/latin1.json", Buffer.concat([
        Buffer.from(JSON.stringify(capsule("capsule.latin1", { title: "Caf#" })).split("#")[0]),
        Buffer.from([0xe9]),
        Buffer.from(JSON.stringify(capsule("capsule.latin1", { title: "Caf#" })).split("#")[1])
      ]))
    ]
  },
  {
    name: "json_key_order_and_duplicate_keys",
    tree: [
      ...withoutCapsules(),
      file("demo-capsules/order.json", `{"extensions":{"b.dev/x":{"z":1,"10":2,"2":[{"b":1,"0":2}]},"a.dev/y":true},${JSON.stringify(capsule("capsule.order")).slice(1)}`),
      file("demo-capsules/dup.json", `{"title":"first",${JSON.stringify(capsule("capsule.dup")).slice(1, -1)},"title":"last"}`),
      file("demo-capsules/order.yml", `extensions:\n  b.dev/x:\n    z: 1\n    "10": 2\n${readFileSync(join(FIXTURE, "demo-capsules/golden-showcase.yml"), "utf8").replace("capsule.showcase.golden", "capsule.order_yaml")}`)
    ]
  },
  {
    name: "same_capsule_as_yaml_and_json_hash_alike",
    tree: [
      ...withoutCapsules(),
      jsonCapsule("demo-capsules/one.json", { ...capsule("capsule.one") }),
      file("demo-capsules/two.yml", `${JSON.stringify(capsule("capsule.two"))}\n`)
    ]
  },
  {
    name: "unreadable_capsule_file_throws",
    tree: [...withoutCapsules(), valid("demo-capsules/locked.json", "capsule.locked"), mode("demo-capsules/locked.json", 0o000)]
  },
  {
    name: "unreadable_directory_throws",
    tree: [...withoutCapsules(), valid("demo-capsules/inner/a.json", "capsule.a"), mode("demo-capsules/inner", 0o000)]
  },
  {
    name: "demo_capsules_is_a_file_throws",
    tree: [...withoutCapsules(), file("demo-capsules", "not a directory")]
  },
  {
    name: "demo_capsules_is_a_dangling_symlink",
    tree: [...withoutCapsules(), symlink("demo-capsules", "missing")]
  }
];

function runLoadCase(testCase) {
  const workspace = buildWorkspace(testCase.tree);
  try {
    const context = resolveWorkspaceContext({ workspaceRoot: workspace });
    let outcome;
    try {
      outcome = { result: loadDemoCapsules({ context }) };
    } catch (error) {
      outcome = { thrown: thrown(error) };
    }
    return { name: testCase.name, tree: testCase.tree, outcome: tokenized(outcome, workspace) };
  } finally {
    restoreModes(workspace, testCase.tree);
    rmSync(workspace, { recursive: true, force: true });
  }
}

// ---------------------------------------------------------------------------
// Planning

const secondUseCase = file("use-cases/second.yml", readFileSync(join(FIXTURE, "use-cases/showcase-live.yml"), "utf8")
  .replace("id: showcase.live\n", "id: showcase.second\n")
  .replaceAll("showcase.live.golden", "showcase.second.golden"));
const brokenUseCase = file("use-cases/broken.yml", "schema_version: 1\nfeature: [unclosed\n");

const planCases = [
  { name: "generated_showcase", tree: BASE, capsule_id: "capsule.showcase.golden" },
  { name: "generated_walkthrough", tree: [...withoutCapsules(), yamlCapsule("demo-capsules/w.yml", "capsule.walk")], capsule_id: "capsule.walk" },
  { name: "capsule_not_found", tree: BASE, capsule_id: "capsule.nope" },
  { name: "no_capsules_directory_is_not_found", tree: withoutCapsules(), capsule_id: "capsule.showcase.golden" },
  {
    name: "integrity_blocked_keeps_the_found_capsule",
    tree: [...BASE, file("demo-capsules/zz-broken.json", "{")],
    capsule_id: "capsule.showcase.golden"
  },
  {
    name: "integrity_blocked_without_the_capsule",
    tree: [...BASE, file("demo-capsules/zz-broken.json", "{")],
    capsule_id: "capsule.nope"
  },
  {
    name: "matrix_diagnostics_are_carried",
    tree: [...BASE, brokenUseCase],
    capsule_id: "capsule.showcase.golden"
  },
  {
    name: "two_items_and_an_unknown_use_case",
    tree: [
      ...withoutCapsules(),
      secondUseCase,
      jsonCapsule("demo-capsules/two.json", capsule("capsule.two", {
        timebox_seconds: 60,
        items: [
          { use_case_id: "showcase.second.golden", runbook: [] },
          { use_case_id: "showcase.missing", runbook: [] },
          { use_case_id: "showcase.live.golden", runbook: [] }
        ]
      }))
    ],
    capsule_id: "capsule.two"
  }
];

function runPlanCase(testCase) {
  const workspace = buildWorkspace(testCase.tree);
  try {
    const context = resolveWorkspaceContext({ workspaceRoot: workspace });
    let outcome;
    try {
      outcome = { result: planDemoCapsule({ context, capsuleId: testCase.capsule_id }) };
    } catch (error) {
      outcome = { thrown: thrown(error) };
    }
    return { name: testCase.name, tree: testCase.tree, capsule_id: testCase.capsule_id, outcome: tokenized(outcome, workspace) };
  } finally {
    rmSync(workspace, { recursive: true, force: true });
  }
}

// ---------------------------------------------------------------------------
// Running

const CLOCK = 1_789_600_000_000;
const NUL = String.fromCharCode(0);

// A run: `options` are runDemoCapsule's (minus context), `environment` the
// process environment in force, `clock_ms` Date.now(), `before` files written
// first. A timeout that JSON cannot carry is spelled as a string.
const run = (options, extra = {}) => ({ options: { idempotencyKey: "corpus:key", ...options }, ...extra });
const numberOption = (value) => (Number.isFinite(value) ? value : String(value));

const runCases = [
  { name: "static_capsule_leaves_observation_pending", tree: BASE, runs: [run({ capsuleId: "capsule.showcase.golden" })] },
  {
    name: "default_idempotency_key_reads_the_clock",
    tree: BASE,
    runs: [run({ capsuleId: "capsule.showcase.golden", idempotencyKey: undefined })]
  },
  { name: "empty_idempotency_key_is_kept", tree: BASE, runs: [run({ capsuleId: "capsule.showcase.golden", idempotencyKey: "" })] },
  {
    name: "actor_host_and_recorded_at_options",
    tree: BASE,
    runs: [run({ capsuleId: "capsule.showcase.golden", actorType: "system", hostSurface: "claude.code", recordedAt: "2026-09-17T08:00:00.000Z" })]
  },
  {
    name: "command_pending_without_execution",
    tree: [...BASE, commandCapsule("capsule.pending", [command(["echo ran > ran.txt"])])],
    runs: [run({ capsuleId: "capsule.pending" })]
  },
  {
    name: "command_passes_and_run_finishes",
    tree: [...BASE, commandCapsule("capsule.pass", [
      { kind: "instruction", text: "Run it." },
      command(["printf '%s\\n' \"$@\" > argv.txt; printf 'done\\n'", "sh", "literal && touch pwned.txt", "$HOME"])
    ])],
    runs: [run({ capsuleId: "capsule.pass", executeCommands: true })]
  },
  {
    name: "command_passes_as_script_led_walkthrough",
    tree: [...BASE, commandCapsule("capsule.walk", [command(["exit 0"])], { mode: "walkthrough" })],
    runs: [run({ capsuleId: "capsule.walk", executeCommands: true, actorType: "script" })]
  },
  {
    name: "command_fails_and_run_stays_open",
    tree: [...BASE, commandCapsule("capsule.fail", [command(["echo failing >&2; exit 2"])])],
    runs: [run({ capsuleId: "capsule.fail", executeCommands: true })]
  },
  {
    name: "command_without_expected_codes_fails",
    tree: [...BASE, commandCapsule("capsule.none", [command(["exit 0"], { expected_exit_codes: [] })])],
    runs: [run({ capsuleId: "capsule.none", executeCommands: true })]
  },
  {
    name: "command_matches_one_of_several_codes",
    tree: [...BASE, commandCapsule("capsule.several", [command(["exit 3"], { expected_exit_codes: [0, 3, -1] }), command(["exit 255"], { expected_exit_codes: [255] })])],
    runs: [run({ capsuleId: "capsule.several", executeCommands: true })]
  },
  {
    name: "command_execution_not_permitted",
    tree: [...BASE, commandCapsule("capsule.denied", [command(["echo ran > ran.txt"])], { permissions: { command_execution: false } })],
    runs: [run({ capsuleId: "capsule.denied", executeCommands: true }), run({ capsuleId: "capsule.denied" })]
  },
  {
    name: "execution_requested_without_command_steps",
    tree: BASE,
    runs: [run({ capsuleId: "capsule.showcase.golden", executeCommands: true, commandTimeoutMs: 0 })]
  },
  {
    name: "working_directories",
    tree: [
      ...BASE,
      directory("sub/dir"),
      directory("..dots"),
      symlink("out-link", "/usr"),
      symlink("in-link", "sub"),
      file("plain.txt", "file"),
      file("here.txt", "root\n"),
      file("sub/here.txt", "sub\n"),
      file("sub/dir/here.txt", "sub/dir\n"),
      commandCapsule("capsule.cwd_ok", [
        command(["cat here.txt"], { working_directory: "sub/dir" }),
        command(["cat here.txt"], { working_directory: "" }),
        command(["cat here.txt"], { working_directory: "in-link" }),
        command(["cat here.txt"], { working_directory: "sub/../sub/./dir/" }),
        command(["cat here.txt"], { working_directory: "./" })
      ]),
      commandCapsule("capsule.cwd_missing", [command(["cat here.txt"], { working_directory: "missing/dir" })]),
      commandCapsule("capsule.cwd_file", [command(["cat here.txt"], { working_directory: "plain.txt" })]),
      commandCapsule("capsule.cwd_parent", [command(["cat here.txt"], { working_directory: "../" }), command(["cat here.txt"], { working_directory: "sub/../.." })]),
      commandCapsule("capsule.cwd_absolute", [command(["cat here.txt"], { working_directory: "/" })]),
      commandCapsule("capsule.cwd_link_out", [command(["cat here.txt"], { working_directory: "out-link" })]),
      commandCapsule("capsule.cwd_dots", [command(["cat here.txt"], { working_directory: "..dots" })])
    ],
    runs: [
      run({ capsuleId: "capsule.cwd_ok", executeCommands: true, idempotencyKey: "corpus:ok" }),
      run({ capsuleId: "capsule.cwd_missing", executeCommands: true, idempotencyKey: "corpus:missing" }),
      run({ capsuleId: "capsule.cwd_file", executeCommands: true, idempotencyKey: "corpus:file" }),
      run({ capsuleId: "capsule.cwd_parent", executeCommands: true, idempotencyKey: "corpus:parent" }),
      run({ capsuleId: "capsule.cwd_absolute", executeCommands: true, idempotencyKey: "corpus:absolute" }),
      run({ capsuleId: "capsule.cwd_link_out", executeCommands: true, idempotencyKey: "corpus:link" }),
      run({ capsuleId: "capsule.cwd_dots", executeCommands: true, idempotencyKey: "corpus:dots" }),
      run({ capsuleId: "capsule.cwd_parent", idempotencyKey: "corpus:parent_pending" })
    ]
  },
  {
    name: "command_timeouts",
    tree: [...BASE, commandCapsule("capsule.timeout", [command(["exit 0"])])],
    runs: [0, -5, 300_001, Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY, 300_000, 60_000].map((timeout, index) =>
      run({ capsuleId: "capsule.timeout", executeCommands: true, commandTimeoutMs: timeout, idempotencyKey: `corpus:timeout_${index}` })
    )
  },
  {
    name: "fractional_timeout_throws_from_spawn",
    tree: [...BASE, commandCapsule("capsule.fraction", [{ kind: "instruction", text: "First." }, command(["exit 0"])])],
    runs: [run({ capsuleId: "capsule.fraction", executeCommands: true, commandTimeoutMs: 1.5 })]
  },
  {
    name: "command_times_out",
    tree: [...BASE, commandCapsule("capsule.slow", [command(["printf partial; exec sleep 5"])])],
    runs: [run({ capsuleId: "capsule.slow", executeCommands: true, commandTimeoutMs: 300 })]
  },
  {
    name: "timed_out_command_that_ignores_sigterm_passes",
    tree: [...BASE, commandCapsule("capsule.stubborn", [command(["trap '' TERM; sleep 1; exit 0"])])],
    runs: [run({ capsuleId: "capsule.stubborn", executeCommands: true, commandTimeoutMs: 200 })]
  },
  {
    name: "command_killed_by_signals",
    tree: [...BASE, commandCapsule("capsule.killed", [
      command(["kill -KILL $$"]),
      command(["kill -SEGV $$"]),
      command(["kill -USR1 $$"]),
      command(["kill -INT $$"]),
      command(["kill -HUP $$"])
    ])],
    runs: [run({ capsuleId: "capsule.killed", executeCommands: true })]
  },
  {
    name: "executables_that_cannot_start",
    tree: [
      ...BASE,
      file("not-executable.sh", "#!/bin/sh\nexit 0\n"),
      file("no-shebang.sh", "exit 0\n"),
      mode("no-shebang.sh", 0o755),
      file("bad-interpreter.sh", "#!/nonexistent/interpreter\n"),
      mode("bad-interpreter.sh", 0o755),
      directory("a-directory"),
      commandCapsule("capsule.unstartable", [
        command([], { executable: "definitely-missing-use-cases-tool", argv: [] }),
        command([], { executable: "./not-executable.sh", argv: [] }),
        command([], { executable: "./no-shebang.sh", argv: [] }),
        command([], { executable: "./bad-interpreter.sh", argv: [] }),
        command([], { executable: "a-directory", argv: [] }),
        command([], { executable: "./a-directory", argv: [] }),
        command([], { executable: "sh", argv: ["-c", "exit 0"] }),
        command([], { executable: "has space", argv: [], expected_exit_codes: [] })
      ])
    ],
    runs: [run({ capsuleId: "capsule.unstartable", executeCommands: true })]
  },
  {
    name: "relative_executable_resolves_against_the_working_directory",
    tree: [
      ...BASE,
      file("sub/tool.sh", "#!/bin/sh\necho from-sub\n"),
      mode("sub/tool.sh", 0o755),
      commandCapsule("capsule.relative", [command([], { executable: "./tool.sh", argv: [], working_directory: "sub" })])
    ],
    runs: [run({ capsuleId: "capsule.relative", executeCommands: true })]
  },
  {
    name: "output_is_redacted_and_truncated",
    tree: [...BASE, commandCapsule("capsule.output", [
      command(["printf 'token=abc123 password: hunter2\\nsk-abcdefghijklmnop\\n'; printf 'AKIAABCDEFGHIJKLMNOP\\n' >&2"]),
      command(["i=0; while [ $i -lt 2100 ]; do printf 'line-%04d\\n' $i; i=$((i+1)); done"]),
      command(["head -c 16384 /dev/zero | tr '\\0' x"]),
      command(["head -c 16385 /dev/zero | tr '\\0' y >&2"]),
      command(["head -c 16390 /dev/zero | tr '\\0' z; printf 'secret=%s' $(head -c 20 /dev/zero | tr '\\0' q)"]),
      command(["printf '\\377a\\342\\202'"]),
      command(["printf ''"])
    ])],
    runs: [run({ capsuleId: "capsule.output", executeCommands: true })]
  },
  {
    name: "output_overflows_max_buffer",
    tree: [...BASE, commandCapsule("capsule.overflow", [
      command([], { executable: "/usr/bin/yes", argv: [], expected_exit_codes: [0, 1] }),
      command(["exec /usr/bin/yes stderr-line 1>&2"], { expected_exit_codes: [] }),
      command(["head -c 1048576 /dev/zero | tr '\\0' o"]),
      command(["printf 'short'; exec /usr/bin/yes both-streams 1>&2"])
    ])],
    runs: [run({ capsuleId: "capsule.overflow", executeCommands: true })]
  },
  {
    name: "environment_is_allowlisted",
    tree: [...BASE, commandCapsule("capsule.env", [command([], { executable: "/usr/bin/env", argv: [] })])],
    runs: [
      run({ capsuleId: "capsule.env", executeCommands: true, idempotencyKey: "corpus:env_a" }),
      run({ capsuleId: "capsule.env", executeCommands: true, idempotencyKey: "corpus:env_b" }, {
        environment: { WINDIR: "C:\\Windows", TMP: "/tmp-b", SystemRoot: "C:\\Windows", TEMP: "/temp-b", HOME: "/home-b", EXTRA: "x", PATH }
      }),
      run({ capsuleId: "capsule.env", executeCommands: true, idempotencyKey: "corpus:env_c" }, { environment: { HOME: "" } })
    ]
  },
  {
    name: "idempotent_retry_does_not_rerun_commands",
    tree: [
      ...BASE,
      file("counter.txt", "0"),
      commandCapsule("capsule.retry", [command(["n=$(cat counter.txt); echo $((n+1)) > counter.txt; echo counted"])])
    ],
    runs: [
      run({ capsuleId: "capsule.retry", executeCommands: true }),
      run({ capsuleId: "capsule.retry", executeCommands: true }),
      run({ capsuleId: "capsule.retry", executeCommands: true, idempotencyKey: "corpus:other" })
    ]
  },
  {
    name: "retry_after_a_failure_records_an_item_pass",
    tree: [
      ...BASE,
      commandCapsule("capsule.flaky", [command(["if [ -f fixed.txt ]; then exit 0; fi; echo not yet; exit 1"])])
    ],
    runs: [
      run({ capsuleId: "capsule.flaky", executeCommands: true }),
      run({ capsuleId: "capsule.flaky", executeCommands: true }, { before: [file("fixed.txt", "yes")] })
    ]
  },
  {
    name: "retry_without_execution_after_commands_ran",
    tree: [...BASE, commandCapsule("capsule.later", [command(["exit 0"])])],
    runs: [run({ capsuleId: "capsule.later", executeCommands: true }), run({ capsuleId: "capsule.later" })]
  },
  {
    name: "changed_capsule_conflicts_with_its_idempotency_key",
    tree: BASE,
    runs: [
      run({ capsuleId: "capsule.showcase.golden" }),
      run({ capsuleId: "capsule.showcase.golden" }, {
        before: [file("demo-capsules/golden-showcase.yml", readFileSync(join(FIXTURE, "demo-capsules/golden-showcase.yml"), "utf8").replace("Start the live showcase.", "Start it differently."))]
      })
    ]
  },
  {
    name: "two_items_mixing_observation_and_command",
    tree: [
      ...withoutCapsules(),
      secondUseCase,
      jsonCapsule("demo-capsules/mixed.json", capsule("capsule.mixed", {
        items: [
          { use_case_id: "showcase.live.golden", runbook: [{ kind: "observation", text: "Look." }] },
          { use_case_id: "showcase.second.golden", runbook: [command(["echo second"]), { kind: "instruction", text: "Then." }] }
        ],
        permissions: { command_execution: true }
      }))
    ],
    runs: [run({ capsuleId: "capsule.mixed", executeCommands: true }), run({ capsuleId: "capsule.mixed" })]
  },
  {
    name: "item_with_empty_runbook",
    tree: [
      ...withoutCapsules(),
      secondUseCase,
      jsonCapsule("demo-capsules/empty.json", capsule("capsule.empty_runbook", {
        items: [
          { use_case_id: "showcase.live.golden", runbook: [] },
          { use_case_id: "showcase.second.golden", runbook: [command(["exit 0"])] }
        ],
        permissions: { command_execution: true }
      }))
    ],
    runs: [run({ capsuleId: "capsule.empty_runbook", executeCommands: true })]
  },
  {
    name: "blocked_before_the_run",
    tree: [
      ...withoutCapsules(),
      secondUseCase,
      jsonCapsule("demo-capsules/missing-item.json", capsule("capsule.missing_item", {
        items: [
          { use_case_id: "showcase.live.golden", runbook: [] },
          { use_case_id: "showcase.nowhere", runbook: [] },
          { use_case_id: "showcase.elsewhere", runbook: [] }
        ]
      })),
      jsonCapsule("demo-capsules/no-eligible.json", capsule("capsule.no_eligible", { items: [{ use_case_id: "showcase.nowhere", runbook: [] }] }))
    ],
    runs: [
      run({ capsuleId: "capsule.nope" }),
      run({ capsuleId: "capsule.missing_item" }),
      run({ capsuleId: "capsule.no_eligible" })
    ]
  },
  {
    name: "integrity_blocked_capsules",
    tree: [...BASE, file("demo-capsules/zz.json", "[")],
    runs: [run({ capsuleId: "capsule.showcase.golden" })]
  },
  {
    name: "incomplete_plan_is_blocked",
    tree: [...BASE, brokenUseCase],
    runs: [run({ capsuleId: "capsule.showcase.golden" })]
  },
  {
    name: "null_bytes_throw_from_spawn",
    tree: [
      ...BASE,
      commandCapsule("capsule.nul_argument", [command(["exit 0"]), command(["exit 0", `a${NUL}b`])]),
      commandCapsule("capsule.nul_executable", [command([], { executable: `/bin/s${NUL}h`, argv: [] })]),
      commandCapsule("capsule.nul_directory", [command(["exit 0"], { working_directory: `sub${NUL}dir` })])
    ],
    runs: [
      run({ capsuleId: "capsule.nul_argument", executeCommands: true, idempotencyKey: "corpus:nul_a" }),
      run({ capsuleId: "capsule.nul_executable", executeCommands: true, idempotencyKey: "corpus:nul_e" }),
      run({ capsuleId: "capsule.nul_directory", executeCommands: true, idempotencyKey: "corpus:nul_d" })
    ]
  },
  {
    name: "truncation_can_split_a_surrogate_pair",
    tree: [...BASE, commandCapsule("capsule.surrogate", [command(["head -c 16383 /dev/zero | tr '\\0' s; printf '\\360\\237\\230\\200tail'"])])],
    runs: [run({ capsuleId: "capsule.surrogate", executeCommands: true })]
  }
];

// A lone surrogate cannot be held by a Swift String, so the Swift port can
// never produce one: truncation that splits a pair leaves U+FFFD there. The
// case that shows it is recorded with U+FFFD in place of the lone surrogate
// and flagged, and its ledger (whose intent digests hash the lone surrogate)
// is not compared.
function replacingLoneSurrogates(value) {
  let replaced = false;
  const text = JSON.stringify(value).replace(/\\u(d[89ab][0-9a-f]{2})(?!\\u(d[c-f][0-9a-f]{2}))|(?<!\\ud[89ab][0-9a-f]{2})\\u(d[c-f][0-9a-f]{2})/g, () => {
    replaced = true;
    return "\\ufffd";
  });
  return { value: JSON.parse(text), replaced };
}

function runRunCase(testCase) {
  const workspace = buildWorkspace(testCase.tree);
  const realDateNow = Date.now;
  const realEnvironment = process.env;
  try {
    const context = resolveWorkspaceContext({ workspaceRoot: workspace });
    const runs = testCase.runs.map((entry) => {
      for (const before of entry.before ?? []) {
        writeFileSync(join(workspace, before.path), before.text);
      }
      const environment = entry.environment ?? ENVIRONMENT;
      const options = { ...entry.options };
      if (options.idempotencyKey === undefined) {
        delete options.idempotencyKey;
      }
      Date.now = () => CLOCK;
      process.env = { ...environment };
      let outcome;
      try {
        outcome = { result: runDemoCapsule({ context, ...options }) };
      } catch (error) {
        outcome = { thrown: thrown(error) };
      } finally {
        Date.now = realDateNow;
        process.env = realEnvironment;
      }
      const recordedOptions = { ...options };
      if (recordedOptions.commandTimeoutMs !== undefined) {
        recordedOptions.commandTimeoutMs = numberOption(recordedOptions.commandTimeoutMs);
      }
      return {
        options: recordedOptions,
        clock_ms: CLOCK,
        environment: Object.entries(environment),
        before: entry.before ?? [],
        outcome: tokenized(outcome, workspace)
      };
    });
    const recorded = replacingLoneSurrogates(runs);
    return {
      name: testCase.name,
      tree: testCase.tree,
      runs: recorded.value,
      lone_surrogate_replaced: recorded.replaced,
      after: tokenized(listTree(workspace), workspace)
    };
  } finally {
    Date.now = realDateNow;
    process.env = realEnvironment;
    restoreModes(workspace, testCase.tree);
    rmSync(workspace, { recursive: true, force: true });
  }
}

// ---------------------------------------------------------------------------
// Output

const corpus = {
  load: loadCases.map(runLoadCase),
  plan: planCases.map(runPlanCase),
  run: runCases.map(runRunCase)
};

// ASCII only, and no use-case marker token anywhere in the text.
function asciiJson(value) {
  return JSON.stringify(value)
    .replace(/[\u007f-\uffff]/g, (character) => `\\u${character.charCodeAt(0).toString(16).padStart(4, "0")}`)
    .replaceAll("@use-case", "\\u0040use-case");
}

function nameList(propertyName, names) {
  return `  static let ${propertyName}: [String] = [\n${names.map((name) => `    ${asciiJson(name)},`).join("\n")}\n  ]\n\n`;
}

const json = asciiJson(corpus);
let pounds = "#";
while (json.includes(`\\${pounds}`) || json.includes(`"""${pounds}`) || json.includes(`"${pounds}`)) {
  pounds += "#";
}
const disabledRules = "line_length single_line_closure_body";
const contents = `// swiftlint:disable ${disabledRules}
// A generated data file: the corpus below is one JSON literal.
// Generated from the TypeScript demo capsule code. DO NOT EDIT BY HAND.
//
// What packages/core/dist/capsules' loadDemoCapsules, planDemoCapsule and
// runDemoCapsule returned or threw for each workspace, and what a run left
// behind.
//
// Regenerate with:
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-capsules-corpus.mjs
enum CapsulesGoldenCorpus {
${nameList("loadCaseNames", corpus.load.map((item) => item.name))}${nameList("planCaseNames", corpus.plan.map((item) => item.name))}${nameList("runCaseNames", corpus.run.map((item) => item.name))}  /// The corpus itself: one JSON object, ASCII only.
  static let json = ${pounds}"""
  ${json}
  """${pounds}
}

// swiftlint:enable ${disabledRules}
`;
mkdirSync(testsDirectory, { recursive: true });
const target = join(testsDirectory, "CapsulesGoldenCorpus.swift");
writeFileSync(target, contents);
if (!/^[\x00-\x7f]*$/.test(readFileSync(target, "utf8"))) {
  throw new Error("corpus is not ASCII");
}
console.log(`wrote ${target}: ${corpus.load.length} load, ${corpus.plan.length} plan, ${corpus.run.length} run cases`);
