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

export type SkillAssetValidationResult = {
  schema_version: 1;
  complete: boolean;
  skill_count: number;
  skills: SkillAssetSummary[];
  bootstrap: SkillBootstrapSummary;
  command_references: SkillCommandReference[];
  diagnostics: Diagnostic[];
};
