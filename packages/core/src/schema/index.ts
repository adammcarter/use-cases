// Barrel for the schema module. The implementation is split by responsibility
// into sibling files; this file re-exports EXACTLY the public surface (explicit
// named re-exports, no `export *`), so private cross-module helpers never leak
// and every importer across core/cli/mcp is unaffected.
export { diagnostic } from "./diagnostic.js";
export type { Diagnostic, ValidationResult } from "./diagnostic.js";
export type { CliContext, CliResult } from "./cliResult.js";
export { createCliResult } from "./cliResult.js";
export type { ParsedYamlResult, FixtureValidationResult } from "./validate.js";
export { parseYamlToJson, validateFixtureWorkspace, computeSemanticHash } from "./validate.js";
export { PUBLIC_SCHEMA_IDS, getPublicSchemas, validatePublicSchemas, validateBySchemaId, copySchemasToDist } from "./registry.js";
