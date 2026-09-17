import Foundation

/// Adds, replaces and retires rows in the committed use-case files.
///
/// The port of `packages/core/src/useCases/mutateUseCaseMatrix.ts`. The matrix
/// must load complete first. The target file is read into plain JSON — its
/// comments, quoting and block styles are NOT kept — changed, validated as a
/// whole, and written back through ``UseCaseFileEmitter`` to
/// `<file>.tmp-<pid>` in the same directory, then renamed over the original.
/// No fsync, as the TypeScript does none.
public enum UseCaseMatrixMutator {
  static let recordedAt = "1970-01-01T00:00:00.000Z"

  public static func mutate(
    _ options: UseCaseMutationOptions,
    registry: SchemaRegistry,
  ) throws(UseCaseMatrixError) -> UseCaseMutationResult {
    let matrix = try UseCaseMatrixLoader.load(context: options.context, registry: registry)
    guard matrix.isComplete else {
      return blocked(
        options,
        "matrix.mutation_incomplete_matrix",
        "Use cases must be complete before mutation.",
      )
    }
    switch options.operation {
    case .upsert:
      return try upsert(options, registry: registry)
    case .remove:
      return try remove(options, registry: registry)
    }
  }

  // MARK: - Upsert

  private static func upsert(
    _ options: UseCaseMutationOptions,
    registry: SchemaRegistry,
  ) throws(UseCaseMatrixError) -> UseCaseMutationResult {
    guard let targetFile = present(options.targetFile), let useCase = options.useCase else {
      return blocked(options, "matrix.mutation_invalid_arguments", "Missing targetFile or useCase.")
    }
    guard let identifier = present(useCase["id"]?.stringValue) else {
      return blocked(
        options,
        "matrix.mutation_missing_use_case_id",
        "Use case JSON must include an id.",
      )
    }
    let target: Target
    switch resolveTarget(options.context, targetFile) {
    case let .refused(code, message):
      return blocked(options, code, message, identifier: identifier)
    case let .resolved(resolved):
      target = resolved
    }
    let file: UseCaseFileContents
    switch try read(fullPath: target.fullPath) {
    case let .refused(code, message):
      return blocked(options, code, message, identifier: identifier, filePath: target.sourcePath)
    case let .read(contents):
      file = contents
    }

    let existingIndex = index(of: identifier, in: file.rows)
    var change = Change(
      operation: .upsert,
      identifier: identifier,
      sourcePath: target.sourcePath,
      fullPath: target.fullPath,
      beforeHash: existingIndex.map { position in
        SemanticHash.compute(file.rows[position])
      },
      document: file.document,
      rows: file.rows,
    )
    if change.beforeHash != nil, let mismatch = hashMismatch(options, change) {
      return mismatch
    }
    if let existingIndex {
      change.rows[existingIndex] = .object(useCase)
    } else {
      change.rows.append(.object(useCase))
    }
    return try commit(
      change,
      writing: useCase,
      as: existingIndex == nil ? .created : .updated,
      registry: registry,
    )
  }

  // MARK: - Remove

  private static func remove(
    _ options: UseCaseMutationOptions,
    registry: SchemaRegistry,
  ) throws(UseCaseMatrixError) -> UseCaseMutationResult {
    guard let identifier = present(options.useCaseIdentifier),
          let reason = present(options.reason)
    else {
      return blocked(options, "matrix.mutation_invalid_arguments", "Missing useCaseId or reason.")
    }
    // The TypeScript loads the matrix a second time here; so does the port.
    let matrix = try UseCaseMatrixLoader.load(context: options.context, registry: registry)
    let resolution = matrix.resolveUseCase(identifier)
    guard case let .resolved(_, resolved) = resolution else {
      let message = "Use case '\(identifier)' is \(resolution.kind)."
      return blocked(
        options,
        "matrix.mutation_unresolved_use_case",
        message,
        identifier: identifier,
      )
    }
    let sourcePath = resolved.source.path
    let fullPath = NodePath.join(options.context.dataRoot, sourcePath)
    let file: UseCaseFileContents
    switch try read(fullPath: fullPath) {
    case let .refused(code, message):
      return blocked(options, code, message, identifier: identifier, filePath: sourcePath)
    case let .read(contents):
      file = contents
    }

    guard let existingIndex = index(of: identifier, in: file.rows),
          let existing = file.rows[existingIndex].objectValue
    else {
      let message = "Use case '\(identifier)' was not found in its source file."
      let code = "matrix.mutation_unresolved_use_case"
      return blocked(options, code, message, identifier: identifier, filePath: sourcePath)
    }
    var change = Change(
      operation: .remove,
      identifier: identifier,
      sourcePath: sourcePath,
      fullPath: fullPath,
      beforeHash: SemanticHash.compute(file.rows[existingIndex]),
      document: file.document,
      rows: file.rows,
    )
    if let mismatch = hashMismatch(options, change) {
      return mismatch
    }
    let next = retired(existing, reason: reason, actor: options.actor ?? "agent")
    change.rows[existingIndex] = .object(next)
    return try commit(change, writing: next, as: .removed, registry: registry)
  }

  /// The existing row's hash against a non-empty `expectedSemanticHash`.
  private static func hashMismatch(
    _ options: UseCaseMutationOptions,
    _ change: Change,
  ) -> UseCaseMutationResult? {
    guard let expected = present(options.expectedSemanticHash), expected != change.beforeHash else {
      return nil
    }
    return blocked(
      options,
      "matrix.mutation_hash_mismatch",
      "Existing use-case hash did not match expected hash.",
      identifier: change.identifier,
      filePath: change.sourcePath,
      beforeHash: change.beforeHash,
    )
  }

  /// `{ ...existing, lifecycle: "removed", extensions: { ...extensions,
  /// "use-cases/removal": { ...removal, reason, actor, recorded_at } } }`: a key
  /// already present keeps its place, a new one goes last.
  private static func retired(
    _ existing: JSONObject,
    reason: String,
    actor: String,
  ) -> JSONObject {
    var next = existing
    next["lifecycle"] = .string("removed")
    var extensions = existing["extensions"]?.objectValue ?? JSONObject()
    var removal = extensions["use-cases/removal"]?.objectValue ?? JSONObject()
    removal["reason"] = .string(reason)
    removal["actor"] = .string(actor)
    removal["recorded_at"] = .string(recordedAt)
    extensions["use-cases/removal"] = .object(removal)
    next["extensions"] = .object(extensions)
    return next
  }

  // MARK: - Committing

  /// A mutation that got as far as changing a row: whose, where, and the rows
  /// of the document with the change applied.
  private struct Change {
    let operation: UseCaseMutationOperation
    let identifier: String
    let sourcePath: String
    let fullPath: String
    let beforeHash: String?
    let document: JSONObject
    var rows: [JSONValue]
  }

  /// The changed rows go back into the document, the WHOLE document is
  /// validated, and only a valid document is written.
  private static func commit(
    _ change: Change,
    writing row: JSONObject,
    as status: UseCaseMutationStatus,
    registry: SchemaRegistry,
  ) throws(UseCaseMatrixError) -> UseCaseMutationResult {
    var document = change.document
    document["use_cases"] = .array(change.rows)
    let validation = registry.validate(
      schemaIdentifier: UseCaseFileValidator.schemaIdentifier,
      value: .object(document),
      sourcePath: change.sourcePath,
    )
    let isValid = validation.isValid
    if isValid {
      try write(document, fullPath: change.fullPath)
    }
    return UseCaseMutationResult(
      operation: change.operation,
      status: isValid ? status : .blocked,
      useCaseIdentifier: change.identifier,
      filePath: change.sourcePath,
      beforeHash: change.beforeHash,
      afterHash: isValid ? SemanticHash.compute(.object(row)) : nil,
      diagnostics: isValid ? [] : validation.diagnostics,
    )
  }

  // MARK: - Helpers

  /// JavaScript truthiness for an optional string: present and not empty.
  static func present(_ text: String?) -> String? {
    guard let text, !text.isEmpty else {
      return nil
    }
    return text
  }

  /// `rows.findIndex((item) => item.id === identifier)`.
  private static func index(
    of identifier: String,
    in rows: [JSONValue],
  ) -> Int? {
    rows.firstIndex { row in
      guard let rowIdentifier = row["id"]?.stringValue else {
        return false
      }
      return rowIdentifier.utf16.elementsEqual(identifier.utf16)
    }
  }

  /// `blocked(...)`: one diagnostic, and the caller's own `useCaseId` unless a
  /// resolved id is given.
  private static func blocked(
    _ options: UseCaseMutationOptions,
    _ code: String,
    _ message: String,
    identifier: String? = nil,
    filePath: String? = nil,
    beforeHash: String? = nil,
  ) -> UseCaseMutationResult {
    let reportedIdentifier = identifier ?? options.useCaseIdentifier
    return UseCaseMutationResult(
      operation: options.operation,
      status: .blocked,
      useCaseIdentifier: reportedIdentifier,
      filePath: filePath,
      beforeHash: beforeHash,
      afterHash: nil,
      diagnostics: [Diagnostic(
        code: code,
        message: message,
        sourcePath: filePath,
        entityIdentifier: reportedIdentifier,
      )],
    )
  }
}
