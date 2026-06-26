import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../..");

function run(command: string, args: string[], cwd = repoRoot) {
  return spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
}

function runWithInput(command: string, args: string[], input: string, cwd = repoRoot) {
  return spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    input,
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
}

function requireSuccess(result: ReturnType<typeof run>) {
  if (result.status !== 0) {
    throw new Error(
      [
        `command failed with status ${result.status}`,
        `stdout:\n${result.stdout}`,
        `stderr:\n${result.stderr}`
      ].join("\n")
    );
  }
}

describe("P0 package entrypoints", () => {
  test("built core package exports version metadata", async () => {
    requireSuccess(run("corepack", ["pnpm", "build"]));

    const core = await import(
      resolve(repoRoot, "packages/ucm-core/dist/index.js")
    );

    expect(core.getVersionInfo()).toEqual({
      name: "presentation-skills",
      version: "1.0.0"
    });
  });

  test("CLI prints version JSON through the public binary entrypoint", () => {
    requireSuccess(run("corepack", ["pnpm", "build"]));

    const result = run("node", [
      "packages/ucm-cli/dist/index.js",
      "--version",
      "--json"
    ]);

    requireSuccess(result);
    expect(JSON.parse(result.stdout)).toMatchObject({
      ok: true,
      command: "version",
      schema_version: 1,
      protocol_version: 1,
      complete: true,
      data: {
        name: "presentation-skills",
        version: "1.0.0"
      },
      diagnostics: []
    });
  });

  test("packed packages install into a clean consumer and expose imports and bins", () => {
    requireSuccess(run("corepack", ["pnpm", "build"]));

    const packDir = mkdtempSync(join(tmpdir(), "presentation-skills-pack-"));
    for (const filter of [
      "@presentation-skills/ucm-core",
      "@presentation-skills/ucm-cli",
      "@presentation-skills/ucm-mcp"
    ]) {
      requireSuccess(
        run("corepack", [
          "pnpm",
          "--filter",
          filter,
          "pack",
          "--pack-destination",
          packDir
        ])
      );
    }

    const consumer = mkdtempSync(join(tmpdir(), "presentation-skills-consumer-"));
    writeFileSync(
      join(consumer, "package.json"),
      JSON.stringify({ type: "module", dependencies: {} }, null, 2)
    );

    const tarballs = [
      "presentation-skills-ucm-core-1.0.0.tgz",
      "presentation-skills-ucm-cli-1.0.0.tgz",
      "presentation-skills-ucm-mcp-1.0.0.tgz"
    ].map((name) => join(packDir, name));
    writeFileSync(
      join(consumer, "pnpm-workspace.yaml"),
      [
        "overrides:",
        `  "@presentation-skills/ucm-core": "file:${tarballs[0]}"`,
        ""
      ].join("\n")
    );

    requireSuccess(run("corepack", ["pnpm", "add", ...tarballs], consumer));

    writeFileSync(
      join(consumer, "check.mjs"),
      [
        "import { getVersionInfo } from '@presentation-skills/ucm-core';",
        "const info = getVersionInfo();",
        "if (info.name !== 'presentation-skills' || info.version !== '1.0.0') throw new Error('bad version export');"
      ].join("\n")
    );
    requireSuccess(run("node", ["check.mjs"], consumer));

    const binDir = join(consumer, "node_modules/.bin");
    const cli = run(join(binDir, "presentation-skills"), ["--version", "--json"], consumer);
    requireSuccess(cli);
    expect(JSON.parse(cli.stdout).data.version).toBe("1.0.0");

    const mcp = runWithInput(
      join(binDir, "presentation-skills-mcp"),
      [],
      [
        JSON.stringify({
          jsonrpc: "2.0",
          id: 1,
          method: "initialize",
          params: {
            protocolVersion: "2024-11-05",
            capabilities: {},
            clientInfo: { name: "packed-consumer", version: "0.0.0" }
          }
        }),
        JSON.stringify({ jsonrpc: "2.0", id: 2, method: "tools/list", params: {} }),
        JSON.stringify({
          jsonrpc: "2.0",
          id: 3,
          method: "tools/call",
          params: {
            name: "host_doctor",
            arguments: { repo: repoRoot, host: "codex" }
          }
        }),
        ""
      ].join("\n"),
      consumer
    );
    requireSuccess(mcp);
    expect(mcp.stdout.trim().split("\n").map((line) => JSON.parse(line))).toEqual([
      expect.objectContaining({
        id: 1,
        result: expect.objectContaining({
          serverInfo: { name: "presentation-skills", version: "1.0.0" }
        })
      }),
      expect.objectContaining({
        jsonrpc: "2.0",
        id: 2,
        result: {
          tools: expect.arrayContaining([
            expect.objectContaining({ name: "matrix_validate" }),
            expect.objectContaining({ name: "showcase_request_approval" }),
            expect.objectContaining({ name: "host_doctor" })
          ])
        }
      }),
      expect.objectContaining({
        jsonrpc: "2.0",
        id: 3,
        result: expect.objectContaining({
          structuredContent: expect.objectContaining({
            command: "host.doctor",
            ok: true,
            data: expect.objectContaining({
              host: "codex",
              support_status: expect.any(String)
            })
          })
        })
      })
    ]);
  });
});

describe("P0 staged plugin", () => {
  test("distributable manifest paths resolve inside a staged plugin root", () => {
    requireSuccess(run("corepack", ["pnpm", "build"]));

    const staged = mkdtempSync(join(tmpdir(), "presentation-skills-plugin-"));
    mkdirSync(join(staged, ".codex-plugin"), { recursive: true });
    mkdirSync(join(staged, ".claude-plugin"), { recursive: true });
    mkdirSync(join(staged, "packages/ucm-mcp/dist"), { recursive: true });

    for (const [from, to] of [
      [".codex-plugin/plugin.json", ".codex-plugin/plugin.json"],
      [".claude-plugin/plugin.json", ".claude-plugin/plugin.json"],
      ["plugin.json", "plugin.json"],
      [".mcp.json", ".mcp.json"],
      ["packages/ucm-mcp/dist/index.js", "packages/ucm-mcp/dist/index.js"]
    ] as const) {
      writeFileSync(join(staged, to), readFileSync(join(repoRoot, from)));
    }

    const manifest = JSON.parse(
      readFileSync(join(staged, ".codex-plugin/plugin.json"), "utf8")
    );
    expect(manifest.mcpServers).toBe("./.mcp.json");

    const mcpConfig = JSON.parse(readFileSync(join(staged, ".mcp.json"), "utf8"));
    const server = mcpConfig.mcpServers["presentation-skills"];
    expect(server.command).toBe("node");
    expect(resolve(staged, server.args[0])).toBe(
      join(staged, "packages/ucm-mcp/dist/index.js")
    );
  });
});
