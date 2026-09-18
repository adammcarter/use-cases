// THE TWO EXPERIMENTS, run against the published CLI artifact.
//
// Measured against a real repo before this change, both directions:
//
//   typed ONE fake JSON line into the results file      285 -> 286
//   nothing executed, stdout hash literally sha256:de1e7e…dead
//
//   recorded FIVE genuine hand-drive evidence records   285 -> 285
//   against the shipped binary                          (no change)
//
// The claim read the forgeable ledger and ignored the ledger of behaviour
// actually driven. This suite pins the reversal end to end: typing must not move
// the number, and driving the product must.
//
// It installs the packed tarballs into a copy of the committed python-pytest
// example and drives the real `use-cases` binary, so nothing here is a unit stub. Every
// run points `UC_RUN_KEY_FILE` at a throwaway path, so no test ever touches the
// developer's own machine-local key.
import { spawnSync, type SpawnSyncReturns } from "node:child_process";
import { appendFileSync, cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { packedTarball } from "../helpers/package-version";

const repoRoot = resolve(import.meta.dirname, "../..");
const exampleDir = join(repoRoot, "examples/python-pytest");
const ROW_ID = "example.checkout.apply_coupon";

const tempDirs: string[] = [];
let coreTarball = "";
let cliTarball = "";

function run(
  command: string,
  args: string[],
  cwd = repoRoot,
  env: Record<string, string> = {}
): SpawnSyncReturns<string> {
  return spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0", ...env }
  });
}

function requireSuccess(result: SpawnSyncReturns<string>, label: string): void {
  if (result.status !== 0) {
    throw new Error(
      [`${label} failed with status ${result.status}`, result.stdout, result.stderr].join("\n")
    );
  }
}

function pytestAvailable(): boolean {
  return spawnSync("pytest", ["--version"], { encoding: "utf8" }).status === 0;
}

interface Consumer {
  dir: string;
  uc: string;
  resultsPath: string;
  env: Record<string, string>;
}

function installConsumer(): Consumer {
  const dir = mkdtempSync(join(tmpdir(), "honest-claim-consumer-"));
  tempDirs.push(dir);
  cpSync(exampleDir, dir, { recursive: true });
  writeFileSync(
    join(dir, "package.json"),
    JSON.stringify({ name: "honest-claim-consumer", private: true, type: "module" }, null, 2)
  );
  const cache = mkdtempSync(join(process.platform === "darwin" ? "/tmp" : tmpdir(), "hc-npm-"));
  tempDirs.push(cache);
  requireSuccess(
    run("npm", ["install", "--cache", cache, "--no-audit", "--no-fund", coreTarball, cliTarball], dir),
    "npm install (published tarballs)"
  );
  return {
    dir,
    uc: join(dir, "node_modules/.bin/use-cases"),
    resultsPath: join(dir, ".use-cases", "verification-results.jsonl"),
    // The machine-local run key goes in the throwaway workspace, never in $HOME.
    env: { UC_RUN_KEY_FILE: join(dir, "machine", "run-key") }
  };
}

function uc(
  consumer: Consumer,
  args: string[]
): { ok: boolean; data: Record<string, any>; diagnostics: Array<Record<string, any>> } {
  const result = run(consumer.uc, args, consumer.dir, consumer.env);
  if (typeof result.stdout !== "string" || result.stdout.trim() === "") {
    throw new Error(`use-cases ${args.join(" ")} produced no JSON (status ${result.status}): ${result.stderr}`);
  }
  return JSON.parse(result.stdout) as {
    ok: boolean;
    data: Record<string, any>;
    diagnostics: Array<Record<string, any>>;
  };
}

function claimOf(consumer: Consumer) {
  return uc(consumer, ["scan", "--repo", consumer.dir, "--json"]).data.status.acceptance_claim;
}

beforeAll(() => {
  requireSuccess(run("corepack", ["pnpm", "build"]), "pnpm build");
  if (!pytestAvailable()) {
    throw new Error(
      "pytest is required for the acceptance-claim experiments (verify runs the REAL " +
        "verifier). Install it with `python3 -m pip install pytest` and re-run."
    );
  }
  const packDir = mkdtempSync(join(tmpdir(), "honest-claim-pack-"));
  tempDirs.push(packDir);
  for (const filter of ["@adammcarter/use-cases-core", "@adammcarter/use-cases-cli"]) {
    requireSuccess(
      run("corepack", ["pnpm", "--filter", filter, "pack", "--pack-destination", packDir]),
      `pack ${filter}`
    );
  }
  coreTarball = packedTarball(packDir, "core");
  cliTarball = packedTarball(packDir, "cli");
}, 300_000);

afterAll(() => {
  for (const dir of tempDirs.splice(0)) {
    try {
      rmSync(dir, { recursive: true, force: true });
    } catch {
      /* the OS reaps tmp regardless */
    }
  }
}, 120_000);

describe("EXPERIMENT 1: typing a line must not move the acceptance claim", () => {
  test("a fabricated results line proves nothing", () => {
    const consumer = installConsumer();
    expect(
      uc(consumer, [
        "bind", "--repo", consumer.dir, "--row", ROW_ID,
        "--file", "src/coupon.py", "--mode", "explicit", "--register-existing", "--json"
      ]).ok
    ).toBe(true);
    expect(uc(consumer, ["verify", "--repo", consumer.dir, "--all", "--out", consumer.resultsPath, "--json"]).data.exit_code).toBe(0);

    const before = claimOf(consumer);
    expect(before.proven).toBe(1);

    // The forgery, verbatim in shape: take the genuine record, keep every hash,
    // rename the row, and hand-write it back. Nothing ran.
    const genuine = JSON.parse(readFileSync(consumer.resultsPath, "utf8").trim().split("\n")[0]);
    delete genuine.run_attestation;
    genuine.stdout_sha256 = `sha256:${"de1e7e".padEnd(60, "0")}dead`;
    appendFileSync(consumer.resultsPath, `${JSON.stringify(genuine)}\n`);

    const after = claimOf(consumer);
    expect(after.proven).toBe(before.proven);
  });

  test("stripping the attestation from a real record un-proves the row", () => {
    const consumer = installConsumer();
    uc(consumer, [
      "bind", "--repo", consumer.dir, "--row", ROW_ID,
      "--file", "src/coupon.py", "--mode", "explicit", "--register-existing", "--json"
    ]);
    uc(consumer, ["verify", "--repo", consumer.dir, "--all", "--out", consumer.resultsPath, "--json"]);
    expect(claimOf(consumer).proven).toBe(1);

    const stripped = readFileSync(consumer.resultsPath, "utf8")
      .split("\n")
      .filter((line) => line.trim() !== "")
      .map((line) => {
        const record = JSON.parse(line);
        delete record.run_attestation;
        return JSON.stringify(record);
      })
      .join("\n");
    writeFileSync(consumer.resultsPath, `${stripped}\n`);

    const after = claimOf(consumer);
    expect(after.proven).toBe(0);
    expect(after.unattested).toBe(1);
    expect(after.basis).toContain("unattested");
  });
});

describe("EXPERIMENT 2: driving the product must move the acceptance claim", () => {
  test("a performed run recorded by the tool proves the row", () => {
    const consumer = installConsumer();
    uc(consumer, [
      "bind", "--repo", consumer.dir, "--row", ROW_ID,
      "--file", "src/coupon.py", "--mode", "explicit", "--register-existing", "--json"
    ]);

    // Nothing verified, nothing driven.
    const before = claimOf(consumer);
    expect(before.proven).toBe(0);

    // Drive the behaviour for real. `use-cases` spawns the command itself and records
    // the argv it ran — which is the thing a hand-written record cannot supply.
    const recorded = uc(consumer, [
      "evidence", "record", "--repo", consumer.dir, "--use-case", ROW_ID,
      "--json", "--perform", "--",
      "python3", "-c",
      "import sys; sys.path.insert(0, 'src'); import coupon; assert coupon.apply_coupon(1000, 'SAVE10') == 900; print('coupon applied')"
    ]);
    expect(recorded.ok).toBe(true);

    const after = claimOf(consumer);
    expect(after.proven).toBe(1);
    expect(after.by_evidence.performed_run).toBe(1);
    expect(after.by_evidence.local_run).toBe(0);
    expect(after.basis).toContain("1 performed run");
  });

  test("a run that FAILS does not prove the row", () => {
    const consumer = installConsumer();
    uc(consumer, [
      "bind", "--repo", consumer.dir, "--row", ROW_ID,
      "--file", "src/coupon.py", "--mode", "explicit", "--register-existing", "--json"
    ]);
    const recorded = uc(consumer, [
      "evidence", "record", "--repo", consumer.dir, "--use-case", ROW_ID,
      "--json", "--perform", "--", "python3", "-c", "import sys; sys.exit(3)"
    ]);
    const performed = recorded.diagnostics.find((d) => d.code === "evidence.performed_run");
    expect(performed?.message).toContain("exit 3");
    expect(claimOf(consumer).proven).toBe(0);
  });

  test("a self-reported record (no --perform) still proves nothing", () => {
    // The tier the ledger already calls weakest stays weakest. This is the same
    // shape as the five hand-drive records that moved the number by zero — and
    // it must KEEP moving it by zero, or the fix would be theatre.
    const consumer = installConsumer();
    uc(consumer, [
      "bind", "--repo", consumer.dir, "--row", ROW_ID,
      "--file", "src/coupon.py", "--mode", "explicit", "--register-existing", "--json"
    ]);
    uc(consumer, [
      "evidence", "record", "--repo", consumer.dir, "--use-case", ROW_ID,
      "--kind", "live_demo", "--result", "pass",
      "--summary", "Drove the shipped binary by hand and it worked.", "--json"
    ]);
    expect(claimOf(consumer).proven).toBe(0);
  });
});
