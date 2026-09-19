/// One file's outcome, the rows it offers, and what was wrong with it.
public struct UseCaseFileValidationResult: Sendable, Equatable {
  public let file: MatrixFileResult
  public let candidates: [LoadedUseCase]
  public let diagnostics: [Diagnostic]
}

/// The rows a file offers, and the rows it could not.
private struct LoadedRows {
  let candidates: [LoadedUseCase]
  let diagnostics: [Diagnostic]
}

/// Reads and validates one use-case file.
///
/// The port of `packages/core/src/useCases/validateUseCaseFile.ts`. The file is
/// read as BYTES: the byte hash is taken over exactly what is on disk, and the
/// bytes are then decoded as `new TextDecoder("utf-8", { fatal: true })`
/// decodes them — one leading byte-order mark dropped, and any ill-formed
/// sequence failing the whole file as `parse_error`.
public enum UseCaseFileValidator {
  static let schemaIdentifier = "https://use-cases.dev/schemas/v1/use-case-file.schema.json"

  /// The text of the `TypeError` node's `TextDecoder` throws on bad UTF-8.
  static let invalidEncodingMessage = "The encoded data was not valid for encoding utf-8"

  public static func validate(
    filePath: String,
    sourcePath: String,
    registry: SchemaRegistry,
  ) -> UseCaseFileValidationResult {
    let bytes: [UInt8]
    do throws(FileAccessError) {
      bytes = try NodeFile.readBytes(atPath: filePath)
    } catch {
      return failed(.inputOutputError, sourcePath: sourcePath, message: error.message)
    }

    let fileHash = MarkerDigest.sha256(bytes: bytes)
    guard let source = decodeStrictly(bytes) else {
      return failed(
        .parseError,
        sourcePath: sourcePath,
        message: invalidEncodingMessage,
        fileHash: fileHash,
      )
    }

    let parsed = YamlParser.parseToJSON(
      source: strippingYamlByteOrderMark(source),
      sourcePath: sourcePath,
    )
    guard parsed.isValid, let value = parsed.value else {
      return UseCaseFileValidationResult(
        file: MatrixFileResult(path: sourcePath, status: .parseError, fileHash: fileHash),
        candidates: [],
        diagnostics: parsed.diagnostics,
      )
    }

    return validateParsed(value, sourcePath: sourcePath, fileHash: fileHash, registry: registry)
  }

  /// Version dispatch, then the schema, then the rows, for a file that parsed.
  private static func validateParsed(
    _ value: JSONValue,
    sourcePath: String,
    fileHash: String,
    registry: SchemaRegistry,
  ) -> UseCaseFileValidationResult {
    func result(
      _ status: MatrixFileStatus,
      _ diagnostics: [Diagnostic],
      _ candidates: [LoadedUseCase] = [],
    ) -> UseCaseFileValidationResult {
      UseCaseFileValidationResult(
        file: MatrixFileResult(
          path: sourcePath,
          status: status,
          semanticHash: SemanticHash.compute(value),
          fileHash: fileHash,
        ),
        candidates: candidates,
        diagnostics: diagnostics,
      )
    }
    if let versionDiagnostic = versionDiagnostic(for: value, sourcePath: sourcePath) {
      let status: MatrixFileStatus = versionDiagnostic
        .code == "unknown_version" ? .unknownVersion : .schemaError
      return result(status, [versionDiagnostic])
    }
    let validation = registry.validate(
      schemaIdentifier: schemaIdentifier,
      value: value,
      sourcePath: sourcePath,
    )
    guard validation.isValid else {
      return result(.schemaError, validation.diagnostics.map(renamingMissingVersion))
    }
    let rows = loadedRows(of: value, sourcePath: sourcePath, fileHash: fileHash)
    return result(.loaded, rows.diagnostics, rows.candidates)
  }

  /// Every row of a schema-valid file as a candidate — except a row declaring
  /// the same variant key twice, which is reported instead. JSON Schema can
  /// constrain each key but not their uniqueness across siblings.
  private static func loadedRows(
    of value: JSONValue,
    sourcePath: String,
    fileHash: String,
  ) -> LoadedRows {
    let feature = value["feature"]?.objectValue ?? JSONObject()
    var candidates: [LoadedUseCase] = []
    var diagnostics: [Diagnostic] = []
    for (index, element) in (value["use_cases"]?.arrayValue ?? []).enumerated() {
      guard let useCase = element.objectValue else {
        continue
      }
      let identifier = useCase["id"]?.stringValue ?? ""
      if let duplicate = firstDuplicateVariantKey(useCase["variants"]) {
        diagnostics.append(Diagnostic(
          code: "duplicate_variant_key",
          message: "Use case \(identifier) declares variant key \"\(duplicate)\" more than once.",
          sourcePath: sourcePath,
          entityIdentifier: identifier,
        ))
        continue
      }
      candidates.append(LoadedUseCase(
        value: useCase,
        feature: feature,
        semanticHash: SemanticHash.compute(element),
        source: UseCaseSource(
          path: sourcePath,
          jsonPointer: "/use_cases/\(index)",
          fileByteHash: fileHash,
        ),
      ))
    }
    return LoadedRows(candidates: candidates, diagnostics: diagnostics)
  }

  /// Fatal UTF-8 decoding with the byte-order mark stripped once, or nil when
  /// any sequence is ill-formed (overlong, surrogate, beyond U+10FFFF,
  /// truncated).
  static func decodeStrictly(_ bytes: [UInt8]) -> String? {
    var scalars = String.UnicodeScalarView()
    var decoder = UTF8()
    var iterator = bytes.makeIterator()
    var isFirst = true
    while true {
      switch decoder.decode(&iterator) {
      case let .scalarValue(scalar):
        if !(isFirst && scalar == "\u{FEFF}") {
          scalars.append(scalar)
        }
        isFirst = false
      case .error:
        return nil
      case .emptyInput:
        return String(scalars)
      }
    }
  }

  /// The `yaml` package's lexer skips one byte-order mark at the start of the
  /// text it is given; ``YamlParser`` hands the text to Yams, which refuses it.
  /// Every TypeScript read path therefore parses text with ONE more mark
  /// removed than it decoded: the validator's (after `TextDecoder` already
  /// dropped one) and the mutator's (`readFileSync(…, "utf8")` drops none).
  static func strippingYamlByteOrderMark(_ source: String) -> String {
    guard source.unicodeScalars.first == "\u{FEFF}" else {
      return source
    }
    return String(source.unicodeScalars.dropFirst())
  }

  /// A numeric `schema_version` of exactly 1, or the diagnostic saying why not.
  private static func versionDiagnostic(
    for value: JSONValue,
    sourcePath: String,
  ) -> Diagnostic? {
    guard let version = value["schema_version"]?.numberValue else {
      return Diagnostic(
        code: "schema_error",
        message: "Use-case file must declare numeric schema_version: 1.",
        sourcePath: sourcePath,
      )
    }
    guard version == 1 else {
      return Diagnostic(
        code: "unknown_version",
        message: "Unsupported use-case schema_version \(javaScriptString(version)).",
        sourcePath: sourcePath,
      )
    }
    return nil
  }

  /// `String(number)`: ``JavaScriptNumber`` for finite values, and JavaScript's
  /// own words for the rest.
  private static func javaScriptString(_ number: Double) -> String {
    if number.isNaN {
      return "NaN"
    }
    if number.isInfinite {
      return number < 0 ? "-Infinity" : "Infinity"
    }
    return JavaScriptNumber.text(number)
  }

  private static func renamingMissingVersion(_ diagnostic: Diagnostic) -> Diagnostic {
    guard diagnostic.code == "schema_version.required" else {
      return diagnostic
    }
    return Diagnostic(
      code: "schema_error",
      severity: diagnostic.severity,
      message: diagnostic.message,
      sourcePath: diagnostic.sourcePath,
      jsonPointer: diagnostic.jsonPointer,
      sourceSpan: diagnostic.sourceSpan,
      entityIdentifier: diagnostic.entityIdentifier,
      relatedIdentifiers: diagnostic.relatedIdentifiers,
    )
  }

  /// The first variant key seen twice. Variant keys match `^[a-z0-9_-]+$`, so
  /// Swift string identity is code-unit identity here.
  private static func firstDuplicateVariantKey(_ variants: JSONValue?) -> String? {
    var seen = Set<String>()
    for variant in variants?.arrayValue ?? [] {
      let key = variant["key"]?.stringValue ?? ""
      if seen.contains(key) {
        return key
      }
      seen.insert(key)
    }
    return nil
  }

  private static func failed(
    _ status: MatrixFileStatus,
    sourcePath: String,
    message: String,
    fileHash: String? = nil,
  ) -> UseCaseFileValidationResult {
    UseCaseFileValidationResult(
      file: MatrixFileResult(path: sourcePath, status: status, fileHash: fileHash),
      candidates: [],
      diagnostics: [Diagnostic(code: status.rawValue, message: message, sourcePath: sourcePath)],
    )
  }
}
