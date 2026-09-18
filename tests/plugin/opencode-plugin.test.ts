import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../..");
const modulePath = join(repoRoot, "opencode/plugin.js");

type Captured = {
  mcp: Record<string, unknown>;
  skills: Array<Record<string, unknown>>;
  system: Record<string, string[]>;
  env: Record<string, string>;
};

// A fake of the OpenCode v2 plugin context: editors for MCP and skills, session
// hooks by kind, and the shell create.before hook — enough to see what setup
// registers without booting OpenCode.
async function runSetup(root: string): Promise<Captured> {
  const captured: Captured = { mcp: {}, skills: [], system: {}, env: { PATH: "/usr/bin" } };
  const sessionHooks: Record<string, (event: { system: Array<{ type: string; text: string }> }) => unknown> = {};
  let shellHook: ((event: { env: Record<string, string> }) => unknown) | undefined;
  const ctx = {
    mcp: { transform: async (fn: (editor: { set: (n: string, c: unknown) => void }) => void) => fn({ set: (n, c) => { captured.mcp[n] = c; } }) },
    skill: { transform: async (fn: (editor: { add: (s: Record<string, unknown>) => void }) => void) => fn({ add: (s) => captured.skills.push(s) }) },
    session: { hook: async (name: string, fn: (event: { system: Array<{ type: string; text: string }> }) => unknown) => { sessionHooks[name] = fn; } },
    shell: { hook: async (_name: string, fn: (event: { env: Record<string, string> }) => unknown) => { shellHook = fn; } }
  };
  const mod = await import(modulePath);
  expect(typeof mod.default.id).toBe("string");
  const definition = root === repoRoot ? mod.default : mod.definePlugin(root);
  await definition.setup(ctx);
  for (const [kind, fn] of Object.entries(sessionHooks)) {
    const event = { system: [] as Array<{ type: string; text: string }> };
    await fn(event);
    captured.system[kind] = event.system.map((p) => p.text);
  }
  if (shellHook) await shellHook({ env: captured.env });
  return captured;
}

//: @use-case:plugin.install.opencode_from_git
describe("OpenCode installs the plugin from git", () => {
  test("package.json exports the plugin module and it is plain JavaScript", () => {
    const pkg = JSON.parse(readFileSync(join(repoRoot, "package.json"), "utf8"));
    expect(pkg.exports["."]).toBe("./opencode/plugin.js");
    expect(pkg.type).toBe("module");
    expect(existsSync(modulePath)).toBe(true);
    const source = readFileSync(modulePath, "utf8");
    for (const line of source.split("\n").filter((l) => /^import /.test(l))) {
      expect(line, line).toMatch(/from "node:/);
    }
  });

  test("setup registers the MCP server, every skill, the bootstrap and use-cases on PATH", async () => {
    const out = await runSetup(repoRoot);
    expect(out.mcp["use-cases"]).toEqual({ type: "local", command: ["bash", join(repoRoot, "bin/use-cases-mcp")], cwd: repoRoot, enabled: true });
    expect(readFileSync(modulePath, "utf8"), "the module must not name the committed bundle").not.toContain("dist/uc");
    const skillDirs = readdirSync(join(repoRoot, "skills")).sort();
    expect(out.skills.map((s) => s.name).sort()).toEqual(skillDirs);
    for (const skill of out.skills) {
      expect(skill.id).toBe(skill.name);
      expect(String(skill.description).length).toBeGreaterThan(10);
      expect(String(skill.content)).not.toMatch(/^---/);
      expect(String(skill.location)).toContain(`/skills/${skill.name}/SKILL.md`);
    }
    for (const kind of ["context", "compaction", "generate", "title"]) {
      expect(out.system[kind]?.join("\n"), kind).toContain("<EXTREMELY_IMPORTANT>");
    }
    expect(out.env.PATH.split(":")[0]).toBe(join(repoRoot, "bin"));
  });

  test("a missing bootstrap still registers everything and says so in the injected text", async () => {
    const out = await runSetup(join(repoRoot, "tests/fixtures/workspaces/minimal-valid"));
    expect(out.mcp["use-cases"]).toBeDefined();
    expect(out.env.PATH.split(":")[0]).toContain("/bin");
    expect(out.system.context?.join("\n")).toContain("could not be read");
  });

  test.skip("live: opencode run shows use-cases from the plugin bin, the use-cases tools and the bootstrap", () => {});
});
//: @use-case:end plugin.install.opencode_from_git
