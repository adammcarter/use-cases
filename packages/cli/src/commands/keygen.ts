// `uc keygen` — mint an ed25519 keypair for the OPT-IN signed proof tier.
//
// This removes the biggest adoption barrier for signing: manual key handling.
// It prints the keypair (default) or writes it to --out <dir>, in the exact PEM
// formats prove/--public-key already consume (docs/security/key-management.md).
// It NEVER writes into the repo tree — --out inside --repo is refused — and it
// prints a loud "the private key belongs only in CI secrets" warning. `--ci
// github` additionally emits a ready-to-paste GitHub release-workflow snippet
// that loads the private key from a repo secret and signs via OIDC id-token (no
// long-lived token embedded).
//
// keygen is a SETUP command: it runs before a workspace exists, so it does NOT
// go through resolveContextOrError (which requires a populated --repo). It only
// uses --repo, when given, to guard --out against landing inside the tree.
import { mkdirSync, writeFileSync } from "node:fs";
import { isAbsolute, join, relative, resolve } from "node:path";
import type { CliCommand, ParsedFlags } from "../command/types.js";
import { createCliResult, errorEnvelope, generateSigningKeypair } from "../runtime.js";

const PRIVATE_KEY_FILENAME = "ci-signing-key.pem";
const PUBLIC_KEY_FILENAME = "ci-signing-key.pub.pem";

// The single, loud warning every keygen result carries: the private key is a CI
// secret and must never be committed.
const PRIVATE_KEY_WARNING =
  "The private key is a CI secret: store it ONLY in your CI secret store " +
  "(never commit it, never write it into the repo). Commit / distribute only the public key.";

// Is `candidate` the repo dir itself or nested inside it? Pure path math — no
// filesystem access, so it works before a workspace exists.
function isInside(repoRoot: string, candidate: string): boolean {
  const rel = relative(repoRoot, candidate);
  return rel === "" || (!rel.startsWith(`..${"/"}`) && rel !== ".." && !isAbsolute(rel));
}

// Build the `--ci github` snippet: a release-workflow job that verifies proofs
// with a committed public key and signs with a private key pulled from a GitHub
// *secret*, authenticating via OIDC `id-token`. No long-lived token is embedded.
function githubCiSnippet(): string {
  return [
    "# .github/workflows/release.yml — sign use-cases proofs in CI",
    "#",
    "# 1. Add the PRIVATE key PEM as a repository secret named UCM_CI_SIGNING_KEY",
    "#    (Settings -> Secrets and variables -> Actions -> New repository secret).",
    "# 2. Commit the PUBLIC key (ci-signing-key.pub.pem) so scan/validate-ledger can verify.",
    "#",
    "permissions:",
    "  contents: read",
    "  id-token: write   # OIDC — no long-lived token needed",
    "",
    "jobs:",
    "  prove:",
    "    runs-on: ubuntu-latest",
    "    steps:",
    "      - uses: actions/checkout@v4",
    "      - name: Mint signed proofs",
    "        env:",
    "          UCM_CI_SIGNING_KEY: ${{ secrets.UCM_CI_SIGNING_KEY }}",
    "        run: |",
    "          uc prove --all --trusted-ci \\",
    "            --signing-key-env UCM_CI_SIGNING_KEY \\",
    "            --key-id ci-key-1",
    ""
  ].join("\n");
}

// Resolve the (optional) repo root the same way the workspace commands do, but
// WITHOUT requiring it to exist — keygen is a pre-workspace setup command.
function repoRootFrom(flags: ParsedFlags): string {
  const repoRaw = flags.repo as string | undefined;
  return resolve(process.cwd(), repoRaw ?? ".");
}

export const keygenCommand: CliCommand = {
  path: ["keygen"],
  command: "markers.keygen",
  summary: "Generate an ed25519 keypair for the opt-in signed proof tier.",
  flags: [
    { key: "repo", name: "--repo", kind: "string", valueName: "<path>", summary: "Workspace root (used only to keep --out outside the tree)." },
    { key: "out", name: "--out", kind: "string", valueName: "<dir>", summary: "Write the keypair to <dir> instead of printing it (must be OUTSIDE --repo)." },
    { key: "ci", name: "--ci", kind: "string", valueName: "<provider>", summary: "Emit a CI setup snippet for <provider> (currently: github)." },
    { key: "json", name: "--json", kind: "boolean", summary: "Emit the machine-readable JSON result envelope." }
  ],
  handler: ({ flags }) => {
    const repoRoot = repoRootFrom(flags);

    // Validate --ci up front (only github is supported today).
    const ciRaw = flags.ci as string | undefined;
    if (ciRaw !== undefined && ciRaw !== "github") {
      return {
        envelope: errorEnvelope("markers.keygen", "cli_invalid_arguments", `Unsupported --ci provider: ${ciRaw} (supported: github).`),
        exitCode: 2
      };
    }

    const { privatePem, publicPem } = generateSigningKeypair();
    const ciSnippet = ciRaw === "github" ? githubCiSnippet() : undefined;

    const outRaw = flags.out as string | undefined;
    if (outRaw) {
      const outDir = resolve(process.cwd(), outRaw);
      // The private key must NEVER land in the repo tree — refuse an --out that
      // resolves inside --repo (or the default cwd repo root).
      if (isInside(repoRoot, outDir)) {
        return {
          envelope: errorEnvelope(
            "markers.keygen",
            "keygen.out_inside_repo",
            `--out (${outDir}) is inside --repo (${repoRoot}). The private key must never be written into the repo tree — choose a directory outside it.`
          ),
          exitCode: 4
        };
      }
      const privatePath = join(outDir, PRIVATE_KEY_FILENAME);
      const publicPath = join(outDir, PUBLIC_KEY_FILENAME);
      mkdirSync(outDir, { recursive: true });
      // Private key: owner-read/write only. Never echo it inline when written to
      // a file, so it can't leak into command logs — the path is enough.
      writeFileSync(privatePath, privatePem, { mode: 0o600 });
      writeFileSync(publicPath, publicPem);
      return {
        envelope: createCliResult(
          "markers.keygen",
          {
            algorithm: "ed25519",
            private_key_path: privatePath,
            public_key_path: publicPath,
            public_key: publicPem,
            warning: PRIVATE_KEY_WARNING,
            ...(ciSnippet ? { ci_snippet: ciSnippet } : {})
          },
          { ok: true, complete: true, workspaceRoot: repoRoot }
        ),
        exitCode: 0
      };
    }

    // Print path: return both PEMs inline plus the CI-only warning.
    return {
      envelope: createCliResult(
        "markers.keygen",
        {
          algorithm: "ed25519",
          private_key: privatePem,
          public_key: publicPem,
          warning: PRIVATE_KEY_WARNING,
          ...(ciSnippet ? { ci_snippet: ciSnippet } : {})
        },
        { ok: true, complete: true, workspaceRoot: repoRoot }
      ),
      exitCode: 0
    };
  }
};

export const keygenCommands: CliCommand[] = [keygenCommand];
