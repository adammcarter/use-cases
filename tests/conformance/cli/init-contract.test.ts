// `uc init` contract test (public-v1 Phase 5 onboarding).
//
// Proves the new scaffolding command takes a brand-new repo from nothing to a
// bindable, verifiable Use Case Matrix workspace in ONE command:
//   1. `uc init` writes a workspace config + an example matrix file, and the
//      scaffolded workspace IMMEDIATELY passes `uc matrix validate`.
//   2. Each --template (generic | js-vitest | python-pytest | go-test) writes the
//      matching `verifiers.default`.
//   3. The generated config + use-case file validate against their v1 schemas.
//   4. Safety: re-running without --force REFUSES (stable error, proper envelope,
//      non-zero exit) and does not clobber; --force overwrites.
//   5. The emitted envelope is a valid `init` result envelope, with --json parity.
//
// Runs the BUILT CLI against fresh temp dirs so it is hermetic and repeatable.

import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { parseYamlToJson, validateBySchemaId } from "../../../packages/core/src/schema/index.js";

const repoRoot = resolve(import.meta.dirname, "../../..");
const ENVELOPE_SCHEMA_ID = "https://use-cases.dev/schemas/v1/cli-result.schema.json";
const WORKSPACE_CONFIG_SCHEMA_ID = "https://use-cases.dev/schemas/v1/workspace-config.schema.json";
const USE_CASE_FILE_SCHEMA_ID = "https://use-cases.dev/schemas/v1/use-case-file.schema.json";

const tempDirs: string[] = [];

function freshRepo(label: string): string {
  const dir = mkdtempSync(join(tmpdir(), `ucm-init-${label}-`));
  tempDirs.push(dir);
  return dir;
}

function runCli(args: string[]) {
  return spawnSync("node", ["packages/cli/dist/index.js", ...args], {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
}

function parseEnvelope(stdout: string): { command: string; ok: boolean; complete: boolean; data: Record<string, unknown> } {
  const payload = JSON.parse(stdout);
  const envelope = validateBySchemaId(ENVELOPE_SCHEMA_ID, payload);
  expect(envelope, `envelope diagnostics ${JSON.stringify(envelope.diagnostics)}`).toMatchObject({ ok: true, diagnostics: [] });
  return payload;
}

function readConfig(repoDir: string): Record<string, unknown> {
  const source = readFileSync(join(repoDir, "use-cases.yml"), "utf8");
  const parsed = parseYamlToJson(source, "use-cases.yml");
  expect(parsed.ok, `config did not parse: ${JSON.stringify(parsed)}`).toBe(true);
  return parsed.value as Record<string, unknown>;
}

beforeAll(() => {
  const build = spawnSync("corepack", ["pnpm", "build"], {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
  if (build.status !== 0) {
    throw new Error(build.stderr || build.stdout);
  }
}, 180_000);

afterAll(() => {
  for (const dir of tempDirs.splice(0)) {
    try {
      rmSync(dir, { recursive: true, force: true });
    } catch {
      /* ignore */
    }
  }
});

describe("uc init", () => {
  test("scaffolds a workspace that immediately passes matrix validate", () => {
    const repo = freshRepo("validate");
    const init = runCli(["init", "--repo", repo, "--json"]);
    expect(init.status, init.stderr).toBe(0);
    const payload = parseEnvelope(init.stdout);
    expect(payload.command).toBe("init");
    expect(payload.ok).toBe(true);
    expect(payload.data).toMatchObject({ status: "created", template: "generic" });
    const created = payload.data.created_files as string[];
    expect(created).toContain("use-cases.yml");
    expect(created.some((p) => p.startsWith("use-cases/"))).toBe(true);
    expect((payload.data.next_steps as string[]).length).toBeGreaterThan(0);

    // The whole point: the scaffolded workspace is valid + complete out of the box.
    const validate = runCli(["matrix", "validate", "--repo", repo, "--json"]);
    expect(validate.status, validate.stderr).toBe(0);
    const validatePayload = JSON.parse(validate.stdout);
    expect(validatePayload).toMatchObject({ command: "matrix.validate", ok: true, complete: true });
  });

  test("generated config and use-case file validate against their v1 schemas", () => {
    const repo = freshRepo("schemas");
    expect(runCli(["init", "--repo", repo, "--json"]).status).toBe(0);

    const config = readConfig(repo);
    const configValidation = validateBySchemaId(WORKSPACE_CONFIG_SCHEMA_ID, config);
    expect(configValidation, JSON.stringify(configValidation.diagnostics)).toMatchObject({ ok: true, diagnostics: [] });

    const payload = parseEnvelope(runCli(["init", "--repo", freshRepo("schemas2"), "--json"]).stdout);
    const useCaseRel = (payload.data.created_files as string[]).find((p) => p.startsWith("use-cases/"));
    expect(useCaseRel).toBeDefined();
    // Re-init the first repo's use-case file path to read it back.
    const useCaseSource = readFileSync(join(repo, useCaseRel as string), "utf8");
    const parsed = parseYamlToJson(useCaseSource, useCaseRel as string);
    expect(parsed.ok).toBe(true);
    const useCaseValidation = validateBySchemaId(USE_CASE_FILE_SCHEMA_ID, parsed.value);
    expect(useCaseValidation, JSON.stringify(useCaseValidation.diagnostics)).toMatchObject({ ok: true, diagnostics: [] });
  });

  test("derives a sane component id from the repo directory name", () => {
    const repo = freshRepo("My_Cool.Project");
    expect(runCli(["init", "--repo", repo, "--json"]).status).toBe(0);
    const config = readConfig(repo);
    expect(typeof config.component_id).toBe("string");
    // Canonical id: lowercase, no separators that would break path/id rules.
    expect(config.component_id as string).toMatch(/^[a-z0-9][a-z0-9_-]*(?:\.[a-z0-9][a-z0-9_-]*)*$/);
  });

  test("honours an explicit --component id", () => {
    const repo = freshRepo("component");
    expect(runCli(["init", "--repo", repo, "--component", "billing-service", "--json"]).status).toBe(0);
    const config = readConfig(repo);
    expect(config.component_id).toBe("billing-service");
  });

  const templateCases: Array<{ template: string; expectVerifier: Record<string, unknown> }> = [
    { template: "js-vitest", expectVerifier: { preset: "js.vitest" } },
    { template: "python-pytest", expectVerifier: { preset: "python.pytest" } },
    { template: "go-test", expectVerifier: { preset: "go.test" } }
  ];

  test.each(templateCases)("--template $template writes the matching default verifier", ({ template, expectVerifier }) => {
    const repo = freshRepo(template);
    const init = runCli(["init", "--repo", repo, "--template", template, "--json"]);
    expect(init.status, init.stderr).toBe(0);
    const payload = parseEnvelope(init.stdout);
    expect(payload.data).toMatchObject({ template });

    const config = readConfig(repo);
    const verifiers = config.verifiers as Record<string, unknown>;
    const defaultId = verifiers.default as string;
    expect(defaultId).toBeTruthy();
    expect(verifiers[defaultId]).toMatchObject(expectVerifier);

    // Schema still valid + matrix still validates with a preset default verifier.
    expect(validateBySchemaId(WORKSPACE_CONFIG_SCHEMA_ID, config)).toMatchObject({ ok: true, diagnostics: [] });
    expect(runCli(["matrix", "validate", "--repo", repo, "--json"]).status).toBe(0);
  });

  test("--template generic writes a script verifier with a clearly-TODO placeholder command", () => {
    const repo = freshRepo("generic");
    expect(runCli(["init", "--repo", repo, "--template", "generic", "--json"]).status).toBe(0);
    const config = readConfig(repo);
    const verifiers = config.verifiers as Record<string, unknown>;
    const def = verifiers[verifiers.default as string] as { kind?: string; command?: string[] };
    expect(def.kind).toBe("script");
    expect(Array.isArray(def.command)).toBe(true);
    expect((def.command as string[]).join(" ").toUpperCase()).toContain("TODO");
    expect(validateBySchemaId(WORKSPACE_CONFIG_SCHEMA_ID, config)).toMatchObject({ ok: true, diagnostics: [] });
  });

  test("refuses an existing workspace without --force (stable error, non-zero, no clobber)", () => {
    const repo = freshRepo("refuse");
    expect(runCli(["init", "--repo", repo, "--component", "first-component", "--json"]).status).toBe(0);
    const firstConfig = readFileSync(join(repo, "use-cases.yml"), "utf8");

    const second = runCli(["init", "--repo", repo, "--component", "second-component", "--json"]);
    expect(second.status).not.toBe(0);
    const payload = JSON.parse(second.stdout);
    expect(payload).toMatchObject({ command: "init", ok: false, complete: false });
    expect(payload.diagnostics[0].code).toBe("init.workspace_exists");
    // Existing config is untouched.
    expect(readFileSync(join(repo, "use-cases.yml"), "utf8")).toBe(firstConfig);
  });

  test("--force overwrites an existing workspace", () => {
    const repo = freshRepo("force");
    expect(runCli(["init", "--repo", repo, "--component", "first-component", "--json"]).status).toBe(0);
    const forced = runCli(["init", "--repo", repo, "--component", "second-component", "--force", "--json"]);
    expect(forced.status, forced.stderr).toBe(0);
    const payload = parseEnvelope(forced.stdout);
    expect(payload.data).toMatchObject({ status: "created" });
    expect(readConfig(repo).component_id).toBe("second-component");
  });

  test("human (non --json) output prints the next steps", () => {
    const repo = freshRepo("human");
    const init = runCli(["init", "--repo", repo]);
    expect(init.status, init.stderr).toBe(0);
    // Onboarding steps must cite a shipped doc (never the unshipped getting-started).
    expect(init.stdout).toMatch(/docs\/(cli|markers-adoption|security)\.md/i);
    expect(init.stdout).not.toMatch(/getting-started/i);
    expect(init.stdout.toLowerCase()).toContain("next steps");
    // Still scaffolded a valid workspace.
    expect(runCli(["matrix", "validate", "--repo", repo, "--json"]).status).toBe(0);
  });
});
