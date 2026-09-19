import Foundation

/// A use-case file read into JSON: the whole document, and its `use_cases`.
struct UseCaseFileContents {
  let document: JSONObject
  let rows: [JSONValue]
}

/// Finding, reading and atomically rewriting the file a mutation targets.
extension UseCaseMatrixMutator {
  struct Target {
    let fullPath: String
    let sourcePath: String
  }

  enum TargetResolution {
    case resolved(Target)
    case refused(code: String, message: String)
  }

  enum ReadResult {
    case read(UseCaseFileContents)
    case refused(code: String, message: String)
  }

  /// `resolveTargetFile`: backslashes become slashes; an absolute path or any
  /// `..` segment is refused; only `.yml`/`.yaml`; a leading `use-cases/` is
  /// dropped whatever the configured directory is called; and a path whose
  /// relative form STARTS with `..` — including a name like `..x.yml` — is
  /// refused as an escape.
  static func resolveTarget(
    _ context: ResolvedWorkspaceContext,
    _ requestedPath: String,
  ) -> TargetResolution {
    var scalars = String.UnicodeScalarView()
    for scalar in requestedPath.unicodeScalars {
      scalars.append(scalar == "\\" ? "/" : scalar)
    }
    let normalized = String(scalars)
    let escapes: TargetResolution = .refused(
      code: "matrix.mutation_path_escape",
      message: "Target file must stay under use-cases.",
    )
    let segments = normalized.utf16.split(
      separator: CodeUnits.solidus,
      omittingEmptySubsequences: false,
    )
    let climbs = segments.contains { segment in
      segment.elementsEqual(parentSegment)
    }
    if NodePath.isAbsolute(normalized) || climbs {
      return escapes
    }
    guard [".yml", ".yaml"].contains(NodePath.extname(normalized)) else {
      return .refused(
        code: "matrix.mutation_invalid_file",
        message: "Target file must be .yml or .yaml.",
      )
    }
    let prefix = Array("use-cases/".utf16)
    let stripped = normalized.utf16.starts(with: prefix)
      ? CodeUnits.string(normalized.utf16.dropFirst(prefix.count))
      : normalized
    let fullPath = NodePath.join(context.useCasesRoot, stripped)
    let relativePath = NodePath.relative(from: context.useCasesRoot, to: fullPath)
    if relativePath.isEmpty || relativePath.utf16.starts(with: parentSegment) || NodePath
      .isAbsolute(relativePath)
    {
      return escapes
    }
    return .resolved(Target(
      fullPath: fullPath,
      sourcePath: NodePath.relative(from: context.dataRoot, to: fullPath),
    ))
  }

  /// `readUseCaseFile`: `readFileSync(path, "utf8")` — lenient decoding, a
  /// byte-order mark left for the parser to skip — then parsed to JSON.
  static func read(fullPath: String) throws(UseCaseMatrixError) -> ReadResult {
    guard NodeFile.exists(atPath: fullPath) else {
      return .refused(
        code: "matrix.mutation_file_missing",
        message: "Target use-case file does not exist.",
      )
    }
    let source: String
    do throws(FileAccessError) {
      source = try NodeFile.readText(atPath: fullPath)
    } catch {
      throw .fileAccess(error)
    }
    let parsed = YamlParser.parseToJSON(
      source: UseCaseFileValidator.strippingYamlByteOrderMark(source),
      sourcePath: fullPath,
    )
    guard parsed.isValid else {
      return .refused(
        code: "matrix.mutation_parse_error",
        message: parsed.diagnostics.first?.message ?? "Could not parse target YAML.",
      )
    }
    guard let document = parsed.value?.objectValue,
          let rows = document["use_cases"]?.arrayValue
    else {
      return .refused(
        code: "matrix.mutation_invalid_file",
        message: "Target file is not a use-case file.",
      )
    }
    return .read(UseCaseFileContents(document: document, rows: rows))
  }

  /// `writeUseCaseFile`: the parent directory made, the YAML written to
  /// `<path>.tmp-<pid>` beside the file, and renamed over it.
  static func write(
    _ document: JSONObject,
    fullPath: String,
  ) throws(UseCaseMatrixError) {
    let temporaryPath = "\(fullPath).tmp-\(getpid())"
    do throws(FileAccessError) {
      try NodeFile.makeDirectories(atPath: WorkspacePath.dirname(fullPath))
      try NodeFile.writeText(UseCaseFileEmitter.stringify(document), atPath: temporaryPath)
    } catch {
      throw .fileAccess(error)
    }
    guard rename(temporaryPath, fullPath) == 0 else {
      throw .fileAccess(FileAccessError(
        errorNumber: errno,
        operation: "rename",
        path: temporaryPath,
        destination: fullPath,
      ))
    }
  }

  private static let parentSegment: [UInt16] = [CodeUnits.fullStop, CodeUnits.fullStop]
}
