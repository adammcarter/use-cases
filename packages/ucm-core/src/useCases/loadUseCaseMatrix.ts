import { existsSync, lstatSync, readdirSync, realpathSync } from "node:fs";
import { extname, isAbsolute, join, relative, sep } from "node:path";
import type { Diagnostic } from "../schema/index.js";
import type { ResolvedWorkspaceContext } from "../roots.js";
import { buildMatrixSnapshot } from "./integrity.js";
import type { LoadedUseCase, MatrixFileResult, MatrixSnapshot } from "./types.js";
import { validateUseCaseFile } from "./validateUseCaseFile.js";

export type MatrixLoadOptions = {
  context: ResolvedWorkspaceContext;
};

export function loadUseCaseMatrix(options: MatrixLoadOptions): MatrixSnapshot {
  const diagnostics: Diagnostic[] = [];
  const files: MatrixFileResult[] = [];
  const candidates: LoadedUseCase[] = [];

  const root = options.context.use_cases_root;
  if (!existsSync(root)) {
    return buildMatrixSnapshot({
      context: options.context,
      files,
      candidates,
      diagnostics
    });
  }

  const rootRealPath = realpathSync(root);
  for (const entry of listUseCaseEntries(root, root, options.context.data_root, rootRealPath, diagnostics, files)) {
    const result = validateUseCaseFile(entry.filePath, entry.sourcePath);
    files.push(result.file);
    candidates.push(...result.candidates);
    diagnostics.push(...result.diagnostics);
  }

  return buildMatrixSnapshot({
    context: options.context,
    files,
    candidates,
    diagnostics
  });
}

function listUseCaseEntries(
  root: string,
  current: string,
  dataRoot: string,
  rootRealPath: string,
  diagnostics: Diagnostic[],
  files: MatrixFileResult[]
): Array<{ filePath: string; sourcePath: string }> {
  const entries = readdirSync(current, { withFileTypes: true }).sort((left, right) =>
    left.name.localeCompare(right.name)
  );
  const results: Array<{ filePath: string; sourcePath: string }> = [];

  for (const entry of entries) {
    const fullPath = join(current, entry.name);
    const sourcePath = normalizeRelative(dataRoot, fullPath);
    const stat = lstatSync(fullPath);

    if (stat.isSymbolicLink()) {
      files.push({ path: sourcePath, status: "symlink_rejected" });
      diagnostics.push(diagnostic("symlink_rejected", "Symlinks under use-cases are not followed.", sourcePath));
      continue;
    }

    if (stat.isDirectory()) {
      results.push(...listUseCaseEntries(root, fullPath, dataRoot, rootRealPath, diagnostics, files));
      continue;
    }

    if (!stat.isFile()) {
      files.push({ path: sourcePath, status: "io_error" });
      diagnostics.push(diagnostic("io_error", "Only regular files are supported under use-cases.", sourcePath));
      continue;
    }

    if (![".yml", ".yaml"].includes(extname(fullPath))) {
      continue;
    }

    const realPath = realpathSync(fullPath);
    if (!isContained(rootRealPath, realPath)) {
      files.push({ path: sourcePath, status: "path_escape" });
      diagnostics.push(diagnostic("path_escape", "Use-case file escapes use_cases_root.", sourcePath));
      continue;
    }

    results.push({ filePath: fullPath, sourcePath });
  }

  return results;
}

function normalizeRelative(root: string, path: string): string {
  return relative(root, path).split(sep).join("/");
}

function isContained(root: string, child: string): boolean {
  const relativePath = relative(root, child);
  return relativePath === "" || (!relativePath.startsWith("..") && !isAbsolute(relativePath));
}

function diagnostic(code: string, message: string, sourcePath: string): Diagnostic {
  return {
    code,
    severity: "error",
    message,
    source_path: sourcePath,
    json_pointer: null,
    entity_id: null,
    related_ids: []
  };
}
