import Foundation

struct GroupsLoader: GroupsLoading {
  /// The one name the file has (chapter 03).
  static let fileName = "use-case-groups.yml"

  private let fileSystem: any FileSystemReading
  private let yamlReader: any YAMLReading
  private let schema: any SchemaChecking
  private let resolver: any GroupResolving
  private let locator: any OwnedFileLocating

  /// - Parameter schema: The checker for the groups schema.
  init(
    fileSystem: any FileSystemReading,
    yamlReader: any YAMLReading,
    schema: any SchemaChecking,
    resolver: any GroupResolving,
    locator: any OwnedFileLocating,
  ) {
    self.fileSystem = fileSystem
    self.yamlReader = yamlReader
    self.schema = schema
    self.resolver = resolver
    self.locator = locator
  }

  func load(
    in root: WorkspaceRoot,
    scopes: [LoadedScope],
    among known: KnownUseCases,
  ) -> GroupsLoadResult {
    let file = WorkspacePath.root.appending(literal: Self.fileName)
    let location: OwnedFileLocation

    do {
      location = try locator.locate(
        Self.fileName,
        in: root,
        scopes: scopes,
        belowRoot: Diagnostic.groupsBelowRoot,
      )
    } catch {
      return problems([.unreadableGroups(file, because: error)])
    }

    guard let entry = location.entry else {
      return problems(location.diagnostics)
    }

    guard entry.kind == .file else {
      return problems(location.diagnostics + [.groupsNotAFile(file, kind: entry.kind)])
    }

    let text: String

    do {
      text = try fileSystem.readText(at: root.location(of: file))
    } catch {
      return problems(location.diagnostics + [.unreadableGroups(file, because: error)])
    }

    let read = read(
      text,
      file: file,
      among: known,
    )

    return GroupsLoadResult(
      groups: read.groups,
      diagnostics: location.diagnostics + read.diagnostics,
    )
  }

  private func read(
    _ text: String,
    file: WorkspacePath,
    among known: KnownUseCases,
  ) -> GroupsLoadResult {
    let value: AuthoredValue

    do {
      value = try yamlReader.read(
        text,
        file: file.text,
        kind: .settings,
      )
    } catch {
      return problems([error.diagnostic(in: file)])
    }

    let failures = schema.check(value)

    guard failures.isEmpty else {
      return problems(
        failures.map { failure in
          failure.diagnostic(in: file)
        }.sorted(),
      )
    }

    let parsed: GroupsFile

    do {
      parsed = try GroupsFile(authored: AuthoredObject(value, at: ""))
    } catch {
      return problems([Diagnostic(error: .invalidValue, in: file, message: error.description)])
    }

    return resolver.resolve(
      parsed,
      among: known,
      in: file,
    )
  }

  private func problems(_ diagnostics: [Diagnostic]) -> GroupsLoadResult {
    GroupsLoadResult(
      groups: [],
      diagnostics: diagnostics,
    )
  }
}
