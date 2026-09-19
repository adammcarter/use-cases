// OpenCode plugin for Use Cases (OpenCode v2 plugin surface).
//
// OpenCode installs a plugin as a package (`opencode plugin add
// 'github:adammcarter/use-cases'`), so this module is the whole host wiring:
// it registers the MCP server, every shipped skill, the trusted bootstrap, and
// puts bin/ on PATH for shells. Nothing is configured by hand.
//
// It is plain JavaScript with no dependencies so the git-installed package
// loads without a build; node_modules is not needed for any of this.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { delimiter, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// The plugin root is the repo root, one level up from this file.
const defaultRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

const BOOTSTRAP_MARKER = "<EXTREMELY_IMPORTANT>";

function readBootstrap(root) {
  const path = join(root, "bootstrap/use-cases.md");
  try {
    const text = readFileSync(path, "utf8").trimEnd();
    const body = text.includes(BOOTSTRAP_MARKER) ? text : `${BOOTSTRAP_MARKER}\n${text}\n</EXTREMELY_IMPORTANT>`;
    return `${body}\n\nThe use-cases command for this plugin is ${join(root, "bin/use-cases")}; it is first on PATH in shells OpenCode runs.`;
  } catch {
    return `${BOOTSTRAP_MARKER}\nThe use-cases bootstrap could not be read at ${path}. The use-cases command is ${join(root, "bin/use-cases")}.\n</EXTREMELY_IMPORTANT>`;
  }
}

// One skill per skills/<name>/SKILL.md: front-matter gives name and description,
// the rest is the body OpenCode shows the model.
function readSkills(root) {
  const dir = join(root, "skills");
  if (!existsSync(dir)) return [];
  const skills = [];
  for (const name of readdirSync(dir).sort()) {
    const location = join(dir, name, "SKILL.md");
    if (!existsSync(location)) continue;
    const source = readFileSync(location, "utf8");
    const match = source.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);
    const frontmatter = match ? match[1] : "";
    const content = (match ? match[2] : source).trim();
    const field = (key) => frontmatter.match(new RegExp(`^${key}:\\s*(.+)$`, "m"))?.[1]?.trim() ?? "";
    const id = field("name") || name;
    skills.push({ id, name: id, description: field("description"), content, location });
  }
  return skills;
}

// Exported so tests can point the same definition at a fixture root.
//: @use-case:plugin.install.opencode_from_git#module
export function definePlugin(root = defaultRoot) {
  return {
  id: "use-cases",
  setup: async (ctx) => {
    const bootstrap = readBootstrap(root);

    await ctx.mcp.transform((editor) => {
      editor.set("use-cases", { type: "local", command: ["bash", join(root, "bin/use-cases-mcp")], cwd: root, enabled: true });
    });

    const skills = readSkills(root);
    await ctx.skill.transform((editor) => {
      for (const skill of skills) editor.add(skill);
    });

    // Every outgoing request kind carries the bootstrap in its system prompt.
    for (const kind of ["context", "compaction", "generate", "title"]) {
      await ctx.session.hook(kind, (event) => {
        if (!Array.isArray(event.system)) return;
        if (event.system.some((part) => part?.text?.includes(BOOTSTRAP_MARKER))) return;
        event.system.push({ type: "text", text: bootstrap });
      });
    }

    await ctx.shell.hook("create.before", (event) => {
      if (!event.env) return;
      const bin = join(root, "bin");
      const current = event.env.PATH ?? process.env.PATH ?? "";
      if (current.split(delimiter)[0] === bin) return;
      event.env.PATH = [bin, current].filter(Boolean).join(delimiter);
    });
    // No return value: OpenCode treats a truthy return as a disposer.
  },
  };
}

export default definePlugin();
//: @use-case:end plugin.install.opencode_from_git#module
