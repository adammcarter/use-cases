import { describe, expect, test } from "vitest";
import { allCommands } from "../../packages/cli/src/command/registry.js";
import { mcpTools } from "../../packages/mcp/src/tools.js";

// Operation-contract parity guard (the architecture audit's #1 structural risk).
// The CLI and MCP wrap the same core operations through SEPARATE registries, so
// they can silently drift — an operation exposed one way but not the other, or
// under a different id. This test pins the intended relationship: MCP is a
// curated SUBSET of the CLI's operations (same operation ids), with a short,
// explicit allowlist of deliberate differences. A new MCP tool whose id doesn't
// match a CLI command — or a rename on one side — fails here loudly.

const cliOps = new Set(allCommands.map((command) => command.command));
const mcpOps = mcpTools.map((tool) => ({ name: tool.name, command: tool.command, mutability: tool.mutability }));
const mcpOpIds = new Set(mcpOps.map((tool) => tool.command));

// Operations exposed over MCP that intentionally have NO identically-named CLI
// command. Keep this list tiny and documented — it is the record of allowed
// transport drift.
const MCP_ONLY: Record<string, string> = {
  // MCP can REQUEST a user approval (elicitation/out-of-band); the CLI ACTS on it
  // via showcase approve/reject. An agent cannot mint trusted sign-off either way
  // (ADR 0006).
  "showcase.request-approval": "MCP requests approval; the CLI approves/rejects (ADR 0006)."
};

// Operations that MUST stay CLI/CI-only — never exposed as MCP tools. The signing
// and binding surface is the trust root; exposing it to an autonomous MCP client
// would let an agent mint its own proofs.
const CLI_ONLY_INVARIANT = [
  "markers.prove",
  "markers.bind",
  "markers.scan",
  "markers.verify",
  "markers.validate-ledger"
];

describe("CLI/MCP operation-contract parity", () => {
  test("every MCP tool maps to a CLI command with the same operation id (or is an allowlisted difference)", () => {
    for (const tool of mcpOps) {
      if (MCP_ONLY[tool.command]) {
        continue;
      }
      expect(cliOps, `MCP tool '${tool.name}' (op '${tool.command}') has no matching CLI command — drift or rename?`).toContain(
        tool.command
      );
    }
  });

  test("the MCP_ONLY allowlist stays accurate (no stale entries)", () => {
    for (const op of Object.keys(MCP_ONLY)) {
      expect(mcpOpIds, `MCP_ONLY lists '${op}' but no MCP tool exposes it`).toContain(op);
      expect(cliOps, `MCP_ONLY lists '${op}' but the CLI now also has it — remove the allowlist entry`).not.toContain(op);
    }
  });

  test("the signing/binding trust surface is NEVER exposed over MCP", () => {
    for (const op of CLI_ONLY_INVARIANT) {
      expect(cliOps, `expected CLI command '${op}'`).toContain(op);
      expect(mcpOpIds, `SECURITY: '${op}' must not be an MCP tool`).not.toContain(op);
    }
  });
});
