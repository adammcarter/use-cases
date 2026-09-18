import { existsSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import {
  canRunBootstrap,
  cleanupScratch,
  fileTree,
  publishStandInRelease,
  repoRoot,
  runBootstrap,
  scratch,
  unameStub
} from "../helpers/release-stand-in.js";

const REFUSED_BASE_URL = "http://127.0.0.1:1/downloads";

afterEach(() => {
  cleanupScratch();
});

describe.skipIf(!canRunBootstrap)("a download that cannot be completed says what went wrong and what to do", () => {
  test("an asset the release does not carry names the asset, the release and the URL", () => {
    const release = publishStandInRelease({ omitArchive: true });
    const cacheDir = scratch("use-cases-cache-");

    const result = runBootstrap({
      env: {
        USE_CASES_VERSION: release.version,
        USE_CASES_RELEASE_BASE_URL: release.baseUrl,
        USE_CASES_CACHE_DIR: cacheDir
      }
    });

    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain(release.assetName);
    expect(result.stderr).toContain(`v${release.version}`);
    expect(result.stderr).toContain(`${release.baseUrl}/v${release.version}/${release.assetName}`);
    expect(result.stderr).toMatch(/does not carry/);
    // bin/use-cases now runs whatever the resolver picks, so the escape hatch a
    // failed download names is the committed bundle itself, by its path.
    expect(result.stderr).toContain(join(repoRoot, "dist/uc.js"));
    expect(existsSync(join(repoRoot, "dist/uc.js")), "the hint must name a path that exists").toBe(true);
    expect(fileTree(cacheDir)).toEqual([]);
  });

  test("a host that refuses connections is reported as a download failure, not a checksum one", () => {
    const cacheDir = scratch("use-cases-cache-");

    const result = runBootstrap({
      env: {
        USE_CASES_VERSION: "9.9.9-standin",
        USE_CASES_RELEASE_BASE_URL: REFUSED_BASE_URL,
        USE_CASES_CACHE_DIR: cacheDir
      }
    });

    expect(result.status).not.toBe(0);
    expect(result.stderr).toMatch(/could not reach/);
    expect(result.stderr).toContain(REFUSED_BASE_URL);
    expect(result.stderr).not.toMatch(/checksum mismatch/);
    expect(result.stderr).not.toMatch(/does not carry/);
    expect(fileTree(cacheDir)).toEqual([]);
  });

  test("a release with no SHA256SUMS is refused with its own message", () => {
    const release = publishStandInRelease({ omitSums: true });
    const cacheDir = scratch("use-cases-cache-");

    const result = runBootstrap({
      env: {
        USE_CASES_VERSION: release.version,
        USE_CASES_RELEASE_BASE_URL: release.baseUrl,
        USE_CASES_CACHE_DIR: cacheDir
      }
    });

    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain("SHA256SUMS");
    expect(result.stderr).toMatch(/published no checksums/);
    expect(result.stderr).toMatch(/unverified/);
    expect(fileTree(cacheDir)).toEqual([]);
  });

  test("a SHA256SUMS that does not list the asset is refused before the archive is trusted", () => {
    const release = publishStandInRelease({ omitSumsLine: true });
    const cacheDir = scratch("use-cases-cache-");

    const result = runBootstrap({
      env: {
        USE_CASES_VERSION: release.version,
        USE_CASES_RELEASE_BASE_URL: release.baseUrl,
        USE_CASES_CACHE_DIR: cacheDir
      }
    });

    expect(result.status).not.toBe(0);
    expect(result.stderr).toMatch(/do(es)? not list/);
    expect(result.stderr).toContain(release.assetName);
    expect(result.stderr).toMatch(/unverified/);
    expect(fileTree(cacheDir)).toEqual([]);
  });

  test("an unsupported machine is named and refused before any request", () => {
    // An Intel Mac and a machine that is not a Mac at all. Apple Silicon is
    // the only published platform, so BOTH are unsupported — and an Intel Mac
    // must be told so rather than handed an arm64 binary.
    for (const [osName, machine] of [
      ["Darwin", "x86_64"],
      ["Linux", "aarch64"]
    ] as const) {
      const cacheDir = scratch("use-cases-cache-");
      const result = runBootstrap({
        pathPrefix: unameStub(osName, machine),
        env: {
          USE_CASES_VERSION: "9.9.9-standin",
          // A URL that would fail noisily if it were ever read.
          USE_CASES_RELEASE_BASE_URL: REFUSED_BASE_URL,
          USE_CASES_CACHE_DIR: cacheDir
        }
      });

      expect(result.status, `${osName}/${machine}`).not.toBe(0);
      expect(result.stderr).toContain("no published binary");
      expect(result.stderr).toContain(osName);
      expect(result.stderr).toContain(machine);
      // The published list is named, and it is Apple Silicon only.
      expect(result.stderr).toContain("macos-arm64");
      expect(result.stderr).not.toContain("macos-x86_64");
      // The platform refusal, not a network error: nothing was fetched.
      expect(result.stderr).not.toMatch(/could not reach/);
      expect(fileTree(cacheDir)).toEqual([]);
    }
  });

  test("an archive that does not contain the requested executable is refused", () => {
    const release = publishStandInRelease({ omitExecutable: "use-cases" });
    const cacheDir = scratch("use-cases-cache-");

    const result = runBootstrap({
      env: {
        USE_CASES_VERSION: release.version,
        USE_CASES_RELEASE_BASE_URL: release.baseUrl,
        USE_CASES_CACHE_DIR: cacheDir
      }
    });

    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain(release.assetName);
    expect(result.stderr).toContain("use-cases");
    expect(result.stdout).toBe("");
  });

  test("an unknown executable name is refused by the bootstrap itself", () => {
    const result = runBootstrap({ entry: "bootstrap", args: ["uc-legacy"] });
    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain("uc-legacy");
    expect(result.stderr).toContain("use-cases-mcp");
  });
});
