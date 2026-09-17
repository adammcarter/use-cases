/// Walks `use-cases/` and loads every use-case file in it.
///
/// The port of `packages/core/src/useCases/loadUseCaseMatrix.ts`. Each
/// directory is listed in libuv's byte order and then stably re-sorted by
/// `localeCompare`, which fixes the order rows are found in. Entries are judged
/// by `lstat`, so a symlink — to a file, a directory, itself, or somewhere
/// outside — is rejected without ever being followed. The use-cases root
/// itself IS followed if it is a symlink.
///
/// A directory that cannot be listed or an entry that cannot be inspected is
/// not a diagnostic: the error escapes, as node's does.
public enum UseCaseMatrixLoader {
  public static func load(
    context: ResolvedWorkspaceContext,
    registry: SchemaRegistry,
  ) throws(UseCaseMatrixError) -> MatrixSnapshot {
    var files: [MatrixFileResult] = []
    var candidates: [LoadedUseCase] = []
    var diagnostics: [Diagnostic] = []

    let root = context.useCasesRoot
    if NodeFile.exists(atPath: root) {
      do throws(FileAccessError) {
        let walk = try Walk(dataRoot: context.dataRoot, rootRealPath: NodeFile.realPath(root))
        for entry in try walk.entries(in: root, diagnostics: &diagnostics, files: &files) {
          let result = UseCaseFileValidator.validate(
            filePath: entry.filePath,
            sourcePath: entry.sourcePath,
            registry: registry,
          )
          files.append(result.file)
          candidates += result.candidates
          diagnostics += result.diagnostics
        }
      } catch {
        throw .fileAccess(error)
      }
    }

    return MatrixSnapshot(
      context: context,
      files: files,
      candidates: candidates,
      diagnostics: diagnostics,
    )
  }

  private struct Entry {
    let filePath: String
    let sourcePath: String
  }

  private struct Walk {
    let dataRoot: String
    let rootRealPath: String

    /// `listUseCaseEntries`: the loadable files under `current`, depth first,
    /// recording every rejected entry as it is met.
    func entries(
      in current: String,
      diagnostics: inout [Diagnostic],
      files: inout [MatrixFileResult],
    ) throws(FileAccessError) -> [Entry] {
      let names = try NodeFile.directoryNames(atPath: current)
        .sorted(by: JavaScriptStringOrder.localeAscending)
      var results: [Entry] = []
      for name in names {
        let fullPath = NodePath.join(current, name)
        let sourcePath = NodePath.relative(from: dataRoot, to: fullPath)

        switch try NodeFile.kind(atPath: fullPath) {
        case .symbolicLink:
          files.append(MatrixFileResult(path: sourcePath, status: .symlinkRejected))
          diagnostics.append(Diagnostic(
            code: "symlink_rejected",
            message: "Symlinks under use-cases are not followed.",
            sourcePath: sourcePath,
          ))
        case .directory:
          results += try entries(in: fullPath, diagnostics: &diagnostics, files: &files)
        case .other:
          files.append(MatrixFileResult(path: sourcePath, status: .inputOutputError))
          diagnostics.append(Diagnostic(
            code: "io_error",
            message: "Only regular files are supported under use-cases.",
            sourcePath: sourcePath,
          ))
        case .regularFile:
          guard [".yml", ".yaml"].contains(NodePath.extname(fullPath)) else {
            continue
          }
          guard try Self.isContained(root: rootRealPath, child: NodeFile.realPath(fullPath)) else {
            files.append(MatrixFileResult(path: sourcePath, status: .pathEscape))
            diagnostics.append(Diagnostic(
              code: "path_escape",
              message: "Use-case file escapes use_cases_root.",
              sourcePath: sourcePath,
            ))
            continue
          }
          results.append(Entry(filePath: fullPath, sourcePath: sourcePath))
        }
      }
      return results
    }

    /// `relative(root, child)` is empty, or neither climbs nor is absolute.
    /// The climb test is a string prefix, so a file NAMED `..x.yml` directly
    /// under the root reads as escaping — the TypeScript's own verdict.
    private static func isContained(
      root: String,
      child: String,
    ) -> Bool {
      let relativePath = NodePath.relative(from: root, to: child)
      return relativePath.isEmpty
        || (!relativePath.utf16.starts(with: [CodeUnits.fullStop, CodeUnits.fullStop])
          && !NodePath.isAbsolute(relativePath))
    }
  }
}
