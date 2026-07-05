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
import {
  AssuranceMethod,
  buildWebAuthnApprovalToken,
  createCliResult,
  errorEnvelope,
  isAssuranceMethod,
  signApprovalToken
} from "../runtime.js";

const DECISIONS = ["approved", "approved_with_known_gaps", "rejected"] as const;
type Decision = (typeof DECISIONS)[number];
const ED25519_ASSURANCE_METHODS = [
  AssuranceMethod.AUTOMATION,
  AssuranceMethod.SAME_CHANNEL,
  AssuranceMethod.OS_PRESENCE
];

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

function loadWebAuthnAssertion(filePath: string): {
  ok: true;
  assertion: Parameters<typeof buildWebAuthnApprovalToken>[0]["assertion"];
} | { ok: false; code: string; message: string } {
  let value: unknown;
  try {
    value = JSON.parse(readFileSync(resolve(process.cwd(), filePath), "utf8"));
  } catch (error) {
    return {
      ok: false,
      code: "approve_run.webauthn_assertion_unreadable",
      message: `could not read/parse --webauthn-assertion: ${error instanceof Error ? error.message : String(error)}`
    };
  }
  if (
    !value ||
    typeof value !== "object" ||
    typeof (value as { credential_id?: unknown }).credential_id !== "string" ||
    typeof (value as { authenticator_data?: unknown }).authenticator_data !== "string" ||
    typeof (value as { client_data_json?: unknown }).client_data_json !== "string" ||
    typeof (value as { signature?: unknown }).signature !== "string"
  ) {
    return {
      ok: false,
      code: "approve_run.webauthn_assertion_malformed",
      message:
        "--webauthn-assertion must be JSON with credential_id, authenticator_data, client_data_json, and signature base64url fields."
    };
  }
  return {
    ok: true,
    assertion: value as Parameters<typeof buildWebAuthnApprovalToken>[0]["assertion"]
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
    { key: "keyId", name: "--key-id", kind: "string", valueName: "<id>", summary: "Keyring key_id the plugin verifies the ed25519 token against." },
    { key: "webauthnAssertion", name: "--webauthn-assertion", kind: "string", valueName: "<file>", summary: "JSON WebAuthn assertion from the operator's platform authenticator; ceremony is out of scope, verification happens against pinned approval_trust." },
    { key: "decision", name: "--decision", kind: "string", valueName: "<decision>", summary: "approved | approved_with_known_gaps | rejected (default approved)." },
    { key: "assuranceMethod", name: "--assurance-method", kind: "string", valueName: "<method>", summary: "ed25519: automation | same_channel | os_presence (default os_presence). WebAuthn assertions record webauthn." },
    { key: "out", name: "--out", kind: "string", valueName: "<file>", summary: "Write the token to <file> instead of printing it inline." },
    { key: "json", name: "--json", kind: "boolean", summary: "Emit the machine-readable JSON result envelope." }
  ],
  handler: ({ flags }) => {
    const requestPath = flags.request as string | undefined;
    const keyId = flags.keyId as string | undefined;
    const webauthnAssertionPath = flags.webauthnAssertion as string | undefined;
    if (!requestPath || (!webauthnAssertionPath && !keyId)) {
      return {
        envelope: errorEnvelope(
          "showcase.approve_run",
          "cli_invalid_arguments",
          "Missing --request, or missing --key-id for ed25519 signing."
        ),
        exitCode: 2
      };
    }
    if (webauthnAssertionPath && (flags.keyFile || flags.keyEnv)) {
      return {
        envelope: errorEnvelope(
          "showcase.approve_run",
          "cli_invalid_arguments",
          "--webauthn-assertion packages an authenticator assertion; do not also pass --key-file or --key-env."
        ),
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

    const assuranceMethodFlag = flags.assuranceMethod as string | undefined;
    const assuranceMethodRaw = assuranceMethodFlag ?? AssuranceMethod.OS_PRESENCE;
    if (webauthnAssertionPath && assuranceMethodFlag && assuranceMethodFlag !== AssuranceMethod.WEBAUTHN) {
      return {
        envelope: errorEnvelope(
          "showcase.approve_run",
          "cli_invalid_arguments",
          "--webauthn-assertion always records assurance_method webauthn; omit --assurance-method or pass webauthn."
        ),
        exitCode: 2
      };
    }
    if (!webauthnAssertionPath && (!isAssuranceMethod(assuranceMethodRaw) || assuranceMethodRaw === AssuranceMethod.WEBAUTHN)) {
      return {
        envelope: errorEnvelope(
          "showcase.approve_run",
          "cli_invalid_arguments",
          `Unsupported ed25519 --assurance-method: ${assuranceMethodRaw} (allowed: ${ED25519_ASSURANCE_METHODS.join(", ")}).`
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

    let token;
    try {
      if (webauthnAssertionPath) {
        const assertion = loadWebAuthnAssertion(webauthnAssertionPath);
        if (!assertion.ok) {
          return { envelope: errorEnvelope("showcase.approve_run", assertion.code, assertion.message), exitCode: 2 };
        }
        token = buildWebAuthnApprovalToken({
          request: request as Parameters<typeof buildWebAuthnApprovalToken>[0]["request"],
          decision,
          assertion: assertion.assertion
        });
      } else {
        // Load the out-of-scope private key. No key => cannot mint (custody guarantee).
        const key = loadPrivateKey({ keyFile: flags.keyFile as string | undefined, keyEnv: flags.keyEnv as string | undefined });
        if (!key.ok) {
          return { envelope: errorEnvelope("showcase.approve_run", key.code, key.message), exitCode: 2 };
        }
        token = signApprovalToken({
          request: request as Parameters<typeof signApprovalToken>[0]["request"],
          decision,
          privateKey: key.pem,
          keyId: keyId as string,
          assuranceMethod: assuranceMethodRaw as Parameters<typeof signApprovalToken>[0]["assuranceMethod"]
        });
      }
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
            credential_id: token.signature.alg === "webauthn" ? token.signature.credential_id : undefined,
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
          credential_id: token.signature.alg === "webauthn" ? token.signature.credential_id : undefined,
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
