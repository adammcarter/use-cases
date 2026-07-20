import type { Diagnostic } from "../schema/index.js";

export type SkillAssetSummary = {
  name: string;
  path: string;
  description: string;
  complete: boolean;
};

export type SkillCommandReference = {
  command: string;
  source_path: string;
};

export type SkillBootstrapSummary = {
  path: string;
  complete: boolean;
  sections: string[];
};

// Whether a host can actually LOAD the skills, as distinct from whether the
// SKILL.md files exist. The two came apart once: every asset check passed while
// no agent on any host could reach the showcase protocol.
export type SkillHostRegistrationSummary = {
  host: string;
  manifest_path: string;
  // The manifest names a directory that contains the canonical skills.
  declares_skill_root: boolean;
  // The package can be added as a plugin at all — without this, the manifest
  // above is never read, so declaring the directory achieves nothing.
  installable: boolean;
};

export type SkillHostRegistrationResult = {
  complete: boolean;
  hosts: SkillHostRegistrationSummary[];
};

export type SkillAssetValidationResult = {
  schema_version: 1;
  complete: boolean;
  skill_count: number;
  skills: SkillAssetSummary[];
  host_registration: SkillHostRegistrationResult;
  bootstrap: SkillBootstrapSummary;
  command_references: SkillCommandReference[];
  diagnostics: Diagnostic[];
};
