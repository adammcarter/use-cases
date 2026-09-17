/// Loads every capsule under `demo-capsules/`
/// (packages/core/src/capsules/loadCapsule.ts).
///
/// Each directory is listed in libuv's byte order and then stably re-sorted
/// by `localeCompare`. Entries are judged by `lstat`, so a symlink is rejected
/// without being followed; the root itself IS followed. The whole tree is
/// walked before any file is read, so every rejected entry is listed before
/// the first file read. A directory that cannot be listed or a file that
/// cannot be read is not a diagnostic: node's error escapes.
public enum DemoCapsuleLoader {
  static let schemaIdentifier = "https://use-cases.dev/schemas/v1/demo-capsule.schema.json"

  /// `demoCapsulesRoot`.
  public static func root(context: ResolvedWorkspaceContext) -> String {
    NodePath.join(context.dataRoot, "demo-capsules")
  }

  /// `loadDemoCapsules`.
  public static func load(
    context: ResolvedWorkspaceContext,
    registry: SchemaRegistry,
  ) throws(DemoCapsuleError) -> CapsuleSnapshot {
    var files: [CapsuleFileResult] = []
    var capsules: [LoadedDemoCapsule] = []
    var diagnostics: [Diagnostic] = []
    let root = root(context: context)
    guard NodeFile.exists(atPath: root) else {
      return CapsuleSnapshot(files: files, capsules: capsules, diagnostics: diagnostics)
    }

    var seen: [CodeUnitKey: String] = [:]
    do throws(FileAccessError) {
      let walk = try Walk(dataRoot: context.dataRoot, rootRealPath: NodeFile.realPath(root))
      for entry in try walk.entries(in: root, diagnostics: &diagnostics, files: &files) {
        let result = try validate(entry, registry: registry)
        files.append(result.file)
        diagnostics += result.diagnostics
        guard let capsule = result.capsule else {
          continue
        }
        let identifier = capsule.definition.capsuleIdentifier
        if let duplicatePath = seen[CodeUnitKey(identifier)] {
          diagnostics.append(Diagnostic(
            code: "capsule.duplicate_id",
            message: "Duplicate capsule id '\(identifier)'.",
            sourcePath: capsule.path,
            entityIdentifier: identifier,
            relatedIdentifiers: [duplicatePath],
          ))
          files[files.count - 1] = result.file.with(status: .schemaError)
          continue
        }
        seen[CodeUnitKey(identifier)] = capsule.path
        capsules.append(capsule)
      }
    } catch {
      throw .fileAccess(error)
    }

    return CapsuleSnapshot(files: files, capsules: capsules, diagnostics: diagnostics)
  }

  /// `validateCapsuleFile`.
  private static func validate(
    _ entry: Entry,
    registry: SchemaRegistry,
  ) throws(FileAccessError) -> Validated {
    let source = try NodeFile.readText(atPath: entry.filePath)
    let fileHash = SemanticHash.compute(.string(source))
    let parsed = parse(source, sourcePath: entry.sourcePath, filePath: entry.filePath)
    guard parsed.isValid, let value = parsed.value.map(JavaScriptPropertyOrder.reordered) else {
      return Validated(
        file: CapsuleFileResult(path: entry.sourcePath, status: .parseError, fileHash: fileHash),
        capsule: nil,
        diagnostics: parsed.diagnostics,
      )
    }
    let validation = registry.validate(
      schemaIdentifier: schemaIdentifier,
      value: value,
      sourcePath: entry.sourcePath,
    )
    guard validation.isValid, let definition = DemoCapsule(value) else {
      return Validated(
        file: CapsuleFileResult(path: entry.sourcePath, status: .schemaError, fileHash: fileHash),
        capsule: nil,
        diagnostics: validation.diagnostics,
      )
    }
    return Validated(
      file: CapsuleFileResult(path: entry.sourcePath, status: .loaded, fileHash: fileHash),
      capsule: LoadedDemoCapsule(
        capsule: value,
        definition: definition,
        path: entry.sourcePath,
        semanticHash: SemanticHash.compute(value),
      ),
      diagnostics: [],
    )
  }

  /// `parseCapsuleSource`: `JSON.parse` for `.json`, the YAML reader for the
  /// rest. `JSON.parse`'s own message wording is not reproduced.
  private static func parse(
    _ source: String,
    sourcePath: String,
    filePath: String,
  ) -> ParsedYamlResult {
    guard NodePath.extname(filePath) == ".json" else {
      return YamlParser.parseToJSON(
        source: UseCaseFileValidator.strippingYamlByteOrderMark(source),
        sourcePath: sourcePath,
      )
    }
    do throws(SchemaError) {
      return try ParsedYamlResult(isValid: true, value: JSONParser.parse(source), diagnostics: [])
    } catch {
      return ParsedYamlResult(
        isValid: false,
        value: nil,
        diagnostics: [Diagnostic(
          code: "parse_error",
          message: error.message,
          sourcePath: sourcePath,
        )],
      )
    }
  }

  /// What reading one file gave: its entry, the capsule if it loaded, and
  /// the diagnostics if it did not.
  private struct Validated {
    let file: CapsuleFileResult
    let capsule: LoadedDemoCapsule?
    let diagnostics: [Diagnostic]
  }

  private struct Entry {
    let filePath: String
    let sourcePath: String
  }

  private struct Walk {
    let dataRoot: String
    let rootRealPath: String

    /// `listCapsuleEntries`: the loadable files under `current`, depth first,
    /// recording every rejected entry as it is met.
    func entries(
      in current: String,
      diagnostics: inout [Diagnostic],
      files: inout [CapsuleFileResult],
    ) throws(FileAccessError) -> [Entry] {
      let names = try NodeFile.directoryNames(atPath: current)
        .sorted(by: JavaScriptStringOrder.localeAscending)
      var results: [Entry] = []
      for name in names {
        let fullPath = NodePath.join(current, name)
        let sourcePath = NodePath.relative(from: dataRoot, to: fullPath)
        switch try NodeFile.kind(atPath: fullPath) {
        case .symbolicLink:
          reject(
            sourcePath,
            .symlinkRejected,
            "Symlinks under demo-capsules are not followed.",
            &diagnostics,
            &files,
          )
        case .directory:
          results += try entries(in: fullPath, diagnostics: &diagnostics, files: &files)
        case .other:
          reject(
            sourcePath,
            .inputOutputError,
            "Only regular files are supported under demo-capsules.",
            &diagnostics,
            &files,
          )
        case .regularFile:
          guard [".yml", ".yaml", ".json"].contains(NodePath.extname(fullPath)) else {
            continue
          }
          guard try Self.isContained(root: rootRealPath, child: NodeFile.realPath(fullPath)) else {
            reject(
              sourcePath,
              .pathEscape,
              "Capsule file escapes demo-capsules root.",
              &diagnostics,
              &files,
            )
            continue
          }
          results.append(Entry(filePath: fullPath, sourcePath: sourcePath))
        }
      }
      return results
    }

    private func reject(
      _ sourcePath: String,
      _ status: CapsuleFileStatus,
      _ message: String,
      _ diagnostics: inout [Diagnostic],
      _ files: inout [CapsuleFileResult],
    ) {
      files.append(CapsuleFileResult(path: sourcePath, status: status))
      diagnostics.append(Diagnostic(
        code: "capsule.\(status.rawValue)",
        message: message,
        sourcePath: sourcePath,
      ))
    }

    /// `relative(root, child)` neither climbs nor is absolute. The climb test
    /// is a string prefix, so a file NAMED `..x.json` directly under the root
    /// reads as escaping — the TypeScript's own verdict.
    private static func isContained(
      root: String,
      child: String,
    ) -> Bool {
      let relativePath = NodePath.relative(from: root, to: child)
      return !relativePath.utf16.starts(with: [CodeUnits.fullStop, CodeUnits.fullStop])
        && !NodePath.isAbsolute(relativePath)
    }
  }
}
