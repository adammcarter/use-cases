// Regenerates the two use-case matrix corpora by running every case below
// through the REAL TypeScript in `packages/core/dist/useCases` against REAL
// temporary directories, and recording exactly what it returns and writes.
//
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-use-cases-corpus.mjs
//
// Two files are written:
//
//   Tests/UseCasesCoreTests/UseCases/UseCasesGoldenCorpus.swift
//     hand-built trees (sort orders, symlinks, damaged files, decoding), the
//     query cases, the mutation cases, and the YAML emitter cases.
//   Tests/UseCasesCoreTests/UseCases/UseCasesRepositoryMatrixCorpus.swift
//     a SNAPSHOT of this repository's own `use-cases/` tree, what loading it
//     returns, and the exact bytes a no-op upsert, a one-field upsert and a
//     removal write into each file.
//
// The TypeScript is the oracle (ADR 0007 decision 8). The script refuses to
// run against a `dist` older than its `src`, or against a `yaml` package other
// than the one whose emitter the Swift port reproduces.
//
// Inputs whose key ORDER matters are carried as JSON TEXT, and both corpora
// are emitted ASCII-only, so neither `JSON.stringify` nor the Swift compiler
// gets a chance to reorder or normalize an input before the code under test
// reads it. Absolute paths are replaced by `<workspace>` and the process id in
// a temporary file name by `<pid>`.
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  chmodSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  realpathSync,
  rmSync,
  statSync,
  symlinkSync,
  writeFileSync
} from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const packageRoot = dirname(scriptDirectory);
const repositoryRoot = dirname(packageRoot);
const coreRoot = join(repositoryRoot, "packages/core");
const sourceDirectory = join(coreRoot, "src/useCases");
const distDirectory = join(coreRoot, "dist/useCases");
const testsDirectory = join(packageRoot, "Tests/UseCasesCoreTests/UseCases");

const PORTED = [
  "types",
  "query",
  "integrity",
  "validateUseCaseFile",
  "loadUseCaseMatrix",
  "mutateUseCaseMatrix"
];

for (const name of PORTED) {
  const source = statSync(join(sourceDirectory, `${name}.ts`)).mtimeMs;
  const built = statSync(join(distDirectory, `${name}.js`)).mtimeMs;
  if (built < source) {
    throw new Error(`dist/useCases/${name}.js is older than src; rebuild packages/core first`);
  }
}

const requireFromCore = createRequire(join(coreRoot, "package.json"));
const YAML_VERSION = "2.9.0";
const yamlVersion = requireFromCore("yaml/package.json").version;
if (yamlVersion !== YAML_VERSION) {
  throw new Error(`yaml ${yamlVersion} is installed; the Swift emitter reproduces ${YAML_VERSION}`);
}
const { stringify } = requireFromCore("yaml");

const core = await import(join(coreRoot, "dist/index.js"));
const {
  loadUseCaseMatrix,
  mutateUseCaseMatrix,
  queryUseCases,
  resolveWorkspaceContext,
  toMatrixListResult,
  toMatrixValidationResult,
  validateUseCaseFile
} = core;

// ---------------------------------------------------------------------------
// Trees on disk
// ---------------------------------------------------------------------------

const file = (path, text) => ({ kind: "file", path, text });
const bytesFile = (path, bytes) => ({
  kind: "file",
  path,
  base64: Buffer.from(bytes).toString("base64")
});
const directory = (path) => ({ kind: "directory", path });
const symlink = (path, target) => ({ kind: "symlink", path, target });
const fifo = (path) => ({ kind: "fifo", path });
const mode = (path, octal) => ({ kind: "mode", path, mode: octal });

function buildTree(tree) {
  const workspace = realpathSync(mkdtempSync(join(tmpdir(), "use-cases-corpus-")));
  for (const entry of tree) {
    const target = join(workspace, entry.path);
    if (entry.kind !== "mode") {
      mkdirSync(dirname(target), { recursive: true });
    }
    switch (entry.kind) {
      case "file":
        writeFileSync(
          target,
          entry.base64 !== undefined ? Buffer.from(entry.base64, "base64") : entry.text
        );
        break;
      case "directory":
        mkdirSync(target, { recursive: true });
        break;
      case "symlink":
        symlinkSync(entry.target, target);
        break;
      case "fifo":
        execFileSync("mkfifo", [target]);
        break;
      case "mode":
        chmodSync(target, entry.mode);
        break;
      default:
        throw new Error(`unknown tree entry ${entry.kind}`);
    }
  }
  return workspace;
}

function removeTree(workspace, tree) {
  for (const entry of [...tree].reverse()) {
    if (entry.kind === "mode") {
      chmodSync(join(workspace, entry.path), 0o755);
    }
  }
  rmSync(workspace, { recursive: true, force: true });
}

function tokenized(value, workspace) {
  const text = JSON.stringify(value)
    .split(workspace)
    .join("<workspace>")
    .split(`.tmp-${process.pid}`)
    .join(".tmp-<pid>");
  return JSON.parse(text);
}

function listTree(root, current = root) {
  const names = readdirSync(current).sort();
  const out = [];
  for (const name of names) {
    const full = join(current, name);
    const stat = lstatSync(full);
    const path = relative(root, full);
    if (stat.isDirectory()) {
      out.push(`${path}/`);
      out.push(...listTree(root, full));
    } else {
      out.push(path);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Use-case file builders (JSON text is YAML, and keeps its key order)
// ---------------------------------------------------------------------------

// An ordered object for `jsonText`: `pairs(["b", 1], ["10", 2])` stays in that
// order in the TEXT, even though `JSON.parse` would move "10" first.
const pairs = (...entries) => ({ __pairs: entries });

// DEL, the C1 controls, the line and paragraph separators and the byte-order
// mark are written as \u escapes: the text is read as YAML by the Swift side
// too, and those characters RAW are a YAML reader difference (Yams refuses or
// folds them), not the behaviour these cases measure. Everything else stays
// raw, because a surrogate-pair escape is itself refused by Yams.
const escapedString = (text) =>
  JSON.stringify(text).replace(/[\u007f-\u009f\u2028\u2029\ufeff]/g, (character) => `\\u${character.charCodeAt(0).toString(16).padStart(4, "0")}`);

function jsonText(value) {
  if (value && typeof value === "object" && Array.isArray(value.__pairs)) {
    return `{${value.__pairs.map(([key, member]) => `${escapedString(key)}:${jsonText(member)}`).join(",")}}`;
  }
  if (Array.isArray(value)) {
    return `[${value.map(jsonText).join(",")}]`;
  }
  if (value && typeof value === "object") {
    return `{${Object.keys(value).map((key) => `${escapedString(key)}:${jsonText(value[key])}`).join(",")}}`;
  }
  if (Object.is(value, -0)) {
    return "-0";
  }
  return typeof value === "string" ? escapedString(value) : JSON.stringify(value);
}

function row(id, extra = {}) {
  return {
    id,
    title: `Row ${id}`,
    lifecycle: "planned",
    value_tier: "core",
    journey_role: "golden",
    usage_frequency: "common",
    ...extra
  };
}

function useCaseFile(featureId, rows, extra = {}) {
  return (
    [
      "schema_version: 1",
      "feature:",
      `  id: ${featureId}`,
      "  name: Fixture feature",
      "  summary: A fixture feature.",
      "use_cases:",
      ...rows.map((item) => `  - ${jsonText(item)}`),
      ...Object.entries(extra).map(([key, value]) => `${key}: ${jsonText(value)}`)
    ].join("\n") + "\n"
  );
}

// ---------------------------------------------------------------------------
// Load cases
// ---------------------------------------------------------------------------

function contextFor(workspace) {
  return resolveWorkspaceContext({ workspaceRoot: workspace });
}

function snapshotRecord(snapshot, probes = {}) {
  return {
    complete: snapshot.complete,
    integrity: snapshot.integrity,
    validation: toMatrixValidationResult(snapshot),
    list: toMatrixListResult(snapshot, queryUseCases(snapshot)),
    diagnostics: snapshot.diagnostics,
    candidates: snapshot.candidates.map((item) => ({
      id: item.value.id,
      feature_id: item.feature.id,
      semantic_hash: item.semanticHash,
      source_path: item.source.path,
      json_pointer: item.source.jsonPointer,
      file_byte_hash: item.source.fileByteHash
    })),
    addressable_ids: snapshot.addressableUseCases.map((item) => item.value.id),
    use_case_resolutions: (probes.useCases ?? []).map((id) => resolutionRecord(id, snapshot.resolveUseCase(id))),
    scenario_resolutions: (probes.scenarios ?? []).map(([useCaseId, scenarioId]) => ({
      use_case_id: useCaseId,
      scenario_id: scenarioId,
      ...resolutionRecord(null, snapshot.resolveScenario(useCaseId, scenarioId))
    }))
  };
}

function resolutionRecord(id, resolution) {
  return {
    ...(id === null ? {} : { id }),
    kind: resolution.kind,
    source_paths:
      resolution.kind === "resolved"
        ? [resolution.useCase.source.path]
        : resolution.kind === "ambiguous"
          ? resolution.candidates.map((item) => item.source.path)
          : []
  };
}

function runLoad(testCase) {
  const workspace = buildTree(testCase.tree);
  try {
    const context = contextFor(workspace);
    let record;
    try {
      record = { snapshot: snapshotRecord(loadUseCaseMatrix({ context }), testCase.probes) };
    } catch (error) {
      record = { throws: { code: error.code ?? null, message: error.message } };
    }
    return tokenized({ name: testCase.name, tree: testCase.tree, probes: testCase.probes ?? {}, ...record }, workspace);
  } finally {
    removeTree(workspace, testCase.tree);
  }
}

const validRow = (id) => useCaseFile("fixture.feature", [row(id)]);

const loadCases = [
  { name: "no_use_cases_directory", tree: [file("README.md", "nothing here\n")] },
  { name: "empty_use_cases_directory", tree: [directory("use-cases")] },
  {
    name: "nested_directories_and_non_yaml_files",
    tree: [
      file("use-cases/top.yml", validRow("top.row")),
      file("use-cases/deep/er/nested.yaml", validRow("nested.row")),
      file("use-cases/notes.md", "not a use case\n"),
      file("use-cases/upper.YML", validRow("upper.row")),
      file("use-cases/.yml", validRow("dotfile.row")),
      file("use-cases/..yml", validRow("dotdot.row")),
      file("use-cases/archive.yml.bak", validRow("backup.row")),
      file("use-cases/trailing.", "x\n"),
      directory("use-cases/empty-directory"),
      directory("use-cases/folder.yml")
    ],
    probes: { useCases: ["top.row", "nested.row", "upper.row", "dotdot.row", "missing.row"] }
  },
  {
    name: "readdir_locale_order_decides_candidate_order",
    tree: [
      "a.yml",
      "B.yml",
      "_x.yml",
      "-x.yml",
      "a-b.yml",
      "a_b.yml",
      "a.b.yml",
      "a0.yml",
      "ab.yml",
      "\u00e9.yml",
      "e.yml",
      "f.yml",
      "item10.yml",
      "item9.yml",
      "Z/inner.yml"
    ].map((name, index) => file(`use-cases/${name}`, validRow(`order.row${String(index).padStart(2, "0")}`)))
  },
  {
    name: "ignorable_characters_tie_under_locale_order",
    tree: [
      file("use-cases/ab.yml", validRow("tie.plain")),
      file("use-cases/a\u0001b.yml", validRow("tie.control")),
      file("use-cases/a\u200bb.yml", validRow("tie.zero_width"))
    ]
  },
  {
    name: "ambiguous_source_paths_sort_by_code_unit",
    tree: [
      file("use-cases/a.yml", validRow("shared.row")),
      file("use-cases/B.yml", validRow("shared.row")),
      file("use-cases/_c.yml", validRow("shared.row")),
      file("use-cases/other.yml", validRow("other.row"))
    ],
    probes: { useCases: ["shared.row", "other.row"], scenarios: [["shared.row", "any"]] }
  },
  {
    name: "ambiguous_groups_sort_by_locale",
    tree: [
      // First appearance is code-unit order, so only a locale sort gives the
      // expected group order.
      file("use-cases/one.yml", useCaseFile("one", ["x.a-b", "x.a.b", "x.a0", "x.a_b", "x.ab"].map((id) => row(id)))),
      file("use-cases/two.yml", useCaseFile("two", ["x.ab", "x.a0", "x.a.b", "x.a-b", "x.a_b"].map((id) => row(id))))
    ]
  },
  {
    name: "addressable_rows_sort_by_locale",
    tree: [
      file(
        "use-cases/rows.yml",
        useCaseFile("rows", ["x.a-b", "x.a.b", "x.a0", "x.a_b", "x.ab", "x.b"].map((id) => row(id)))
      )
    ]
  },
  {
    name: "duplicate_id_within_one_file",
    tree: [file("use-cases/twice.yml", useCaseFile("twice", [row("dup.row"), row("dup.row"), row("solo.row")]))]
  },
  {
    name: "broken_and_ambiguous_references",
    tree: [
      file(
        "use-cases/refs.yml",
        useCaseFile("refs", [
          row("refs.source", { related_use_cases: ["refs.missing", "refs.shared", "refs.target"] }),
          row("refs.target", { related_use_cases: ["refs.source"] }),
          row("refs.clean")
        ])
      ),
      file("use-cases/shared-a.yml", validRow("refs.shared")),
      file("use-cases/shared-b.yml", validRow("refs.shared"))
    ]
  },
  {
    name: "broken_reference_only_is_partial",
    tree: [file("use-cases/refs.yml", useCaseFile("refs", [row("refs.lonely", { related_use_cases: ["refs.nowhere"] })]))]
  },
  {
    name: "every_file_invalid_is_unusable",
    tree: [file("use-cases/bad.yml", "schema_version: 1\nfeature: [\n")]
  },
  {
    name: "damaged_files_are_excluded_but_others_load",
    tree: [
      file("use-cases/good.yml", validRow("good.row")),
      file("use-cases/invalid-yaml.yml", "schema_version: 1\nfeature: {\n  id: x\n"),
      file("use-cases/schema-invalid.yml", useCaseFile("bad", [{ id: "bad.row", title: "" }])),
      file("use-cases/unknown-version.yml", "schema_version: 2\n"),
      file("use-cases/string-version.yml", 'schema_version: "1"\n'),
      file("use-cases/no-version.yml", "feature: {}\n"),
      file("use-cases/list.yml", "- 1\n- 2\n"),
      file("use-cases/duplicate-keys.yml", "schema_version: 1\nschema_version: 1\n"),
      file("use-cases/merge-key.yml", "base: &base {a: 1}\nother:\n  <<: *base\n"),
      file("use-cases/custom-tag.yml", "schema_version: !custom 1\n"),
      file(
        "use-cases/variants.yml",
        useCaseFile("variants", [
          row("variants.twice", { variants: [{ key: "a" }, { key: "b" }, { key: "a" }] }),
          row("variants.once", { variants: [{ key: "a" }, { key: "b" }] })
        ])
      )
    ],
    probes: { useCases: ["good.row", "variants.twice", "variants.once"] }
  },
  {
    name: "symlinks_are_rejected_without_being_followed",
    tree: [
      file("use-cases/real.yml", validRow("real.row")),
      file("outside/escaped.yml", validRow("escaped.row")),
      directory("outside/dir"),
      file("outside/dir/inside.yml", validRow("inside.row")),
      symlink("use-cases/linked-file.yml", "real.yml"),
      symlink("use-cases/linked-dir", "../outside/dir"),
      symlink("use-cases/escaping.yml", "../outside/escaped.yml"),
      symlink("use-cases/loop.yml", "loop.yml"),
      symlink("use-cases/dangling.yml", "does-not-exist.yml"),
      symlink("use-cases/linked-notes.md", "real.yml")
    ],
    probes: { useCases: ["real.row", "escaped.row", "inside.row"] }
  },
  {
    // A rejection is recorded during the walk, before any file is validated,
    // so only the final sort puts it between the two loaded files.
    name: "rejected_entries_sort_among_loaded_files",
    tree: [
      file("use-cases/a.yml", validRow("sorted.first")),
      file("use-cases/z.yml", validRow("sorted.last")),
      symlink("use-cases/m-link.yml", "a.yml")
    ]
  },
  {
    name: "symlinked_use_cases_root_is_followed",
    tree: [file("real-root/row.yml", validRow("root.row")), symlink("use-cases", "real-root")]
  },
  {
    name: "dangling_use_cases_root_is_absent",
    tree: [symlink("use-cases", "nowhere")]
  },
  {
    name: "fifo_is_not_a_regular_file",
    tree: [file("use-cases/row.yml", validRow("fifo.row")), fifo("use-cases/pipe.yml")]
  },
  {
    name: "unreadable_file_is_an_io_error",
    tree: [
      file("use-cases/row.yml", validRow("readable.row")),
      file("use-cases/locked.yml", validRow("locked.row")),
      mode("use-cases/locked.yml", 0o000)
    ]
  },
  {
    name: "use_cases_root_is_a_file",
    tree: [file("use-cases", "not a directory\n")]
  },
  {
    name: "unreadable_subdirectory_throws",
    tree: [file("use-cases/locked/row.yml", validRow("locked.row")), mode("use-cases/locked", 0o000)]
  },
  {
    name: "unsearchable_subdirectory_throws_on_lstat",
    tree: [file("use-cases/listable/row.yml", validRow("listable.row")), mode("use-cases/listable", 0o644)]
  },
  {
    name: "scenarios_resolve_by_id",
    tree: [
      file(
        "use-cases/scenarios.yml",
        useCaseFile("scenarios", [
          row("scenarios.row", {
            scenarios: [
              { id: "scenarios.row.one", kind: "steps", steps: ["do"], observable_outcomes: ["done"] },
              { id: "scenarios.row.twice", kind: "steps", steps: ["do"], observable_outcomes: ["done"] },
              { id: "scenarios.row.twice", kind: "steps", steps: ["again"], observable_outcomes: ["done"] }
            ]
          }),
          row("scenarios.bare")
        ])
      )
    ],
    probes: {
      useCases: ["scenarios.row"],
      scenarios: [
        ["scenarios.row", "scenarios.row.one"],
        ["scenarios.row", "scenarios.row.twice"],
        ["scenarios.row", "scenarios.row.none"],
        ["scenarios.bare", "scenarios.bare.any"],
        ["scenarios.nowhere", "x"]
      ]
    }
  },
  {
    name: "configured_use_cases_directory",
    tree: [
      file(
        "use-cases.yml",
        "schema_version: 1\nworkspace_id: fixture\ncomponent_id: fixture\ndata_root: .\nuse_cases_dir: matrix\nevidence_dir: evidence\ndemo_capsules_dir: demo-capsules\nshowcase_runs_dir: showcase-runs\n"
      ),
      file("matrix/row.yml", useCaseFile("config", [row("config.row", { related_use_cases: ["config.gone"] })]))
    ]
  }
];

// ---------------------------------------------------------------------------
// validateUseCaseFile on raw bytes
// ---------------------------------------------------------------------------

const textBytes = (text) => [...Buffer.from(text, "utf8")];
const validText = validRow("bytes.row");
const crlfText = validText.replaceAll("\n", "\r\n");

const validateCases = [
  { name: "plain_utf8", bytes: textBytes(validText) },
  { name: "utf8_byte_order_mark_is_stripped", bytes: [0xef, 0xbb, 0xbf, ...textBytes(validText)] },
  { name: "two_byte_order_marks", bytes: [0xef, 0xbb, 0xbf, 0xef, 0xbb, 0xbf, ...textBytes(validText)] },
  { name: "crlf_line_endings", bytes: textBytes(crlfText) },
  { name: "byte_order_mark_and_crlf", bytes: [0xef, 0xbb, 0xbf, ...textBytes(crlfText)] },
  { name: "empty_file", bytes: [] },
  { name: "only_byte_order_mark", bytes: [0xef, 0xbb, 0xbf] },
  { name: "whitespace_only", bytes: textBytes("\n \n") },
  { name: "null_document", bytes: textBytes("null\n") },
  { name: "scalar_document", bytes: textBytes("just text\n") },
  { name: "invalid_continuation_byte", bytes: [...textBytes("schema_version: 1\n# "), 0x80, 0x0a] },
  { name: "truncated_sequence_at_end", bytes: [...textBytes("schema_version: 1\n# "), 0xe2, 0x82] },
  { name: "overlong_encoding", bytes: [...textBytes("# "), 0xc0, 0xaf, 0x0a] },
  { name: "encoded_surrogate", bytes: [...textBytes("# "), 0xed, 0xa0, 0x80, 0x0a] },
  { name: "beyond_unicode", bytes: [...textBytes("# "), 0xf4, 0x90, 0x80, 0x80, 0x0a] },
  { name: "latin1_byte", bytes: [...textBytes("feature: caf"), 0xe9, 0x0a] },
  { name: "utf16_byte_order_mark", bytes: [0xff, 0xfe, 0x73, 0x00] },
  { name: "non_ascii_valid", bytes: textBytes(useCaseFile("unicode", [row("unicode.row", { title: "caf\u00e9 \ud83d\ude00 e\u0301" })])) },
  { name: "schema_version_float_one", bytes: textBytes(validText.replace("schema_version: 1", "schema_version: 1.0")) },
  { name: "schema_version_one_point_five", bytes: textBytes("schema_version: 1.5\n") },
  { name: "schema_version_negative_zero", bytes: textBytes("schema_version: -0\n") },
  { name: "schema_version_infinity", bytes: textBytes("schema_version: .inf\n") },
  { name: "schema_version_nan", bytes: textBytes("schema_version: .nan\n") },
  { name: "schema_version_true", bytes: textBytes("schema_version: true\n") },
  { name: "missing_required_feature", bytes: textBytes("schema_version: 1\nuse_cases: []\n") },
  { name: "additional_top_level_key", bytes: textBytes(validText + "surprise: yes\n") },
  { name: "invalid_yaml", bytes: textBytes("schema_version: 1\nfeature: [unclosed\n") },
  { name: "duplicate_variant_keys", bytes: textBytes(useCaseFile("v", [row("v.row", { variants: [{ key: "k" }, { key: "k" }] }), row("v.other")])) }
];

function runValidate(testCase) {
  const tree = [bytesFile("use-cases/target.yml", testCase.bytes)];
  const workspace = buildTree(tree);
  try {
    const result = validateUseCaseFile(join(workspace, "use-cases/target.yml"), "use-cases/target.yml");
    return tokenized(
      {
        name: testCase.name,
        base64: Buffer.from(testCase.bytes).toString("base64"),
        result: validationRecord(result)
      },
      workspace
    );
  } finally {
    removeTree(workspace, tree);
  }
}

function validationRecord(result) {
  return {
    file: result.file,
    diagnostics: result.diagnostics,
    candidates: result.candidates.map((item) => ({
      id: item.value.id,
      feature_id: item.feature.id,
      semantic_hash: item.semanticHash,
      source_path: item.source.path,
      json_pointer: item.source.jsonPointer,
      file_byte_hash: item.source.fileByteHash
    }))
  };
}

function runValidateSpecial() {
  const tree = [directory("use-cases/folder.yml")];
  const workspace = buildTree(tree);
  try {
    return [
      tokenized(
        {
          name: "missing_file",
          path: "use-cases/missing.yml",
          result: validationRecord(validateUseCaseFile(join(workspace, "use-cases/missing.yml"), "use-cases/missing.yml"))
        },
        workspace
      ),
      tokenized(
        {
          name: "directory_instead_of_file",
          path: "use-cases/folder.yml",
          result: validationRecord(validateUseCaseFile(join(workspace, "use-cases/folder.yml"), "use-cases/folder.yml"))
        },
        workspace
      )
    ];
  } finally {
    removeTree(workspace, tree);
  }
}

// ---------------------------------------------------------------------------
// queryUseCases
// ---------------------------------------------------------------------------

const queryTree = [
  file(
    "use-cases/query.yml",
    useCaseFile("query", [
      row("q.b-critical", {
        value_tier: "critical",
        journey_role: "edge",
        tags: ["alpha", "beta"],
        source_refs: [{ kind: "file", path: "src/one.ts" }],
        host_applicability: [
          { host_surface: "claude.cli", supported: true },
          { host_surface: "codex.cli", supported: false }
        ]
      }),
      row("q.a_core", {
        lifecycle: "deprecated",
        tags: ["beta"],
        source_refs: [{ kind: "file", path: "./src/two.ts" }]
      }),
      row("q.a.long", {
        value_tier: "long_tail",
        journey_role: "failure",
        lifecycle: "removed",
        host_applicability: [{ host_surface: "codex.cli", supported: true }],
        source_refs: [{ kind: "file", path: "src\\three.ts" }]
      }),
      row("q.a0", { tags: [] })
    ])
  ),
  file("use-cases/dupes.yml", useCaseFile("dupes", [row("q.dup"), row("q.dup")]))
];

const queries = {
  empty: {},
  empty_arrays_match_everything: { valueTiers: [], journeyRoles: [], lifecycles: [], hostSurfaces: [], tagsAny: [], tagsAll: [], changedPaths: [] },
  value_tier: { valueTiers: ["critical", "long_tail"] },
  journey_role: { journeyRoles: ["golden"] },
  lifecycle: { lifecycles: ["removed", "deprecated"] },
  unknown_value_matches_nothing: { valueTiers: ["bogus"] },
  host_surface_supported_only: { hostSurfaces: ["codex.cli"] },
  host_surface_claude: { hostSurfaces: ["claude.cli"] },
  tags_any: { tagsAny: ["alpha", "gamma"] },
  tags_all: { tagsAll: ["alpha", "beta"] },
  tags_any_and_all: { tagsAny: ["beta"], tagsAll: ["alpha"] },
  changed_paths_normalized: { changedPaths: ["./src/one.ts", "src/two.ts", "src\\three.ts"] },
  changed_paths_backslash_query: { changedPaths: ["src\\one.ts"] },
  changed_paths_double_dot_slash_is_not_stripped: { changedPaths: ["././src/one.ts"] },
  changed_paths_no_match: { changedPaths: ["src/four.ts"] },
  combined: { valueTiers: ["core", "critical"], lifecycles: ["planned"], hostSurfaces: ["claude.cli"] }
};

function runQueries() {
  const workspace = buildTree(queryTree);
  try {
    const snapshot = loadUseCaseMatrix({ context: contextFor(workspace) });
    return {
      tree: queryTree,
      cases: Object.entries(queries).map(([name, query]) => ({
        name,
        query,
        ids: queryUseCases(snapshot, query).map((item) => item.value.id),
        list: toMatrixListResult(snapshot, queryUseCases(snapshot, query))
      }))
    };
  } finally {
    removeTree(workspace, queryTree);
  }
}

// ---------------------------------------------------------------------------
// mutateUseCaseMatrix
// ---------------------------------------------------------------------------

// `use_case_json` is TEXT: the Swift side must see the caller's key order.
function runMutation(testCase) {
  const workspace = buildTree(testCase.tree);
  try {
    const context = contextFor(workspace);
    const options = { context, operation: testCase.options.operation };
    for (const [from, to] of [
      ["target_file", "targetFile"],
      ["use_case_id", "useCaseId"],
      ["expected_semantic_hash", "expectedSemanticHash"],
      ["reason", "reason"],
      ["actor", "actor"]
    ]) {
      if (testCase.options[from] !== undefined) {
        options[to] = testCase.options[from];
      }
    }
    if (testCase.options.use_case_json !== undefined) {
      options.useCase = JSON.parse(testCase.options.use_case_json);
    }
    let record;
    try {
      record = { result: mutateUseCaseMatrix(options) };
    } catch (error) {
      record = { throws: { code: error.code ?? null, message: error.message } };
    }
    const useCasesRoot = join(workspace, "use-cases");
    for (const entry of [...testCase.tree].reverse()) {
      if (entry.kind === "mode") {
        chmodSync(join(workspace, entry.path), 0o755);
      }
    }
    const files = listTree(useCasesRoot).map((path) => {
      const full = join(useCasesRoot, path);
      if (path.endsWith("/") || lstatSync(full).isSymbolicLink()) {
        return { path };
      }
      return { path, text: readFileSync(full, "utf8") };
    });
    return tokenized({ name: testCase.name, tree: testCase.tree, options: testCase.options, ...record, files_after: files }, workspace);
  } finally {
    removeTree(workspace, testCase.tree);
  }
}

const baseRow = row("m.row", { tags: ["one"], extensions: { "x/keep": { order: [3, 1, 2] } } });
const baseTree = [
  file("use-cases/main.yml", useCaseFile("m", [baseRow, row("m.second")])),
  file("use-cases/sub/nested.yml", useCaseFile("n", [row("n.row", { extensions: pairs(["x/removal-first", 1], ["use-cases/removal", pairs(["note", "earlier"], ["actor", "user"])]) })]))
];

const baseRowHash = (() => {
  const workspace = buildTree(baseTree);
  try {
    const snapshot = loadUseCaseMatrix({ context: contextFor(workspace) });
    if (!snapshot.complete) {
      throw new Error(`base tree is not complete: ${JSON.stringify(snapshot.diagnostics)}`);
    }
    return snapshot.resolveUseCase("m.row").useCase.semanticHash;
  } finally {
    removeTree(workspace, baseTree);
  }
})();

const upsert = (extra) => ({ operation: "upsert", ...extra });
const remove = (extra) => ({ operation: "remove", ...extra });

const mutationCases = [
  { name: "upsert_unchanged_row", tree: baseTree, options: upsert({ target_file: "main.yml", use_case_json: jsonText(baseRow) }) },
  { name: "upsert_changed_title", tree: baseTree, options: upsert({ target_file: "use-cases/main.yml", use_case_json: jsonText({ ...baseRow, title: "Changed" }) }) },
  { name: "upsert_new_row_is_appended", tree: baseTree, options: upsert({ target_file: "main.yml", use_case_json: jsonText(row("m.added", { intent: "Appended." })) }) },
  { name: "upsert_into_nested_file", tree: baseTree, options: upsert({ target_file: "sub/nested.yml", use_case_json: jsonText(row("n.added")) }) },
  { name: "upsert_backslash_target", tree: baseTree, options: upsert({ target_file: "use-cases\\sub\\nested.yml", use_case_json: jsonText(row("n.row")) }) },
  { name: "upsert_dot_slash_and_double_slash_target", tree: baseTree, options: upsert({ target_file: "./sub//nested.yml", use_case_json: jsonText(row("n.row")) }) },
  { name: "upsert_matching_expected_hash", tree: baseTree, options: upsert({ target_file: "main.yml", expected_semantic_hash: baseRowHash, use_case_json: jsonText({ ...baseRow, title: "Guarded" }) }) },
  { name: "upsert_mismatched_expected_hash", tree: baseTree, options: upsert({ target_file: "main.yml", expected_semantic_hash: "sha256:0", use_case_json: jsonText(baseRow) }) },
  { name: "upsert_expected_hash_ignored_for_new_row", tree: baseTree, options: upsert({ target_file: "main.yml", expected_semantic_hash: "sha256:0", use_case_json: jsonText(row("m.fresh")) }) },
  { name: "upsert_empty_expected_hash_is_ignored", tree: baseTree, options: upsert({ target_file: "main.yml", expected_semantic_hash: "", use_case_json: jsonText(baseRow) }) },
  { name: "upsert_schema_invalid_row", tree: baseTree, options: upsert({ target_file: "main.yml", use_case_json: jsonText({ ...baseRow, title: "", surprise: 1 }) }) },
  { name: "upsert_missing_target", tree: baseTree, options: upsert({ use_case_json: jsonText(baseRow), use_case_id: "carried.id" }) },
  { name: "upsert_empty_target", tree: baseTree, options: upsert({ target_file: "", use_case_json: jsonText(baseRow) }) },
  { name: "upsert_missing_use_case", tree: baseTree, options: upsert({ target_file: "main.yml" }) },
  { name: "upsert_use_case_without_id", tree: baseTree, options: upsert({ target_file: "main.yml", use_case_json: '{"title":"x"}' }) },
  { name: "upsert_use_case_empty_id", tree: baseTree, options: upsert({ target_file: "main.yml", use_case_json: '{"id":""}' }) },
  { name: "upsert_use_case_numeric_id", tree: baseTree, options: upsert({ target_file: "main.yml", use_case_json: '{"id":7}' }) },
  { name: "upsert_absolute_target", tree: baseTree, options: upsert({ target_file: "/etc/main.yml", use_case_json: jsonText(baseRow) }) },
  { name: "upsert_parent_segment_target", tree: baseTree, options: upsert({ target_file: "sub/../main.yml", use_case_json: jsonText(baseRow) }) },
  { name: "upsert_backslash_parent_target", tree: baseTree, options: upsert({ target_file: "..\\main.yml", use_case_json: jsonText(baseRow) }) },
  { name: "upsert_double_dot_prefixed_name_is_an_escape", tree: [...baseTree, file("use-cases/..main.yml", useCaseFile("dd", [row("dd.row")]))], options: upsert({ target_file: "..main.yml", use_case_json: jsonText(row("dd.row")) }) },
  { name: "upsert_wrong_extension", tree: baseTree, options: upsert({ target_file: "main.YML", use_case_json: jsonText(baseRow) }) },
  { name: "upsert_json_extension", tree: baseTree, options: upsert({ target_file: "main.json", use_case_json: jsonText(baseRow) }) },
  { name: "upsert_yaml_extension_missing_file", tree: baseTree, options: upsert({ target_file: "new.yaml", use_case_json: jsonText(row("new.row")) }) },
  { name: "upsert_into_incomplete_matrix", tree: [...baseTree, file("use-cases/broken.yml", "schema_version: 1\n")], options: upsert({ target_file: "main.yml", use_case_json: jsonText(baseRow), use_case_id: "carried.id" }) },
  { name: "upsert_into_empty_workspace", tree: [directory("use-cases")], options: upsert({ target_file: "main.yml", use_case_json: jsonText(baseRow) }) },
  {
    name: "upsert_rewrites_byte_order_mark_crlf_and_comments",
    tree: [bytesFile("use-cases/main.yml", [0xef, 0xbb, 0xbf, ...textBytes(`# a comment\n${useCaseFile("m", [baseRow])}`.replaceAll("\n", "\r\n"))])],
    options: upsert({ target_file: "main.yml", use_case_json: jsonText(baseRow) })
  },
  {
    name: "upsert_byte_order_mark_directly_before_first_key",
    tree: [bytesFile("use-cases/main.yml", [0xef, 0xbb, 0xbf, ...textBytes(useCaseFile("m", [baseRow]))])],
    options: upsert({ target_file: "main.yml", use_case_json: jsonText(baseRow) })
  },
  {
    name: "upsert_into_read_only_directory_throws",
    tree: [...baseTree, mode("use-cases", 0o555)],
    options: upsert({ target_file: "main.yml", use_case_json: jsonText(baseRow) })
  },
  { name: "remove_row", tree: baseTree, options: remove({ use_case_id: "m.row", reason: "Retired." }) },
  { name: "remove_row_with_actor_and_hash", tree: baseTree, options: remove({ use_case_id: "m.row", reason: "Retired.", actor: "user", expected_semantic_hash: baseRowHash }) },
  { name: "remove_keeps_existing_removal_key_order", tree: baseTree, options: remove({ use_case_id: "n.row", reason: "Again.", actor: "script" }) },
  { name: "remove_mismatched_hash", tree: baseTree, options: remove({ use_case_id: "m.row", reason: "Retired.", expected_semantic_hash: "sha256:0" }) },
  { name: "remove_unknown_row", tree: baseTree, options: remove({ use_case_id: "m.nowhere", reason: "Retired." }) },
  { name: "remove_without_reason", tree: baseTree, options: remove({ use_case_id: "m.row" }) },
  { name: "remove_empty_reason", tree: baseTree, options: remove({ use_case_id: "m.row", reason: "" }) },
  { name: "remove_without_id", tree: baseTree, options: remove({ reason: "Retired." }) },
  { name: "remove_actor_invalid_for_schema", tree: baseTree, options: remove({ use_case_id: "m.row", reason: "Retired.", actor: "robot" }) },
  { name: "remove_from_incomplete_matrix", tree: [...baseTree, file("use-cases/broken.yml", "nope: [\n")], options: remove({ use_case_id: "m.row", reason: "Retired." }) }
];

// ---------------------------------------------------------------------------
// The emitter: `stringify(value, { lineWidth: 0 })`, exactly as mutate calls it
// ---------------------------------------------------------------------------

const longKey = "k".repeat(1025);
const edgeKey = "k".repeat(1024);

const emitterStrings = [
  "plain",
  "two words",
  "",
  " ",
  "  leading",
  "trailing ",
  "a: b",
  "a:b",
  "a:",
  ":a",
  ":",
  "a:\tb",
  "a #b",
  "a\t#b",
  "a#b",
  "#a",
  "#",
  "-",
  "- a",
  "-a",
  "-\ta",
  "--",
  "?",
  "? a",
  "?a",
  "[a]",
  "a]",
  "{a}",
  "a}",
  "a,b",
  ",a",
  "*a",
  "&a",
  "!a",
  "|a",
  ">a",
  "'a",
  '"a',
  "%a",
  "@a",
  "`a",
  "a'b",
  'a"b',
  "both ' and \"",
  "null",
  "Null",
  "NULL",
  "nULL",
  "~",
  "true",
  "True",
  "TRUE",
  "tRUE",
  "false",
  "yes",
  "no",
  "on",
  "off",
  "y",
  "123",
  "-123",
  "+1",
  "0123",
  "0o17",
  "0o19",
  "0x1F",
  "0x1g",
  "0b101",
  "1.5",
  ".5",
  "1.",
  "-.5",
  "1e3",
  "1E-3",
  "+1.5e+3",
  "1e",
  ".inf",
  "-.Inf",
  "+.INF",
  ".nan",
  ".NaN",
  "1_000",
  "2024-01-01",
  "---",
  "--- a",
  "...",
  "---a",
  "a\n---",
  "%YAML",
  "multi\nline",
  "multi\nline\n",
  "multi\nline\n\n",
  "multi\nline\n\n\n",
  "\nleading newline",
  "\n\nleading newlines",
  "\n",
  "\n\n",
  "  indented\nnext",
  " \n x",
  "trailing space \nx",
  "x\n  y",
  "x\n\ty",
  "x\ny  ",
  "x\ny\n  ",
  "x\n\t",
  "a\n\n\nb",
  "a\n\n\nb\n\n",
  "a\n#b",
  "a\n- b",
  "a\n---\nb",
  "a: b\nc",
  "'quoted'\nnext",
  '"quoted"\nnext',
  "it's\nnext",
  "tab\tinside",
  "\ttab first",
  "tab last\t",
  "ctrl\u0001",
  "nul\u0000",
  "bell\u0007",
  "backspace\u0008",
  "vtab\u000b",
  "formfeed\u000c",
  "cr\rinside",
  "esc\u001b",
  "del\u007f",
  "c1\u0085",
  "c1 high\u009f",
  "nbsp\u00a0inside",
  "line separator\u2028inside",
  "emoji \ud83d\ude00",
  "caf\u00e9",
  "e\u0301",
  "\ufeffbom first",
  "short ctrl\u0001\nnext",
  "a double-quoted string that is long enough to fold \u0001\nsecond line",
  "a double-quoted string that is long enough to fold \u0001 \nspace before newline",
  "a double-quoted string that is long enough to fold \u0001\n space after newline",
  "a double-quoted string that is long enough to fold \u0001\n\n\ntwo blank lines",
  "a double-quoted string that is long enough to fold \u0001\n",
  "a double-quoted string that is long enough to fold \u0001\n\n",
  "back\\slash",
  "quote\"and\nnewline",
  "single ' and newline\n",
  "ends with colon space: ",
  "x".repeat(200)
];

const emitterDocuments = [
  ...emitterStrings.map((value, index) => ({
    name: `string_${String(index).padStart(3, "0")}`,
    json: jsonText(
      pairs(
        ["value", value],
        ["list", [value, [value]]],
        ["deep", [pairs(["inner", [pairs(["leaf", value])]])]],
        [value === "value" ? "value-key" : value, "as a key"]
      )
    )
  })),
  { name: "empty_collections", json: jsonText(pairs(["object", {}], ["array", []], ["nested", [[], {}, [[]], [{}]]], ["deep", pairs(["a", pairs(["b", {}])])])) },
  { name: "scalars", json: '{"zero":0,"negative_zero":-0,"integer":42,"negative":-7,"fraction":1.5,"big":1e21,"bigger":123456789012345680000,"small":1e-7,"tiny":5e-324,"max":1.7976931348623157e308,"true":true,"false":false,"null":null}' },
  { name: "integer_like_keys_move_first", json: '{"b":1,"10":2,"2":3,"01":4,"-1":5,"4294967295":6,"4294967294":7,"1.5":8,"a":9,"0":10}' },
  { name: "proto_key", json: '{"a":1,"__proto__":{"b":2},"c":3}' },
  { name: "long_keys", json: jsonText(pairs([edgeKey, "edge"], [longKey, "scalar"], [`${longKey}m`, pairs(["a", 1], ["b", [1, 2]])], [`${longKey}s`, [1, pairs(["c", 2])]], [`${longKey}e`, []])) },
  { name: "multiline_keys", json: jsonText(pairs(["a\nb", 1], ["---", 2], ["%x", 3], ["...", pairs(["---", 4])], ["", 5])) },
  { name: "top_level_empty_object", json: "{}" },
  { name: "sequence_of_sequences", json: jsonText(pairs(["root", [[1, [2, [3]]], [pairs(["a", [pairs(["b", "multi\nline"])]])]]])) }
];

function runEmitter(testCase) {
  return { name: testCase.name, json: testCase.json, yaml: stringify(JSON.parse(testCase.json), { lineWidth: 0 }) };
}

// The same values, through the real mutate path, inside a schema-valid row.
const emitterMutationCases = [
  {
    name: "emitter_strings_through_mutation",
    // NUL has its own case; U+FEFF is dropped by the Swift YAML READER even
    // from a `\ufeff` escape, so a file holding it cannot round-trip there.
    strings: emitterStrings.filter((value) => !value.includes("\u0000") && !value.includes("\ufeff"))
  },
  { name: "emitter_nul_through_mutation", strings: ["nul\u0000"] }
].map(({ name, strings }) => {
  const extensions = pairs(
    ["x/strings", strings],
    ["x/keys", pairs(...strings.map((value, index) => [value, index]))],
    ["x/ordering", { __pairs: [["b", 1], ["10", 2], ["2", 3], ["a", pairs(["z", 1], ["1", 2])]] }],
    ["x/scalars", pairs(["zero", 0], ["negative_zero", -0], ["fraction", 1.5], ["big", 1e21], ["flag", true], ["nothing", null], ["empty_object", {}], ["empty_array", []])]
  );
  const theRow = row("emitter.row", { intent: "multi\nline intent\n", extensions });
  const text = [
    "schema_version: 1",
    "feature:",
    "  id: emitter",
    `  name: ${escapedString(strings.find((value) => value.includes("\n")) ?? "Emitter")}`,
    "  summary: '- leading indicator'",
    "use_cases:",
    `  - ${jsonText(theRow)}`,
    // Over 1024 code units, so an EXPLICIT key: Yams cannot read an implicit
    // key that long, and `yaml` writes it explicit anyway.
    "extensions:",
    "  x/long:",
    `    ? ${longKey}`,
    "    : a: 1",
    `    ${edgeKey}: edge`,
    ""
  ].join("\n");
  return {
    name,
    tree: [file("use-cases/emitter.yml", text)],
    options: upsert({ target_file: "emitter.yml", use_case_json: jsonText(theRow) })
  };
});

// Numbers and keys only YAML can spell reach the emitter through a real file.
emitterMutationCases.push({
  name: "emitter_yaml_only_numbers_and_keys",
  tree: [
    file(
      "use-cases/numbers.yml",
      [
        "schema_version: 1",
        "feature:",
        "  id: numbers",
        "  name: Numbers",
        "  summary: Numbers only YAML can spell.",
        "use_cases:",
        "  - id: numbers.row",
        "    title: Numbers",
        "    lifecycle: planned",
        "    value_tier: core",
        "    journey_role: edge",
        "    usage_frequency: rare",
        "extensions:",
        "  x/numbers:",
        "    infinity: .inf",
        "    negative_infinity: -.Inf",
        "    not_a_number: .NaN",
        "    octal: 0o17",
        "    hexadecimal: 0x1F",
        "    exponent: 1e3",
        "    negative_zero: -0",
        "    trailing_zero: 1.50",
        "    leading_zeros: 007",
        "    huge: 123456789012345678901234567890",
        "    yes: yes",
        "    quoted_true: 'true'",
        "    1: integer key",
        "    true: boolean key",
        "    tilde: ~",
        ""
      ].join("\n")
    )
  ],
  options: upsert({ target_file: "numbers.yml", use_case_json: '{"id":"numbers.row","title":"Numbers","lifecycle":"planned","value_tier":"core","journey_role":"edge","usage_frequency":"rare"}' })
});

// ---------------------------------------------------------------------------
// This repository's matrix, snapshotted
// ---------------------------------------------------------------------------

function walkYaml(directoryPath) {
  return readdirSync(directoryPath, { withFileTypes: true }).flatMap((entry) => {
    const full = join(directoryPath, entry.name);
    if (entry.isDirectory()) {
      return walkYaml(full);
    }
    return entry.isFile() ? [full] : [];
  });
}

const repositoryFiles = walkYaml(join(repositoryRoot, "use-cases"))
  .map((full) => ({ path: relative(repositoryRoot, full).split("\\").join("/"), text: readFileSync(full, "utf8") }))
  .sort((left, right) => (left.path < right.path ? -1 : left.path > right.path ? 1 : 0));

const sha256 = (text) => `sha256:${createHash("sha256").update(text).digest("hex")}`;

function runRepositoryMatrix() {
  const tree = repositoryFiles.map((entry) => file(entry.path, entry.text));
  const workspace = buildTree(tree);
  let load;
  let firstRows;
  try {
    const snapshot = loadUseCaseMatrix({ context: contextFor(workspace) });
    load = tokenized(snapshotRecord(snapshot), workspace);
    firstRows = Object.fromEntries(
      repositoryFiles.map((entry) => {
        const candidate = snapshot.candidates.find((item) => item.source.path === entry.path && item.source.jsonPointer === "/use_cases/0");
        return [entry.path, candidate];
      })
    );
  } finally {
    removeTree(workspace, tree);
  }

  const mutations = [];
  for (const entry of repositoryFiles) {
    const first = firstRows[entry.path];
    const target = entry.path.slice("use-cases/".length);
    const kinds = {
      unchanged: upsert({ target_file: target, use_case_json: JSON.stringify(first.value), expected_semantic_hash: first.semanticHash }),
      one_field: upsert({ target_file: target, use_case_json: JSON.stringify({ ...first.value, title: `${first.value.title} (edited)` }) }),
      removed: remove({ use_case_id: first.value.id, reason: "Corpus removal.", expected_semantic_hash: first.semanticHash })
    };
    for (const [kind, options] of Object.entries(kinds)) {
      const run = runMutation({ name: `${entry.path}:${kind}`, tree, options });
      const written = run.files_after.find((item) => item.path === target);
      mutations.push({
        path: entry.path,
        kind,
        options,
        result: run.result,
        written_sha256: sha256(written.text),
        written_length: Buffer.byteLength(written.text),
        ...(kind === "unchanged" ? { written_text: written.text } : {}),
        unchanged_from_input: written.text === entry.text
      });
    }
  }
  return { files: repositoryFiles, load, mutations };
}

// ---------------------------------------------------------------------------
// Emit
// ---------------------------------------------------------------------------

function asciiJson(value) {
  return JSON.stringify(value).replace(
    /[\u007f-\uffff]/g,
    (character) => `\\u${character.charCodeAt(0).toString(16).padStart(4, "0")}`
  );
}

function nameList(propertyName, names) {
  return `  static let ${propertyName}: [String] = [\n${names.map((name) => `    ${asciiJson(name)},`).join("\n")}\n  ]\n\n`;
}

function swiftFile(typeName, body, summary, nameLists, disabledRules) {
  const json = asciiJson(body);
  let pounds = "#";
  while (json.includes(`\\${pounds}`) || json.includes(`"""${pounds}`) || json.includes(`"${pounds}`)) {
    pounds += "#";
  }
  return `// swiftlint:disable ${disabledRules}
// A generated data file: the corpus below is one JSON literal.
// Generated from the TypeScript use-case matrix code. DO NOT EDIT BY HAND.
//
// ${summary}
//
// Regenerate with:
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-use-cases-corpus.mjs
enum ${typeName} {
${nameLists}  /// The corpus itself: one JSON object, ASCII only.
  static let json = ${pounds}"""
  ${json}
  """${pounds}
}

// swiftlint:enable ${disabledRules}
`;
}

function write(name, contents) {
  const target = join(testsDirectory, name);
  mkdirSync(testsDirectory, { recursive: true });
  writeFileSync(target, contents);
  if (!/^[\x00-\x7f]*$/.test(readFileSync(target, "utf8"))) {
    throw new Error(`${name} is not ASCII`);
  }
  return target;
}

const golden = {
  yaml_version: YAML_VERSION,
  load: loadCases.map(runLoad),
  validate: [...validateCases.map(runValidate), ...runValidateSpecial()],
  query: runQueries(),
  mutation: [...mutationCases, ...emitterMutationCases].map(runMutation),
  emitter: emitterDocuments.map(runEmitter)
};

const repository = runRepositoryMatrix();

const goldenPath = write(
  "UseCasesGoldenCorpus.swift",
  swiftFile(
    "UseCasesGoldenCorpus",
    golden,
    "Every expected value is what packages/core/dist/useCases returned or wrote for\n// the tree, bytes or options beside it.",
    nameList("loadCaseNames", golden.load.map((item) => item.name)) +
      nameList("validateCaseNames", golden.validate.map((item) => item.name)) +
      nameList("queryCaseNames", golden.query.cases.map((item) => item.name)) +
      nameList("mutationCaseNames", golden.mutation.map((item) => item.name)) +
      nameList("emitterCaseNames", golden.emitter.map((item) => item.name)),
    "line_length"
  )
);
const repositoryPath = write(
  "UseCasesRepositoryMatrixCorpus.swift",
  swiftFile(
    "UseCasesRepositoryMatrixCorpus",
    repository,
    "A snapshot of this repository's use-cases/ tree, what the TypeScript loader\n// returned for it, and the bytes each mutation wrote into each file.",
    nameList("mutationCaseNames", repository.mutations.map((item) => `${item.path}:${item.kind}`)),
    // The snapshot's own YAML text holds `{ … }` runs the closure rule misreads.
    "line_length single_line_closure_body"
  )
);

console.log(
  `wrote ${goldenPath}: ${golden.load.length} load, ${golden.validate.length} validate, ` +
    `${golden.query.cases.length} query, ${golden.mutation.length} mutation, ${golden.emitter.length} emitter cases`
);
console.log(
  `wrote ${repositoryPath}: ${repository.files.length} files, ${repository.mutations.length} mutations ` +
    `(${repository.mutations.filter((item) => item.result?.status !== "blocked").length} written)`
);
