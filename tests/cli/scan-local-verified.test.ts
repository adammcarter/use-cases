// Keyless daily loop acceptance (0.2.0, Task 1): a bound row reaches the green
// keyless signal VERIFIED_LOCAL with NO ed25519 key and NO `prove` — the whole
// point of the keyless tier. The flow is bind -> verify (writes the UNSIGNED
// results ledger to the auto-discovered default path) -> scan, and scan reports
// `local_status: "VERIFIED_LOCAL"` while the signed `status` stays `UNPROVEN`
// (no signed proof exists). Then breaking the code drops it to STALE_LOCAL.
//
// Runs the PUBLISHED CLI artifact against a clean copy of the pure-Python example
// (mirrors example-python-pytest.test.ts) so the assertion is end-to-end, not a
// unit stub. pytest is a hard requirement (the verifier really runs).
//
// Hermetic: everything happens in temp dirs removed in afterAll.
import { spawnSync, type SpawnSyncReturns } from "node:child_process";
import { cpSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
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
  const dir = mkdtempSync(join(stableCacheRoot(), "scan-local-npm-cache-"));
  tempDirs.push(dir);
  return dir;
}

function pytestAvailable(): boolean {
  return spawnSync("pytest", ["--version"], { encoding: "utf8" }).status === 0;
}

function runUcm(
  uc: string,
  consumer: string,
  args: string[],
  env: Record<string, string> = {}
): { ok: boolean; data: Record<string, any>; raw: SpawnSyncReturns<string> } {
  const result = run(uc, args, consumer, env);
  if (typeof result.stdout !== "string" || result.stdout.trim() === "") {
    throw new Error(
      `uc ${args.join(" ")} produced no JSON (status ${result.status}, stderr: ${result.stderr})`
    );
  }
  const payload = JSON.parse(result.stdout) as { ok: boolean; data: Record<string, any> };
  return { ok: payload.ok, data: payload.data, raw: result };
}

interface Consumer {
  dir: string;
  uc: string;
  // The DEFAULT auto-discovered results path (<data_root>/.use-cases/…) so scan
  // picks it up with no --results flag — the zero-config keyless loop.
  defaultVrPath: string;
}

// A clean consumer: a COPY of the committed example with the published tarballs
// installed via npm (no workspace linking). Deliberately NO ed25519 keypair —
// the keyless loop must not need one.
function installConsumer(): Consumer {
  const dir = mkdtempSync(join(tmpdir(), "scan-local-consumer-"));
  tempDirs.push(dir);
  cpSync(exampleDir, dir, { recursive: true });

  writeFileSync(
    join(dir, "package.json"),
    JSON.stringify(
      { name: "scan-local-consumer", private: true, type: "module", dependencies: {} },
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
    uc: join(dir, "node_modules/.bin/uc"),
    defaultVrPath: join(dir, ".use-cases", "verification-results.jsonl")
  };
}

function bind(c: Consumer) {
  return runUcm(c.uc, c.dir, [
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

// verify writes the UNSIGNED results ledger to the DEFAULT auto-discover path.
// No signing key, no --public-key: this is the keyless path.
function verify(c: Consumer) {
  return runUcm(c.uc, c.dir, [
    "verify",
    "--repo",
    c.dir,
    "--all",
    "--out",
    c.defaultVrPath,
    "--json"
  ]);
}

// scan with NO key material at all — signed proofs are not part of this loop.
function scan(c: Consumer) {
  return runUcm(c.uc, c.dir, ["scan", "--repo", c.dir, "--json"]);
}

function rowOf(scanData: Record<string, any>, rowId = ROW_ID) {
  return scanData.status.rows.find((row: { row_id: string }) => row.row_id === rowId);
}

beforeAll(() => {
  requireSuccess(run("corepack", ["pnpm", "build"]), "pnpm build");

  if (!pytestAvailable()) {
    throw new Error(
      "pytest is required for the keyless-loop acceptance test (verify runs the REAL " +
        "verifier). Install it with `python3 -m pip install pytest` and re-run."
    );
  }

  const packDir = mkdtempSync(join(tmpdir(), "scan-local-pack-"));
  tempDirs.push(packDir);
  for (const filter of ["@adammcarter/use-cases-core", "@adammcarter/use-cases-cli"]) {
    requireSuccess(
      run("corepack", ["pnpm", "--filter", filter, "pack", "--pack-destination", packDir]),
      `pack ${filter}`
    );
  }
  coreTarball = join(packDir, "adammcarter-use-cases-core-0.4.0.tgz");
  cliTarball = join(packDir, "adammcarter-use-cases-cli-0.4.0.tgz");
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

describe("keyless daily loop: bind -> verify -> scan reaches VERIFIED_LOCAL with no key", () => {
  test("a bound + locally verified row is VERIFIED_LOCAL while status stays UNPROVEN", () => {
    const consumer = installConsumer();

    expect(bind(consumer).ok).toBe(true);

    // Before verify: bound but unverified locally.
    const scanBefore = scan(consumer);
    const rowBefore = rowOf(scanBefore.data);
    expect(rowBefore.status).toBe("UNPROVEN");
    expect(rowBefore.local_status).toBe("UNVERIFIED_LOCAL");

    // verify runs the REAL pytest verifier (exit 0 => pass) and writes the
    // unsigned results ledger to the auto-discovered default path.
    const verified = verify(consumer);
    expect(verified.data.exit_code).toBe(0);
    expect(existsSync(consumer.defaultVrPath)).toBe(true);

    // scan auto-discovers the unsigned results: the keyless green light is on,
    // WITHOUT any signed proof (status stays UNPROVEN) and WITHOUT any key.
    const scanAfter = scan(consumer);
    expect(scanAfter.ok).toBe(true);
    const rowAfter = rowOf(scanAfter.data);
    expect(rowAfter.status).toBe("UNPROVEN");
    expect(rowAfter.local_status).toBe("VERIFIED_LOCAL");
    // The signed tier is untouched: no proof was minted.
    expect(scanAfter.data.status.summary.fresh).toBe(0);
  });

  test("editing the bound code after a local verify drops it to STALE_LOCAL", () => {
    const consumer = installConsumer();
    expect(bind(consumer).ok).toBe(true);
    expect(verify(consumer).data.exit_code).toBe(0);
    expect(rowOf(scan(consumer).data).local_status).toBe("VERIFIED_LOCAL");

    // Change the bound production code (the span hash / binding set drifts).
    const couponPath = join(consumer.dir, "src/coupon.py");
    const edited = readFileSync(couponPath, "utf8").replace(
      "return subtotal_cents - discount",
      "return subtotal_cents - discount  # unrelated tweak"
    );
    expect(edited).toContain("unrelated tweak");
    writeFileSync(couponPath, edited);

    // The prior local result no longer matches the current binding set.
    const rowAfter = rowOf(scan(consumer).data);
    expect(rowAfter.local_status).toBe("STALE_LOCAL");
    expect(rowAfter.local_reason).toBeTruthy();
  });
});
