// Language-agnostic verifier presets.
//
// A preset is a named, reusable expansion of the "what command verifies this
// row" question. Each preset expands — with `{slug}` substituted everywhere it
// appears — to a `{ kind:"script", command, inputs }` triple. Presets let a
// workspace adopt the matrix WITHOUT inheriting the historical pnpm/vitest
// assumption: that convention now lives here as `js.vitest`, alongside npm,
// pytest, go, make, and a bring-your-own-argv `command.generic`.
//
// Pure + deterministic: `expandPreset` substitutes `{slug}` and returns either a
// resolved expansion or a BLOCKED result for an unknown preset id (never throws),
// mirroring the resolver's return-blocked contract so the two compose cleanly.

const SLUG_TOKEN = "{slug}";
const VARIANT_TOKEN = "{variant}";

// The canonical preset id union. Keep in sync with the `verifier_preset_id`
// enum in schemas/v1/common.schema.json.
export const VERIFIER_PRESET_IDS = [
  "command.generic",
  "js.vitest",
  "js.npm-test",
  "python.pytest",
  "go.test",
  "make.target"
] as const;

export type VerifierPresetId = (typeof VERIFIER_PRESET_IDS)[number];

export interface ExpandedPreset {
  kind: "script";
  command: string[];
  inputs: string[];
}

export type PresetExpansion =
  | { status: "resolved"; preset: VerifierPresetId; expansion: ExpandedPreset }
  | { status: "blocked"; reason: string };

// Raw (un-substituted) preset templates. `command.generic` ships an empty
// command on purpose: the caller supplies the argv, so there is no default.
const PRESET_TEMPLATES: Record<VerifierPresetId, { command: string[]; inputs: string[] }> = {
  "command.generic": { command: [], inputs: [] },
  "js.vitest": {
    // Resolve the locally-installed vitest via `npx --no-install` so an
    // npm-only machine with no global pnpm still verifies. pnpm installs
    // vitest into node_modules/.bin, which npx resolves too, so pnpm users
    // are unaffected. `--no-install` forbids any network fetch — if vitest
    // is not installed locally, the command fails fast rather than hanging.
    command: ["npx", "--no-install", "vitest", "run", "tests/use-cases/{slug}.test.ts"],
    inputs: ["tests/use-cases/{slug}.test.ts"]
  },
  "js.npm-test": { command: ["npm", "test"], inputs: [] },
  "python.pytest": {
    command: ["pytest", "tests/use_cases/{slug}_test.py"],
    inputs: ["tests/use_cases/{slug}_test.py"]
  },
  "go.test": { command: ["go", "test", "./..."], inputs: [] },
  "make.target": { command: ["make", "test-use-case", "SLUG={slug}"], inputs: [] }
};

export function isVerifierPresetId(value: unknown): value is VerifierPresetId {
  return typeof value === "string" && (VERIFIER_PRESET_IDS as readonly string[]).includes(value);
}

// Expand a preset id into its concrete `{ kind, command, inputs }`, substituting
// `{slug}` (and, for a variant row, `{variant}`) throughout. Unknown ids return
// BLOCKED rather than throwing.
export function expandPreset(
  presetId: string,
  slug: string,
  variant?: string
): PresetExpansion {
  if (!isVerifierPresetId(presetId)) {
    return {
      status: "blocked",
      reason: `unknown verifier preset '${presetId}'; known presets: ${VERIFIER_PRESET_IDS.join(", ")}`
    };
  }
  const template = PRESET_TEMPLATES[presetId];
  return {
    status: "resolved",
    preset: presetId,
    expansion: {
      kind: "script",
      command: template.command.map((part) => substituteTokens(part, slug, variant)),
      inputs: template.inputs.map((part) => substituteTokens(part, slug, variant))
    }
  };
}

function substituteTokens(value: string, slug: string, variant: string | undefined): string {
  const withSlug = value.split(SLUG_TOKEN).join(slug);
  return variant === undefined ? withSlug : withSlug.split(VARIANT_TOKEN).join(variant);
}
