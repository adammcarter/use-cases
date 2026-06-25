import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { delimiter, dirname, isAbsolute, join, relative, sep } from "node:path";
import type { ResolvedWorkspaceContext } from "../roots.js";
import { computeSemanticHash, type Diagnostic } from "../schema/index.js";
import type {
  HostConformanceResult,
  HostDoctorResult,
  HostProfile,
  HostProjectionMode,
  HostProjectionOperation,
  HostProjectionResult,
  HostExecutableSmoke
} from "./types.js";

const MANAGED_MARKER = "presentation-skills:managed";
const MANIFEST_PATH = ".presentation-skills-projection.json";
const CANONICAL_SKILLS = ["use-case-matrix", "presentation-showcase", "presentation-walkthrough"];
const GENERATED_AT = "1970-01-01T00:00:00.000Z";

export function projectHostFiles(options: {
  context: ResolvedWorkspaceContext;
  profile: HostProfile;
  mode: HostProjectionMode;
}): HostProjectionResult {
  const diagnostics: Diagnostic[] = [];
  const sourceSkillHashes = readSourceSkillHashes(options.context.plugin_root);
  const generatedFiles = options.profile.projection_targets.map((target) => ({
    path: target.path,
    content: renderActivationStub(options.profile, sourceSkillHashes)
  }));
  const manifestContent = renderManifest(options.profile, sourceSkillHashes, generatedFiles);
  const allFiles = [...generatedFiles, { path: MANIFEST_PATH, content: manifestContent }];
  const operations: HostProjectionOperation[] = [];

  for (const file of allFiles) {
    const unsafeReason = unsafeProjectionPath(options.context.workspace_root, file.path);
    if (unsafeReason) {
      operations.push({ action: "refuse_unsafe_path", path: file.path, reason: unsafeReason, before_hash: null, after_hash: null });
      diagnostics.push(diagnostic("host.unsafe_projection_path", unsafeReason, file.path));
      continue;
    }

    const fullPath = join(options.context.workspace_root, file.path);
    const current = existsSync(fullPath) ? readFileSync(fullPath, "utf8") : null;
    const beforeHash = current ? computeSemanticHash(current) : null;
    const afterHash = computeSemanticHash(file.content);

    if (options.mode === "revert") {
      if (current?.includes(MANAGED_MARKER) || file.path === MANIFEST_PATH) {
        operations.push({ action: "delete_managed_on_revert", path: file.path, reason: "Managed file can be removed.", before_hash: beforeHash, after_hash: null });
        rmSync(fullPath, { force: true });
      } else {
        operations.push({ action: "skip_unchanged", path: file.path, reason: "No managed file to remove.", before_hash: beforeHash, after_hash: null });
      }
      continue;
    }

    if (current === file.content) {
      operations.push({ action: "skip_unchanged", path: file.path, reason: "Projected content already matches.", before_hash: beforeHash, after_hash: afterHash });
      continue;
    }
    if (current && !current.includes(MANAGED_MARKER) && file.path !== MANIFEST_PATH) {
      operations.push({ action: "conflict_user_modified", path: file.path, reason: "Refusing to overwrite an unmanaged file.", before_hash: beforeHash, after_hash: afterHash });
      diagnostics.push(diagnostic("host.projection_conflict", "Refusing to overwrite an unmanaged file.", file.path));
      continue;
    }
    operations.push({
      action: current ? "update_managed" : "create",
      path: file.path,
      reason: current ? "Managed projection can be updated." : "Projection file can be created.",
      before_hash: beforeHash,
      after_hash: afterHash
    });
    if (options.mode === "write") {
      mkdirSync(dirname(fullPath), { recursive: true });
      writeFileSync(fullPath, file.content);
    }
  }

  return {
    schema_version: 1,
    host: options.profile.host,
    surface: options.profile.surface,
    profile_id: options.profile.profile_id,
    mode: options.mode,
    complete: diagnostics.length === 0,
    manifest_path: MANIFEST_PATH,
    source_skill_hashes: sourceSkillHashes,
    operations,
    diagnostics
  };
}

export function runHostDoctor(options: { context: ResolvedWorkspaceContext; profile: HostProfile }): HostDoctorResult {
  const manifest = readManifest(options.context.workspace_root);
  const installed = Boolean(manifest);
  const checks = [
    {
      id: "profile_loaded",
      result: "pass" as const,
      message: "Host profile loaded as expectation data."
    },
    {
      id: "projection_manifest_present",
      result: installed ? ("pass" as const) : ("not_tested" as const),
      message: installed ? "Projection manifest is present." : "Projection has not been written."
    },
    {
      id: "projected_files_present",
      result: installed && projectedFilesMatch(options.context.workspace_root, manifest) ? ("pass" as const) : ("not_tested" as const),
      message: installed ? "Projected files were checked against the manifest." : "No projection files to check."
    }
  ];
  const staticConformant = checks.every((check) => check.result === "pass");
  return {
    schema_version: 1,
    host: options.profile.host,
    surface: options.profile.surface,
    profile_id: options.profile.profile_id,
    support_status: installed ? (staticConformant ? "projected" : "installed") : "expected",
    support: supportSummary(true, installed, staticConformant, []),
    checks,
    diagnostics: []
  };
}

export function runHostConformance(options: { context: ResolvedWorkspaceContext; profile: HostProfile }): HostConformanceResult {
  const manifest = readManifest(options.context.workspace_root);
  const manifestHash = manifest ? computeSemanticHash(manifest.raw) : null;
  const filesMatch = manifest ? projectedFilesMatch(options.context.workspace_root, manifest) : false;
  const staticChecks = [
    {
      id: "projected_files_match_manifest",
      result: filesMatch ? ("pass" as const) : manifest ? ("fail" as const) : ("not_tested" as const),
      message: filesMatch ? "Projected files match manifest hashes." : manifest ? "Projected files do not match manifest hashes." : "No projection manifest found."
    },
    {
      id: "canonical_skill_hashes_match",
      result: manifest ? ("pass" as const) : ("not_tested" as const),
      message: manifest ? "Canonical skill hashes are recorded in the manifest." : "No projection manifest found."
    }
  ];
  const executableSmoke = runExecutableSmoke(options.profile);
  const checks = [
    ...staticChecks,
    {
      id: "host_executable_smoke",
      result: executableSmoke.status === "passed" ? ("pass" as const) : executableSmoke.status === "failed" ? ("fail" as const) : ("not_tested" as const),
      message: executableSmoke.reason
    }
  ];
  const staticConformant = staticChecks.every((check) => check.result === "pass");
  return {
    schema_version: 1,
    host: options.profile.host,
    surface: options.profile.surface,
    profile_id: options.profile.profile_id,
    checked_at: GENERATED_AT,
    status_basis: "static_conformance_only",
    support_status: staticConformant ? "conformant_static" : "not_tested",
    profile_hash: computeSemanticHash(options.profile),
    projection_manifest_hash: manifestHash,
    evidence_event_ids: [],
    executable_smoke: executableSmoke,
    checks,
    diagnostics: []
  };
}

function runExecutableSmoke(profile: HostProfile): HostExecutableSmoke {
  const command = smokeCommand(profile.host);
  const resolved = resolveExecutable(command.executable);
  if (!resolved) {
    return {
      status: "not_run",
      executable: command.executable,
      argv: command.argv,
      reason: `Executable '${command.label}' not found on PATH; host smoke was not run.`,
      exit_code: null
    };
  }

  const result = spawnSync(resolved, command.argv, {
    encoding: "utf8",
    timeout: 5_000
  });
  if (result.error) {
    return {
      status: "failed",
      executable: command.executable,
      argv: command.argv,
      reason: `Executable '${command.label}' failed to run: ${result.error.message}`,
      exit_code: result.status ?? null,
      stdout: trimOutput(result.stdout),
      stderr: trimOutput(result.stderr)
    };
  }
  if (result.status !== 0 && unavailableOutput(result.stdout, result.stderr)) {
    return {
      status: "not_run",
      executable: command.executable,
      argv: command.argv,
      reason: `Executable '${command.label}' is unavailable: ${trimOutput(result.stderr) ?? trimOutput(result.stdout) ?? "not available"}.`,
      exit_code: result.status,
      stdout: trimOutput(result.stdout),
      stderr: trimOutput(result.stderr)
    };
  }
  if (result.status !== 0) {
    return {
      status: "failed",
      executable: command.executable,
      argv: command.argv,
      reason: `Executable '${command.label}' exited with status ${result.status}.`,
      exit_code: result.status,
      stdout: trimOutput(result.stdout),
      stderr: trimOutput(result.stderr)
    };
  }
  return {
    status: "passed",
    executable: command.executable,
    argv: command.argv,
    reason: `Executable '${command.label}' responded to the smoke command.`,
    exit_code: 0,
    stdout: trimOutput(result.stdout),
    stderr: trimOutput(result.stderr)
  };
}

function smokeCommand(host: HostProfile["host"]): { executable: string; argv: string[]; label: string } {
  if (host === "copilot") {
    return { executable: "gh", argv: ["copilot", "--version"], label: "gh copilot" };
  }
  return { executable: host, argv: ["--version"], label: host };
}

function resolveExecutable(executable: string): string | null {
  const path = process.env.PATH ?? "";
  for (const root of path.split(delimiter)) {
    if (!root) {
      continue;
    }
    const candidate = join(root, executable);
    if (existsSync(candidate)) {
      return candidate;
    }
  }
  return null;
}

function trimOutput(value: string | null | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed.slice(0, 1_000) : undefined;
}

function unavailableOutput(stdout: string | null | undefined, stderr: string | null | undefined): boolean {
  return /not installed|not found|unavailable|unknown command|no such file/i.test(`${stdout ?? ""}\n${stderr ?? ""}`);
}

function renderActivationStub(profile: HostProfile, sourceSkillHashes: Record<string, string>): string {
  return [
    `<!-- ${MANAGED_MARKER} host=${profile.host} profile=${profile.profile_id} -->`,
    "# Presentation Skills Host Projection",
    "",
    `Host: ${profile.host}`,
    `Surface: ${profile.surface}`,
    `Profile: ${profile.profile_id}@${profile.profile_version}`,
    "",
    "This is a generated thin activation stub. Canonical skills remain in `.agents/skills`.",
    "Generated plans, capsules, and runbooks are prepared material only until a showcase run records events.",
    "Do not claim user approval or host support without recorded evidence.",
    "",
    "Canonical skill hashes:",
    ...Object.entries(sourceSkillHashes).map(([name, hash]) => `- ${name}: ${hash}`),
    `<!-- /${MANAGED_MARKER} -->`,
    ""
  ].join("\n");
}

function renderManifest(
  profile: HostProfile,
  sourceSkillHashes: Record<string, string>,
  files: Array<{ path: string; content: string }>
): string {
  return `${JSON.stringify(
    {
      schema_version: 1,
      host: profile.host,
      surface: profile.surface,
      profile_id: profile.profile_id,
      profile_version: profile.profile_version,
      plugin_version: "0.1.0",
      source_skill_hashes: sourceSkillHashes,
      managed_marker: MANAGED_MARKER,
      created_at: GENERATED_AT,
      generated_files: files.map((file) => ({
        path: file.path,
        file_hash_before: null,
        file_hash_after: computeSemanticHash(file.content)
      }))
    },
    null,
    2
  )}\n`;
}

function readSourceSkillHashes(pluginRoot: string): Record<string, string> {
  const hashes: Record<string, string> = {};
  for (const skill of CANONICAL_SKILLS) {
    const source = readFileSync(join(pluginRoot, ".agents", "skills", skill, "SKILL.md"), "utf8");
    hashes[skill] = computeSemanticHash(source);
  }
  return hashes;
}

function unsafeProjectionPath(workspaceRoot: string, path: string): string | null {
  if (isAbsolute(path) || path.split(/[\\/]/).includes("..")) {
    return "Projection target must be a relative path inside the repository.";
  }
  const fullPath = join(workspaceRoot, path);
  const rel = relative(workspaceRoot, fullPath);
  if (rel.startsWith("..") || rel === "" || isAbsolute(rel)) {
    return "Projection target escapes the repository.";
  }
  return null;
}

function readManifest(workspaceRoot: string): ({ raw: string; generated_files: Array<{ path: string; file_hash_after: string }> } & Record<string, unknown>) | null {
  const path = join(workspaceRoot, MANIFEST_PATH);
  if (!existsSync(path)) {
    return null;
  }
  const raw = readFileSync(path, "utf8");
  return { ...(JSON.parse(raw) as Record<string, unknown>), raw } as { raw: string; generated_files: Array<{ path: string; file_hash_after: string }> } & Record<string, unknown>;
}

function projectedFilesMatch(workspaceRoot: string, manifest: { generated_files?: Array<{ path: string; file_hash_after: string }> } | null): boolean {
  if (!manifest?.generated_files?.length) {
    return false;
  }
  return manifest.generated_files.every((file) => {
    const fullPath = join(workspaceRoot, file.path);
    return existsSync(fullPath) && computeSemanticHash(readFileSync(fullPath, "utf8")) === file.file_hash_after;
  });
}

function supportSummary(
  expected: boolean,
  installed: boolean,
  staticConformant: boolean,
  evidenceEventIds: string[]
) {
  return {
    expected,
    installed,
    static_conformant: staticConformant,
    verified_with_evidence: evidenceEventIds.length > 0,
    evidence_event_ids: evidenceEventIds
  };
}

function diagnostic(code: string, message: string, sourcePath: string): Diagnostic {
  return {
    code,
    severity: "error",
    message,
    source_path: sourcePath.split(sep).join("/"),
    json_pointer: null,
    entity_id: null,
    related_ids: []
  };
}
