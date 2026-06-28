import Ajv2020Module, { type ValidateFunction } from "ajv/dist/2020.js";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, test } from "vitest";

function verificationPolicyValidator(): ValidateFunction {
  const Ajv2020 = Ajv2020Module.default;
  const ajv = new Ajv2020({ allErrors: true, strict: true });
  const schemaPath = fileURLToPath(
    new URL("../../../../schemas/v1/common.schema.json", import.meta.url)
  );
  const schema = JSON.parse(readFileSync(schemaPath, "utf8")) as { $id: string };
  ajv.addSchema(schema);
  const validator = ajv.getSchema(`${schema.$id}#/$defs/verification_policy`);
  if (!validator) {
    throw new Error("verification_policy subschema did not compile");
  }
  return validator;
}

describe("verification_policy schema", () => {
  const validate = verificationPolicyValidator();

  test("accepts mode:none (backward compatible)", () => {
    expect(validate({ mode: "none" })).toBe(true);
  });

  test("accepts a requirements policy WITHOUT verifiers (backward compatible)", () => {
    expect(
      validate({
        mode: "requirements",
        requirements: [
          { evidence_kind: "test_result", required_verifiers: ["script"], minimum_count: 1 }
        ]
      })
    ).toBe(true);
  });

  test("accepts a requirements policy WITH a script verifier", () => {
    expect(
      validate({
        mode: "requirements",
        verifiers: {
          acceptance: {
            kind: "script",
            evidence_kind: "test_result",
            command: ["pnpm", "-s", "vitest", "run", "tests/use-cases/{slug}.test.ts"],
            inputs: ["tests/use-cases/{slug}.test.ts"],
            timeout_seconds: 600
          }
        },
        requirements: [
          { evidence_kind: "test_result", required_verifiers: ["acceptance"], minimum_count: 1 }
        ]
      })
    ).toBe(true);
  });

  test("rejects a verifier that omits its command", () => {
    expect(
      validate({
        mode: "requirements",
        verifiers: {
          acceptance: { kind: "script", evidence_kind: "test_result" }
        },
        requirements: [
          { evidence_kind: "test_result", required_verifiers: ["acceptance"], minimum_count: 1 }
        ]
      })
    ).toBe(false);
  });

  test("rejects an unknown verifier kind", () => {
    expect(
      validate({
        mode: "requirements",
        verifiers: {
          acceptance: {
            kind: "manual",
            evidence_kind: "test_result",
            command: ["echo", "hi"]
          }
        },
        requirements: [
          { evidence_kind: "test_result", required_verifiers: ["acceptance"], minimum_count: 1 }
        ]
      })
    ).toBe(false);
  });
});
