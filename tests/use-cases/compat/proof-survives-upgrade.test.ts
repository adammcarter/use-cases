// MECHANICAL PROOF-SURVIVAL TEST: a workspace signed to FRESH by 0.5.5 must read
// FRESH under this build, with every hash bit-identical.
//
// `tests/fixtures/backcompat/proven-0.5.5/` is a REAL workspace as the published
// 0.5.5 binary left it: two bound rows, an unsigned verification-results ledger,
// and one row minted to a signed proof in (simulated) trusted CI, with the
// trusted public key beside it. Nothing here was authored by hand.
//
// The trust model is the part of this tool with the least room for a shrug. A
// release that quietly invalidated existing signed proofs would send every
// upgrading project back through CI to re-prove rows whose code never changed —
// and a release that quietly ACCEPTED a proof it should have rejected would be
// worse. This pins both directions against an artifact from the previous version.
import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../../..");
const fixture = join(repoRoot, "tests/fixtures/backcompat/proven-0.5.5");
const cliBin = join(repoRoot, "packages/cli/dist/index.js");

interface Row {
  row_id: string;
  status: string;
  local_status: string | null;
  row_hash: string;
  current_binding_set_hash: string | null;
  verification_policy_hash: string;
  approval_policy_hash: string;
}

let workspace: string;
let rows: Row[];
let exitCode: number | null;

// The machine-local run key must never be the developer's real one, so every
// spawn here points at a throwaway path inside the copied workspace.
function runKeyEnv() {
  return { ...process.env, UC_RUN_KEY_FILE: join(workspace, "machine", "run-key") };
}

function scan(dir: string, extra: string[] = []) {
  return spawnSync(
    "node",
    [cliBin, "scan", "--repo", dir, "--public-key", join(dir, "trusted-public-key.pem"), "--json", ...extra],
    { encoding: "utf8", env: runKeyEnv() }
  );
}

beforeAll(() => {
  if (!existsSync(cliBin)) {
    const build = spawnSync("corepack", ["pnpm", "build"], {
      cwd: repoRoot,
      encoding: "utf8",
      env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
    });
    if (build.status !== 0) {
      throw new Error(build.stderr || build.stdout);
    }
  }
  // Copy out of the repo: scan reads the workspace, and a fixture inside the
  // repo tree would otherwise be walked by the repo's own scan.
  workspace = mkdtempSync(join(tmpdir(), "proven-0.5.5-"));
  cpSync(fixture, workspace, { recursive: true });
  const result = scan(workspace);
  exitCode = result.status;
  const payload = JSON.parse(result.stdout) as {
    data: { status: { rows: Row[]; integrity_errors: unknown[] } };
  };
  rows = payload.data.status.rows;
}, 180_000);

afterAll(() => {
  if (workspace) {
    rmSync(workspace, { recursive: true, force: true });
  }
});

function row(id: string): Row {
  const found = rows.find((entry) => entry.row_id === id);
  if (!found) {
    throw new Error(`row ${id} missing from scan output`);
  }
  return found;
}

describe("a workspace proven by 0.5.5 still reads correctly", () => {
  test("scan succeeds with no integrity errors", () => {
    expect(exitCode).toBe(0);
  });

  test("the signed row is still FRESH", () => {
    // Not merely "not worse": FRESH is the exact state 0.5.5 left it in, and it
    // requires the ed25519 signature to verify against the committed public key.
    expect(row("checkout.apply_coupon").status).toBe("FRESH");
  });

  // THE ONE DELIBERATE DEGRADATION IN THE KEYLESS TIER, pinned here rather than
  // left for an adopter to discover.
  //
  // 0.5.5 wrote its verification-results ledger with no run attestation, because
  // there was none to write: any line whose hashes matched was accepted, which is
  // exactly why typing a line moved the acceptance claim. Under this build such a
  // record reads UNATTESTED_LOCAL — it is not silently promoted to verified, and
  // equally it is not silently discarded: the row says what is wrong and the next
  // test proves the cure is one command.
  //
  // The SIGNED tier is untouched: the FRESH row above is still FRESH.
  test("an unattested 0.5.5 result is neither promoted nor believed", () => {
    const unsigned = row("checkout.refund_order");
    expect(unsigned.status).toBe("UNPROVEN");
    expect(unsigned.local_status).toBe("UNATTESTED_LOCAL");
  });

  test("re-running verify restores VERIFIED_LOCAL — the upgrade cure is one command", () => {
    const verified = spawnSync(
      "node",
      [cliBin, "verify", "--repo", workspace, "--row", "checkout.refund_order", "--json"],
      { encoding: "utf8", env: runKeyEnv() }
    );
    expect(verified.status).toBe(0);

    const rescanned = JSON.parse(scan(workspace).stdout) as {
      data: { status: { rows: Row[] } };
    };
    const unsigned = rescanned.data.status.rows.find(
      (entry) => entry.row_id === "checkout.refund_order"
    );
    expect(unsigned?.local_status).toBe("VERIFIED_LOCAL");
  });

  test("every hash the proof binds to is bit-identical to what 0.5.5 recorded", () => {
    // Captured from the published 0.5.5 binary against this exact fixture. A
    // change to ANY hashed input — row content, binding set, either policy —
    // would break every existing signed proof in the wild, silently.
    expect({
      row_hash: row("checkout.apply_coupon").row_hash,
      binding_set_hash: row("checkout.apply_coupon").current_binding_set_hash,
      verification_policy_hash: row("checkout.apply_coupon").verification_policy_hash,
      approval_policy_hash: row("checkout.apply_coupon").approval_policy_hash
    }).toEqual({
      row_hash: "sha256:c2b25e8d096ff4a88ebe6e4f7165b32aabeec49ce588a08e28925c041d5df01e",
      binding_set_hash: "sha256:11d49e5c5db18d8fa81d7f933f0b28fa940d4b70582ed58491260cdc40da039e",
      verification_policy_hash: "sha256:326d64cf7b78e949deaa5aa703b55a3cde3bfd0f0164336ae8069e3c132a921f",
      approval_policy_hash: "sha256:7f517f97e00a688b0b402e4005866127e5c928bf44a94ca53477ac34e24b5ef1"
    });
  });

  test("the release gate still passes on it", () => {
    const gated = scan(workspace, ["--gate"]);
    expect(gated.status).toBe(0);
  });

  test("a proof whose signature does not verify is NOT read as FRESH", () => {
    // The counter-check: without the trusted key, the same signed proof must
    // read UNPROVEN. Otherwise the test above would pass on a build that had
    // stopped checking signatures at all.
    const unkeyed = spawnSync("node", [cliBin, "scan", "--repo", workspace, "--json"], {
      encoding: "utf8"
    });
    const payload = JSON.parse(unkeyed.stdout) as { data: { status: { rows: Row[] } } };
    const coupon = payload.data.status.rows.find((r) => r.row_id === "checkout.apply_coupon");
    expect(coupon?.status).toBe("UNPROVEN");
  });
});
