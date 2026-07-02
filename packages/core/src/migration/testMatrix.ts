import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { stringify } from "yaml";
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import { UseCasesPluginError } from "../errors.js";
import type { ResolvedWorkspaceContext } from "../roots.js";
import { computeSemanticHash, type Diagnostic } from "../schema/index.js";

type AstNode = {
  type?: string;
  value?: string;
  url?: string;
  children?: AstNode[];
};

type LegacyRow = {
  tableIndex: number;
  rowIndex: number;
  rowRef: string;
  raw: Record<string, string>;
  fields: {
    id: string;
    feature: string;
    scenario: string;
    steps: string;
    expected: string;
    status: string;
    evidence: string;
    notes: string;
  };
  warnings: TestMatrixMigrationWarning[];
};

export type TestMatrixMigrationMode = "dry_run" | "write";

export type TestMatrixMigrationWarning = {
  code: string;
  row_ref: string | null;
  message: string;
};

export type TestMatrixMigrationResult = {
  schema_version: 1;
  source: {
    path: string;
    digest: string;
    parser: string;
  };
  mode: TestMatrixMigrationMode;
  summary: {
    tables_found: number;
    rows_seen: number;
    rows_importable: number;
    rows_needing_review: number;
    files_planned: number;
    files_written: number;
  };
  drafts: Array<{
    output_path: string;
    feature_id: string;
    use_case_ids: string[];
    content: string;
  }>;
  warnings: TestMatrixMigrationWarning[];
  would_write: Array<{
    path: string;
    action: "create" | "update_generated" | "skip_unchanged" | "conflict";
  }>;
};

export function migrateTestMatrix(options: {
  context: ResolvedWorkspaceContext;
  sourcePath: string;
  outDir?: string;
  mode: TestMatrixMigrationMode;
}): TestMatrixMigrationResult {
  const sourceRel = normalizeRelativePath(options.sourcePath);
  const sourcePath = resolveInside(options.context.workspace_root, sourceRel, "migration_unsafe_source_path");
  const outRel = normalizeRelativePath(options.outDir ?? "use-cases/_migrated");
  const outPath = resolveOutputPath(options.context, outRel);
  const source = readFileSync(sourcePath, "utf8");
  const sourceDigest = computeSemanticHash(source);
  const rows = parseLegacyRows(source, sourceRel, sourceDigest);
  const warnings = rows.flatMap((row) => row.warnings);
  if (rows.length === 0) {
    warnings.push({
      code: "no_tables_found",
      row_ref: null,
      message: "No parseable GFM tables were found in the source markdown."
    });
  }
  const grouped = groupRows(rows);
  const drafts = [...grouped.entries()].map(([featureSlug, featureRows]) =>
    renderDraft(featureSlug, featureRows, sourceRel, sourceDigest, outRel)
  );
  const wouldWrite = drafts.map((draft) => ({
    path: draft.output_path,
    action: plannedAction(join(options.context.data_root, draft.output_path), draft.content)
  }));
  if (wouldWrite.some((operation) => operation.action === "conflict")) {
    warnings.push({
      code: "migration_output_conflict",
      row_ref: null,
      message: "Existing output file is not managed by this migration."
    });
  }
  let filesWritten = 0;
  if (options.mode === "write" && !wouldWrite.some((operation) => operation.action === "conflict")) {
    mkdirSync(outPath, { recursive: true });
    for (const draft of drafts) {
      const fullPath = join(options.context.data_root, draft.output_path);
      mkdirSync(dirname(fullPath), { recursive: true });
      const current = existsSync(fullPath) ? readFileSync(fullPath, "utf8") : null;
      if (current !== draft.content) {
        writeFileSync(fullPath, draft.content);
        filesWritten += 1;
      }
    }
    writeFileSync(join(outPath, ".use-case-matrix-migration.json"), `${JSON.stringify({
      schema_version: 1,
      source: { path: sourceRel, digest: sourceDigest },
      generated_files: drafts.map((draft) => ({
        path: draft.output_path,
        hash: computeSemanticHash(draft.content),
        use_case_ids: draft.use_case_ids
      })),
      created_at: "1970-01-01T00:00:00.000Z"
    }, null, 2)}\n`);
  }
  const rowsNeedingReview = rows.filter((row) => row.warnings.some((warning) => warning.code !== "old_status_not_evidence")).length;
  return {
    schema_version: 1,
    source: {
      path: sourceRel,
      digest: sourceDigest,
      parser: "remark-gfm-v1"
    },
    mode: options.mode,
    summary: {
      tables_found: new Set(rows.map((row) => row.tableIndex)).size,
      rows_seen: rows.length,
      rows_importable: rows.length,
      rows_needing_review: rowsNeedingReview,
      files_planned: drafts.length,
      files_written: filesWritten
    },
    drafts,
    warnings,
    would_write: wouldWrite
  };
}

function parseLegacyRows(source: string, sourcePath: string, sourceDigest: string): LegacyRow[] {
  const tree = unified().use(remarkParse).use(remarkGfm).parse(source) as AstNode;
  const tables: AstNode[] = [];
  visit(tree, (node) => {
    if (node.type === "table") {
      tables.push(node);
    }
  });
  return tables.flatMap((table, tableIndex) => rowsFromTable(table, tableIndex + 1, sourcePath, sourceDigest));
}

function rowsFromTable(table: AstNode, tableIndex: number, sourcePath: string, sourceDigest: string): LegacyRow[] {
  const rows = table.children ?? [];
  const [header, ...body] = rows;
  const headers = (header?.children ?? []).map((cell) => normalizeHeader(textOf(cell)));
  return body.map((row, index) => {
    const raw: Record<string, string> = {};
    for (const [cellIndex, cell] of (row.children ?? []).entries()) {
      raw[headers[cellIndex] ?? `extra_${cellIndex}`] = textOf(cell).trim();
    }
    const rowIndex = index + 1;
    const rowRef = `${sourcePath}#table-${tableIndex}-row-${rowIndex}`;
    const fields = {
      id: field(raw, "id"),
      feature: field(raw, "feature") || "Uncategorized",
      scenario: field(raw, "scenario"),
      steps: field(raw, "steps"),
      expected: field(raw, "expected"),
      status: field(raw, "status"),
      evidence: field(raw, "evidence"),
      notes: field(raw, "notes")
    };
    const warnings = warningsFor(fields, rowRef, sourceDigest);
    return { tableIndex, rowIndex, rowRef, raw, fields, warnings };
  });
}

function warningsFor(fields: LegacyRow["fields"], rowRef: string, sourceDigest: string): TestMatrixMigrationWarning[] {
  const warnings: TestMatrixMigrationWarning[] = [];
  if (fields.status) {
    warnings.push({
      code: "old_status_not_evidence",
      row_ref: rowRef,
      message: `Old status '${fields.status}' is migration context only and did not create evidence.`
    });
  }
  if (fields.evidence) {
    warnings.push({
      code: "legacy_evidence_not_imported",
      row_ref: rowRef,
      message: "Legacy evidence text is review context only and did not create evidence events."
    });
  }
  if (/\b(approved|signed off|accepted|signoff)\b/i.test(`${fields.notes} ${fields.status}`)) {
    warnings.push({
      code: "legacy_approval_not_imported",
      row_ref: rowRef,
      message: "Legacy approval wording is review context only and did not create approval events."
    });
  }
  if (!fields.expected) {
    warnings.push({
      code: "missing_expected_outcome",
      row_ref: rowRef,
      message: `Row has no expected outcome and needs review before becoming active. Source ${sourceDigest}.`
    });
  }
  if (!fields.scenario && !fields.steps) {
    warnings.push({
      code: "ambiguous_row",
      row_ref: rowRef,
      message: "Row does not clearly describe behavior and needs review."
    });
  }
  return warnings;
}

function groupRows(rows: LegacyRow[]): Map<string, LegacyRow[]> {
  const grouped = new Map<string, LegacyRow[]>();
  for (const row of rows) {
    const key = slug(row.fields.feature || "uncategorized");
    grouped.set(key, [...(grouped.get(key) ?? []), row]);
  }
  return grouped;
}

function renderDraft(featureSlug: string, rows: LegacyRow[], sourcePath: string, sourceDigest: string, outRel: string) {
  const featureName = titleCase(featureSlug);
  const featureId = `migrated.${featureSlug}`;
  const useCases = rows.map((row) => useCaseFromRow(row, featureSlug, sourceDigest));
  const document = {
    schema_version: 1,
    feature: {
      id: featureId,
      name: featureName,
      summary: `Draft use cases migrated from ${sourcePath}.`
    },
    metadata: {
      lifecycle: "planned",
      extensions: {
        "use-case-matrix.dev/migration": {
          source_path: sourcePath,
          source_digest: sourceDigest,
          review_required: rows.some((row) => row.warnings.length > 0)
        }
      }
    },
    use_cases: useCases
  };
  const content = [
    "# Generated by use-case-matrix migrate test-matrix.",
    "# Draft intended behavior only. Old status/evidence was not imported as proof.",
    "# Review before relying on these use cases.",
    stringify(document)
  ].join("\n");
  return {
    output_path: `${stripTrailingSlash(outRel)}/${featureSlug}.yml`,
    feature_id: featureId,
    use_case_ids: useCases.map((useCase) => useCase.id as string),
    content
  };
}

function useCaseFromRow(row: LegacyRow, featureSlug: string, sourceDigest: string): Record<string, unknown> {
  const clearBehavior = Boolean(row.fields.scenario && row.fields.expected);
  const id = `migrated.${featureSlug}.${slug(row.fields.id || stableRowSuffix(row.rowRef))}`;
  const base: Record<string, unknown> = {
    id,
    title: row.fields.scenario || row.fields.id || `Migrated row ${row.rowIndex}`,
    lifecycle: clearBehavior ? "active" : "planned",
    value_tier: "supporting",
    journey_role: inferJourneyRole(row),
    usage_frequency: "occasional",
    tags: ["migrated"],
    source_refs: [{ kind: "file", path: row.rowRef }],
    extensions: {
      "use-case-matrix.dev/migration": {
        legacy_id: row.fields.id || null,
        legacy_status: row.fields.status || null,
        legacy_evidence_text: row.fields.evidence || null,
        legacy_notes: row.fields.notes || null,
        source_digest: sourceDigest,
        table_index: row.tableIndex,
        row_index: row.rowIndex,
        review_required: row.warnings.length > 0,
        warnings: row.warnings.map((warning) => warning.code)
      }
    }
  };
  if (clearBehavior) {
    Object.assign(base, {
      actor: "user",
      intent: row.fields.scenario,
      preconditions: ["Migrated from a legacy TEST-MATRIX row; review before relying on it."],
      trigger: row.fields.steps || row.fields.scenario,
      scenarios: [{
        id: `${id}.legacy`,
        kind: "steps",
        steps: splitSteps(row.fields.steps || row.fields.scenario),
        observable_outcomes: [row.fields.expected]
      }],
      observable_outcomes: [row.fields.expected],
      host_applicability: [{ host_surface: "unknown", supported: true }],
      verification_policy: { mode: "none" },
      approval_policy: { mode: "none" }
    });
  }
  return base;
}

function resolveInside(root: string, value: string, code: string): string {
  if (isAbsolute(value) || value.split(/[\\/]/).includes("..")) {
    throw new UseCasesPluginError(
      `Migration source path '${value}' must be relative to the repository root (${root}) and stay inside it. Pass a path like 'TEST-MATRIX.md' or 'docs/TEST-MATRIX.md', not an absolute path or one containing '..'.`,
      code
    );
  }
  const fullPath = resolve(root, value);
  const rel = relative(root, fullPath);
  if (rel.startsWith("..") || isAbsolute(rel)) {
    throw new UseCasesPluginError(
      `Migration source path '${value}' escapes the repository root (${root}); it must be relative to the repository root and stay inside it.`,
      code
    );
  }
  return fullPath;
}

function resolveOutputPath(context: ResolvedWorkspaceContext, outRel: string): string {
  if (isAbsolute(outRel) || outRel.split(/[\\/]/).includes("..")) {
    throw new UseCasesPluginError("Migration output must stay inside the data root.", "migration_unsafe_output_path");
  }
  const blocked = outRel.split(/[\\/]/)[0];
  if (blocked === "evidence" || blocked === "showcase-runs" || blocked === ".codex" || blocked === ".claude") {
    throw new UseCasesPluginError("Migration output cannot target evidence, showcase, or host projection roots.", "migration_unsafe_output_path");
  }
  const fullPath = resolve(context.data_root, outRel);
  const rel = relative(context.data_root, fullPath);
  if (rel.startsWith("..") || isAbsolute(rel)) {
    throw new UseCasesPluginError("Migration output escapes the data root.", "migration_unsafe_output_path");
  }
  return fullPath;
}

function plannedAction(path: string, content: string): "create" | "update_generated" | "skip_unchanged" | "conflict" {
  if (!existsSync(path)) {
    return "create";
  }
  const current = readFileSync(path, "utf8");
  if (current === content) {
    return "skip_unchanged";
  }
  return current.includes("Generated by use-case-matrix migrate test-matrix") ? "update_generated" : "conflict";
}

function field(raw: Record<string, string>, canonical: keyof LegacyRow["fields"]): string {
  return raw[canonical] ?? "";
}

function normalizeHeader(value: string): string {
  const key = slug(value);
  if (["id", "case", "test", "row", "key"].includes(key)) return "id";
  if (["feature", "area", "component", "module"].includes(key)) return "feature";
  if (["scenario", "behavior", "behaviour", "use-case", "case"].includes(key)) return "scenario";
  if (["steps", "action", "when", "procedure"].includes(key)) return "steps";
  if (["expected", "then", "result", "outcome"].includes(key)) return "expected";
  if (["status", "pass-fail", "state"].includes(key)) return "status";
  if (["evidence", "proof", "artifact", "receipt"].includes(key)) return "evidence";
  if (["notes", "comments", "caveats"].includes(key)) return "notes";
  return key;
}

function textOf(node: AstNode): string {
  if (node.value) return node.value;
  if (node.url) return node.url;
  return (node.children ?? []).map(textOf).join(" ");
}

function visit(node: AstNode, fn: (node: AstNode) => void): void {
  fn(node);
  for (const child of node.children ?? []) {
    visit(child, fn);
  }
}

function slug(value: string): string {
  const normalized = value.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  return normalized || "uncategorized";
}

function titleCase(value: string): string {
  return value.split("-").map((part) => `${part.slice(0, 1).toUpperCase()}${part.slice(1)}`).join(" ");
}

function inferJourneyRole(row: LegacyRow): "alternate" | "edge" | "negative" | "failure" | "golden" {
  const text = `${row.fields.scenario} ${row.fields.steps} ${row.fields.expected}`.toLowerCase();
  if (/\b(error|invalid|reject|denied|bad)\b/.test(text)) return "negative";
  if (/\b(fallback|recovery|outage|degraded)\b/.test(text)) return "failure";
  if (/\b(edge|boundary|limit)\b/.test(text)) return "edge";
  if (/\b(golden|happy path|smoke|primary)\b/.test(text)) return "golden";
  return "alternate";
}

function splitSteps(value: string): string[] {
  return value.split(/;|\n/).map((part) => part.trim()).filter(Boolean);
}

function stableRowSuffix(value: string): string {
  return createHash("sha256").update(value).digest("hex").slice(0, 10);
}

function normalizeRelativePath(value: string): string {
  return value.split(sep).join("/");
}

function stripTrailingSlash(value: string): string {
  return value.replace(/\/+$/g, "");
}
