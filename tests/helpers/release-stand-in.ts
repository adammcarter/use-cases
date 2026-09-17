// A stand-in for GitHub Releases, on disk.
//
// The bootstrap (bin/use-cases-bootstrap) downloads its executable from a
// release, so a black-box test of it needs a release. These helpers publish one
// into a temp directory laid out exactly as GitHub serves it
// (<downloads>/v<version>/<asset>) and hand back a file:// base URL, so the
// suite never touches the network and never reads the developer's own cache.
import { execFileSync, spawnSync, type SpawnSyncReturns } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { arch, platform, tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

export const repoRoot = resolve(import.meta.dirname, "../..");
export const bootstrapPath = join(repoRoot, "bin/use-cases-bootstrap");

/** The executables a release archive carries, and the wrappers in bin/. */
export const EXECUTABLES = ["use-cases", "use-cases-mcp"] as const;

const dirs: string[] = [];

export function scratch(prefix = "use-cases-bootstrap-"): string {
  const dir = mkdtempSync(join(tmpdir(), prefix));
  dirs.push(dir);
  return dir;
}

export function cleanupScratch(): void {
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true });
}

/** The platform slug the bootstrap must resolve on the machine running the suite. */
export function hostPlatform(): string {
  if (platform() !== "darwin") {
    throw new Error(`the release bootstrap is macOS-only (ADR 0007); this machine is ${platform()}`);
  }
  return arch() === "arm64" ? "macos-arm64" : "macos-x86_64";
}

export interface StandInOptions {
  version?: string;
  platform?: string;
  /** Publish an archive whose bytes do not match the sums file. */
  corruptArchive?: boolean;
  /** Publish the sums file but not the archive (an asset missing from the release). */
  omitArchive?: boolean;
  /** Publish the archive but no SHA256SUMS at all. */
  omitSums?: boolean;
  /** Publish a SHA256SUMS that does not mention this asset. */
  omitSumsLine?: boolean;
  /** Leave the requested executable out of the archive. */
  omitExecutable?: string;
}

export interface StandIn {
  /** Local directory serving as the release downloads root. */
  downloadsRoot: string;
  /** file:// URL for USE_CASES_RELEASE_BASE_URL. */
  baseUrl: string;
  version: string;
  platform: string;
  assetName: string;
  /** The SHA256 the sums file publishes for the asset. */
  publishedSha256: string;
  /** The SHA256 of the bytes actually served (differs when corruptArchive). */
  servedSha256: string;
}

function standInExecutable(name: string): string {
  // A shell script, not a Mach-O: the bootstrap's job is to verify and exec
  // whatever the release published, and a script makes the test hermetic.
  return [
    "#!/bin/sh",
    `if [ "$1" = "--fail" ]; then echo "stand-in ${name} refused" >&2; exit 3; fi`,
    `echo "stand-in ${name} args:$*"`,
    ""
  ].join("\n");
}

function sha256Of(path: string): string {
  return execFileSync("shasum", ["-a", "256", path], { encoding: "utf8" }).trim().split(/\s+/)[0]!;
}

/** Publish a release into a temp directory and return how to reach it. */
export function publishStandInRelease(options: StandInOptions = {}): StandIn {
  const version = options.version ?? "9.9.9-standin";
  const slug = options.platform ?? hostPlatform();
  const assetName = `use-cases-${version}-${slug}.tar.gz`;

  const root = scratch("use-cases-standin-");
  const downloadsRoot = join(root, "downloads");
  const releaseDir = join(downloadsRoot, `v${version}`);
  mkdirSync(releaseDir, { recursive: true });

  // Stage the executables the archive carries.
  const stage = join(root, "stage");
  mkdirSync(stage, { recursive: true });
  const members: string[] = [];
  for (const name of EXECUTABLES) {
    if (options.omitExecutable === name) continue;
    const path = join(stage, name);
    writeFileSync(path, standInExecutable(name));
    chmodSync(path, 0o755);
    members.push(name);
  }

  // Build the archive outside the release dir so omitArchive can simply not
  // publish it while its checksum is still what the sums file claims.
  const built = join(root, assetName);
  execFileSync("tar", ["-czf", built, "-C", stage, ...members]);
  const trueSha = sha256Of(built);

  let servedSha = trueSha;
  if (!options.omitArchive) {
    const published = join(releaseDir, assetName);
    if (options.corruptArchive) {
      // Same name, different bytes: the mismatch the bootstrap must refuse.
      writeFileSync(published, "this is not the archive that was checksummed\n");
      servedSha = sha256Of(published);
    } else {
      execFileSync("cp", [built, published]);
    }
  }

  if (!options.omitSums) {
    const lines = options.omitSumsLine
      ? [`${"0".repeat(64)}  some-other-asset.tar.gz`]
      : [`${trueSha}  ${assetName}`];
    writeFileSync(join(releaseDir, "SHA256SUMS"), `${lines.join("\n")}\n`);
  }

  return {
    downloadsRoot,
    baseUrl: pathToFileURL(downloadsRoot).href,
    version,
    platform: slug,
    assetName,
    publishedSha256: trueSha,
    servedSha256: servedSha
  };
}

export interface RunOptions {
  /** Which bin/ entry to run: a wrapper name, or "bootstrap" for the engine. */
  entry?: (typeof EXECUTABLES)[number] | "bootstrap";
  args?: string[];
  env?: Record<string, string | undefined>;
  /** Prepend this directory to PATH (used to stub uname). */
  pathPrefix?: string;
}

/**
 * Run a bin/ entry with every real cache and release setting stripped, so a
 * test can never read the network or the developer's own cache by accident.
 */
export function runBootstrap(options: RunOptions = {}): SpawnSyncReturns<string> {
  const env: Record<string, string> = { ...process.env } as Record<string, string>;
  for (const key of Object.keys(env)) {
    if (key.startsWith("USE_CASES_")) delete env[key];
  }
  delete env.XDG_CACHE_HOME;
  // A HOME nothing else shares: an unset cache override must not reach ~/Library.
  env.HOME = scratch("use-cases-home-");
  for (const [key, value] of Object.entries(options.env ?? {})) {
    if (value === undefined) delete env[key];
    else env[key] = value;
  }
  if (options.pathPrefix) env.PATH = `${options.pathPrefix}:${env.PATH}`;

  const entry = options.entry ?? "use-cases";
  const script = entry === "bootstrap" ? bootstrapPath : join(repoRoot, "bin", entry);
  return spawnSync(script, options.args ?? [], { encoding: "utf8", env });
}

/** Every file under a directory, relative and sorted — for "nothing was written". */
export function fileTree(root: string): string[] {
  const out: string[] = [];
  const walk = (dir: string, prefix: string): void => {
    let entries: string[];
    try {
      entries = readdirSync(dir);
    } catch {
      return;
    }
    for (const entry of entries.sort()) {
      const path = join(dir, entry);
      const rel = prefix ? `${prefix}/${entry}` : entry;
      if (statSync(path).isDirectory()) walk(path, rel);
      else out.push(rel);
    }
  };
  walk(root, "");
  return out.sort();
}

/** A PATH-stub directory whose `uname` reports another operating system. */
export function unameStub(osName: string, machine: string): string {
  const dir = scratch("use-cases-uname-");
  const path = join(dir, "uname");
  writeFileSync(
    path,
    ["#!/bin/sh", `case "$1" in`, `  -m) echo "${machine}" ;;`, `  *) echo "${osName}" ;;`, "esac", ""].join("\n")
  );
  chmodSync(path, 0o755);
  return dir;
}
