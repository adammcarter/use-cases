import Foundation

/// Plans `init` from the file system: which of the files of chapter 17 §2 are there, which are
/// missing and wanted, and what to do about `.gitignore`.
public struct WorkspaceInitializer: WorkspaceInitializing {
  let fileSystem: any FileSystemReading
  let schemaLoader: any SchemaLoading
  let yamlReader: any YAMLReading
  let scopeReader: any ScopeConfigurationReading
  let gitignorePlanner: any GitignorePlanning

  /// Makes the initializer that reads the real file system.
  public init() {
    let fileSystem = LocalFileSystem()

    self.init(
      fileSystem: fileSystem,
      schemaLoader: BundledSchemaLoader(),
      yamlReader: StrictYAMLReader(),
      scopeReader: ScopeConfigurationReader(),
      gitignorePlanner: GitignorePlanner(fileSystem: fileSystem),
    )
  }

  init(
    fileSystem: any FileSystemReading,
    schemaLoader: any SchemaLoading,
    yamlReader: any YAMLReading,
    scopeReader: any ScopeConfigurationReading,
    gitignorePlanner: any GitignorePlanning,
  ) {
    self.fileSystem = fileSystem
    self.schemaLoader = schemaLoader
    self.yamlReader = yamlReader
    self.scopeReader = scopeReader
    self.gitignorePlanner = gitignorePlanner
  }

  public func plan(_ request: InitRequest) throws(InitError) -> InitPlan {
    let prefix = try validated(request.prefix)
    let folder = try canonicalFolder(request.folder)
    let site = try site(of: folder)

    if case let .workspace(existing) = site, let prefix, prefix != existing {
      throw .differentPrefix(
        existing: existing?.text,
        asked: prefix.text,
      )
    }

    let files = try files(
      request.form,
      prefix: prefix,
      site: site,
      in: folder,
    )
    let gitignore = try gitignorePlanner.plan(for: folder)

    return InitPlan(
      root: folder,
      isExistingWorkspace: site != .fresh,
      writes: WritePlan(changes: files.changes + (gitignore.change.map { [$0] } ?? [])),
      created: files.created,
      kept: files.kept,
      gitignore: gitignore.outcome,
      notes: gitignore.notes,
    )
  }

  private func validated(_ text: String?) throws(InitError) -> Namespace? {
    guard let text else {
      return nil
    }

    do {
      return try Namespace(validating: text)
    } catch {
      throw .invalidPrefix(
        text: text,
        reason: error.reason,
      )
    }
  }

  private func canonicalFolder(_ folder: URL) throws(InitError) -> URL {
    let canonical = fileSystem.canonicalLocation(of: folder)

    let kind: FileEntryKind?

    do {
      kind = try fileSystem.kindOfItem(at: canonical)
    } catch {
      throw .invalidWorkspace(problems: [error.description])
    }

    guard kind == .directory else {
      throw .notAFolder(path: folder.path)
    }

    return canonical
  }
}
