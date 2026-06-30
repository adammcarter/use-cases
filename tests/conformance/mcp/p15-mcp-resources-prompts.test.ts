import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { handleMcpMessage } from "../../../packages/mcp/src/index.js";

const repoRoot = resolve(import.meta.dirname, "../../..");
const fixture = resolve(repoRoot, "tests/fixtures/workspaces/minimal-valid");

// The repo-scoped resources, by URI. ucp://schemas and ucp://config either need
// no repo (schemas) or report config (config still needs a repo for context).
const REPO_SCOPED_RESOURCES = [
  "ucp://matrix",
  "ucp://matrix/status",
  "ucp://freshness",
  "ucp://bindings",
  "ucp://ledger",
  "ucp://evidence",
  "ucp://config"
] as const;

describe("P15 MCP resources + prompts surface", () => {
  let savedRepoEnv: string | undefined;

  beforeEach(() => {
    savedRepoEnv = process.env.UCP_MCP_REPO;
    delete process.env.UCP_MCP_REPO;
  });

  afterEach(() => {
    if (savedRepoEnv === undefined) {
      delete process.env.UCP_MCP_REPO;
    } else {
      process.env.UCP_MCP_REPO = savedRepoEnv;
    }
  });

  test("initialize advertises resources and prompts capabilities alongside tools", () => {
    const response = handleMcpMessage({
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: { protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "p15", version: "0.0.0" } }
    });
    const capabilities = (response?.result as { capabilities: Record<string, unknown> }).capabilities;
    expect(capabilities).toHaveProperty("tools");
    expect(capabilities).toHaveProperty("resources");
    expect(capabilities).toHaveProperty("prompts");
  });

  test("resources/list returns the expected UCM state URIs with metadata", () => {
    const response = handleMcpMessage({ jsonrpc: "2.0", id: 1, method: "resources/list", params: {} });
    const resources = (response?.result as { resources: Array<{ uri: string; name: string; description: string; mimeType: string }> }).resources;
    const uris = resources.map((entry) => entry.uri);

    for (const uri of [
      "ucp://matrix",
      "ucp://matrix/status",
      "ucp://freshness",
      "ucp://bindings",
      "ucp://ledger",
      "ucp://evidence",
      "ucp://schemas",
      "ucp://config"
    ]) {
      expect(uris).toContain(uri);
    }

    for (const entry of resources) {
      expect(entry.name).toBeTruthy();
      expect(entry.description).toBeTruthy();
      expect(entry.mimeType).toBe("application/json");
    }

    // SECURITY: no generic file-read resource is exposed.
    expect(uris.some((uri) => uri.startsWith("ucp://file") || uri.includes("{path}"))).toBe(false);
  });

  test("resources/read of ucp://matrix returns valid structured matrix content", () => {
    const result = readResource(`ucp://matrix?repo=${fixture}`);
    const contents = (result.result as { contents: Array<{ uri: string; mimeType: string; text: string }> }).contents;
    expect(contents).toHaveLength(1);
    expect(contents[0].mimeType).toBe("application/json");
    expect(contents[0].uri).toBe(`ucp://matrix?repo=${fixture}`);

    const parsed = JSON.parse(contents[0].text) as { command: string; ok: boolean; data: { validation: unknown; list: unknown } };
    expect(parsed.command).toBe("matrix.validate");
    expect(parsed.data).toHaveProperty("validation");
    expect(parsed.data).toHaveProperty("list");
  });

  test("resources/read of ucp://schemas/{name} returns the requested public schema without needing a repo", () => {
    const result = readResource("ucp://schemas/common.schema.json");
    const contents = (result.result as { contents: Array<{ text: string }> }).contents;
    const parsed = JSON.parse(contents[0].text) as { id: string; schema: { $id?: string } };
    expect(parsed.id).toContain("common.schema.json");
    expect(parsed.schema).toBeTruthy();
  });

  test("resources/read of ucp://schemas index lists available schema ids", () => {
    const result = readResource("ucp://schemas");
    const contents = (result.result as { contents: Array<{ text: string }> }).contents;
    const parsed = JSON.parse(contents[0].text) as { schemas: Array<{ id: string; uri: string }> };
    expect(parsed.schemas.length).toBeGreaterThan(0);
    expect(parsed.schemas.some((entry) => entry.id.includes("common.schema.json"))).toBe(true);
  });

  test("resources/read rejects a traversal repo path", () => {
    const result = readResource("ucp://matrix?repo=../../../../../../../../etc");
    expect(result.error).toMatchObject({ code: expect.any(Number) });
    expect(result.error?.message).toMatch(/escape|contain|boundary|UCP_PATH_ESCAPE/i);
    expect(result.result).toBeUndefined();
  });

  test("resources/read requires a repo when none is configured", () => {
    const result = readResource("ucp://matrix");
    expect(result.error).toMatchObject({ code: expect.any(Number) });
    expect(result.error?.message).toMatch(/repo/i);
    expect(result.result).toBeUndefined();
  });

  test("resources/read falls back to the configured default repo", () => {
    process.env.UCP_MCP_REPO = fixture;
    const result = readResource("ucp://matrix");
    const contents = (result.result as { contents: Array<{ text: string }> }).contents;
    expect(JSON.parse(contents[0].text).command).toBe("matrix.validate");
  });

  test("resources/read of an unknown resource returns a not-found error", () => {
    const result = readResource("ucp://does-not-exist");
    expect(result.error).toMatchObject({ code: expect.any(Number) });
    expect(result.result).toBeUndefined();
  });

  test("no repo-scoped resource read mutates workspace state", () => {
    const before = readTreeBytes(fixture);
    for (const uri of REPO_SCOPED_RESOURCES) {
      const response = readResource(`${uri}?repo=${fixture}`);
      expect(response.error, `${uri} should read cleanly`).toBeUndefined();
    }
    expect(readTreeBytes(fixture)).toEqual(before);
  });

  test("prompts/list returns the expected guided-workflow prompt names", () => {
    const response = handleMcpMessage({ jsonrpc: "2.0", id: 1, method: "prompts/list", params: {} });
    const prompts = (response?.result as { prompts: Array<{ name: string; description: string; arguments: unknown[] }> }).prompts;
    const names = prompts.map((entry) => entry.name);

    for (const name of ["ucp/adopt-repo", "ucp/bind-row", "ucp/recover-suspect-row", "ucp/release-review"]) {
      expect(names).toContain(name);
    }
    for (const entry of prompts) {
      expect(entry.description).toBeTruthy();
      expect(Array.isArray(entry.arguments)).toBe(true);
    }
  });

  test("prompts/get returns a grounded message and honours arguments", () => {
    const response = handleMcpMessage({
      jsonrpc: "2.0",
      id: 1,
      method: "prompts/get",
      params: { name: "ucp/bind-row", arguments: { row: "auth.login" } }
    });
    const result = response?.result as { description: string; messages: Array<{ role: string; content: { type: string; text: string } }> };
    expect(result.description).toBeTruthy();
    expect(result.messages.length).toBeGreaterThan(0);
    expect(result.messages[0].content.type).toBe("text");
    // Grounded in the real CLI command and the supplied argument.
    expect(result.messages[0].content.text).toContain("ucp bind");
    expect(result.messages[0].content.text).toContain("auth.login");
    // Safety: prompts never instruct minting proofs as part of binding.
    expect(result.messages[0].content.text).not.toContain("ucp init");
  });

  test("prompts never expose prove on the MCP surface and keep proofs CI-mediated", () => {
    const list = handleMcpMessage({ jsonrpc: "2.0", id: 1, method: "prompts/list", params: {} });
    const names = (list?.result as { prompts: Array<{ name: string }> }).prompts.map((entry) => entry.name);
    expect(names).not.toContain("ucp/prove");

    const recover = handleMcpMessage({
      jsonrpc: "2.0",
      id: 2,
      method: "prompts/get",
      params: { name: "ucp/recover-suspect-row", arguments: { row: "auth.login" } }
    });
    const text = (recover?.result as { messages: Array<{ content: { text: string } }> }).messages
      .map((message) => message.content.text)
      .join("\n");
    // The recovery path names the real verify/prove CLI commands and is explicit
    // that prove runs in trusted CI, not over MCP.
    expect(text).toContain("ucp verify");
    expect(text.toLowerCase()).toContain("ci");
  });

  test("prompts/get for an unknown prompt returns an error", () => {
    const response = handleMcpMessage({ jsonrpc: "2.0", id: 1, method: "prompts/get", params: { name: "ucp/nope" } });
    expect(response?.error).toMatchObject({ code: expect.any(Number) });
    expect(response?.result).toBeUndefined();
  });
});

type ReadResponse = {
  result?: { contents?: unknown };
  error?: { code: number; message: string };
};

function readResource(uri: string): ReadResponse {
  const response = handleMcpMessage({
    jsonrpc: "2.0",
    id: 1,
    method: "resources/read",
    params: { uri }
  });
  return (response ?? {}) as ReadResponse;
}

function readTreeBytes(root: string): string {
  const parts: string[] = [];
  for (const entry of readdirSync(root).sort()) {
    const path = join(root, entry);
    if (statSync(path).isDirectory()) {
      parts.push(`${entry}/`, readTreeBytes(path));
    } else {
      parts.push(entry, readFileSync(path, "utf8"));
    }
  }
  return parts.join("\n");
}
