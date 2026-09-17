import { join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import {
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

//: @use-case:release.distribution.failed_download_says_what_to_do
describe("a download that cannot be completed says what went wrong and what to do", () => {
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
    // The Node bundle is still there until the plugin cuts over, so say so.
    expect(result.stderr).toContain(join(repoRoot, "bin/uc"));
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

  test("an unsupported operating system and architecture are named and refused before any request", () => {
    const cacheDir = scratch("use-cases-cache-");

    const result = runBootstrap({
      pathPrefix: unameStub("Linux", "aarch64"),
      env: {
        USE_CASES_VERSION: "9.9.9-standin",
        // A URL that would fail noisily if it were ever read.
        USE_CASES_RELEASE_BASE_URL: REFUSED_BASE_URL,
        USE_CASES_CACHE_DIR: cacheDir
      }
    });

    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain("Linux");
    expect(result.stderr).toContain("aarch64");
    expect(result.stderr).toContain("macos-arm64");
    expect(result.stderr).toContain("macos-x86_64");
    // The platform refusal, not a network error: nothing was fetched.
    expect(result.stderr).not.toMatch(/could not reach/);
    expect(fileTree(cacheDir)).toEqual([]);
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
//: @use-case:end release.distribution.failed_download_says_what_to_do
