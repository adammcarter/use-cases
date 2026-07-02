// MCP prompts: guided agent workflows as text templates (MCP 2025-11-25).
//
// Prompts are PURE TEXT. They never execute commands, run verifiers, or mint
// proofs — they explain the real `ucm` CLI workflow so an agent can drive it
// through the host. Every command named here is a real CLI command verified
// against packages/cli (matrix / bind / scan / verify / prove /
// validate-ledger / evidence). There is no `ucm init`; a workspace is adopted by
// authoring `use-case-matrix.yml` + a `use-cases/` tree. `prove` is
// deliberately absent from the MCP tool surface and only ever runs in trusted CI.

export type McpPromptArgument = {
  name: string;
  description: string;
  required: boolean;
};

export type McpPromptDescriptor = {
  name: string;
  description: string;
  arguments: McpPromptArgument[];
};

export type McpPromptMessage = {
  role: "user" | "assistant";
  content: { type: "text"; text: string };
};

export type McpPromptResult = {
  description: string;
  messages: McpPromptMessage[];
};

type PromptDefinition = McpPromptDescriptor & {
  build: (args: Record<string, string>) => McpPromptResult;
};

function arg(name: string, description: string, required = false): McpPromptArgument {
  return { name, description, required };
}

function userMessage(text: string): McpPromptMessage {
  return { role: "user", content: { type: "text", text } };
}

// `repo` placeholder used in example commands; falls back to a readable token.
function repoOf(args: Record<string, string>): string {
  const value = args.repo;
  return value && value.length > 0 ? value : "<repo>";
}

function rowOf(args: Record<string, string>): string {
  const value = args.row;
  return value && value.length > 0 ? value : "<row-id>";
}

const promptDefinitions: PromptDefinition[] = [
  {
    name: "ucm/adopt-repo",
    description: "Bring a repository under Use-Case Matrix governance: author the workspace, validate the matrix, bind rows to code, then wire scan/verify/prove into CI.",
    arguments: [arg("repo", "Absolute path to the repository/workspace root.")],
    build: (args) => {
      const repo = repoOf(args);
      return {
        description: "Step-by-step adoption of the use-case matrix in a repository.",
        messages: [
          userMessage(
            [
              "Goal: adopt Use Cases Plugin in this repository so every shippable behaviour is a matrix row that can be bound to code and proven fresh in CI.",
              "",
              `Fastest start: \`ucm init --repo ${repo}\` scaffolds the workspace (a use-case-matrix.yml config + a use-cases/ directory with one example row). To adopt by hand instead — e.g. onto an existing repo — author the same two things:`,
              `1. A workspace config \`use-case-matrix.yml\` at the repo root (declares data_root, use_cases_dir, component_id, and optional verifiers/release_gate).`,
              "2. A `use-cases/` directory of use-case YAML files, one row per behaviour.",
              "",
              "Then drive the CLI in this order:",
              `- Validate the matrix:    ucm matrix validate --repo ${repo} --json`,
              `- List/inspect rows:      ucm matrix list --repo ${repo} --json`,
              `- Bind a row to code:     ucm bind --repo ${repo} --row <row-id> --file <path> --mode explicit --line <n> --json`,
              `                          (or --mode swift-func for Swift functions)`,
              `- Scan freshness:         ucm scan --repo ${repo} --policy-mode feature --json`,
              `- Verify a row locally:   ucm verify --repo ${repo} --row <row-id> --out results.jsonl --json`,
              "",
              "In CI (trusted runner only) mint and check proofs:",
              `- Mint proofs:            ucm prove --repo ${repo} --all --verification-results results.jsonl --append --trusted-ci --json`,
              `- Gate the ledger:        ucm validate-ledger --repo ${repo} --json`,
              `- Release gate:           ucm scan --repo ${repo} --policy-mode release --json`,
              "",
              "`prove` mints signed proofs and must run only in trusted CI; it is intentionally not exposed over MCP. Use the read-only MCP resources (ucm://matrix, ucm://freshness, ucm://ledger, ucm://bindings) to inspect state at any point."
            ].join("\n")
          )
        ]
      };
    }
  },
  {
    name: "ucm/bind-row",
    description: "Bind one matrix row to the code that implements it, then confirm the binding with a freshness scan.",
    arguments: [
      arg("row", "The row id to bind (e.g. auth.login).", true),
      arg("file", "Path to the source file that implements the row."),
      arg("repo", "Absolute path to the repository/workspace root.")
    ],
    build: (args) => {
      const repo = repoOf(args);
      const row = rowOf(args);
      const file = args.file && args.file.length > 0 ? args.file : "<path/to/source>";
      return {
        description: `Bind row ${row} to its implementation.`,
        messages: [
          userMessage(
            [
              `Goal: bind matrix row \`${row}\` to the code that implements it so its freshness can be tracked.`,
              "",
              "1. Confirm the row exists in the matrix:",
              `   ucm matrix list --repo ${repo} --json   (look for ${row})`,
              "",
              "2. Place a binding marker in the source and register it. For an explicit line/span:",
              `   ucm bind --repo ${repo} --row ${row} --file ${file} --mode explicit --line <n> --json`,
              "   For a Swift function body (span inferred from the function):",
              `   ucm bind --repo ${repo} --row ${row} --file ${file} --mode swift-func --json`,
              "   Add --suffix <name> to register more than one binding slug for the same row.",
              "",
              "3. Confirm the binding took and inspect freshness:",
              `   ucm scan --repo ${repo} --policy-mode feature --json`,
              `   The row should move from UNBOUND to UNPROVEN (a binding exists but no proof yet).`,
              "",
              "Binding only edits source + the append-only registry. It never mints a proof — proving happens later in trusted CI (`ucm prove`), which is not available over MCP."
            ].join("\n")
          )
        ]
      };
    }
  },
  {
    name: "ucm/recover-suspect-row",
    description: "Diagnose why a row is SUSPECT and walk it back to FRESH via re-binding, local verification, and a CI-minted proof.",
    arguments: [
      arg("row", "The SUSPECT row id to recover (e.g. auth.login).", true),
      arg("repo", "Absolute path to the repository/workspace root.")
    ],
    build: (args) => {
      const repo = repoOf(args);
      const row = rowOf(args);
      return {
        description: `Recover SUSPECT row ${row} back to FRESH.`,
        messages: [
          userMessage(
            [
              `Goal: get row \`${row}\` from SUSPECT back to FRESH.`,
              "",
              "Why a row goes SUSPECT (per the freshness rules):",
              "- The bound code changed since the proof was minted (the row hash / binding-set hash no longer matches the proof), or",
              "- A registered binding was removed, or",
              "- The verifier or its declared inputs changed, so the proof's recorded verification context hash no longer matches the current one.",
              "A SUSPECT row has a real proof, but that proof no longer describes the current code/verifier — it is stale, not absent.",
              "",
              "1. Inspect the current state and the exact reason:",
              `   ucm scan --repo ${repo} --policy-mode feature --json   (read rows[].status and rows[].reasons for ${row})`,
              "",
              "2. If the binding moved (code edited/relocated), re-bind so the marker tracks the new span:",
              `   ucm bind --repo ${repo} --row ${row} --file <path> --mode explicit --line <n> --json`,
              "",
              "3. Re-run verification locally to produce fresh results:",
              `   ucm verify --repo ${repo} --row ${row} --out results.jsonl --json`,
              "",
              "4. In trusted CI, mint a new proof from those results and append it to the ledger:",
              `   ucm prove --repo ${repo} --row ${row} --verification-results results.jsonl --append --trusted-ci --json`,
              "   NOTE: `prove` runs ONLY in trusted CI and is intentionally not exposed over MCP. Do not attempt to mint proofs from an agent session.",
              "",
              "5. Confirm the row is FRESH again:",
              `   ucm scan --repo ${repo} --policy-mode feature --json`,
              `   ucm validate-ledger --repo ${repo} --json`
            ].join("\n")
          )
        ]
      };
    }
  },
  {
    name: "ucm/release-review",
    description: "Before a release, confirm every required_for_release row is FRESH and the ledger is intact.",
    arguments: [arg("repo", "Absolute path to the repository/workspace root.")],
    build: (args) => {
      const repo = repoOf(args);
      return {
        description: "Release gate review for required_for_release rows.",
        messages: [
          userMessage(
            [
              "Goal: confirm the matrix is release-ready — every row marked required_for_release is FRESH and the proof ledger is intact.",
              "",
              "1. Run the release-mode scan (release policy blocks any required row that is not FRESH, and any INVALID row):",
              `   ucm scan --repo ${repo} --policy-mode release --json`,
              "   Read guard_ok plus rows[]: every row with required_for_release=true must have status FRESH and policy_block=false.",
              "",
              "2. Cross-check matrix + evidence health:",
              `   ucm matrix status --repo ${repo} --json`,
              "",
              "3. Validate ledger/registry integrity (append-only discipline, signatures, hash chain):",
              `   ucm validate-ledger --repo ${repo} --json`,
              "",
              "If any required row is SUSPECT/UNPROVEN/UNBOUND/INVALID, recover it (see the ucm/recover-suspect-row prompt) before releasing.",
              "These are read-only checks — you can also inspect ucm://freshness, ucm://ledger, and ucm://matrix/status over MCP without running anything."
            ].join("\n")
          )
        ]
      };
    }
  }
];

export const mcpPrompts: McpPromptDescriptor[] = promptDefinitions.map(
  ({ build: _build, ...descriptor }) => descriptor
);

export type GetPromptOutcome =
  | { ok: true; result: McpPromptResult }
  | { ok: false; code: number; message: string };

export function getMcpPrompt(name: string, args: Record<string, unknown>): GetPromptOutcome {
  const definition = promptDefinitions.find((candidate) => candidate.name === name);
  if (!definition) {
    return { ok: false, code: -32602, message: `Unknown prompt: ${name}` };
  }
  const stringArgs: Record<string, string> = {};
  for (const [key, value] of Object.entries(args)) {
    if (typeof value === "string") {
      stringArgs[key] = value;
    }
  }
  for (const required of definition.arguments.filter((entry) => entry.required)) {
    if (!stringArgs[required.name]) {
      return { ok: false, code: -32602, message: `Prompt '${name}' requires argument '${required.name}'.` };
    }
  }
  return { ok: true, result: definition.build(stringArgs) };
}
