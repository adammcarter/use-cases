# Support

How to get help with Use Case Matrix, and what we support at v1.

## Supported matrix

| Area | v1 support |
|---|---|
| **Node** | Active LTS lines. Use Case Matrix is built and tested against current LTS. |
| **CI authority** | **GitHub Actions** is the reference, first-class path. The verify/prove proof model is **CI-neutral**: other providers (GitLab CI, CircleCI, generic) are best-effort and supported via the documented authority contract — see [`docs/security/ci-hardening.md`](docs/security/ci-hardening.md). |
| **Verifiers** | Command verifiers for **any** language/toolchain (executable + argv, no shell). `pnpm`/`vitest` is one preset, not an assumption. |
| **MCP transport** | **Local stdio** only. Remote/HTTP MCP is **not** a v1 contract. |
| **Packages** | `@adammcarter/use-cases-core`, `@adammcarter/use-cases-cli` (`ucm`), `@adammcarter/use-cases-mcp` (`ucm-mcp`), released together at the same version. |

The authoritative declaration of what is stable vs experimental is
[`docs/reference/stability.md`](docs/reference/stability.md).

## Getting help

- **Questions, usage help, and bug reports** → open a
  [GitHub issue](https://github.com/adammcarter/use-case-matrix/issues/new/choose).
  For bugs, use the bug form; it asks for `ucm --version --json`, the failing
  command with its `--json` output, and `ucm matrix status --json` so we can
  reproduce.
- **Feature requests** → open a feature issue using the feature form.
- **Documentation** → start with the [README](README.md), then the reference
  docs under [`docs/`](docs/).

## Reporting a security vulnerability

**Do not** open a public issue for a vulnerability. Report it privately through
GitHub's security advisories:

> https://github.com/adammcarter/use-case-matrix/security/advisories/new

See [SECURITY.md](SECURITY.md) for the threat model, guarantees, and what is
explicitly out of scope.

## Before you file

- Confirm you're on a supported Node version and the latest released `1.x`.
- Include the JSON output (`--json`) for any failing command — the human-readable
  text is not part of the stable contract, the JSON is.
- For freshness / release-gate questions, include `ucm matrix status --json`,
  which combines matrix integrity and evidence replay status.
