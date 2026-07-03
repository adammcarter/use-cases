import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { TextDecoder } from "node:util";
import {
  computeSemanticHash,
  diagnostic,
  parseYamlToJson,
  validateBySchemaId,
  type Diagnostic
} from "../schema/index.js";
import type { FeatureV1, LoadedUseCase, MatrixFileResult, UseCaseV1 } from "./types.js";

export type UseCaseFileValidationResult = {
  file: MatrixFileResult;
  candidates: LoadedUseCase[];
  diagnostics: Diagnostic[];
};

export function validateUseCaseFile(
  filePath: string,
  sourcePath: string
): UseCaseFileValidationResult {
  let bytes: Buffer;
  try {
    bytes = readFileSync(filePath);
  } catch (error) {
    return failedFile("io_error", sourcePath, messageFor(error));
  }

  const fileHash = hashBytes(bytes);
  let source: string;
  try {
    source = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch (error) {
    return failedFile("parse_error", sourcePath, messageFor(error), fileHash);
  }

  const parsed = parseYamlToJson(source, sourcePath);
  if (!parsed.ok) {
    return {
      file: { path: sourcePath, status: "parse_error", file_hash: fileHash },
      candidates: [],
      diagnostics: parsed.diagnostics.map((diagnostic) => ({
        ...diagnostic,
        code: diagnostic.code === "parse_error" ? "parse_error" : diagnostic.code
      }))
    };
  }

  const versionDiagnostic = versionDispatch(parsed.value, sourcePath);
  if (versionDiagnostic) {
    return {
      file: {
        path: sourcePath,
        status: versionDiagnostic.code === "unknown_version" ? "unknown_version" : "schema_error",
        semantic_hash: computeSemanticHash(parsed.value),
        file_hash: fileHash
      },
      candidates: [],
      diagnostics: [versionDiagnostic]
    };
  }

  const schemaResult = validateBySchemaId(
    "https://use-cases.dev/schemas/v1/use-case-file.schema.json",
    parsed.value,
    sourcePath
  );
  if (!schemaResult.ok) {
    return {
      file: {
        path: sourcePath,
        status: "schema_error",
        semantic_hash: computeSemanticHash(parsed.value),
        file_hash: fileHash
      },
      candidates: [],
      diagnostics: schemaResult.diagnostics.map((diagnostic) => ({
        ...diagnostic,
        code: diagnostic.code === "schema_version.required" ? "schema_error" : diagnostic.code
      }))
    };
  }

  const value = parsed.value as {
    feature: FeatureV1;
    use_cases: UseCaseV1[];
  };
  return {
    file: {
      path: sourcePath,
      status: "loaded",
      semantic_hash: computeSemanticHash(parsed.value),
      file_hash: fileHash
    },
    candidates: value.use_cases.map((useCase, index) => ({
      value: useCase,
      feature: value.feature,
      semanticHash: computeSemanticHash(useCase),
      source: {
        path: sourcePath,
        jsonPointer: `/use_cases/${index}`,
        fileByteHash: fileHash
      }
    })),
    diagnostics: []
  };
}

function versionDispatch(value: unknown, sourcePath: string): Diagnostic | null {
  if (!isRecord(value) || !("schema_version" in value) || typeof value.schema_version !== "number") {
    return diagnostic("schema_error", "Use-case file must declare numeric schema_version: 1.", sourcePath);
  }
  if (value.schema_version !== 1) {
    return diagnostic("unknown_version", `Unsupported use-case schema_version ${value.schema_version}.`, sourcePath);
  }
  return null;
}

function failedFile(
  status: MatrixFileResult["status"],
  sourcePath: string,
  message: string,
  fileHash?: string
): UseCaseFileValidationResult {
  return {
    file: { path: sourcePath, status, file_hash: fileHash },
    candidates: [],
    diagnostics: [diagnostic(status, message, sourcePath)]
  };
}

function hashBytes(bytes: Buffer): string {
  return `sha256:${createHash("sha256").update(bytes).digest("hex")}`;
}

function messageFor(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
