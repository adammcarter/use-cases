import { spawn } from "node:child_process";
import { once } from "node:events";
import { resolve } from "node:path";
import { describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../..");

describe("P0 MCP wire contract", () => {
  test("distributed MCP executable initializes and lists tools over stdio", async () => {
    await expect(runPnpm(["build"])).resolves.toBeUndefined();

    const child = spawn("node", ["packages/ucm-mcp/dist/index.js"], {
      cwd: repoRoot,
      stdio: ["pipe", "pipe", "pipe"]
    });

    const stdoutLines: string[] = [];
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk: string) => {
      stdoutLines.push(
        ...chunk
          .split("\n")
          .map((line) => line.trim())
          .filter(Boolean)
      );
    });

    child.stdin.write(
      `${JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: {
          protocolVersion: "2024-11-05",
          capabilities: {},
          clientInfo: { name: "p0-smoke", version: "0.0.0" }
        }
      })}\n`
    );
    child.stdin.write(
      `${JSON.stringify({
        jsonrpc: "2.0",
        method: "notifications/initialized"
      })}\n`
    );
    child.stdin.write(
      `${JSON.stringify({
        jsonrpc: "2.0",
        id: 2,
        method: "tools/list",
        params: {}
      })}\n`
    );

    await waitFor(() => stdoutLines.length >= 2);
    child.stdin.end();
    await once(child, "exit");

    const responses = stdoutLines.map((line) => JSON.parse(line));
    expect(responses[0]).toMatchObject({
      jsonrpc: "2.0",
      id: 1,
      result: {
        serverInfo: {
          name: "use-case-matrix",
          version: "1.0.0"
        }
      }
    });
    expect(responses[1]).toMatchObject({
      jsonrpc: "2.0",
      id: 2,
      result: {
        tools: expect.arrayContaining([
          expect.objectContaining({ name: "matrix_validate" }),
          expect.objectContaining({ name: "showcase_request_approval" }),
          expect.objectContaining({ name: "host_doctor" })
        ])
      }
    });
  });
});

async function runPnpm(args: string[]) {
  const child = spawn("corepack", ["pnpm", ...args], {
    cwd: repoRoot,
    stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
  const [code] = (await once(child, "exit")) as [number | null];
  if (code !== 0) {
    throw new Error(`corepack pnpm ${args.join(" ")} failed with ${code}`);
  }
}

async function waitFor(predicate: () => boolean) {
  const started = Date.now();
  while (!predicate()) {
    if (Date.now() - started > 10_000) {
      throw new Error("timed out waiting for MCP responses");
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
}
