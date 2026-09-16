// The commands a skill or agent body may tell its reader to run. SINGLE SOURCE
// OF TRUTH for that check: validateSkillAssets and the shipped-asset tests all
// read these two sets.
//
// They must mirror the CLI's declarative registry exactly. A parity test
// (tests/cli/known-commands-parity.test.ts) asserts that against `allCommands`,
// because the previous hand-maintained copy silently fell behind: `uc impact` and
// `uc showcase request-approval` shipped as real commands while the validator
// still reported them as unknown, which would have flagged a correct body.
//
// `packages/core` cannot import `packages/cli` (the dependency runs the other
// way), so the parity is enforced by test rather than by derivation.

/** Two-token commands, keyed as "<command> <subcommand>". */
export const KNOWN_CLI_COMMANDS = new Set([
  "capsule list",
  "capsule plan",
  "capsule run",
  "capsule validate",
  "doctor roots",
  "doctor skills",
  "evidence record",
  "evidence status",
  "evidence void",
  "matrix list",
  "matrix remove",
  "matrix status",
  "matrix upsert",
  "matrix validate",
  "migrate test-matrix",
  "plan cards",
  "plan showcase",
  "plan walkthrough",
  "schema list",
  "schema validate-fixtures",
  "showcase approve",
  "showcase correct",
  "showcase decide",
  "showcase finish",
  "showcase pause",
  "showcase record-observation",
  "showcase record-verdict",
  "showcase reject",
  "showcase request-approval",
  "showcase resume",
  "showcase start",
  "showcase status",
  "workflow mode",
  "workflow set-mode"
]);

// Commands handled outside the registry, in builtins.ts, because their output is
// bespoke rather than a result envelope. They are still real commands a body may
// reference.
export const BUILTIN_FLAT_CLI_COMMANDS = ["init", "version"] as const;

/**
 * Single-segment commands. A reference like `uc bind --repo ...` carries a flag
 * as its second token, so it is validated by its bare command name rather than
 * as a "<command> <subcommand>" pair.
 */
export const KNOWN_FLAT_CLI_COMMANDS = new Set([
  "approve-run",
  "bind",
  "impact",
  "init",
  "keygen",
  "prove",
  "rebind",
  "recover",
  "scan",
  "unbind",
  "validate-ledger",
  "verify",
  "version"
]);
