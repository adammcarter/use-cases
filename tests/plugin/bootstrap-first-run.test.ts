import { existsSync, statSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import {
  canRunBootstrap,
  cleanupScratch,
  fileTree,
  hostPlatform,
  publishStandInRelease,
  runBootstrap,
  scratch,
  unpublishedPlatform
} from "../helpers/release-stand-in.js";

afterEach(() => {
  cleanupScratch();
});

function cachedPath(cacheDir: string, version: string, exe: string): string {
  return join(cacheDir, "bin", version, hostPlatform(), exe);
}

describe.skipIf(!canRunBootstrap)("the first run downloads the machine's binary, verifies its checksum and caches it", () => {
  test("downloads the matching archive, verifies it, caches both executables and execs the one asked for", () => {
    const release = publishStandInRelease();
    const cacheDir = scratch("use-cases-cache-");

    const result = runBootstrap({
      args: ["hello", "world"],
      env: {
        USE_CASES_VERSION: release.version,
        USE_CASES_RELEASE_BASE_URL: release.baseUrl,
        USE_CASES_CACHE_DIR: cacheDir
      }
    });

    expect(result.status, result.stderr).toBe(0);
    expect(result.stdout.trim()).toBe("stand-in use-cases args:hello world");

    const cached = cachedPath(cacheDir, release.version, "use-cases");
    expect(existsSync(cached), `expected the executable at ${cached}`).toBe(true);
    expect(statSync(cached).mode & 0o111).not.toBe(0);
    // One download serves both executables the archive carries.
    expect(existsSync(cachedPath(cacheDir, release.version, "use-cases-mcp"))).toBe(true);
  });

  test("the executable's exit code and stderr are the bootstrap's own", () => {
    const release = publishStandInRelease();
    const cacheDir = scratch("use-cases-cache-");
    const env = {
      USE_CASES_VERSION: release.version,
      USE_CASES_RELEASE_BASE_URL: release.baseUrl,
      USE_CASES_CACHE_DIR: cacheDir
    };

    const result = runBootstrap({ args: ["--fail"], env });
    expect(result.status).toBe(3);
    expect(result.stderr).toContain("stand-in use-cases refused");

    // The mcp wrapper reaches its own executable, not the CLI.
    const mcp = runBootstrap({ entry: "use-cases-mcp", args: ["ping"], env });
    expect(mcp.status, mcp.stderr).toBe(0);
    expect(mcp.stdout.trim()).toBe("stand-in use-cases-mcp args:ping");
  });

  test("an archive whose checksum does not match is refused, named and never cached", () => {
    const release = publishStandInRelease({ corruptArchive: true });
    const cacheDir = scratch("use-cases-cache-");

    const result = runBootstrap({
      env: {
        USE_CASES_VERSION: release.version,
        USE_CASES_RELEASE_BASE_URL: release.baseUrl,
        USE_CASES_CACHE_DIR: cacheDir
      }
    });

    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain("checksum mismatch");
    expect(result.stderr).toContain(release.assetName);
    expect(result.stderr).toContain(release.publishedSha256);
    expect(result.stderr).toContain(release.servedSha256);
    expect(result.stdout).toBe("");
    // Nothing unverified is left behind for the next run to pick up.
    expect(fileTree(cacheDir)).toEqual([]);
  });

  test("with no cache override the cache is per-user state under the user cache directory", () => {
    const release = publishStandInRelease();
    const home = scratch("use-cases-home-");

    const result = runBootstrap({
      env: {
        HOME: home,
        XDG_CACHE_HOME: undefined,
        USE_CASES_CACHE_DIR: undefined,
        USE_CASES_VERSION: release.version,
        USE_CASES_RELEASE_BASE_URL: release.baseUrl
      }
    });

    expect(result.status, result.stderr).toBe(0);
    const cached = join(home, "Library/Caches/use-cases/bin", release.version, hostPlatform(), "use-cases");
    expect(existsSync(cached), `expected the executable at ${cached}`).toBe(true);
    // Nothing is written into the repository or the plugin checkout.
    expect(cached.startsWith(home)).toBe(true);
  });

  test("XDG_CACHE_HOME moves the cache when it is set", () => {
    const release = publishStandInRelease();
    const xdg = scratch("use-cases-xdg-");

    const result = runBootstrap({
      env: {
        XDG_CACHE_HOME: xdg,
        USE_CASES_CACHE_DIR: undefined,
        USE_CASES_VERSION: release.version,
        USE_CASES_RELEASE_BASE_URL: release.baseUrl
      }
    });

    expect(result.status, result.stderr).toBe(0);
    expect(existsSync(join(xdg, "use-cases/bin", release.version, hostPlatform(), "use-cases"))).toBe(true);
  });

  test("a cache directory that already exists from an earlier version is left alone", () => {
    const first = publishStandInRelease({ version: "1.0.0-standin" });
    const second = publishStandInRelease({ version: "2.0.0-standin" });
    const cacheDir = scratch("use-cases-cache-");

    for (const release of [first, second]) {
      const result = runBootstrap({
        env: {
          USE_CASES_VERSION: release.version,
          USE_CASES_RELEASE_BASE_URL: release.baseUrl,
          USE_CASES_CACHE_DIR: cacheDir
        }
      });
      expect(result.status, result.stderr).toBe(0);
    }

    // Keyed by version, so both live side by side and an upgrade re-downloads.
    expect(existsSync(cachedPath(cacheDir, "1.0.0-standin", "use-cases"))).toBe(true);
    expect(existsSync(cachedPath(cacheDir, "2.0.0-standin", "use-cases"))).toBe(true);
  });

  test("a forced platform decides the asset and the cache key, and one no release publishes is refused", () => {
    // A well-formed slug that no release carries: Apple Silicon is the only
    // published platform, so this is what a second platform would be tested
    // through, and what a user forcing a retired one now gets.
    const forced = unpublishedPlatform();
    const release = publishStandInRelease({ platform: forced });
    const cacheDir = scratch("use-cases-cache-");
    const env = {
      USE_CASES_PLATFORM: forced,
      USE_CASES_VERSION: release.version,
      USE_CASES_RELEASE_BASE_URL: release.baseUrl,
      USE_CASES_CACHE_DIR: cacheDir
    };

    const result = runBootstrap({ args: ["forced"], env });
    expect(result.status, result.stderr).toBe(0);
    expect(result.stdout.trim()).toBe("stand-in use-cases args:forced");
    expect(existsSync(join(cacheDir, "bin", release.version, forced, "use-cases"))).toBe(true);
    // Not under this machine's own slug: the force decided the cache key too.
    expect(existsSync(join(cacheDir, "bin", release.version, hostPlatform(), "use-cases"))).toBe(false);

    // A forced platform the release does not publish is refused at the
    // checksums — the sums are the gate — never exec'd as the wrong slice.
    const absent = runBootstrap({
      env: { ...env, USE_CASES_PLATFORM: hostPlatform(), USE_CASES_CACHE_DIR: scratch("use-cases-cache-") }
    });
    expect(absent.status).not.toBe(0);
    expect(absent.stderr).toMatch(/do(es)? not list|does not carry/);
    expect(absent.stderr).toContain(`use-cases-${release.version}-${hostPlatform()}.tar.gz`);
    expect(absent.stdout).toBe("");
  });
});
