import { describe, expect, test } from "vitest";
import { validateBySchemaId } from "../../src/schema/index.js";

const WORKSPACE_CONFIG_SCHEMA_ID =
  "https://use-cases.dev/schemas/v1/workspace-config.schema.json";

const BASE = {
  schema_version: 1 as const,
  workspace_id: "markers.fixture",
  data_root: ".",
  use_cases_dir: "use-cases",
  evidence_dir: "evidence",
  demo_capsules_dir: "demo-capsules",
  showcase_runs_dir: "showcase-runs",
  component_id: "presentation-skills"
};

function validate(value: unknown): boolean {
  return validateBySchemaId(WORKSPACE_CONFIG_SCHEMA_ID, value).ok;
}

describe("workspace-config verifiers section", () => {
  test("a config WITHOUT a verifiers section still validates (backward compatible)", () => {
    expect(validate(BASE)).toBe(true);
  });

  test("accepts a verifiers section mapping ids to preset references plus a default", () => {
    expect(
      validate({
        ...BASE,
        verifiers: {
          default: "acceptance",
          acceptance: { preset: "js.vitest" },
          py: { preset: "python.pytest", timeout_seconds: 120 }
        }
      })
    ).toBe(true);
  });

  test("accepts an explicit script verifier entry in the verifiers section", () => {
    expect(
      validate({
        ...BASE,
        verifiers: {
          ledger_fsync: {
            kind: "script",
            evidence_kind: "test_result",
            command: ["pnpm", "-s", "vitest", "run", "test/markers/durableWrite.test.ts"],
            inputs: ["src/{slug}/x.ts"],
            timeout_seconds: 300
          }
        }
      })
    ).toBe(true);
  });

  test("accepts a verifiers section with only a default", () => {
    expect(validate({ ...BASE, verifiers: { default: "acceptance" } })).toBe(true);
  });

  test("rejects a verifier entry referencing an unknown preset", () => {
    expect(
      validate({ ...BASE, verifiers: { acceptance: { preset: "ruby.rspec" } } })
    ).toBe(false);
  });

  test("rejects a default that is not a valid id", () => {
    expect(validate({ ...BASE, verifiers: { default: "Not An Id" } })).toBe(false);
  });

  test("rejects a malformed entry (string where a verifier object is required)", () => {
    expect(validate({ ...BASE, verifiers: { acceptance: "js.vitest" } })).toBe(false);
  });

  test("rejects a script entry that omits its command", () => {
    expect(
      validate({
        ...BASE,
        verifiers: { acceptance: { kind: "script", evidence_kind: "test_result" } }
      })
    ).toBe(false);
  });
});
