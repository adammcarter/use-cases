import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { beforeAll, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../../..");

beforeAll(() => {
  const result = spawnSync("corepack", ["pnpm", "build"], {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
  if (result.status !== 0) {
    throw new Error(result.stderr || result.stdout);
  }
}, 30_000);

describe("P14 demo capsule live runner", () => {
  test("runs static capsule text as prompts, not performed proof", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const result = runCli([
      "capsule",
      "run",
      "--repo",
      workspaceRoot,
      "--capsule",
      "capsule.showcase.golden",
      "--json"
    ]);

    expect(result.status).toBe(0);
    const payload = JSON.parse(result.stdout);
    expect(payload).toMatchObject({
      command: "capsule.run",
      ok: true,
      complete: false,
      data: {
        outcome: "performed",
        capsule_id: "capsule.showcase.golden",
        pending_steps: [expect.objectContaining({ reason: "runtime_observation_required" })],
        status: {
          execution_status: "running",
          run_outcome: "incomplete",
          approval_state: "pending"
        }
      }
    });

    const events = readRunEvents(workspaceRoot, payload.data.run_id);
    expect(events.map((event) => event.event_type)).toEqual([
      "run_started",
      "action_recorded",
      "action_recorded"
    ]);
  });

  test("reports command steps as pending unless command execution is explicitly enabled", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    writeCapsule(workspaceRoot, "pending-command.yml", commandCapsule({
      capsuleId: "capsule.command.pending",
      commandExecution: true,
      expectedExitCodes: [0],
      code: "require('fs').writeFileSync('command-ran.txt', 'yes')"
    }));

    const result = runCli([
      "capsule",
      "run",
      "--repo",
      workspaceRoot,
      "--capsule",
      "capsule.command.pending",
      "--json"
    ]);

    expect(result.status).toBe(0);
    const payload = JSON.parse(result.stdout);
    expect(payload).toMatchObject({
      command: "capsule.run",
      ok: true,
      complete: false,
      data: {
        outcome: "performed",
        pending_steps: [expect.objectContaining({ reason: "command_execution_not_requested" })],
        command_results: [],
        status: {
          execution_status: "running",
          run_outcome: "incomplete"
        }
      }
    });
    expect(existsSync(join(workspaceRoot, "command-ran.txt"))).toBe(false);
  });

  test("executes permitted command steps without a shell and records passing verdicts", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    writeCapsule(workspaceRoot, "safe-command.yml", commandCapsule({
      capsuleId: "capsule.command.safe",
      commandExecution: true,
      expectedExitCodes: [0],
      code: [
        "const fs = require('fs');",
        "fs.writeFileSync('argv.json', JSON.stringify(process.argv.slice(1)));"
      ].join(" "),
      extraArg: "literal && touch shell-pwned.txt"
    }));

    const result = runCli([
      "capsule",
      "run",
      "--repo",
      workspaceRoot,
      "--capsule",
      "capsule.command.safe",
      "--execute-commands",
      "--json"
    ]);

    expect(result.status).toBe(0);
    const payload = JSON.parse(result.stdout);
    expect(payload).toMatchObject({
      command: "capsule.run",
      ok: true,
      complete: true,
      data: {
        outcome: "performed",
        pending_steps: [],
        command_results: [expect.objectContaining({ exit_code: 0, matched_expected_exit_code: true })],
        status: {
          execution_status: "completed",
          run_outcome: "passed"
        }
      }
    });
    expect(JSON.parse(readFileSync(join(workspaceRoot, "argv.json"), "utf8"))).toEqual([
      "literal && touch shell-pwned.txt"
    ]);
    expect(existsSync(join(workspaceRoot, "shell-pwned.txt"))).toBe(false);
  });

  test("does not re-execute command side effects on an idempotent retry", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    writeFileSync(join(workspaceRoot, "counter.txt"), "0");
    writeCapsule(workspaceRoot, "idempotent-command.yml", commandCapsule({
      capsuleId: "capsule.command.idempotent",
      commandExecution: true,
      expectedExitCodes: [0],
      code: [
        "const fs = require('fs');",
        "const current = Number(fs.readFileSync('counter.txt', 'utf8'));",
        "fs.writeFileSync('counter.txt', String(current + 1));"
      ].join(" ")
    }));

    const args = [
      "capsule",
      "run",
      "--repo",
      workspaceRoot,
      "--capsule",
      "capsule.command.idempotent",
      "--execute-commands",
      "--idempotency-key",
      "p14:idempotent",
      "--json"
    ];

    expect(runCli(args).status).toBe(0);
    expect(runCli(args).status).toBe(0);
    expect(readFileSync(join(workspaceRoot, "counter.txt"), "utf8")).toBe("1");
  });

  test("records failed command verdicts and leaves the run unfinished for decide/fix flow", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    writeCapsule(workspaceRoot, "failing-command.yml", commandCapsule({
      capsuleId: "capsule.command.fail",
      commandExecution: true,
      expectedExitCodes: [0],
      code: "process.exit(2)"
    }));

    const result = runCli([
      "capsule",
      "run",
      "--repo",
      workspaceRoot,
      "--capsule",
      "capsule.command.fail",
      "--execute-commands",
      "--json"
    ]);

    expect(result.status).toBe(1);
    const payload = JSON.parse(result.stdout);
    expect(payload).toMatchObject({
      command: "capsule.run",
      ok: true,
      complete: false,
      data: {
        outcome: "performed",
        command_results: [expect.objectContaining({ exit_code: 2, matched_expected_exit_code: false })],
        status: {
          execution_status: "running",
          run_outcome: "failed",
          unresolved_failure_count: 1
        }
      }
    });
    const events = readRunEvents(workspaceRoot, payload.data.run_id);
    expect(events.map((event) => event.event_type)).toContain("verdict_recorded");
    expect(events.map((event) => event.event_type)).not.toContain("run_finished");
  });

  test("blocks command execution when permission or cwd safety is missing", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    writeCapsule(workspaceRoot, "not-permitted.yml", commandCapsule({
      capsuleId: "capsule.command.not_permitted",
      commandExecution: false,
      expectedExitCodes: [0],
      code: "require('fs').writeFileSync('should-not-run.txt', 'yes')"
    }));
    writeCapsule(workspaceRoot, "cwd-escape.yml", commandCapsule({
      capsuleId: "capsule.command.cwd_escape",
      commandExecution: true,
      expectedExitCodes: [0],
      workingDirectory: "../outside",
      code: "require('fs').writeFileSync('should-not-run.txt', 'yes')"
    }));

    const notPermitted = runCli([
      "capsule",
      "run",
      "--repo",
      workspaceRoot,
      "--capsule",
      "capsule.command.not_permitted",
      "--execute-commands",
      "--json"
    ]);
    expect(notPermitted.status).toBe(1);
    expect(JSON.parse(notPermitted.stdout)).toMatchObject({
      command: "capsule.run",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "capsule.command_execution_not_permitted" })]
    });

    const cwdEscape = runCli([
      "capsule",
      "run",
      "--repo",
      workspaceRoot,
      "--capsule",
      "capsule.command.cwd_escape",
      "--execute-commands",
      "--json"
    ]);
    expect(cwdEscape.status).toBe(4);
    expect(JSON.parse(cwdEscape.stdout)).toMatchObject({
      command: "capsule.run",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "capsule.command_cwd_escape" })]
    });
    expect(existsSync(join(workspaceRoot, "should-not-run.txt"))).toBe(false);
  });

  test("runs commands with sanitized env, redacted output, bounded output, and validated timeout", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    writeCapsule(workspaceRoot, "env-redaction.yml", commandCapsule({
      capsuleId: "capsule.command.env_redaction",
      commandExecution: true,
      expectedExitCodes: [0],
      code: [
        "process.stdout.write('SECRET=' + (process.env.PRESENTATION_SKILLS_SECRET || 'missing') + '\\n');",
        "process.stdout.write('sk-testsecret1234567890\\n');",
        "process.stdout.write('x'.repeat(20000));",
        "process.stderr.write('token=abc123secret\\n');"
      ].join(" ")
    }));
    process.env.PRESENTATION_SKILLS_SECRET = "super-secret-value";
    try {
      const result = runCli([
        "capsule",
        "run",
        "--repo",
        workspaceRoot,
        "--capsule",
        "capsule.command.env_redaction",
        "--execute-commands",
        "--json"
      ]);
      expect(result.status).toBe(0);
      const commandResult = JSON.parse(result.stdout).data.command_results[0];
      expect(commandResult.stdout).not.toContain("super-secret-value");
      expect(commandResult.stdout).not.toContain("sk-testsecret1234567890");
      expect(commandResult.stderr).not.toContain("abc123secret");
      expect(commandResult.stdout).toContain("[redacted]");
      expect(commandResult.stdout).toContain("[truncated]");
      expect(commandResult.stdout.length).toBeLessThan(17_000);
    } finally {
      delete process.env.PRESENTATION_SKILLS_SECRET;
    }

    const invalidTimeout = runCli([
      "capsule",
      "run",
      "--repo",
      workspaceRoot,
      "--capsule",
      "capsule.command.env_redaction",
      "--execute-commands",
      "--command-timeout-ms",
      "0",
      "--json"
    ]);
    expect(invalidTimeout.status).toBe(1);
    expect(JSON.parse(invalidTimeout.stdout)).toMatchObject({
      command: "capsule.run",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "capsule.command_timeout_invalid" })]
    });
  });
});

function runCli(args: string[]) {
  return spawnSync("node", ["packages/cli/dist/index.js", ...args], {
    cwd: repoRoot,
    encoding: "utf8"
  });
}

function fixtureWorkspace(name: string): string {
  const workspaceRoot = mkdtempSync(join(tmpdir(), `use-case-matrix-capsule-${name}-`));
  cpSync(join(repoRoot, "tests/fixtures/workspaces", name), workspaceRoot, { recursive: true });
  return workspaceRoot;
}

function writeCapsule(workspaceRoot: string, fileName: string, source: string): void {
  mkdirSync(join(workspaceRoot, "demo-capsules"), { recursive: true });
  writeFileSync(join(workspaceRoot, "demo-capsules", fileName), source);
}

function commandCapsule(options: {
  capsuleId: string;
  commandExecution: boolean;
  expectedExitCodes: number[];
  code: string;
  extraArg?: string;
  workingDirectory?: string;
}): string {
  const argv = ["-e", options.code, ...(options.extraArg ? [options.extraArg] : [])];
  return [
    "schema_version: 1",
    `capsule_id: ${options.capsuleId}`,
    "title: Command capsule",
    "mode: showcase",
    "description: Exercise command execution.",
    "audience: reviewer",
    "timebox_seconds: 600",
    "items:",
    "  - use_case_id: showcase.live.golden",
    "    scenario_ids: [showcase.live.golden.cli]",
    "    runbook:",
    "      - kind: instruction",
    "        text: Run the command-backed step.",
    "      - kind: command",
    `        executable: ${JSON.stringify(process.execPath)}`,
    `        argv: ${JSON.stringify(argv)}`,
    `        working_directory: ${JSON.stringify(options.workingDirectory ?? ".")}`,
    `        expected_exit_codes: ${JSON.stringify(options.expectedExitCodes)}`,
    "permissions:",
    `  command_execution: ${options.commandExecution}`
  ].join("\n");
}

function readRunEvents(workspaceRoot: string, runId: string): Array<{ event_type: string }> {
  return readFileSync(join(workspaceRoot, "showcase-runs", runId, "events.jsonl"), "utf8")
    .trim()
    .split("\n")
    .map((line) => JSON.parse(line) as { event_type: string });
}
