// `uc approve-run` — the OUT-OF-BAND human signer for F3 trusted approval.
//
// A real human runs THIS in THEIR OWN shell to turn a plugin-minted
// ApprovalRequest into a signed approval token. The ed25519 signing key MUST
// live OUTSIDE the in-session agent's granted filesystem/env scope: an
// OS-keychain-backed keyfile (0600, user-owned) or an env var the agent is not
// given. Because the key is out of the agent's reach, an agent cannot produce a
// token this command would emit — key custody is the entire guarantee.
//
// The command is deliberately WORKSPACE-FREE: it neither reads nor writes the
// run ledger. It only reads a request file + a private key and prints a token.
// The plugin (append path) is what verifies the token and appends the approval.
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import type { CliCommand } from "../command/types.js";
import { AssuranceMethod, createCliResult, errorEnvelope, isAssuranceMethod, signApprovalToken } from "../runtime.js";

const DECISIONS = ["approved", "approved_with_known_gaps", "rejected"] as const;
type Decision = (typeof DECISIONS)[number];
const ASSURANCE_METHODS = Object.values(AssuranceMethod);

function loadPrivateKey(flags: {
  keyFile?: string;
  keyEnv?: string;
}): { ok: true; pem: string } | { ok: false; code: string; message: string } {
  if (flags.keyFile) {
    try {
      return { ok: true, pem: readFileSync(resolve(process.cwd(), flags.keyFile), "utf8") };
    } catch (error) {
      return {
        ok: false,
        code: "approve_run.key_unreadable",
        message: `could not read --key-file: ${error instanceof Error ? error.message : String(error)}`
      };
    }
  }
  if (flags.keyEnv) {
    const pem = process.env[flags.keyEnv];
    if (!pem || pem.trim().length === 0) {
      return {
        ok: false,
        code: "approve_run.key_env_empty",
        message: `env var ${flags.keyEnv} is empty or unset`
      };
    }
    return { ok: true, pem };
  }
  return {
    ok: false,
    code: "approve_run.no_key",
    message:
      "no signing key: pass --key-file <path> (0600, outside the agent's scope) or --key-env <VAR>. " +
      "The key must be one the in-session agent cannot read — that is what makes the approval unforgeable."
  };
}

export const approveRunCommand: CliCommand = {
  path: ["approve-run"],
  command: "showcase.approve_run",
  summary: "Sign a plugin-minted approval request out-of-band (human, own shell, out-of-scope key).",
  flags: [
    { key: "request", name: "--request", kind: "string", required: true, valueName: "<file>", summary: "Path to the plugin-minted ApprovalRequest JSON." },
    { key: "keyFile", name: "--key-file", kind: "string", valueName: "<path>", summary: "ed25519 private key PEM, OUTSIDE the agent's scope (0600 user-owned)." },
    { key: "keyEnv", name: "--key-env", kind: "string", valueName: "<VAR>", summary: "Env var holding the ed25519 private key PEM (alternative to --key-file)." },
    { key: "keyId", name: "--key-id", kind: "string", required: true, valueName: "<id>", summary: "Keyring key_id the plugin verifies the token against." },
    { key: "decision", name: "--decision", kind: "string", valueName: "<decision>", summary: "approved | approved_with_known_gaps | rejected (default approved)." },
    { key: "assuranceMethod", name: "--assurance-method", kind: "string", valueName: "<method>", summary: "automation | same_channel | os_presence (default os_presence)." },
    { key: "out", name: "--out", kind: "string", valueName: "<file>", summary: "Write the token to <file> instead of printing it inline." },
    { key: "json", name: "--json", kind: "boolean", summary: "Emit the machine-readable JSON result envelope." }
  ],
  handler: ({ flags }) => {
    const requestPath = flags.request as string | undefined;
    const keyId = flags.keyId as string | undefined;
    if (!requestPath || !keyId) {
      return {
        envelope: errorEnvelope("showcase.approve_run", "cli_invalid_arguments", "Missing --request or --key-id."),
        exitCode: 2
      };
    }

    const decisionRaw = (flags.decision as string | undefined) ?? "approved";
    if (!DECISIONS.includes(decisionRaw as Decision)) {
      return {
        envelope: errorEnvelope(
          "showcase.approve_run",
          "cli_invalid_arguments",
          `Unsupported --decision: ${decisionRaw} (allowed: ${DECISIONS.join(", ")}).`
        ),
        exitCode: 2
      };
    }
    const decision = decisionRaw as Decision;

    const assuranceMethodRaw = (flags.assuranceMethod as string | undefined) ?? AssuranceMethod.OS_PRESENCE;
    if (!isAssuranceMethod(assuranceMethodRaw)) {
      return {
        envelope: errorEnvelope(
          "showcase.approve_run",
          "cli_invalid_arguments",
          `Unsupported --assurance-method: ${assuranceMethodRaw} (allowed: ${ASSURANCE_METHODS.join(", ")}).`
        ),
        exitCode: 2
      };
    }

    // Read + parse the request.
    let request: unknown;
    try {
      request = JSON.parse(readFileSync(resolve(process.cwd(), requestPath), "utf8"));
    } catch (error) {
      return {
        envelope: errorEnvelope(
          "showcase.approve_run",
          "approve_run.request_unreadable",
          `could not read/parse --request: ${error instanceof Error ? error.message : String(error)}`
        ),
        exitCode: 2
      };
    }
    if (
      !request ||
      typeof request !== "object" ||
      (request as { approval_request_schema?: unknown }).approval_request_schema !== "ucase-approval-request-v1"
    ) {
      return {
        envelope: errorEnvelope(
          "showcase.approve_run",
          "approve_run.request_malformed",
          "--request is not a ucase-approval-request-v1 object."
        ),
        exitCode: 2
      };
    }

    // Load the out-of-scope private key. No key => cannot mint (custody guarantee).
    const key = loadPrivateKey({ keyFile: flags.keyFile as string | undefined, keyEnv: flags.keyEnv as string | undefined });
    if (!key.ok) {
      return { envelope: errorEnvelope("showcase.approve_run", key.code, key.message), exitCode: 2 };
    }

    let token;
    try {
      token = signApprovalToken({
        request: request as Parameters<typeof signApprovalToken>[0]["request"],
        decision,
        privateKey: key.pem,
        keyId,
        assuranceMethod: assuranceMethodRaw
      });
    } catch (error) {
      return {
        envelope: errorEnvelope(
          "showcase.approve_run",
          "approve_run.sign_failed",
          `could not sign the approval token: ${error instanceof Error ? error.message : String(error)}`
        ),
        exitCode: 2
      };
    }

    const outRaw = flags.out as string | undefined;
    if (outRaw) {
      const outPath = resolve(process.cwd(), outRaw);
      writeFileSync(outPath, `${JSON.stringify(token, null, 2)}\n`, "utf8");
      return {
        envelope: createCliResult(
          "showcase.approve_run",
          {
            approval_token_path: outPath,
            jti: token.jti,
            decision,
            key_id: keyId,
            assurance_method: token.assurance_method,
            assurance_tier: token.assurance_tier
          },
          { ok: true, complete: true, workspaceRoot: process.cwd() }
        ),
        exitCode: 0
      };
    }

    return {
      envelope: createCliResult(
        "showcase.approve_run",
        {
          approval_token: token,
          jti: token.jti,
          decision,
          key_id: keyId,
          assurance_method: token.assurance_method,
          assurance_tier: token.assurance_tier
        },
        { ok: true, complete: true, workspaceRoot: process.cwd() }
      ),
      exitCode: 0
    };
  }
};

export const approveRunCommands: CliCommand[] = [approveRunCommand];
