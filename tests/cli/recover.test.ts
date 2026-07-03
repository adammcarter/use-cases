// `ucm recover` acceptance (0.1.0, Task 4): drive a drifted / unproven row back
// to green with ONE command. `recover` re-runs the row's verifier, writes the
// UNSIGNED results ledger to the canonical auto-discover path, re-scans, and
// reports the resulting local_status + status.
//
//   - STALE_LOCAL row  -> recover           -> VERIFIED_LOCAL (exit 0)
//   - same row         -> recover + signing -> FRESH          (exit 0)
//   - a genuinely FAILING verifier          -> non-zero + diagnostic (NO fake green)
//
// Runs the PUBLISHED CLI artifact against a clean copy of the pure-Python example
// (mirrors scan-local-verified.test.ts) so the assertions are end-to-end, not a
// unit stub. pytest is a hard requirement (the verifier really runs).
//
// Hermetic: everything happens in temp dirs removed in afterAll.
import { spawnSync, type SpawnSyncReturns } from "node:child_process";
import {
  cpSync,
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync
} from "node:fs";
import { generateKeyPairSync } from "node:crypto";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../..");
const exampleDir = join(repoRoot, "examples/python-pytest");
const ROW_ID = "example.checkout.apply_coupon";
const SIGNING_KEY_ENV = "UCM_TEST_SIGNING_KEY";

const tempDirs: string[] = [];
let coreTarball = "";
let cliTarball = "";
let publicKeyPem = "";
let privateKeyPem = "";

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
  const dir = mkdtempSync(join(stableCacheRoot(), "recover-npm-cache-"));
  tempDirs.push(dir);
  return dir;
}

function pytestAvailable(): boolean {
  return spawnSync("pytest", ["--version"], { encoding: "utf8" }).status === 0;
}

function runUcm(
  ucm: string,
  consumer: string,
  args: string[],
  env: Record<string, string> = {}
): { ok: boolean; data: Record<string, any>; raw: SpawnSyncReturns<string> } {
  const result = run(ucm, args, consumer, env);
  if (typeof result.stdout !== "string" || result.stdout.trim() === "") {
    throw new Error(
      `ucm ${args.join(" ")} produced no JSON (status ${result.status}, stderr: ${result.stderr})`
    );
  }
  const payload = JSON.parse(result.stdout) as { ok: boolean; data: Record<string, any> };
  return { ok: payload.ok, data: payload.data, raw: result };
}

interface Consumer {
  dir: string;
  ucm: string;
  defaultVrPath: string;
}

// A clean consumer: a COPY of the committed example with the published tarballs
// installed via npm (no workspace linking). Deliberately NO ed25519 keypair on
// disk — recover's keyless path must not need one.
function installConsumer(): Consumer {
  const dir = mkdtempSync(join(tmpdir(), "recover-consumer-"));
  tempDirs.push(dir);
  cpSync(exampleDir, dir, { recursive: true });

  writeFileSync(
    join(dir, "package.json"),
    JSON.stringify(
      { name: "recover-consumer", private: true, type: "module", dependencies: {} },
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

  return {
    dir,
    ucm: join(dir, "node_modules/.bin/ucm"),
    defaultVrPath: join(dir, ".use-cases", "verification-results.jsonl")
  };
}

function bind(c: Consumer) {
  return runUcm(c.ucm, c.dir, [
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

function verify(c: Consumer) {
  return runUcm(c.ucm, c.dir, [
    "verify",
    "--repo",
    c.dir,
    "--all",
    "--out",
    c.defaultVrPath,
    "--json"
  ]);
}

function scan(c: Consumer) {
  return runUcm(c.ucm, c.dir, ["scan", "--repo", c.dir, "--json"]);
}

function couponPath(c: Consumer): string {
  return join(c.dir, "src/coupon.py");
}

// Edit the bound production code WITHOUT breaking the test: the span hash drifts
// so the earlier local result no longer matches -> STALE_LOCAL. The verifier
// still PASSES, so `recover` can re-establish VERIFIED_LOCAL.
function driftBoundCode(c: Consumer): void {
  const p = couponPath(c);
  const edited = readFileSync(p, "utf8").replace(
    "return subtotal_cents - discount",
    "return subtotal_cents - discount  # unrelated tweak"
  );
  if (!edited.includes("unrelated tweak")) {
    throw new Error("failed to drift the bound code (source shape changed)");
  }
  writeFileSync(p, edited);
}

// Break the implementation so the verifier GENUINELY fails: return the wrong
// total. Kept inside the marker span, so binding still recomputes but pytest
// fails. recover must surface this failure, never fake green.
function breakImplementation(c: Consumer): void {
  const p = couponPath(c);
  const edited = readFileSync(p, "utf8").replace(
    "return subtotal_cents - discount",
    "return subtotal_cents + discount  # BUG: adds the discount"
  );
  if (!edited.includes("BUG: adds the discount")) {
    throw new Error("failed to break the implementation (source shape changed)");
  }
  writeFileSync(p, edited);
}

function rowOf(scanData: Record<string, any>, rowId = ROW_ID) {
  return scanData.status.rows.find((row: { row_id: string }) => row.row_id === rowId);
}

beforeAll(() => {
  requireSuccess(run("corepack", ["pnpm", "build"]), "pnpm build");

  if (!pytestAvailable()) {
    throw new Error(
      "pytest is required for the recover acceptance test (verify runs the REAL " +
        "verifier). Install it with `python3 -m pip install pytest` and re-run."
    );
  }

  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  publicKeyPem = publicKey.export({ type: "spki", format: "pem" }).toString();
  privateKeyPem = privateKey.export({ type: "pkcs8", format: "pem" }).toString();

  const packDir = mkdtempSync(join(tmpdir(), "recover-pack-"));
  tempDirs.push(packDir);
  for (const filter of ["@use-case-matrix/core", "@use-case-matrix/cli"]) {
    requireSuccess(
      run("corepack", ["pnpm", "--filter", filter, "pack", "--pack-destination", packDir]),
      `pack ${filter}`
    );
  }
  coreTarball = join(packDir, "use-case-matrix-core-0.0.3.tgz");
  cliTarball = join(packDir, "use-case-matrix-cli-0.0.3.tgz");
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

describe("ucm recover: drive a drifted / unproven row back to green", () => {
  test("STALE_LOCAL -> recover --row -> VERIFIED_LOCAL (exit 0), no key", () => {
    const consumer = installConsumer();
    expect(bind(consumer).ok).toBe(true);
    expect(verify(consumer).data.exit_code).toBe(0);
    expect(rowOf(scan(consumer).data).local_status).toBe("VERIFIED_LOCAL");

    // Drift the bound code: the earlier local result no longer matches.
    driftBoundCode(consumer);
    expect(rowOf(scan(consumer).data).local_status).toBe("STALE_LOCAL");

    // recover re-verifies and re-establishes the keyless green light.
    const recovered = runUcm(consumer.ucm, consumer.dir, [
      "recover",
      "--repo",
      consumer.dir,
      "--row",
      ROW_ID,
      "--json"
    ]);
    expect(recovered.raw.status).toBe(0);
    expect(recovered.ok).toBe(true);
    const row = rowOf(recovered.data);
    expect(row.local_status).toBe("VERIFIED_LOCAL");
    // No signing key => the signed tier is untouched.
    expect(row.status).toBe("UNPROVEN");

    // And a fresh scan confirms the ledger was actually written.
    expect(existsSync(consumer.defaultVrPath)).toBe(true);
    expect(rowOf(scan(consumer).data).local_status).toBe("VERIFIED_LOCAL");
  });

  test("recover --signing-key-env drives the row to FRESH (exit 0)", () => {
    const consumer = installConsumer();
    expect(bind(consumer).ok).toBe(true);

    const recovered = runUcm(
      consumer.ucm,
      consumer.dir,
      [
        "recover",
        "--repo",
        consumer.dir,
        "--all",
        "--signing-key-env",
        SIGNING_KEY_ENV,
        "--key-id",
        "test-key-1",
        "--public-key",
        writePublicKey(consumer),
        "--json"
      ],
      { [SIGNING_KEY_ENV]: privateKeyPem }
    );
    expect(recovered.raw.status).toBe(0);
    expect(recovered.ok).toBe(true);
    const row = rowOf(recovered.data);
    expect(row.status).toBe("FRESH");
    expect(row.local_status).toBe("VERIFIED_LOCAL");
  });

  test("a genuinely failing verifier -> non-zero + diagnostic, NO fake green", () => {
    const consumer = installConsumer();
    expect(bind(consumer).ok).toBe(true);
    breakImplementation(consumer);

    const recovered = run(
      consumer.ucm,
      ["recover", "--repo", consumer.dir, "--row", ROW_ID, "--json"],
      consumer.dir
    );
    // Non-zero exit — the "command failed" bucket (1), never 0.
    expect(recovered.status).not.toBe(0);
    const payload = JSON.parse(recovered.stdout) as {
      ok: boolean;
      data: Record<string, any>;
      diagnostics?: { message: string }[];
    };
    expect(payload.ok).toBe(false);
    // An actionable diagnostic naming the row that failed.
    const messages = (payload.diagnostics ?? []).map((d) => d.message).join(" ");
    expect(messages.toLowerCase()).toContain("verif");
    expect(messages).toContain(ROW_ID);

    // And it did NOT fake green: no VERIFIED_LOCAL for this row.
    const row = rowOf(scan(consumer).data);
    expect(row.local_status).not.toBe("VERIFIED_LOCAL");
  });
});

// Write the public key OUTSIDE the .use-cases evidence dir but inside the repo so
// scan can consume it via --public-key. Returns the path.
function writePublicKey(c: Consumer): string {
  const p = join(c.dir, "ci-signing-key.pub.pem");
  writeFileSync(p, publicKeyPem);
  return p;
}
