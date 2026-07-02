import { spawnSync } from "node:child_process";
import { accessSync, constants, existsSync, mkdtempSync, readFileSync, readdirSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve } from "node:path";
import { diagnostic, type Diagnostic } from "../schema/index.js";

export type PackageInspectionTarget =
  | { kind: "workspace"; path: string; build?: boolean }
  | { kind: "tarball"; path: string }
  | { kind: "installed_root"; path: string };

export type PackagePathStatus = {
  path: string;
  status: "present" | "missing";
};

export type PackageManifestReference = {
  from: string;
  target: string;
  status: "resolved" | "missing";
};

export type PackageBinEntrypoint = {
  name: string;
  path: string;
  status: "present" | "missing";
  executable: boolean;
  shebang: boolean;
};

export type PackageSmokeCheck = {
  status: "passed" | "failed";
  command: string;
  exit_code: number | null;
  stdout?: string;
  stderr?: string;
};

export type PackageSmokeResult = {
  cli: PackageSmokeCheck;
  mcp: PackageSmokeCheck;
};

export type PackageInspectionResult = {
  schema_version: 1;
  complete: boolean;
  inspection_target: {
    kind: "tarball" | "installed_root";
    path: string;
    source_workspace?: string;
  };
  package_entries: string[];
  required_paths: PackagePathStatus[];
  manifest_references: PackageManifestReference[];
  bin_entrypoints: PackageBinEntrypoint[];
  files_allowlist: string[];
  forbidden_paths: string[];
  forbidden_text: Array<{ path: string; pattern: string }>;
  installed_smoke?: PackageSmokeResult;
  diagnostics: Diagnostic[];
};

const REQUIRED_PACKAGE_PATHS = [
  ".agents/skills/use-case-matrix/SKILL.md",
  ".agents/skills/showcase/SKILL.md",
  ".agents/skills/walkthrough/SKILL.md",
  ".codex-plugin/plugin.json",
  ".claude-plugin/plugin.json",
  ".mcp.json",
  "bootstrap/use-case-matrix.md",
  "docs/release.md",
  "docs/security.md",
  "hosts/codex.yml",
  "packages/cli/dist/index.js",
  "packages/cli/package.json",
  "packages/core/dist/index.js",
  "packages/core/dist/schemas/v1/use-case-file.schema.json",
  "packages/core/package.json",
  "packages/mcp/dist/index.js",
  "packages/mcp/package.json",
  "plugin.json",
  "README.md",
  "CHANGELOG.md",
  "schemas/v1/use-case-file.schema.json",
  "use-cases/showcase/live.yml"
] as const;

const FORBIDDEN_PACKAGE_SEGMENTS = [
  ".albus",
  ".Codex",
  ".cowork-receipts",
  ".DS_Store",
  ".copy-schemas.lock",
  "node_modules",
  "coverage",
  "tests",
  "src"
] as const;

// `src`/`tests` are forbidden for the repo's OWN payload (the published plugin
// must ship built artifacts, never TypeScript sources or the test suite), but
// they are legitimate CONTENT of the example PROJECTS under examples/ — e.g.
// examples/python-pytest ships a real src/ + tests/ layout that an adopter copies
// (the python.pytest verifier preset mandates the tests/ path). Permit only these
// two segments, and only beneath examples/; every other forbidden segment
// (node_modules, coverage, .DS_Store, …) stays forbidden everywhere.
const EXAMPLE_CONTENT_SEGMENTS = new Set<string>(["src", "tests"]);

const FORBIDDEN_TEXT_PATTERNS = [
  { id: "local_user_path", pattern: /\/Users\/admin\b/ },
  { id: "mac_temp_path", pattern: /\/var\/folders\/|\/private\/var\/folders\// },
  { id: "openai_key", pattern: /sk-[A-Za-z0-9_-]{20,}/ },
  { id: "github_token", pattern: /gh[pousr]_[A-Za-z0-9_]{20,}/ },
  { id: "private_key", pattern: /BEGIN (?:OPENSSH|RSA|EC|DSA) PRIVATE KEY/ }
] as const;

export function inspectPackageArtifact(options: { target: PackageInspectionTarget }): PackageInspectionResult {
  const prepared = prepareInspectionTarget(options.target);
  const skipInstalledDependencies = prepared.inspectionTarget.kind === "installed_root";
  const entries = listPackageEntries(prepared.root, { skipNodeModules: skipInstalledDependencies });
  const requiredPaths = REQUIRED_PACKAGE_PATHS.map((path) => ({
    path,
    status: existsSync(join(prepared.root, path)) ? "present" as const : "missing" as const
  }));
  const manifestReferences = packageManifestReferences(prepared.root);
  const binEntrypoints = packageBinEntrypoints(prepared.root);
  const filesAllowlist = packageFilesAllowlist(prepared.root);
  const forbiddenPaths = packageForbiddenPaths(entries, filesAllowlist.files);
  const forbiddenText = scanForbiddenText(prepared.root, { skipNodeModules: skipInstalledDependencies });
  const installedSmoke = prepared.inspectionTarget.kind === "installed_root"
    ? runInstalledPackageSmoke({ installedRoot: prepared.root })
    : undefined;
  const diagnostics = [
    ...requiredPaths
      .filter((item) => item.status === "missing")
      .map((item) => diagnostic("package.required_path_missing", `Missing package path '${item.path}'.`, item.path)),
    ...manifestReferences
      .filter((item) => item.status !== "resolved")
      .map((item) => diagnostic("package.manifest_reference_unresolved", `Manifest reference '${item.target}' from '${item.from}' is not resolved.`, item.target)),
    ...binEntrypoints
      .filter((item) => item.status !== "present")
      .map((item) => diagnostic("package.bin_missing", `Package bin '${item.name}' does not resolve to '${item.path}'.`, item.path)),
    ...binEntrypoints
      .filter((item) => item.status === "present" && !item.executable)
      .map((item) => diagnostic("package.bin_not_executable", `Package bin '${item.name}' is not executable.`, item.path)),
    ...binEntrypoints
      .filter((item) => item.status === "present" && !item.shebang)
      .map((item) => diagnostic("package.bin_shebang_missing", `Package bin '${item.name}' is missing a node shebang.`, item.path)),
    ...filesAllowlist.diagnostics,
    ...forbiddenPaths.map((path) => diagnostic("package.forbidden_path", `Forbidden package path '${path}' is present or allowlisted.`, path)),
    ...forbiddenText.map((hit) => diagnostic("package.forbidden_text", `Forbidden text pattern '${hit.pattern}' found in '${hit.path}'.`, hit.path)),
    ...smokeDiagnostics(installedSmoke)
  ];
  return {
    schema_version: 1,
    complete: diagnostics.length === 0,
    inspection_target: prepared.inspectionTarget,
    package_entries: entries,
    required_paths: requiredPaths,
    manifest_references: manifestReferences,
    bin_entrypoints: binEntrypoints,
    files_allowlist: filesAllowlist.files,
    forbidden_paths: forbiddenPaths,
    forbidden_text: forbiddenText,
    ...(installedSmoke ? { installed_smoke: installedSmoke } : {}),
    diagnostics
  };
}

export function runInstalledPackageSmoke(options: { installedRoot: string }): PackageSmokeResult {
  const cliPath = join(options.installedRoot, "packages/cli/dist/index.js");
  const mcpPath = join(options.installedRoot, "packages/mcp/dist/index.js");
  const cli = spawnSync(process.execPath, [cliPath, "schema", "list", "--json"], {
    cwd: options.installedRoot,
    encoding: "utf8",
    timeout: 10_000
  });
  const mcpInput = [
    JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2024-11-05",
        capabilities: {},
        clientInfo: { name: "package-doctor", version: "0.0.0" }
      }
    }),
    JSON.stringify({ jsonrpc: "2.0", id: 2, method: "tools/list", params: {} }),
    ""
  ].join("\n");
  const mcp = spawnSync(process.execPath, [mcpPath], {
    cwd: options.installedRoot,
    input: mcpInput,
    encoding: "utf8",
    timeout: 10_000
  });
  return {
    cli: smokeCheck(`${process.execPath} ${cliPath} schema list --json`, cli, cli.status === 0 && cli.stdout.includes("schema.list")),
    mcp: smokeCheck(`${process.execPath} ${mcpPath}`, mcp, mcp.status === 0 && mcp.stdout.includes("tools") && mcp.stdout.includes("matrix_validate"))
  };
}

function prepareInspectionTarget(target: PackageInspectionTarget): {
  root: string;
  inspectionTarget: PackageInspectionResult["inspection_target"];
} {
  if (target.kind === "installed_root") {
    return {
      root: resolve(target.path),
      inspectionTarget: { kind: "installed_root", path: resolve(target.path) }
    };
  }
  if (target.kind === "tarball") {
    const tarball = resolve(target.path);
    return {
      root: extractTarball(tarball),
      inspectionTarget: { kind: "tarball", path: tarball }
    };
  }

  const workspace = resolve(target.path);
  if (target.build) {
    requireCommandSuccess(spawnSync("corepack", ["pnpm", "build"], {
      cwd: workspace,
      encoding: "utf8",
      env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
    }), "corepack pnpm build");
  }
  const packDir = mkdtempSync(join(tmpdir(), "use-case-matrix-doctor-pack-"));
  const pack = spawnSync("corepack", ["pnpm", "pack", "--json", "--pack-destination", packDir], {
    cwd: workspace,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
  requireCommandSuccess(pack, "corepack pnpm pack --json");
  const payload = JSON.parse(pack.stdout) as { filename: string };
  return {
    root: extractTarball(payload.filename),
    inspectionTarget: { kind: "tarball", path: payload.filename, source_workspace: workspace }
  };
}

function listPackageEntries(root: string, options: { skipNodeModules: boolean }): string[] {
  return listFiles(root, options).map((path) => normalizePackagePath(relative(root, path))).sort();
}

function extractTarball(tarball: string): string {
  const extractDir = mkdtempSync(join(tmpdir(), "use-case-matrix-doctor-extract-"));
  const result = spawnSync("tar", ["-xzf", tarball, "-C", extractDir], { encoding: "utf8" });
  requireCommandSuccess(result, `tar -xzf ${tarball}`);
  const packageRoot = join(extractDir, "package");
  if (!existsSync(packageRoot)) {
    throw new Error(`Package tarball did not contain a package/ root: ${tarball}`);
  }
  return packageRoot;
}

function packageManifestReferences(root: string): PackageManifestReference[] {
  const references: PackageManifestReference[] = [];
  for (const from of [".codex-plugin/plugin.json", ".claude-plugin/plugin.json", "plugin.json"] as const) {
    const manifestPath = join(root, from);
    if (!existsSync(manifestPath)) {
      continue;
    }
    const manifest = readJson(manifestPath) as {
      mcpServers?: string | Record<string, { args?: string[] }>;
    };
    if (manifest.mcpServers) {
      references.push(...manifestMcpReferences(root, from, manifest.mcpServers));
    }
  }
  const mcpPath = join(root, ".mcp.json");
  if (existsSync(mcpPath)) {
    const mcp = readJson(mcpPath) as { mcpServers?: Record<string, { args?: string[] }> };
    const server = mcp.mcpServers?.["use-case-matrix"];
    const target = resolvePackagedReference(root, ".mcp.json", server?.args?.[0] ?? "");
    references.push({
      from: ".mcp.json",
      target,
      status: target && existsSync(join(root, target)) ? "resolved" : "missing"
    });
  }
  return references;
}

function manifestMcpReferences(
  root: string,
  from: string,
  value: string | Record<string, { args?: string[] }>
): PackageManifestReference[] {
  if (typeof value === "string") {
    const target = resolvePackagedReference(root, from, value);
    return [{
      from,
      target,
      status: target && existsSync(join(root, target)) ? "resolved" : "missing"
    }];
  }
  return Object.values(value).flatMap((server) => {
    const arg = server.args?.[0];
    if (!arg || !arg.startsWith(".")) {
      return [];
    }
    const target = resolvePackagedReference(root, from, arg);
    return [{
      from,
      target,
      status: target && existsSync(join(root, target)) ? "resolved" as const : "missing" as const
    }];
  });
}

function resolvePackagedReference(root: string, from: string, value: string): string {
  const candidates = [
    normalizePackagePath(value),
    normalizePackagePath(join(dirname(from), value))
  ].filter((candidate) => candidate && !candidate.startsWith("../") && candidate !== "..");
  return candidates.find((candidate) => existsSync(join(root, candidate))) ?? candidates[0] ?? "";
}

function packageBinEntrypoints(root: string): PackageBinEntrypoint[] {
  return ["packages/cli/package.json", "packages/mcp/package.json"].flatMap((manifestPath) => {
    const packageJson = readJson(join(root, manifestPath)) as { bin?: Record<string, string> };
    return Object.entries(packageJson.bin ?? {}).map(([name, value]) => {
      const path = normalizePackagePath(join(dirname(manifestPath), value));
      const fullPath = join(root, path);
      return {
        name,
        path,
        status: existsSync(fullPath) ? "present" as const : "missing" as const,
        executable: hasExecutableBit(fullPath),
        shebang: hasNodeShebang(fullPath)
      };
    });
  });
}

function packageFilesAllowlist(root: string): { files: string[]; diagnostics: Diagnostic[] } {
  const packageJson = readJson(join(root, "package.json")) as { files?: unknown };
  if (!Array.isArray(packageJson.files) || !packageJson.files.every((item) => typeof item === "string")) {
    return {
      files: [],
      diagnostics: [diagnostic("package.files_allowlist_missing", "package.json must declare a files allowlist.", "package.json")]
    };
  }
  return {
    files: packageJson.files.map((item) => normalizePackagePath(item)),
    diagnostics: []
  };
}

function packageForbiddenPaths(entries: string[], filesAllowlist: string[]): string[] {
  const forbidden = new Set<string>();
  for (const value of [...entries, ...filesAllowlist]) {
    if (containsForbiddenSegment(value)) {
      forbidden.add(value);
    }
  }
  return Array.from(forbidden).sort();
}

function scanForbiddenText(root: string, options: { skipNodeModules: boolean }): Array<{ path: string; pattern: string }> {
  const hits: Array<{ path: string; pattern: string }> = [];
  for (const file of listFiles(root, options)) {
    if (!isTextFile(file)) {
      continue;
    }
    const rel = normalizePackagePath(relative(root, file));
    const text = readFileSync(file, "utf8");
    for (const forbidden of FORBIDDEN_TEXT_PATTERNS) {
      if (forbidden.pattern.test(text)) {
        hits.push({ path: rel, pattern: forbidden.id });
      }
    }
  }
  return hits;
}

function listFiles(root: string, options: { skipNodeModules: boolean }): string[] {
  const stat = statSync(root);
  if (!stat.isDirectory()) {
    return [root];
  }
  return readdirSync(root).flatMap((entry) => {
    if (options.skipNodeModules && entry === "node_modules") {
      return [];
    }
    return listFiles(join(root, entry), options);
  });
}

function isTextFile(path: string): boolean {
  return /\.(?:cjs|js|json|map|md|mjs|txt|yml|yaml)$/.test(basename(path));
}

function containsForbiddenSegment(path: string): boolean {
  const parts = path.split(/[\\/]/);
  const underExamples = parts.includes("examples");
  return FORBIDDEN_PACKAGE_SEGMENTS.some((segment) => {
    if (underExamples && EXAMPLE_CONTENT_SEGMENTS.has(segment)) {
      return false;
    }
    return parts.includes(segment);
  });
}

function normalizePackagePath(path: string): string {
  return path.replaceAll("\\", "/").replace(/^\.\//, "");
}

function readJson(path: string): unknown {
  return JSON.parse(readFileSync(path, "utf8"));
}

function hasExecutableBit(path: string): boolean {
  try {
    accessSync(path, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function hasNodeShebang(path: string): boolean {
  if (!existsSync(path)) {
    return false;
  }
  return readFileSync(path, "utf8").startsWith("#!/usr/bin/env node");
}

function smokeCheck(command: string, result: ReturnType<typeof spawnSync>, passed: boolean): PackageSmokeCheck {
  return {
    status: passed ? "passed" : "failed",
    command,
    exit_code: result.status ?? null,
    stdout: trimOutput(result.stdout),
    stderr: trimOutput(result.stderr)
  };
}

function smokeDiagnostics(smoke: PackageSmokeResult | undefined): Diagnostic[] {
  if (!smoke) {
    return [];
  }
  return (Object.entries(smoke) as Array<[keyof PackageSmokeResult, PackageSmokeCheck]>)
    .filter(([, check]) => check.status !== "passed")
    .map(([name, check]) => diagnostic("package.installed_smoke_failed", `Installed ${name} smoke failed.`, check.command));
}

function trimOutput(value: string | Buffer | null | undefined): string | undefined {
  const text = typeof value === "string" ? value : value?.toString("utf8");
  const trimmed = text?.trim();
  return trimmed ? trimmed.slice(0, 2_000) : undefined;
}

function requireCommandSuccess(result: ReturnType<typeof spawnSync>, command: string): void {
  if (result.status !== 0) {
    throw new Error([
      `${command} failed with status ${result.status}`,
      `stdout:\n${trimOutput(result.stdout) ?? ""}`,
      `stderr:\n${trimOutput(result.stderr) ?? ""}`
    ].join("\n"));
  }
}
