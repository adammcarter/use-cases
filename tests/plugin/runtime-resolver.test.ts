// The oracle for the plugin cut-over (ADR 0007 row 7).
//
// Every host-facing entry point in bin/ goes through bin/use-cases-runtime, so
// exactly one file decides what a command actually executes. These tests drive
// the wrappers the way a host does and read what came out the other end.
//
// The two branches are proved separately because they are chosen on the
// VERSION, never on a failure: a version whose release publishes the Swift
// archives downloads and verifies one, and a version whose release published
// none runs the committed bundle. The stand-in release's default version
// (9.9.9-standin) is above the first Swift release, and the plugin's own
// version is below it, so the tests need no switch of their own.
import { spawn, spawnSync } from "node:child_process";
import { chmodSync, cpSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import {
  canRunBootstrap,
  cleanupScratch,
  fileTree,
  publishStandInRelease,
  repoRoot,
  runBootstrap,
  scratch
} from "../helpers/release-stand-in.js";

/** Refuses every connection: proof that nothing was fetched. */
const REFUSED_BASE_URL = "http://127.0.0.1:1/downloads";

const pluginVersion = (JSON.parse(readFileSync(join(repoRoot, ".claude-plugin/plugin.json"), "utf8")) as {
  version: string;
}).version;

/** An executable that reports the pid it is running as. */
const pidReporter = (name: string): string =>
  ["#!/bin/sh", `echo "${name} pid:$$"`, ""].join("\n");

afterEach(() => {
  cleanupScratch();
});

//: @use-case:plugin.runtime.release_versions_run_the_verified_swift_binary
describe("a version whose release publishes Swift assets runs the verified binary", () => {
  // golden_every_entry_point_execs_the_downloaded_binary
  test.skipIf(!canRunBootstrap)("bin/uc, bin/use-cases and bin/use-cases-mcp all exec the verified executable", () => {
    const release = publishStandInRelease();
    const cacheDir = scratch("use-cases-cache-");
    const env = {
      USE_CASES_VERSION: release.version,
      USE_CASES_RELEASE_BASE_URL: release.baseUrl,
      USE_CASES_CACHE_DIR: cacheDir
    };

    for (const [entry, expected] of [
      ["use-cases", "stand-in use-cases args:one"],
      ["use-cases-mcp", "stand-in use-cases-mcp args:one"]
    ] as const) {
      const result = runBootstrap({ entry, args: ["one"], env });
      expect(result.status, result.stderr).toBe(0);
      expect(result.stdout.trim()).toBe(expected);
    }

    // bin/uc is not one of the release's executable names, so the stand-in
    // helper cannot spawn it: run it directly with the same environment.
    const uc = spawnSync(join(repoRoot, "bin/uc"), ["one"], {
      encoding: "utf8",
      env: { ...process.env, ...env, HOME: scratch("use-cases-home-") }
    });
    expect(uc.status, uc.stderr).toBe(0);
    // The Swift CLI, not the committed Node bundle: the bundle would have
    // refused an unknown command rather than echoed it.
    expect(uc.stdout.trim()).toBe("stand-in use-cases args:one");
  });

  // golden_the_mcp_entry_point_the_manifests_name_serves_a_host
  test.skipIf(!canRunBootstrap)("the MCP entry point execs through, leaving no shell holding the process", () => {
    const release = publishStandInRelease({ executableBody: pidReporter });
    const result = runBootstrap({
      entry: "use-cases-mcp",
      env: {
        USE_CASES_VERSION: release.version,
        USE_CASES_RELEASE_BASE_URL: release.baseUrl,
        USE_CASES_CACHE_DIR: scratch("use-cases-cache-")
      }
    });

    expect(result.status, result.stderr).toBe(0);
    const reported = /use-cases-mcp pid:(\d+)/.exec(result.stdout)?.[1];
    expect(reported, result.stdout).toBeTruthy();
    // The wrapper, the resolver and the bootstrap all exec: the process the
    // host spawned IS the server, so it owns the pipes, the signals and the
    // exit code.
    expect(Number(reported)).toBe(result.pid);
  });

  // bad_release_without_the_asset_never_falls_back
  test.skipIf(!canRunBootstrap)("a release that carries no asset fails and never runs the committed bundle", () => {
    const release = publishStandInRelease({ omitArchive: true });
    const cacheDir = scratch("use-cases-cache-");

    const result = spawnSync(join(repoRoot, "bin/uc"), ["version", "--json"], {
      encoding: "utf8",
      env: {
        ...process.env,
        USE_CASES_VERSION: release.version,
        USE_CASES_RELEASE_BASE_URL: release.baseUrl,
        USE_CASES_CACHE_DIR: cacheDir,
        HOME: scratch("use-cases-home-")
      }
    });

    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain(release.assetName);
    expect(result.stderr).toContain(`v${release.version}`);
    // The bundle would have printed the version envelope on stdout. Nothing
    // stood in for the release that should have carried a binary.
    expect(result.stdout).toBe("");
    expect(fileTree(cacheDir)).toEqual([]);
  });

  // edge_a_version_that_is_not_a_version_is_refused. No download, so this one
  // runs on every machine.
  test("a version that is not a semantic version is refused rather than guessed", () => {
    const result = spawnSync(join(repoRoot, "bin/uc"), ["version", "--json"], {
      encoding: "utf8",
      env: { ...process.env, USE_CASES_VERSION: "not-a-version", HOME: scratch("use-cases-home-") }
    });

    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain("not-a-version");
    expect(result.stdout).toBe("");
  });
});
//: @use-case:end plugin.runtime.release_versions_run_the_verified_swift_binary

//: @use-case:plugin.runtime.pre_swift_versions_run_the_committed_bundle
describe("a version whose release published no Swift asset runs the committed bundle", () => {
  // golden_the_cli_entry_points_run_the_bundle
  test("bin/uc and bin/use-cases print the version envelope from the committed bundle", () => {
    for (const entry of ["uc", "use-cases"] as const) {
      const result = spawnSync(join(repoRoot, "bin", entry), ["version", "--json"], {
        encoding: "utf8",
        cwd: scratch("use-cases-cwd-"),
        env: { ...process.env, HOME: scratch("use-cases-home-") }
      });
      expect(result.status, `${entry}: ${result.stderr}`).toBe(0);
      const envelope = JSON.parse(result.stdout) as { command: string; data: { version: string } };
      expect(envelope.command).toBe("version");
      expect(envelope.data.version).toBe(pluginVersion);
    }
  });

  // golden_the_mcp_entry_point_the_manifests_name_answers
  test("bin/use-cases-mcp answers initialize and tools/list, and is itself the server", async () => {
    const child = spawn(join(repoRoot, "bin/use-cases-mcp"), [], {
      cwd: repoRoot,
      stdio: ["pipe", "pipe", "pipe"],
      env: { ...process.env, HOME: scratch("use-cases-home-") }
    });
    try {
      const lines: string[] = [];
      let buffer = "";
      child.stdout.on("data", (chunk: Buffer) => {
        buffer += chunk.toString();
        let index: number;
        while ((index = buffer.indexOf("\n")) >= 0) {
          const line = buffer.slice(0, index).trim();
          buffer = buffer.slice(index + 1);
          if (line) lines.push(line);
        }
      });

      child.stdin.write(
        `${JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "row-7", version: "0" } } })}\n`
      );
      child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id: 2, method: "tools/list", params: {} })}\n`);

      const deadline = Date.now() + 20_000;
      while (lines.length < 2 && Date.now() < deadline) {
        await new Promise((resolve) => setTimeout(resolve, 25));
      }
      expect(lines.length, `only got: ${lines.join(" | ")}`).toBeGreaterThanOrEqual(2);

      const initialize = JSON.parse(lines[0]!) as { result?: { serverInfo?: { name?: string } } };
      expect(initialize.result?.serverInfo?.name).toBeTruthy();
      const tools = JSON.parse(lines[1]!) as { result?: { tools?: unknown[] } };
      expect((tools.result?.tools ?? []).length).toBeGreaterThan(0);

      // Every link in bin/ execs, so the process the host spawned is the
      // server itself and not a shell holding its pipes.
      const comm = spawnSync("ps", ["-o", "comm=", "-p", String(child.pid)], { encoding: "utf8" });
      expect(comm.stdout.trim(), "the spawned process should BE the server").toContain("node");
    } finally {
      child.kill("SIGKILL");
    }
  });

  // bad_the_bundle_is_missing
  test("with the committed bundle absent the wrapper names it rather than failing as an interpreter error", () => {
    const plugin = scratch("use-cases-plugin-");
    cpSync(join(repoRoot, "bin"), join(plugin, "bin"), { recursive: true });
    mkdirSync(join(plugin, ".claude-plugin"), { recursive: true });
    writeFileSync(join(plugin, ".claude-plugin/plugin.json"), JSON.stringify({ name: "use-cases", version: pluginVersion }));
    for (const entry of ["uc", "use-cases", "use-cases-mcp", "use-cases-runtime", "use-cases-bootstrap"]) {
      chmodSync(join(plugin, "bin", entry), 0o755);
    }
    expect(existsSync(join(plugin, "dist"))).toBe(false);

    const result = spawnSync(join(plugin, "bin/uc"), ["version", "--json"], {
      encoding: "utf8",
      env: { ...process.env, HOME: scratch("use-cases-home-") }
    });

    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain("dist/uc.js");
    expect(result.stdout).toBe("");
  });

  // edge_no_download_is_attempted
  test("nothing is fetched or cached: the branch is decided by the version, not by a download failing", () => {
    const cacheDir = scratch("use-cases-cache-");
    const result = spawnSync(join(repoRoot, "bin/uc"), ["version", "--json"], {
      encoding: "utf8",
      env: {
        ...process.env,
        USE_CASES_RELEASE_BASE_URL: REFUSED_BASE_URL,
        USE_CASES_CACHE_DIR: cacheDir,
        HOME: scratch("use-cases-home-")
      }
    });

    expect(result.status, result.stderr).toBe(0);
    expect((JSON.parse(result.stdout) as { command: string }).command).toBe("version");
    expect(fileTree(cacheDir)).toEqual([]);
  });
});
//: @use-case:end plugin.runtime.pre_swift_versions_run_the_committed_bundle
