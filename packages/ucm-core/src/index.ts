export const PRESENTATION_SKILLS_NAME = "presentation-skills";
export const PRESENTATION_SKILLS_VERSION = "0.1.0";

export type VersionInfo = {
  name: typeof PRESENTATION_SKILLS_NAME;
  version: typeof PRESENTATION_SKILLS_VERSION;
};

export function getVersionInfo(): VersionInfo {
  return {
    name: PRESENTATION_SKILLS_NAME,
    version: PRESENTATION_SKILLS_VERSION
  };
}

export * from "./schema/index.js";
export * from "./errors.js";
export * from "./roots.js";
export * from "./useCases/integrity.js";
export * from "./useCases/loadUseCaseMatrix.js";
export * from "./useCases/query.js";
export * from "./useCases/types.js";
export * from "./useCases/validateUseCaseFile.js";
