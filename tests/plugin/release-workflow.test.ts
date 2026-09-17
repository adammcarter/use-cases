import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { parse as parseYaml } from "yaml";
import {
  canRunBootstrap,
  cleanupScratch,
  hostPlatform,
  PUBLISHED_PLATFORMS,
  publishStandInRelease,
  repoRoot,
  runBootstrap,
  scratch
} from "../helpers/release-stand-in.js";

const releaseWorkflowPath = join(repoRoot, ".github/workflows/release.yml");
const bootstrapSource = () => readFileSync(join(repoRoot, "bin/use-cases-bootstrap"), "utf8");
const releaseSource = () => readFileSync(releaseWorkflowPath, "utf8");

/** `on:` is a YAML 1.1 boolean; different parsers hand it back either way. */
function triggers(workflow: Record<string, unknown>): Record<string, unknown> {
  const raw = workflow.on ?? (workflow as Record<string, unknown>)["true"] ?? workflow[true as unknown as string];
  expect(raw, "the workflow declares no triggers").toBeTruthy();
  return raw as Record<string, unknown>;
}

function platformSlugs(source: string): string[] {
  return [...new Set(source.match(/macos-(?:arm64|x86_64)/g) ?? [])].sort();
}

/** The asset-name template, with the shell variables normalised away. */
function assetTemplate(source: string): string | null {
  const match = source.match(/use-cases-\$\{?[A-Za-z_][A-Za-z_0-9]*\}?-\$\{?[A-Za-z_][A-Za-z_0-9]*\}?\.tar\.gz/);
  if (!match) return null;
  return match[0].replace(/\$\{?[A-Za-z_][A-Za-z_0-9]*\}?/g, "${}");
}

afterEach(() => {
  cleanupScratch();
});

//: @use-case:release.distribution.release_publishes_checksummed_assets
describe("a release publishes a checksummed archive for every supported platform", () => {
  test("the workflow builds both executables in release configuration for the published platform", () => {
    const source = releaseSource();
    const workflow = parseYaml(source) as Record<string, unknown>;
    const jobs = workflow.jobs as Record<string, { "runs-on"?: string; permissions?: Record<string, string> }>;

    expect(Object.keys(jobs).length).toBeGreaterThan(0);
    for (const job of Object.values(jobs)) {
      expect(job["runs-on"], "release assets must be built on macOS").toMatch(/^macos-/);
    }

    expect(source).toMatch(/swift build .*-c release/);
    expect(source).toContain("--arch arm64");
    expect(source).toContain("UseCasesCLI");
    expect(source).toContain("UseCasesMCP");
    // One thin arm64 build, so there is nothing to slice: lipo stays only as
    // the check that the product really is thin arm64.
    expect(source).toContain("lipo -info");
    expect(source).not.toContain("lipo -thin");
    expect(source).not.toContain("lipo -extract");
  });

  test("the workflow writes SHA256SUMS and attaches every archive to the release", () => {
    const source = releaseSource();
    const workflow = parseYaml(source) as Record<string, unknown>;
    const jobs = workflow.jobs as Record<string, { permissions?: Record<string, string> }>;

    expect(source).toContain("SHA256SUMS");
    expect(source).toMatch(/shasum -a 256/);
    expect(source).toMatch(/gh release (create|upload)/);
    expect(source).toContain("GITHUB_TOKEN");
    // Attaching assets needs write access, declared where the prove job declares it.
    const writesContents = Object.values(jobs).some((job) => job.permissions?.contents === "write");
    expect(writesContents, "a job must declare permissions: contents: write").toBe(true);
  });

  test("the publisher and the bootstrap agree on the asset name, the platforms and the tag", () => {
    const workflow = releaseSource();
    const bootstrap = bootstrapSource();

    expect(assetTemplate(workflow), "the workflow names no use-cases-<version>-<platform>.tar.gz asset").not.toBeNull();
    expect(assetTemplate(bootstrap)).toBe(assetTemplate(workflow));

    expect(platformSlugs(bootstrap)).toEqual(platformSlugs(workflow));
    expect(platformSlugs(workflow)).toEqual([...PUBLISHED_PLATFORMS]);

    // Both resolve the release by the same v-prefixed tag as every existing tag.
    expect(workflow).toMatch(/v\$\{?[A-Za-z_][A-Za-z_0-9]*\}?/);
    expect(bootstrap).toMatch(/v\$\{?[A-Za-z_][A-Za-z_0-9]*\}?/);
    expect(bootstrap).toContain("https://github.com/adammcarter/use-cases/releases/download");
  });

  test("Apple Silicon is the only published platform, in both files", () => {
    const workflow = releaseSource();
    const bootstrap = bootstrapSource();

    // The owner retired the x86_64 asset for 0.8.0: the toolchain warns the
    // architecture is deprecated for the deployment target. Nothing may build,
    // slice or attach one, and the bootstrap may not offer one.
    expect(platformSlugs(workflow)).toEqual(["macos-arm64"]);
    expect(platformSlugs(bootstrap)).toEqual(["macos-arm64"]);
    expect(workflow).not.toContain("x86_64");
    expect(bootstrap).not.toContain("x86_64");
    expect(PUBLISHED_PLATFORMS).toEqual(["macos-arm64"]);
  });

  test.skipIf(!canRunBootstrap)("the bootstrap asks for the plugin's own version by default", () => {
    const pluginVersion = (JSON.parse(readFileSync(join(repoRoot, ".claude-plugin/plugin.json"), "utf8")) as { version: string }).version;
    // A local release AT the manifest's version, carrying only its checksums:
    // the bootstrap then names the asset it wanted, with no network and no
    // USE_CASES_VERSION to tell it which version that is.
    const release = publishStandInRelease({ version: pluginVersion, omitArchive: true });

    const result = runBootstrap({
      env: {
        USE_CASES_VERSION: undefined,
        USE_CASES_RELEASE_BASE_URL: release.baseUrl,
        USE_CASES_CACHE_DIR: scratch("use-cases-cache-")
      }
    });

    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain(`use-cases-${pluginVersion}-${hostPlatform()}.tar.gz`);
    expect(result.stderr).toContain(`v${pluginVersion}`);
  });

  test("the workflow never fires on a push to a branch", () => {
    const workflow = parseYaml(releaseSource()) as Record<string, unknown>;
    const on = triggers(workflow);

    expect(Object.keys(on).sort()).toEqual(["push", "workflow_dispatch"]);
    const push = on.push as Record<string, unknown>;
    expect(push).toBeTruthy();
    expect(push.branches, "a branches filter would publish releases off branch pushes").toBeUndefined();
    expect(push["branches-ignore"]).toBeUndefined();
    expect(Array.isArray(push.tags) && (push.tags as string[]).length > 0).toBe(true);
    for (const tag of push.tags as string[]) expect(tag.startsWith("v")).toBe(true);
  });

  test("the release pipeline is its own workflow and leaves the existing gates alone", () => {
    const ci = readFileSync(join(repoRoot, ".github/workflows/ci.yml"), "utf8");
    const useCases = readFileSync(join(repoRoot, ".github/workflows/use-cases.yml"), "utf8");

    expect(existsSync(releaseWorkflowPath)).toBe(true);
    expect(ci).toContain("pnpm -s test");
    expect(ci).toContain("pnpm -s build");
    for (const other of [ci, useCases]) {
      expect(other).not.toMatch(/gh release/);
      expect(other).not.toContain("SHA256SUMS");
    }
  });

  test.skipIf(!canRunBootstrap)("a stand-in release laid out the way the workflow publishes one satisfies the bootstrap", () => {
    // The naming agreement above is text; this is the same layout end to end.
    const release = publishStandInRelease();
    const result = runBootstrap({
      args: ["layout"],
      env: {
        USE_CASES_VERSION: release.version,
        USE_CASES_RELEASE_BASE_URL: release.baseUrl,
        USE_CASES_CACHE_DIR: scratch("use-cases-cache-")
      }
    });
    expect(result.status, result.stderr).toBe(0);
    expect(result.stdout.trim()).toBe("stand-in use-cases args:layout");
  });
});
//: @use-case:end release.distribution.release_publishes_checksummed_assets
