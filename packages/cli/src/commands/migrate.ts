import type { CliCommand } from "../command/types.js";
import { valueAfter } from "../args/parse.js";
import {
  createCliResult,
  errorEnvelope,
  migrateTestMatrix,
  resolveContextOrError
} from "../runtime.js";
import { workspaceFlags } from "./common.js";

// Local port of the legacy migrationDiagnostics helper: map migration warnings to
// the standard diagnostic shape (unchanged from legacy.ts).
function migrationDiagnostics(result: ReturnType<typeof migrateTestMatrix>) {
  return result.warnings.map((warning) => ({
    code: warning.code,
    severity: "warning" as const,
    message: warning.message,
    source_path: warning.row_ref,
    json_pointer: null,
    entity_id: null,
    related_ids: []
  }));
}

export const migrateTestMatrixCommand: CliCommand = {
  path: ["migrate", "test-matrix"],
  command: "migrate.test-matrix",
  summary: "Migrate a legacy TEST-MATRIX into the use-case matrix.",
  flags: [
    ...workspaceFlags,
    { key: "source", name: "--source", kind: "string", required: true, valueName: "<path>", summary: "Legacy TEST-MATRIX source file." },
    { key: "out", name: "--out", kind: "string", valueName: "<dir>", summary: "Output directory for the migrated use-case files." },
    { key: "dryRun", name: "--dry-run", kind: "boolean", summary: "Preview the migration without writing (default)." },
    { key: "write", name: "--write", kind: "boolean", summary: "Write the migrated use-case files to disk." }
  ],
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "migrate.test-matrix");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const sourcePath = valueAfter(argv, "--source");
    if (!sourcePath) {
      return {
        envelope: errorEnvelope("migrate.test-matrix", "migration_source_required", "Missing --source."),
        exitCode: 2
      };
    }
    const selectedModes = [
      argv.includes("--dry-run") ? "dry_run" : null,
      argv.includes("--write") ? "write" : null
    ].filter((value): value is "dry_run" | "write" => value !== null);
    if (selectedModes.length > 1) {
      return {
        envelope: errorEnvelope("migrate.test-matrix", "migration_mode_conflict", "Use only one of --dry-run or --write."),
        exitCode: 2
      };
    }
    const mode = selectedModes[0] ?? "dry_run";
    try {
      const result = migrateTestMatrix({
        context: context.context,
        sourcePath,
        outDir: valueAfter(argv, "--out") ?? undefined,
        mode
      });
      const hasConflict = result.would_write.some((operation) => operation.action === "conflict");
      return {
        envelope: createCliResult("migrate.test-matrix", result, {
          ok: !hasConflict,
          complete: result.warnings.length === 0 && !hasConflict,
          diagnostics: migrationDiagnostics(result),
          workspaceRoot: context.context.workspace_root,
          dataRoot: context.context.data_root,
          componentId: context.context.component_id
        }),
        exitCode: hasConflict ? 1 : 0
      };
    } catch (error) {
      const code = error instanceof Error && "code" in error ? String(error.code) : "internal_error";
      const exitCode = code === "migration_unsafe_output_path" || code === "migration_unsafe_source_path" ? 4 : 1;
      return {
        envelope: errorEnvelope("migrate.test-matrix", code, error instanceof Error ? error.message : String(error)),
        exitCode
      };
    }
  }
};

export const migrateCommands: CliCommand[] = [migrateTestMatrixCommand];
