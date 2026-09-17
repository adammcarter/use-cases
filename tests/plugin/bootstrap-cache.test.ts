import { chmodSync, existsSync, rmSync, statSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import {
  cleanupScratch,
  fileTree,
  hostPlatform,
  publishStandInRelease,
  runBootstrap,
  scratch
} from "../helpers/release-stand-in.js";

// Nothing listens here, so any attempt to fetch fails immediately. Using it as
// the base URL is what turns "did not need the network" into "made no request".
const REFUSED_BASE_URL = "http://127.0.0.1:1/downloads";

afterEach(() => {
  cleanupScratch();
});

function cachedPath(cacheDir: string, version: string, exe = "use-cases"): string {
  return join(cacheDir, "bin", version, hostPlatform(), exe);
}

//: @use-case:release.distribution.cached_binary_runs_without_network
describe("a cached binary runs without touching the network", () => {
  test("the second run succeeds against a host that refuses connections, and caches nothing new", () => {
    const release = publishStandInRelease();
    const cacheDir = scratch("use-cases-cache-");

    const first = runBootstrap({
      args: ["one"],
      env: {
        USE_CASES_VERSION: release.version,
        USE_CASES_RELEASE_BASE_URL: release.baseUrl,
        USE_CASES_CACHE_DIR: cacheDir
      }
    });
    expect(first.status, first.stderr).toBe(0);
    const afterFirst = fileTree(cacheDir);

    const second = runBootstrap({
      args: ["one"],
      env: {
        USE_CASES_VERSION: release.version,
        USE_CASES_RELEASE_BASE_URL: REFUSED_BASE_URL,
        USE_CASES_CACHE_DIR: cacheDir
      }
    });
    expect(second.status, second.stderr).toBe(0);
    expect(second.stdout).toBe(first.stdout);
    expect(second.stderr).toBe("");
    expect(fileTree(cacheDir)).toEqual(afterFirst);
  });

  test("a cache entry that cannot be exec'd is refetched and verified rather than run", () => {
    const release = publishStandInRelease();
    const cacheDir = scratch("use-cases-cache-");
    const env = {
      USE_CASES_VERSION: release.version,
      USE_CASES_RELEASE_BASE_URL: release.baseUrl,
      USE_CASES_CACHE_DIR: cacheDir
    };

    expect(runBootstrap({ env }).status).toBe(0);
    const cached = cachedPath(cacheDir, release.version);
    chmodSync(cached, 0o644);
    expect(statSync(cached).mode & 0o111).toBe(0);

    const again = runBootstrap({ args: ["two"], env });
    expect(again.status, again.stderr).toBe(0);
    expect(again.stdout.trim()).toBe("stand-in use-cases args:two");
    expect(statSync(cached).mode & 0o111).not.toBe(0);
  });

  test("an unexecutable cache entry is not trusted when the release is unreachable either", () => {
    const release = publishStandInRelease();
    const cacheDir = scratch("use-cases-cache-");

    expect(
      runBootstrap({
        env: {
          USE_CASES_VERSION: release.version,
          USE_CASES_RELEASE_BASE_URL: release.baseUrl,
          USE_CASES_CACHE_DIR: cacheDir
        }
      }).status
    ).toBe(0);
    chmodSync(cachedPath(cacheDir, release.version), 0o644);

    const again = runBootstrap({
      env: {
        USE_CASES_VERSION: release.version,
        USE_CASES_RELEASE_BASE_URL: REFUSED_BASE_URL,
        USE_CASES_CACHE_DIR: cacheDir
      }
    });
    // It fails as a download failure; it never falls back to the entry it refused.
    expect(again.status).not.toBe(0);
    expect(again.stdout).toBe("");
  });

  test("the cache hit short-circuits the download path, the SHA256SUMS fetch included", () => {
    const release = publishStandInRelease();
    const cacheDir = scratch("use-cases-cache-");
    const env = {
      USE_CASES_VERSION: release.version,
      USE_CASES_RELEASE_BASE_URL: release.baseUrl,
      USE_CASES_CACHE_DIR: cacheDir
    };

    expect(runBootstrap({ env }).status).toBe(0);

    // Empty the release entirely: archive and sums both gone, base URL unchanged.
    const releaseDir = join(release.downloadsRoot, `v${release.version}`);
    rmSync(join(releaseDir, release.assetName), { force: true });
    rmSync(join(releaseDir, "SHA256SUMS"), { force: true });
    expect(existsSync(join(releaseDir, "SHA256SUMS"))).toBe(false);

    const again = runBootstrap({ args: ["three"], env });
    expect(again.status, again.stderr).toBe(0);
    expect(again.stdout.trim()).toBe("stand-in use-cases args:three");
  });
});
//: @use-case:end release.distribution.cached_binary_runs_without_network
