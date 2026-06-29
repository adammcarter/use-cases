import { describe, expect, test } from "vitest";
import { handleMcpMessage } from "../../../packages/ucm-mcp/src/index.js";

type ToolSchema = {
  name: string;
  inputSchema: {
    type: string;
    properties: Record<string, { type?: string; enum?: string[]; description?: string }>;
    required?: string[];
    additionalProperties?: boolean;
  };
};

function listTools(): ToolSchema[] {
  const response = handleMcpMessage({ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} });
  return (response?.result as { tools: ToolSchema[] }).tools;
}

function schemaOf(name: string): ToolSchema["inputSchema"] {
  const tool = listTools().find((candidate) => candidate.name === name);
  if (!tool) throw new Error(`tool ${name} not registered`);
  return tool.inputSchema;
}

describe("MCP tool input schemas declare the real parameters", () => {
  test("every tool keeps repo required and preserves CLI-parity passthrough", () => {
    for (const tool of listTools()) {
      expect(tool.inputSchema.type).toBe("object");
      // Passthrough to the CLI must remain open so undeclared args still forward.
      expect(tool.inputSchema.additionalProperties).toBe(true);
      // Workspace-scoped tools keep repo required, and every property is documented.
      expect(tool.inputSchema.required).toContain("repo");
      for (const [key, prop] of Object.entries(tool.inputSchema.properties)) {
        expect(prop.description, `${tool.name}.${key} needs a description`).toBeTruthy();
      }
    }
  });

  test("use_case_upsert declares file + use_case object", () => {
    const schema = schemaOf("use_case_upsert");
    expect(Object.keys(schema.properties)).toEqual(expect.arrayContaining(["file", "use_case", "expected_hash", "allow_write"]));
    expect(schema.properties.use_case.type).toBe("object");
    expect(schema.required).toEqual(expect.arrayContaining(["repo", "file", "use_case"]));
  });

  test("plan_showcase and plan_walkthrough declare the planning knobs", () => {
    for (const name of ["plan_showcase", "plan_walkthrough"]) {
      const schema = schemaOf(name);
      expect(Object.keys(schema.properties)).toEqual(
        expect.arrayContaining(["audience", "max_items", "timebox_seconds", "host"])
      );
      expect(schema.properties.host.enum).toContain("codex.cli");
    }
  });

  test("showcase tools declare run/item/text/verdict/actor parameters", () => {
    const observation = schemaOf("showcase_record_observation");
    expect(Object.keys(observation.properties)).toEqual(expect.arrayContaining(["run", "item", "text", "actor_type"]));
    expect(observation.required).toEqual(expect.arrayContaining(["run", "item", "text"]));

    const verdict = schemaOf("showcase_record_verdict");
    expect(Object.keys(verdict.properties)).toEqual(expect.arrayContaining(["run", "item", "verdict"]));
    expect(verdict.properties.verdict.enum).toEqual(
      expect.arrayContaining(["pass", "partial", "fail", "waived", "blocked"])
    );
    expect(verdict.properties.actor_type.enum).toContain("agent");

    const decide = schemaOf("showcase_decide");
    expect(Object.keys(decide.properties)).toEqual(expect.arrayContaining(["run", "verdict_event", "decision", "reason"]));
    expect(decide.properties.decision.enum).toEqual(
      expect.arrayContaining(["continue", "pause_to_fix", "waive_with_reason", "abort"])
    );

    const start = schemaOf("showcase_start");
    expect(Object.keys(start.properties)).toEqual(expect.arrayContaining(["select", "plan_file"]));
  });

  test("evidence_record declares use_case/kind/result/summary with enums", () => {
    const schema = schemaOf("evidence_record");
    expect(Object.keys(schema.properties)).toEqual(expect.arrayContaining(["use_case", "kind", "result", "summary"]));
    expect(schema.properties.kind.enum).toContain("manual_observation");
    expect(schema.properties.result.enum).toEqual(expect.arrayContaining(["pass", "fail", "inconclusive", "observed"]));
    expect(schema.required).toContain("use_case");
  });
});
