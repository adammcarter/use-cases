// MCP prompts: guided agent workflows as text templates (MCP 2025-11-25).
//
// Prompts are PURE TEXT. They never execute commands, run verifiers, or mint
// proofs — they explain the real `uc` CLI workflow so an agent can drive it
// through the host. Every command + flag named here is verified against
// packages/cli (matrix / init / bind / verify / scan / recover / keygen / prove /
// validate-ledger / evidence). The headline is the KEYLESS DAILY LOOP:
// bind -> verify -> scan shows local_status VERIFIED_LOCAL, with NO keys and NO
// CI. Signing (keygen + prove, or recover --signing-key-env) is the OPT-IN upgrade
// to signed FRESH for release/audit; `prove` is deliberately absent from the MCP
// tool surface and only ever runs in trusted CI.

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
    name: "uc/adopt-repo",
    description: "Bring a repository under Use-Case Matrix governance the keyless way: author the workspace, bind rows to code, verify, and confirm VERIFIED_LOCAL — then add signed CI proofs only when you need a release gate.",
    arguments: [arg("repo", "Absolute path to the repository/workspace root.")],
    build: (args) => {
      const repo = repoOf(args);
      return {
        description: "Step-by-step adoption of the use-case matrix — keyless daily loop first, signing opt-in.",
        messages: [
          userMessage(
            [
              "Goal: adopt Use Case Matrix in this repository so every shippable behaviour is a matrix row bound to code and confirmed still-covered by the KEYLESS daily loop — no keys, no CI. Signing is an opt-in upgrade you add later, only when you want a cryptographic release gate.",
              "",
              `Fastest start: \`uc init --repo ${repo}\` scaffolds the workspace (a use-case-matrix.yml config + a use-cases/ directory with one example row). To adopt by hand instead — e.g. onto an existing repo — author the same two things:`,
              `1. A workspace config \`use-case-matrix.yml\` at the repo root (declares data_root, use_cases_dir, component_id, and optional verifiers/release_gate).`,
              "2. A `use-cases/` directory of use-case YAML files, one row per behaviour.",
              "",
              "THE KEYLESS DAILY LOOP — no keys, no CI:",
              `- Validate the matrix:    uc matrix validate --repo ${repo} --json`,
              `- List/inspect rows:      uc matrix list --repo ${repo} --json`,
              `- Bind a row to code:     uc bind --repo ${repo} --row <row-id> --file <path> --mode explicit --start-line <n> --end-line <m> --json`,
              `                          (or --mode swift-func --line <n> for a Swift function body)`,
              `- Verify locally:         uc verify --repo ${repo} --all --json`,
              "                          (with no --out this writes the UNSIGNED results ledger to <data-root>/.use-cases/verification-results.jsonl, which scan auto-discovers)",
              `- Scan freshness:         uc scan --repo ${repo} --json`,
              "                          each verified row reports local_status: VERIFIED_LOCAL (status stays UNPROVEN — that is a healthy keyless row). `uc scan --gate` exits non-zero if a required row is below the bar (>= VERIFIED_LOCAL by default).",
              "",
              "OPT-IN UPGRADE — signed proofs (FRESH) for a release/audit gate, in trusted CI only:",
              `- Generate a keypair:     uc keygen --out <dir-outside-repo> --ci github   (private key is a CI secret — never in the repo)`,
              `- Mint proofs (CI):       uc prove --repo ${repo} --all --verification-results <results> --append --trusted-ci --signing-key-env <ENV> --json`,
              `- Gate the ledger:        uc validate-ledger --repo ${repo} --json`,
              `- Release gate:           uc scan --repo ${repo} --policy-mode release --gate --json`,
              "",
              "`prove` mints signed proofs and must run only in trusted CI; it is intentionally not exposed over MCP. Everyday agent work stays keyless. Use the read-only MCP resources (uc://matrix, uc://freshness, uc://ledger, uc://bindings) to inspect state at any point."
            ].join("\n")
          )
        ]
      };
    }
  },
  {
    name: "uc/bind-row",
    description: "Bind one matrix row to the code that implements it, verify it, and confirm the keyless VERIFIED_LOCAL green — no keys, no CI.",
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
        description: `Bind row ${row} to its implementation and take it to VERIFIED_LOCAL.`,
        messages: [
          userMessage(
            [
              `Goal: bind matrix row \`${row}\` to the code that implements it and confirm it is green the keyless way — bind -> verify -> VERIFIED_LOCAL, with no keys and no CI.`,
              "",
              "1. Confirm the row exists in the matrix:",
              `   uc matrix list --repo ${repo} --json   (look for ${row})`,
              "",
              "2. Place a binding marker in the source and register it. For an explicit line span (--mode explicit REQUIRES both --start-line and --end-line):",
              `   uc bind --repo ${repo} --row ${row} --file ${file} --mode explicit --start-line <n> --end-line <m> --json`,
              "   For a Swift function body (span inferred from the function line):",
              `   uc bind --repo ${repo} --row ${row} --file ${file} --mode swift-func --line <n> --json`,
              "   Add --suffix <name> to register more than one binding slug for the same row; add --register-existing to register a marker already present in the source.",
              "",
              "3. Run the row's verifier (with no --out this writes the UNSIGNED results ledger scan auto-discovers):",
              `   uc verify --repo ${repo} --row ${row} --json`,
              "",
              "4. Confirm the keyless green:",
              `   uc scan --repo ${repo} --json`,
              `   The row should report local_status: VERIFIED_LOCAL (status stays UNPROVEN — a healthy keyless row: a binding + a passing local verify, no signed proof yet).`,
              "",
              "Binding only edits source + the append-only registry, and verify only writes an UNSIGNED local ledger. Neither mints a proof — signing to FRESH is the opt-in upgrade that runs in trusted CI (`uc prove`), which is not available over MCP."
            ].join("\n")
          )
        ]
      };
    }
  },
  {
    name: "uc/recover-suspect-row",
    description: "Drive a drifted / unproven row back to green in one command — keyless VERIFIED_LOCAL by default, signed FRESH as an opt-in upgrade.",
    arguments: [
      arg("row", "The drifted row id to recover (e.g. auth.login).", true),
      arg("repo", "Absolute path to the repository/workspace root.")
    ],
    build: (args) => {
      const repo = repoOf(args);
      const row = rowOf(args);
      return {
        description: `Recover row ${row} back to green (VERIFIED_LOCAL keyless-first; FRESH opt-in).`,
        messages: [
          userMessage(
            [
              `Goal: get row \`${row}\` back to green. Keyless-first: the everyday target is local_status: VERIFIED_LOCAL (no keys, no CI). Re-proving to signed FRESH is the opt-in upgrade for a release/audit gate.`,
              "",
              "Why a row drifts off green:",
              "- STALE_LOCAL (keyless): a local verify result exists but the bound code or the test has changed since — the keyless analogue of SUSPECT.",
              "- UNVERIFIED_LOCAL: the row is bound but has never been verified locally.",
              "- SUSPECT / UNPROVEN (signed tier): a signed proof is stale (code/binding/verifier changed) or absent.",
              "",
              "1. Inspect the current state and the exact reason:",
              `   uc scan --repo ${repo} --json   (read rows[].status, rows[].local_status and rows[].reasons for ${row})`,
              "",
              "2. If the binding moved (code edited/relocated), re-bind so the marker tracks the new span:",
              `   uc bind --repo ${repo} --row ${row} --file <path> --mode explicit --start-line <n> --end-line <m> --json`,
              "",
              "3. Recover in one command — re-verify and report the new state:",
              `   uc recover --repo ${repo} --row ${row} --json`,
              "   This re-runs the row's verifier (the same run as `uc verify`), writes the unsigned results ledger, re-scans, and reports the resulting local_status/status. The row returns to VERIFIED_LOCAL. `uc recover` NEVER fakes green: if the verifier genuinely fails it exits non-zero and names the failing row — fix the code or the test, then re-run.",
              `   To inspect a raw verifier run on its own, use \`uc verify --repo ${repo} --row ${row} --json\`.`,
              "",
              "4. OPT-IN — also re-prove to signed FRESH (release/audit only, trusted CI):",
              `   uc recover --repo ${repo} --row ${row} --signing-key-env UCM_CI_SIGNING_KEY --public-key <path> --json`,
              "   Supplying --signing-key-env additionally mints a signed proof (trusted-CI). Signing runs only in trusted CI and is intentionally not exposed over MCP; do not attempt to sign from an ordinary agent session.",
              "",
              "5. Confirm the row is green again:",
              `   uc scan --repo ${repo} --json   (expect local_status: VERIFIED_LOCAL, or status: FRESH if you re-proved)`,
              `   uc validate-ledger --repo ${repo} --json   (signed tier only)`
            ].join("\n")
          )
        ]
      };
    }
  },
  {
    name: "uc/release-review",
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
              "1. Run the release-mode scan with the gate (release policy blocks any required row that is not FRESH, and any INVALID row; --gate turns that into a non-zero exit for CI):",
              `   uc scan --repo ${repo} --policy-mode release --gate --json`,
              "   Read guard_ok plus rows[]: every row with required_for_release=true must have status FRESH and policy_block=false. (Outside release, the gate bar is >= VERIFIED_LOCAL — the keyless green.)",
              "",
              "2. Cross-check matrix + evidence health:",
              `   uc matrix status --repo ${repo} --json`,
              "",
              "3. Validate ledger/registry integrity (append-only discipline, signatures, hash chain):",
              `   uc validate-ledger --repo ${repo} --json`,
              "",
              "If any required row is SUSPECT/UNPROVEN/UNBOUND/INVALID, recover it (see the uc/recover-suspect-row prompt) before releasing.",
              "These are read-only checks — you can also inspect uc://freshness, uc://ledger, and uc://matrix/status over MCP without running anything."
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
