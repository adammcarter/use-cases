// The black-box oracle for agents/roster.yml.
//
// These rows are about SHIPPED ARTEFACTS — the agent bodies, the Claude
// manifest, and the command surface an agent body may cite. Nothing here
// imports the product; it reads what ships and drives the binary, which is what
// a host does.
//
// One scenario step is deliberately NOT asserted here, and the gap is flagged
// rather than papered over: golden_declared says "confirm the published package
// files list includes agents", but package.json has no `files` key — it is
// `private`, and npm distribution was removed in 0.7.0 when GitHub became the
// only source. That step describes a mechanism that no longer exists. Changing
// the row is retiring behaviour, which is the owner's call, so it stays
// unasserted and named here until they make it.
import { readFileSync, readdirSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, expect, test } from "vitest";
import { runUc, runUcJson } from "../helpers/uc-binary";

const repoRoot = resolve(import.meta.dirname, "../..");

/** The roster as the spec states it. Hardcoded on purpose: a test that read the
 *  same constant the product reads would agree with it by construction. */
const CANONICAL_AGENTS = ["use-cases-updater", "use-cases-demo", "use-cases-demo-prep"];

function agentBody(name: string): string {
  return readFileSync(join(repoRoot, "agents", `${name}.md`), "utf8");
}

function frontmatter(source: string): Record<string, string> {
  const match = /^---\n([\s\S]*?)\n---\n/.exec(source);
  expect(match, "an agent body must open with YAML frontmatter").not.toBeNull();
  const fields: Record<string, string> = {};
  for (const line of match![1].split("\n")) {
    const pair = /^([a-z_]+):\s*(.*)$/.exec(line);
    if (pair) fields[pair[1]] = pair[2].replace(/^["']|["']$/g, "");
  }
  return fields;
}

describe("agents.roster.shipped_with_plugin", () => {
  // golden_declared, less the retired packaging step.
  test("the agents directory holds exactly the roster, and the manifest declares each one", () => {
    const shipped = readdirSync(join(repoRoot, "agents"))
      .filter((f) => f.endsWith(".md"))
      .map((f) => f.replace(/\.md$/, ""))
      .sort();
    expect(shipped, "no more and no less than the roster").toEqual([...CANONICAL_AGENTS].sort());

    const manifest = JSON.parse(readFileSync(join(repoRoot, ".claude-plugin", "plugin.json"), "utf8")) as {
      agents?: string[];
    };
    expect(manifest.agents, "the manifest declares agents explicitly, by path").toBeTruthy();
    for (const name of CANONICAL_AGENTS) {
      expect(manifest.agents, `${name} must be declared`).toContain(`./agents/${name}.md`);
    }
  });

  // bad_roster_entry_without_a_body and bad_body_shipped_without_being_declared.
  // One equality asserts both directions: a roster name with no body, and a body
  // the roster never named, each break it.
  test("the roster and the shipped directory are held equal in both directions", () => {
    const shipped = readdirSync(join(repoRoot, "agents"))
      .filter((f) => f.endsWith(".md"))
      .map((f) => f.replace(/\.md$/, ""));

    for (const name of CANONICAL_AGENTS) {
      expect(shipped, `${name} is in the roster and must have a body`).toContain(name);
    }
    for (const name of shipped) {
      expect(CANONICAL_AGENTS, `${name} ships but the roster does not name it`).toContain(name);
    }

    // And the manifest is held to the same set, so a body cannot reach one host
    // while being invisible to another.
    const manifest = JSON.parse(readFileSync(join(repoRoot, ".claude-plugin", "plugin.json"), "utf8")) as {
      agents: string[];
    };
    expect(manifest.agents.length).toBe(CANONICAL_AGENTS.length);
  });
});

describe("agents.roster.bodies_hold_the_line", () => {
  // golden_frontmatter_matches_the_filename.
  test("every agent opens with frontmatter whose name matches its filename", () => {
    for (const name of CANONICAL_AGENTS) {
      expect(frontmatter(agentBody(name)).name, `${name} frontmatter`).toBe(name);
    }
  });

  // edge_description_is_specific_enough_to_route_on. A description that merely
  // restates the name tells a dispatching agent nothing about when to reach
  // for it.
  test("every description is a trigger, not a restatement of the name", () => {
    for (const name of CANONICAL_AGENTS) {
      const description = frontmatter(agentBody(name)).description ?? "";
      expect(description.length, `${name} needs a routable description`).toBeGreaterThanOrEqual(40);
      expect(description.trim()).not.toBe(name);
    }
  });

  // bad_cites_a_command_the_cli_does_not_ship. The allowlist is internal, but
  // its consequence is not: every `use-cases` command a body cites must be one the
  // shipped CLI actually dispatches, which --help enumerates.
  test("every use-cases command an agent body cites is one the CLI actually ships", () => {
    const help = runUc(["--help"]);
    expect(help.status).toBe(0);
    const dispatchable = new Set(
      help.stdout
        .split("\n")
        .map((line) => /^ {2}([a-z][a-z-]+(?: [a-z][a-z-]+)?)\s{2,}/.exec(line)?.[1])
        .filter((value): value is string => Boolean(value))
    );
    expect(dispatchable.size, "help must enumerate the command surface").toBeGreaterThan(20);

    for (const name of CANONICAL_AGENTS) {
      for (const match of agentBody(name).matchAll(/`use-cases\s+([^`]+?)`/g)) {
        const tokens = match[1].trim().split(/\s+/);
        const [first, second] = tokens;
        const cited = second && !second.startsWith("-") ? `${first} ${second}` : first;
        const known = dispatchable.has(cited) || dispatchable.has(first);
        expect(known, `${name} cites \`use-cases ${cited}\`, which the CLI does not ship`).toBe(true);
      }
    }
  });

  // bad_claims_the_users_approval. The one thing an agent must never be
  // authorised to do.
  test("no agent body authorises claiming the user's approval or calling prepared material proof", () => {
    for (const name of CANONICAL_AGENTS) {
      const body = agentBody(name);
      expect(body, `${name} must not authorise claiming approval`).not.toMatch(
        /agents?\s+may\s+(claim|record)\s+(user approval|user sign-off)/i
      );
      expect(body, `${name} must not call prepared material proof`).not.toMatch(
        /generated\s+(plan|walkthrough|capsule|runbook)\s+is\s+proof/i
      );
      expect(body).not.toMatch(/\bhost\s+support\s+is\s+verified\./i);
    }
  });

  // bad_names_one_authors_private_setup. These bodies ship to everyone who
  // installs the plugin, so one author's machine is meaningless to them.
  test("no agent body names a private roster, a home path, or a sibling repo", () => {
    for (const name of CANONICAL_AGENTS) {
      expect(agentBody(name), `${name} references a private setup`).not.toMatch(
        /agent-setup|~\/\.claude|\/Users\//
      );
    }
  });
});

describe("agents.roster.command_allowlist_tracks_cli", () => {
  // golden_nested_command_parity and golden_flat_command_parity. The observable
  // half of the parity guarantee: the surface an agent body may cite is the
  // surface the CLI dispatches, and --help is how a body's author discovers it.
  test("help enumerates both nested and flat commands, which is the surface a body may cite", () => {
    const help = runUc(["--help"]);
    const listed = help.stdout;

    for (const flat of ["scan", "verify", "bind", "rebind", "unbind", "init", "recover", "impact"]) {
      expect(listed, `flat command ${flat} must be discoverable`).toContain(flat);
    }
    for (const nested of ["matrix validate", "evidence record", "showcase start", "plan showcase"]) {
      expect(listed, `nested command ${nested} must be discoverable`).toContain(nested);
    }
  });

  // edge_the_commands_that_exposed_the_drift. These two are the regression this
  // gate exists for: both were real and both were once rejected as unknown.
  test("impact and showcase request-approval are both dispatchable", () => {
    const listed = runUc(["--help"]).stdout;
    expect(listed).toContain("impact");
    expect(listed).toContain("showcase request-approval");

    // And they answer, rather than merely appearing in a list. The envelope's
    // command field is namespaced by the module that owns the command, so the
    // CLI word `impact` reports as `markers.impact`.
    const impact = runUcJson(["impact", "--repo", "."], { cwd: repoRoot });
    expect(impact.envelope.command).toBe("markers.impact");
  });

  // bad_registry_command_missing_from_the_allowlist. The consequence an agent
  // can see: a body citing a command the CLI does not ship is caught, which is
  // what the sibling row asserts directly. Here the guard is that the help
  // surface and the doctor's view of command references agree.
  test("doctor reports no unknown command reference in any shipped skill or agent", () => {
    const { envelope } = runUcJson<{ command_references?: unknown }>(
      ["doctor", "skills", "--repo", "."],
      { cwd: repoRoot }
    );
    expect(envelope.ok, "a fictional command anywhere would fail this").toBe(true);
    expect(
      JSON.stringify(envelope.diagnostics),
      "no unknown_cli_command may be reported"
    ).not.toContain("unknown_cli_command");
  });
});
