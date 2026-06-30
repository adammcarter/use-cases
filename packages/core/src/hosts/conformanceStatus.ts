import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { delimiter, join } from "node:path";
import { diagnostic, type Diagnostic } from "../schema/index.js";
import type { HostExecutableSmoke, HostProfile, HostSupportStatus } from "./types.js";

export type HostConformanceDerivation = {
  ok: boolean;
  complete: boolean;
  support_status: HostSupportStatus;
  diagnostics: Diagnostic[];
};

export function deriveHostConformance(input: {
  profile: HostProfile;
  staticConformant: boolean;
  evidenceEventIds: string[];
  executableSmoke: HostExecutableSmoke;
}): HostConformanceDerivation {
  const diagnostics = diagnosticsForExecutableSmoke(input.profile, input.executableSmoke);
  const hasBlockingDiagnostic = diagnostics.some((item) => item.severity === "error");
  return {
    ok: !hasBlockingDiagnostic,
    complete: !hasBlockingDiagnostic,
    support_status: supportStatus({
      staticConformant: input.staticConformant,
      evidenceEventIds: input.evidenceEventIds,
      executableSmoke: input.executableSmoke
    }),
    diagnostics
  };
}

export function runExecutableSmoke(profile: HostProfile): HostExecutableSmoke {
  const command = smokeCommand(profile.host);
  const resolved = resolveExecutable(command.executable);
  if (!resolved) {
    return {
      status: "not_run",
      executable: command.executable,
      argv: command.argv,
      reason_code: "executable_not_found",
      reason: `Executable '${command.label}' not found on PATH; host smoke was not run.`,
      exit_code: null
    };
  }

  const result = spawnSync(resolved, command.argv, {
    encoding: "utf8",
    timeout: 5_000
  });
  if (result.error) {
    if (isTimeoutError(result.error)) {
      return {
        status: "not_run",
        executable: command.executable,
        argv: command.argv,
        reason_code: "executable_timeout",
        reason: `Executable '${command.label}' did not respond within the smoke timeout; host smoke was not run to completion.`,
        exit_code: result.status ?? null,
        stdout: trimOutput(result.stdout),
        stderr: trimOutput(result.stderr)
      };
    }
    return {
      status: "failed",
      executable: command.executable,
      argv: command.argv,
      reason_code: "executable_run_error",
      reason: `Executable '${command.label}' failed to run: ${result.error.message}`,
      exit_code: result.status ?? null,
      stdout: trimOutput(result.stdout),
      stderr: trimOutput(result.stderr)
    };
  }
  if (result.status === null) {
    const detail = result.signal ? `terminated by signal ${result.signal}` : "exited without a status";
    return {
      status: "not_run",
      executable: command.executable,
      argv: command.argv,
      reason_code: "executable_unavailable",
      reason: `Executable '${command.label}' is unavailable: ${detail}.`,
      exit_code: null,
      stdout: trimOutput(result.stdout),
      stderr: trimOutput(result.stderr)
    };
  }
  if (result.status !== 0 && unavailableOutput(result.stdout, result.stderr)) {
    return {
      status: "not_run",
      executable: command.executable,
      argv: command.argv,
      reason_code: "executable_unavailable",
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
      reason_code: "nonzero_exit",
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
    reason_code: "ok",
    reason: `Executable '${command.label}' responded to the smoke command.`,
    exit_code: 0,
    stdout: trimOutput(result.stdout),
    stderr: trimOutput(result.stderr)
  };
}

function supportStatus(input: {
  staticConformant: boolean;
  evidenceEventIds: string[];
  executableSmoke: HostExecutableSmoke;
}): HostSupportStatus {
  if (input.executableSmoke.status === "failed") {
    return "blocked";
  }
  if (input.evidenceEventIds.length > 0) {
    return input.staticConformant ? "verified_with_evidence" : "partial_with_evidence";
  }
  return input.staticConformant ? "conformant_static" : "not_tested";
}

function diagnosticsForExecutableSmoke(profile: HostProfile, smoke: HostExecutableSmoke): Diagnostic[] {
  if (smoke.status === "passed") {
    return [];
  }
  if (smoke.status === "failed") {
    return [diagnostic("host.executable_smoke_failed", smoke.reason, profile.profile_id)];
  }
  const code =
    smoke.reason_code === "executable_unavailable"
      ? "host.executable_unavailable"
      : smoke.reason_code === "executable_timeout"
        ? "host.executable_timeout"
        : "host.executable_not_found";
  return [{ ...diagnostic(code, smoke.reason, profile.profile_id), severity: "warning" }];
}

function isTimeoutError(error: Error): boolean {
  return (error as NodeJS.ErrnoException).code === "ETIMEDOUT";
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
