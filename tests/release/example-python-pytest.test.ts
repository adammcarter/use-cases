// Non-JS adopter proof: the `examples/python-pytest` project goes from nothing to
// a signed FRESH proof using a PURE PYTHON toolchain (pytest) and the PUBLISHED
// CLI artifact — no pnpm, no vitest, no workspace linking anywhere in the consumer.
//
// This is the concrete payoff of the verifier-generality work and the evidence
// behind the headline "anyone can adopt the matrix, not just JS repos":
//
//   1. pack @use-cases-plugin/core + /cli into tarballs and `npm install` them into
//      a CLEAN COPY of the example (mirrors tests/smoke/package-entrypoints.test.ts:
//      a consumer with no repo workspace links, only the published bins);
//   2. generate a throwaway ed25519 keypair in the temp dir (never committed);
//   3. drive the installed `ucp` binary through the real trust flow —
//      bind -> scan(UNPROVEN) -> verify(runs REAL pytest, exit 0) ->
//      prove(--trusted-ci, scratch key, signs) -> scan — and assert the row
//      reaches FRESH;
//   4. tamper (break the production code so the real acceptance test fails) and
//      assert verify fails and the row does NOT reach FRESH — proving the verifier
//      genuinely RUNS pytest rather than rubber-stamping the proof.
//
// The `acceptance` verifier resolves (via the example's workspace config) to the
// `python.pytest` preset, so the command actually executed is
// `pytest tests/use_cases/example.checkout.apply_coupon_test.py`. pytest is a hard
// requirement here (the whole point is a real non-JS verifier); beforeAll fails
// loudly with an actionable message if it is missing rather than silently skipping.
//
// Hermetic: everything happens in temp dirs that are removed in afterAll.

import { spawnSync, type SpawnSyncReturns } from "node:child_process";
import { generateKeyPairSync } from "node:crypto";
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../..");
const exampleDir = join(repoRoot, "examples/python-pytest");
const ROW_ID = "example.checkout.apply_coupon";

const tempDirs: string[] = [];
let coreTarball = "";
let cliTarball = "";

function childEnv(extra: Record<string, string> = {}): NodeJS.ProcessEnv {
  return { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0", ...extra };
}

function run(
  command: string,
  args: string[],
  cwd = repoRoot,
  env: Record<string, string> = {}
): SpawnSyncReturns<string> {
  return spawnSync(command, args, { cwd, encoding: "utf8", env: childEnv(env) });
}

function requireSuccess(result: SpawnSyncReturns<string>, label: string): void {
  if (result.status !== 0) {
    throw new Error(
      [
        `${label} failed with status ${result.status}`,
        `stdout:\n${result.stdout}`,
        `stderr:\n${result.stderr}`
      ].join("\n")
    );
  }
}

function stableCacheRoot(): string {
  return process.platform === "darwin" ? "/tmp" : tmpdir();
}

function npmCacheDir(): string {
  const dir = mkdtempSync(join(stableCacheRoot(), "python-pytest-npm-cache-"));
  tempDirs.push(dir);
  return dir;
}

function pytestAvailable(): boolean {
  return spawnSync("pytest", ["--version"], { encoding: "utf8" }).status === 0;
}

// The parsed CLI envelope for one marker command (bind/scan/verify/prove all emit
// the `{ ok, data, ... }` envelope unconditionally).
function runUcm(
  ucp: string,
  consumer: string,
  args: string[],
  env: Record<string, string> = {}
): { ok: boolean; data: Record<string, any>; raw: SpawnSyncReturns<string> } {
  const result = run(ucp, args, consumer, env);
  if (typeof result.stdout !== "string" || result.stdout.trim() === "") {
    throw new Error(
      `ucp ${args.join(" ")} produced no JSON (status ${result.status}, stderr: ${result.stderr})`
    );
  }
  const payload = JSON.parse(result.stdout) as { ok: boolean; data: Record<string, any> };
  return { ok: payload.ok, data: payload.data, raw: result };
}

interface Consumer {
  dir: string;
  ucp: string;
  publicKeyPath: string;
  privateKeyPem: string;
  vrPath: string;
}

// A clean consumer: a COPY of the committed example with the published tarballs
// installed via npm (no workspace linking), plus a scratch ed25519 keypair. This
// is exactly what an adopter who `npm i @use-cases-plugin/cli`'d would have.
function installConsumer(): Consumer {
  const dir = mkdtempSync(join(tmpdir(), "python-pytest-consumer-"));
  tempDirs.push(dir);
  cpSync(exampleDir, dir, { recursive: true });

  // The CLI is the only Node dependency the adopter installs; the example project
  // itself ships no package.json (it is a pure Python project).
  writeFileSync(
    join(dir, "package.json"),
    JSON.stringify(
      { name: "python-pytest-consumer", private: true, type: "module", dependencies: {} },
      null,
      2
    )
  );
  requireSuccess(
    run(
      "npm",
      ["install", "--cache", npmCacheDir(), "--no-audit", "--no-fund", coreTarball, cliTarball],
      dir
    ),
    "npm install (published tarballs)"
  );

  const keypair = generateKeyPairSync("ed25519");
  const publicKeyPath = join(dir, "public-key.pem");
  writeFileSync(publicKeyPath, keypair.publicKey.export({ type: "spki", format: "pem" }) as string);

  return {
    dir,
    ucp: join(dir, "node_modules/.bin/ucp"),
    publicKeyPath,
    privateKeyPem: keypair.privateKey.export({ type: "pkcs8", format: "pem" }) as string,
    vrPath: join(dir, "verification-results.jsonl")
  };
}

function bind(c: Consumer) {
  return runUcm(c.ucp, c.dir, [
    "bind",
    "--repo",
    c.dir,
    "--row",
    ROW_ID,
    "--file",
    "src/coupon.py",
    "--mode",
    "explicit",
    "--register-existing",
    "--json"
  ]);
}

function scan(c: Consumer) {
  return runUcm(c.ucp, c.dir, ["scan", "--repo", c.dir, "--public-key", c.publicKeyPath, "--json"]);
}

function verify(c: Consumer) {
  return runUcm(c.ucp, c.dir, [
    "verify",
    "--repo",
    c.dir,
    "--all",
    "--out",
    c.vrPath,
    "--public-key",
    c.publicKeyPath,
    "--json"
  ]);
}

function prove(c: Consumer) {
  return runUcm(
    c.ucp,
    c.dir,
    [
      "prove",
      "--repo",
      c.dir,
      "--all",
      "--trusted-ci",
      "--append",
      "--verification-results",
      c.vrPath,
      "--signing-key-env",
      "UCP_SIGNING_KEY",
      "--public-key",
      c.publicKeyPath,
      "--json"
    ],
    { UCP_SIGNING_KEY: c.privateKeyPem }
  );
}

function rowOf(scanData: Record<string, any>, rowId = ROW_ID) {
  return scanData.status.rows.find((row: { row_id: string }) => row.row_id === rowId);
}

beforeAll(() => {
  requireSuccess(run("corepack", ["pnpm", "build"]), "pnpm build");

  if (!pytestAvailable()) {
    throw new Error(
      "pytest is required to run the python-pytest example proof (it runs the REAL " +
        "verifier). Install it with `python3 -m pip install pytest` and re-run."
    );
  }

  const packDir = mkdtempSync(join(tmpdir(), "python-pytest-pack-"));
  tempDirs.push(packDir);
  for (const filter of ["@use-cases-plugin/core", "@use-cases-plugin/cli"]) {
    requireSuccess(
      run("corepack", ["pnpm", "--filter", filter, "pack", "--pack-destination", packDir]),
      `pack ${filter}`
    );
  }
  coreTarball = join(packDir, "use-cases-plugin-core-1.0.0-rc.1.tgz");
  cliTarball = join(packDir, "use-cases-plugin-cli-1.0.0-rc.1.tgz");
}, 180_000);

afterAll(() => {
  for (const dir of tempDirs.splice(0)) {
    try {
      rmSync(dir, { recursive: true, force: true });
    } catch {
      /* the OS reaps tmp regardless */
    }
  }
});

describe("examples/python-pytest reaches FRESH from the published artifact (no pnpm/vitest)", () => {
  test("a Python adopter goes from nothing to a signed FRESH proof via real pytest", () => {
    const consumer = installConsumer();

    // The scaffolded workspace validates out of the box.
    const validate = runUcm(consumer.ucp, consumer.dir, [
      "matrix",
      "validate",
      "--repo",
      consumer.dir,
      "--json"
    ]);
    expect(validate.ok, JSON.stringify(validate.data)).toBe(true);

    // bind: register the marker the example already carries in src/coupon.py.
    const bound = bind(consumer);
    expect(bound.ok, JSON.stringify(bound.data)).toBe(true);
    expect(bound.data.registry_event_appended).toBe(true);
    expect(bound.data.binding_slug).toBe(ROW_ID);

    // scan #1: bound but not yet proven.
    const scan1 = scan(consumer);
    expect(rowOf(scan1.data).status).toBe("UNPROVEN");

    // verify: runs the REAL python.pytest verifier (pytest exit 0 => pass).
    const verified = verify(consumer);
    expect(verified.data.exit_code).toBe(0);
    expect(verified.data.results).toHaveLength(1);
    const result = verified.data.results[0];
    expect(result).toMatchObject({
      row_id: ROW_ID,
      status: "pass",
      verifier_id: "acceptance",
      verifier_kind: "script",
      evidence_kind: "test_result",
      exit_code: 0
    });
    // The unsigned results ledger really was written by verify.
    const vr = readFileSync(consumer.vrPath, "utf8").trim().split("\n").map((l) => JSON.parse(l));
    expect(vr).toHaveLength(1);
    expect(vr[0].status).toBe("pass");

    // prove: trusted-CI signs a proof from the verification result + scratch key.
    const proven = prove(consumer);
    expect(proven.ok, JSON.stringify(proven.data)).toBe(true);
    expect(proven.data.trusted).toBe(true);
    expect(proven.data.proof_events_appended).toBe(1);
    expect(rowOf2(proven.data, ROW_ID).status).toBe("signed");

    // scan #2: the row is now FRESH — the whole point.
    const scan2 = scan(consumer);
    expect(scan2.ok).toBe(true);
    expect(scan2.data.status.summary).toMatchObject({ fresh: 1, unproven: 0, invalid: 0 });
    expect(rowOf(scan2.data).status).toBe("FRESH");
  });

  test("breaking the production code fails verify and keeps the row out of FRESH", () => {
    const consumer = installConsumer();
    expect(bind(consumer).ok).toBe(true);

    // Introduce a real regression: drop the discount so the genuine acceptance
    // test fails. If verify were stubbed this would still 'pass'; it must not.
    const couponPath = join(consumer.dir, "src/coupon.py");
    const broken = readFileSync(couponPath, "utf8").replace(
      "return subtotal_cents - discount",
      "return subtotal_cents  # regression: discount dropped"
    );
    expect(broken).toContain("regression: discount dropped");
    writeFileSync(couponPath, broken);

    // verify runs pytest against the broken code => fail.
    const verified = verify(consumer);
    expect(verified.data.exit_code).not.toBe(0);
    expect(verified.data.results[0]).toMatchObject({ row_id: ROW_ID, status: "fail" });

    // prove refuses to sign a failed verification.
    const proven = prove(consumer);
    expect(proven.ok).toBe(false);
    expect(proven.data.proof_events_appended).toBe(0);
    expect(rowOf2(proven.data, ROW_ID)).toMatchObject({ status: "failed", reason: "RESULT_FAILED" });

    // scan: the row never reached FRESH.
    const scanned = scan(consumer);
    expect(scanned.data.status.summary.fresh).toBe(0);
    expect(rowOf(scanned.data).status).toBe("UNPROVEN");
  });
});

// prove rows live under data.rows (distinct from scan's data.status.rows).
function rowOf2(proveData: Record<string, any>, rowId = ROW_ID) {
  return proveData.rows.find((row: { row_id: string }) => row.row_id === rowId);
}
