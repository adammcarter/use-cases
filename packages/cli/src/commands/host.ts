import type { CliCommand, CommandOutput } from "../command/types.js";
import { valueAfter } from "../args/parse.js";
import {
  createCliResult,
  errorEnvelope,
  loadHostProfile,
  projectHostFiles,
  resolveContextOrError,
  runHostConformance as runHostConformanceCore,
  runHostDoctor as runHostDoctorCore,
  SUPPORTED_HOSTS,
  type CliEnvelope,
  type ResolvedContext
} from "../runtime.js";
import { workspaceFlags } from "./common.js";

// Non-writing port of the legacy `profileFromArgs`: read --host and load its
// profile, returning a tagged error (envelope + exit code) instead of writing.
// Mirrors the legacy exit codes exactly: missing --host is the default
// invalid-arguments exit (2), an unavailable profile is exit 1.
type ProfileResult =
  | { readonly kind: "ok"; readonly profile: NonNullable<ReturnType<typeof loadHostProfile>["profile"]> }
  | { readonly kind: "error"; readonly envelope: CliEnvelope; readonly exitCode: number };

function profileFromArgs(argv: string[], pluginRoot: string, command: string): ProfileResult {
  const host = valueAfter(argv, "--host");
  if (!host) {
    return { kind: "error", envelope: errorEnvelope(command, "host.required", "Missing --host."), exitCode: 2 };
  }
  const result = loadHostProfile({ pluginRoot, host: host as Parameters<typeof loadHostProfile>[0]["host"] });
  if (!result.profile) {
    return {
      kind: "error",
      envelope: errorEnvelope(command, "host.profile_unavailable", result.diagnostics[0]?.message ?? "Host profile unavailable."),
      exitCode: 1
    };
  }
  return { kind: "ok", profile: result.profile };
}

// Local legacy helpers, ported verbatim (pure, no I/O).
function hasBlockingHostDiagnostics(diagnostics: Array<{ severity: string }>): boolean {
  return diagnostics.some((diagnostic) => diagnostic.severity === "error");
}

function hostStaticChecksPass(checks: Array<{ id: string; result: string }>): boolean {
  const staticChecks = checks.filter(
    (check) => check.id === "projected_files_match_manifest" || check.id === "canonical_skill_hashes_match"
  );
  return staticChecks.length > 0 && staticChecks.every((check) => check.result === "pass");
}

export const hostDoctorCommand: CliCommand = {
  path: ["host", "doctor"],
  command: "host.doctor",
  summary: "Diagnose a host profile.",
  flags: [
    ...workspaceFlags,
    { key: "host", name: "--host", kind: "string", valueName: "<name>", summary: "claude | codex | copilot | opencode." }
  ],
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "host.doctor");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const profileResult = profileFromArgs(argv, context.context.plugin_root, "host.doctor");
    if (profileResult.kind === "error") {
      return { envelope: profileResult.envelope, exitCode: profileResult.exitCode };
    }
    const result = runHostDoctorCore({ context: context.context, profile: profileResult.profile });
    return {
      envelope: createCliResult("host.doctor", result, {
        ok: true,
        complete: true,
        workspaceRoot: context.context.workspace_root,
        dataRoot: context.context.data_root,
        componentId: context.context.component_id
      }),
      exitCode: 0
    };
  }
};

export const hostProjectCommand: CliCommand = {
  path: ["host", "project"],
  command: "host.project",
  summary: "Project host files (dry-run/write/revert).",
  flags: [
    ...workspaceFlags,
    { key: "host", name: "--host", kind: "string", valueName: "<name>", summary: "Host to project." },
    { key: "dryRun", name: "--dry-run", kind: "boolean", summary: "Exactly one mode." },
    { key: "write", name: "--write", kind: "boolean", summary: "Exactly one mode." },
    { key: "revert", name: "--revert", kind: "boolean", summary: "Exactly one mode." }
  ],
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "host.project");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const profileResult = profileFromArgs(argv, context.context.plugin_root, "host.project");
    if (profileResult.kind === "error") {
      return { envelope: profileResult.envelope, exitCode: profileResult.exitCode };
    }
    const selectedModes = [
      argv.includes("--dry-run") ? "dry-run" : null,
      argv.includes("--write") ? "write" : null,
      argv.includes("--revert") ? "revert" : null
    ].filter((value): value is "dry-run" | "write" | "revert" => value !== null);
    if (selectedModes.length !== 1) {
      return {
        envelope: errorEnvelope("host.project", "host.project_mode_required", "Use exactly one of --dry-run, --write, or --revert."),
        exitCode: 2
      };
    }
    const mode = selectedModes[0];
    const result = projectHostFiles({ context: context.context, profile: profileResult.profile, mode });
    return {
      envelope: createCliResult("host.project", result, {
        ok: result.complete,
        complete: result.complete,
        diagnostics: result.diagnostics,
        workspaceRoot: context.context.workspace_root,
        dataRoot: context.context.data_root,
        componentId: context.context.component_id
      }),
      exitCode: result.complete ? 0 : 1
    };
  }
};

export const hostConformanceCommand: CliCommand = {
  path: ["host", "conformance"],
  command: "host.conformance",
  summary: "Check host conformance.",
  flags: [
    ...workspaceFlags,
    { key: "host", name: "--host", kind: "string", valueName: "<name>", summary: "Host (or --all)." },
    { key: "all", name: "--all", kind: "boolean", summary: "Check every supported host." }
  ],
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "host.conformance");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    if (argv.includes("--all")) {
      return conformanceAll(context.context);
    }
    const profileResult = profileFromArgs(argv, context.context.plugin_root, "host.conformance");
    if (profileResult.kind === "error") {
      return { envelope: profileResult.envelope, exitCode: profileResult.exitCode };
    }
    const result = runHostConformanceCore({ context: context.context, profile: profileResult.profile });
    return {
      envelope: createCliResult("host.conformance", result, {
        ok: !hasBlockingHostDiagnostics(result.diagnostics),
        complete: !hasBlockingHostDiagnostics(result.diagnostics),
        diagnostics: result.diagnostics,
        workspaceRoot: context.context.workspace_root,
        dataRoot: context.context.data_root,
        componentId: context.context.component_id
      }),
      exitCode: hasBlockingHostDiagnostics(result.diagnostics) ? 1 : 0
    };
  }
};

function conformanceAll(context: ResolvedContext): CommandOutput {
  const hosts = SUPPORTED_HOSTS.map((host) => {
    const profile = loadHostProfile({ pluginRoot: context.plugin_root, host });
    if (!profile.profile) {
      return {
        schema_version: 1,
        host,
        complete: false,
        diagnostics: profile.diagnostics
      };
    }
    return runHostConformanceCore({ context, profile: profile.profile });
  });
  const diagnostics = hosts.flatMap((host) => ("diagnostics" in host ? host.diagnostics : []));
  const hasBlockingDiagnostics = diagnostics.some((diagnostic) => diagnostic.severity === "error");
  const failedExecutableSmokes = hosts.filter(
    (host) => "executable_smoke" in host && host.executable_smoke.status === "failed"
  ).length;
  const notRunExecutableSmokes = hosts.filter(
    (host) => "executable_smoke" in host && host.executable_smoke.status === "not_run"
  ).length;
  const data = {
    schema_version: 1,
    complete: !hasBlockingDiagnostics,
    hosts,
    summary: {
      total_hosts: SUPPORTED_HOSTS.length,
      static_conformant: hosts.filter((host) => "checks" in host && hostStaticChecksPass(host.checks)).length,
      executable_smoke_passed: hosts.filter(
        (host) => "executable_smoke" in host && host.executable_smoke.status === "passed"
      ).length,
      executable_smoke_failed: failedExecutableSmokes,
      executable_smoke_not_run: notRunExecutableSmokes
    }
  };
  return {
    envelope: createCliResult("host.conformance", data, {
      ok: !hasBlockingDiagnostics,
      complete: !hasBlockingDiagnostics,
      diagnostics,
      workspaceRoot: context.workspace_root,
      dataRoot: context.data_root,
      componentId: context.component_id
    }),
    exitCode: hasBlockingDiagnostics ? 1 : 0
  };
}

export const hostCommands: CliCommand[] = [hostConformanceCommand, hostProjectCommand, hostDoctorCommand];
