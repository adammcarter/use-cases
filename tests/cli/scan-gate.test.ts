// `scan --gate` exit-code gating acceptance + `verify --out` DEFAULT path (Task 2,
// 0.2.0 keyless daily loop).
//
// Runs the PUBLISHED CLI artifact against a clean copy of the pure-Python example
// (mirrors scan-local-verified.test.ts) so the assertions are end-to-end. The
// example row is made `required_for_release` so the gate has a required row to
// gate on. Covers:
//   - `scan --gate` exits 1 when a required row is below the bar (UNVERIFIED /
//     SUSPECT / STALE), 0 when it reaches VERIFIED_LOCAL — WITHOUT any key.
//   - `scan` WITHOUT `--gate` still exits 0 for a below-bar row (backward compat).
//   - `verify` with NO `--out` writes the unsigned ledger to the auto-discovered
//     default path, so a bare `verify` then bare `scan` reaches VERIFIED_LOCAL.
//
// Hermetic: everything happens in temp dirs removed in afterAll. pytest required.
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
  const dir = mkdtempSync(join(stableCacheRoot(), "scan-gate-npm-cache-"));
  tempDirs.push(dir);
  return dir;
}

function pytestAvailable(): boolean {
  return spawnSync("pytest", ["--version"], { encoding: "utf8" }).status === 0;
}

interface UcmRun {
  status: number | null;
  ok: boolean;
  data: Record<string, any>;
  raw: SpawnSyncReturns<string>;
}

function runUcm(
  uc: string,
  consumer: string,
  args: string[],
  env: Record<string, string> = {}
): UcmRun {
  const result = run(uc, args, consumer, env);
  if (typeof result.stdout !== "string" || result.stdout.trim() === "") {
    throw new Error(
      `uc ${args.join(" ")} produced no JSON (status ${result.status}, stderr: ${result.stderr})`
    );
  }
  const payload = JSON.parse(result.stdout) as { ok: boolean; data: Record<string, any> };
  return { status: result.status, ok: payload.ok, data: payload.data, raw: result };
}

interface Consumer {
  dir: string;
  uc: string;
  defaultVrPath: string;
}

// A clean consumer: a COPY of the committed example with the published tarballs
// installed. The row is made `required_for_release` so the gate applies to it.
// Deliberately NO ed25519 keypair — the keyless gate must not need one.
function installConsumer(): Consumer {
  const dir = mkdtempSync(join(tmpdir(), "scan-gate-consumer-"));
  tempDirs.push(dir);
  cpSync(exampleDir, dir, { recursive: true });

  // Mark the single example row required_for_release (mode:none keeps it keyless;
  // `required_for_release` is what the gate keys on).
  const checkoutYml = join(dir, "use-cases", "checkout.yml");
  const yaml = readFileSync(checkoutYml, "utf8").replace(
    "    approval_policy:\n      mode: none",
    "    approval_policy:\n      mode: none\n      required_for_release: true"
  );
  if (!yaml.includes("required_for_release: true")) {
    throw new Error("failed to inject required_for_release into the example row");
  }
  writeFileSync(checkoutYml, yaml);

  writeFileSync(
    join(dir, "package.json"),
    JSON.stringify(
      { name: "scan-gate-consumer", private: true, type: "module", dependencies: {} },
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

function bind(c: Consumer): UcmRun {
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

// verify with NO --out: the default path IS the auto-discovered ledger.
function verifyDefault(c: Consumer): UcmRun {
  return runUcm(c.uc, c.dir, ["verify", "--repo", c.dir, "--all", "--json"]);
}

function scan(c: Consumer, extra: string[] = []): UcmRun {
  return runUcm(c.uc, c.dir, ["scan", "--repo", c.dir, "--json", ...extra]);
}

function rowOf(scanData: Record<string, any>, rowId = ROW_ID) {
  return scanData.status.rows.find((row: { row_id: string }) => row.row_id === rowId);
}

beforeAll(() => {
  requireSuccess(run("corepack", ["pnpm", "build"]), "pnpm build");

  if (!pytestAvailable()) {
    throw new Error(
      "pytest is required for the scan --gate acceptance test (verify runs the REAL " +
        "verifier). Install it with `python3 -m pip install pytest` and re-run."
    );
  }

  const packDir = mkdtempSync(join(tmpdir(), "scan-gate-pack-"));
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

describe("scan --gate exit-code gating (keyless, required row)", () => {
  test("a required UNVERIFIED_LOCAL row: --gate exits 1, plain scan exits 0", () => {
    const consumer = installConsumer();
    expect(bind(consumer).ok).toBe(true);

    // Bound but not yet verified locally -> UNVERIFIED_LOCAL, below the dev bar.
    const plain = scan(consumer);
    expect(rowOf(plain.data).local_status).toBe("UNVERIFIED_LOCAL");
    // Backward compat: WITHOUT --gate, a below-bar required row still exits 0.
    expect(plain.status).toBe(0);
    expect(plain.data.gate).toBeUndefined();

    // WITH --gate, the same below-bar required row blocks (exit 1) and is listed.
    const gated = scan(consumer, ["--gate"]);
    expect(gated.status).toBe(1);
    expect(gated.ok).toBe(false);
    expect(gated.data.gate.blocked).toBe(true);
    expect(gated.data.gate.required_bar).toBe("VERIFIED_LOCAL");
    expect(gated.data.gate.offending_rows.map((r: { row_id: string }) => r.row_id)).toContain(
      ROW_ID
    );
  });

  test("after verify the required row is VERIFIED_LOCAL: --gate exits 0", () => {
    const consumer = installConsumer();
    expect(bind(consumer).ok).toBe(true);
    expect(verifyDefault(consumer).data.exit_code).toBe(0);
    expect(rowOf(scan(consumer).data).local_status).toBe("VERIFIED_LOCAL");

    const gated = scan(consumer, ["--gate"]);
    expect(gated.status).toBe(0);
    expect(gated.ok).toBe(true);
    expect(gated.data.gate.blocked).toBe(false);
    expect(gated.data.gate.offending_rows).toEqual([]);
  });

  test("release mode: a VERIFIED_LOCAL (not FRESH) required row still blocks --gate", () => {
    const consumer = installConsumer();
    expect(bind(consumer).ok).toBe(true);
    expect(verifyDefault(consumer).data.exit_code).toBe(0);

    // VERIFIED_LOCAL clears the dev bar but NOT the release bar (FRESH), and no
    // signed proof exists (keyless) -> release --gate blocks.
    const gated = scan(consumer, ["--gate", "--policy-mode", "release"]);
    expect(gated.status).toBe(1);
    expect(gated.data.gate.required_bar).toBe("FRESH");
    expect(gated.data.gate.blocked).toBe(true);
  });
});

describe("verify --out DEFAULT path closes the keyless loop with zero flags", () => {
  test("bare verify writes the auto-discovered ledger; bare scan reads VERIFIED_LOCAL", () => {
    const consumer = installConsumer();
    expect(bind(consumer).ok).toBe(true);

    // Before verify: the default ledger does not exist yet.
    expect(existsSync(consumer.defaultVrPath)).toBe(false);

    // verify with NO --out flag writes to the auto-discovered default path.
    const verified = verifyDefault(consumer);
    expect(verified.data.exit_code).toBe(0);
    // out_path is the default auto-discovered ledger (compared by suffix: macOS
    // resolves the tmp dir through the /private realpath symlink).
    expect(verified.data.out_path).toMatch(/\/\.use-cases\/verification-results\.jsonl$/);
    expect(existsSync(consumer.defaultVrPath)).toBe(true);

    // bare scan (no --results) auto-discovers it: the keyless light is on.
    const rowAfter = rowOf(scan(consumer).data);
    expect(rowAfter.local_status).toBe("VERIFIED_LOCAL");
  });
});
