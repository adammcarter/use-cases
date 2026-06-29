#!/usr/bin/env bash
#
# use-cases precommit hook (spec 10.1 - "precommit is ergonomics, not authority").
#
# Runs the two existing CLI commands and applies the precommit orchestrator's
# BLOCK / WARN / OK logic via exit code:
#
#   validate-ledger --staged   -> BLOCK on any failure (non-append edit, bad /
#                                 unsigned / invalid proof, registry conflict,
#                                 schema failure).
#   scan --policy-mode feature -> BLOCK on an INVALID row (malformed marker,
#                                 duplicate slug, unclosed / mismatched end,
#                                 unsupported inferred marker, unregistered
#                                 current marker) or a ledger/registry failure.
#                                 WARN (does NOT block) on SUSPECT / UNPROVEN /
#                                 UNBOUND rows, printing the loud required-action
#                                 message.
#
# This script is NOT installed into .git/hooks automatically. To enable it:
#
#   ln -s ../../scripts/use-cases-precommit.sh .git/hooks/pre-commit
#   # or, to keep a copy:
#   cp scripts/use-cases-precommit.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
#
# It is idempotent and read-only: it never mutates source, registry, or ledger,
# so running it repeatedly has no side effects.
#
# Overridable via environment:
#   UCP_CLI_JS       path to the built CLI entry (default: packages/ucm-cli/dist/index.js)
#   UCP_BASE_REF     git ref the ledger must stay append-only against (default: HEAD)
#   UCP_PUBLIC_KEY   trusted-CI public key PEM (default: .use-cases/trusted-ci-public-key.pem)
#   UCP_PRODUCT_ROOT product root to scan (default: repo root)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI_JS="${UCP_CLI_JS:-$ROOT/packages/ucm-cli/dist/index.js}"
BASE_REF="${UCP_BASE_REF:-HEAD}"
PUBLIC_KEY="${UCP_PUBLIC_KEY:-$ROOT/.use-cases/trusted-ci-public-key.pem}"
PRODUCT_ROOT="${UCP_PRODUCT_ROOT:-$ROOT}"

if [ ! -f "$CLI_JS" ]; then
  echo "use-cases precommit: CLI not built at $CLI_JS (run 'pnpm build')." >&2
  exit 2
fi

cli() { node "$CLI_JS" "$@"; }

# Pass --public-key only when the configured key file exists, so a repo without a
# trusted key still runs (a ledger that carries proofs will then fail loudly).
key_args=()
if [ -f "$PUBLIC_KEY" ]; then
  key_args=(--public-key "$PUBLIC_KEY")
fi

block=0

# --- 1. validate-ledger (staged == append-only vs the committed HEAD) ---
vl_exit=0
cli validate-ledger \
  --repo "$ROOT" \
  --base-ref "$BASE_REF" \
  ${key_args[@]+"${key_args[@]}"} \
  --json || vl_exit=$?
if [ "$vl_exit" -ne 0 ]; then
  echo "USE-CASE LEDGER BLOCKED (validate-ledger exit $vl_exit)" >&2
  block=1
fi

# --- 2. scan (feature policy) ---
scan_exit=0
scan_out="$(cli scan \
  --repo "$ROOT" \
  --product-root "$PRODUCT_ROOT" \
  --policy-mode feature \
  ${key_args[@]+"${key_args[@]}"} \
  --ci \
  --json)" || scan_exit=$?

# In feature mode scan returns 0 with no integrity errors, 3 on an INVALID row,
# 4 on a ledger/registry failure, 2 on a usage error. Any non-zero exit blocks.
if [ "$scan_exit" -ne 0 ]; then
  echo "USE-CASE SCAN BLOCKED (scan exit $scan_exit)" >&2
  block=1
fi

# Loud WARN for SUSPECT / UNPROVEN / UNBOUND rows (does not block). Reuses scan's
# JSON output (.data.status.rows) rather than recomputing anything.
if [ -n "${scan_out:-}" ]; then
  printf '%s' "$scan_out" | node -e '
    let buf = "";
    process.stdin.on("data", (chunk) => { buf += chunk; });
    process.stdin.on("end", () => {
      let parsed;
      try { parsed = JSON.parse(buf); } catch { return; }
      const status = (parsed && parsed.data && parsed.data.status) || parsed.status;
      const rows = (status && status.rows) || [];
      for (const row of rows) {
        if (!["SUSPECT", "UNPROVEN", "UNBOUND"].includes(row.status)) continue;
        const reason = (row.reasons && row.reasons[0] && row.reasons[0].code) || row.status;
        const action = row.required_action || ("use-cases prove --row " + row.row_id);
        process.stderr.write("USE-CASE ROW " + row.status + "\n");
        process.stderr.write("row: " + row.row_id + "\n");
        process.stderr.write("reason: " + reason + "\n");
        process.stderr.write("required action: " + action + "\n\n");
      }
    });
  ' || true
fi

if [ "$block" -ne 0 ]; then
  echo "use-cases precommit: BLOCKED. Fix the integrity errors above before committing." >&2
  exit 1
fi

echo "use-cases precommit: OK (warnings above, if any, do not block)." >&2
exit 0
