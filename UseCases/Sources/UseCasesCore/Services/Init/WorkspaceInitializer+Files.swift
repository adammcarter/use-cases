import Foundation

extension WorkspaceInitializer {
  /// A file `init` writes, and whether an existing workspace gains it.
  private struct Candidate {
    let path: WorkspacePath
    let text: String

    /// An existing workspace is given only what does not change what `status` and the gate
    /// report: the bridge settings template, never the example or the groups (chapter 17 §3).
    let joinsExistingWorkspace: Bool
  }

  /// Sorts the files of the form into the ones to make and the ones already there. A file that
  /// is there is left exactly as it is, whatever it holds; an existing workspace never gains the
  /// example or the groups.
  func files(
    _ form: InitForm,
    prefix: Namespace?,
    site: InitSite,
    in folder: URL,
  ) throws(InitError) -> InitFiles {
    var changes: [FileChange] = []
    var created: [String] = []
    var kept: [String] = []

    for candidate in candidates(
      form,
      prefix: prefix,
    ) {
      if try exists(
        candidate.path,
        in: folder,
      ) {
        kept.append(candidate.path.text)
      } else if site == .fresh || candidate.joinsExistingWorkspace {
        created.append(candidate.path.text)
        changes.append(
          .create(
            candidate.path,
            text: candidate.text,
          ),
        )
      }
    }

    return InitFiles(
      changes: changes,
      created: created,
      kept: kept,
    )
  }

  private func candidates(
    _ form: InitForm,
    prefix: Namespace?,
  ) -> [Candidate] {
    var candidates = [
      Candidate(
        path: .root.appending(literal: DiscoveredScope.configurationFileName),
        text: InitTemplates.workspace(prefix: prefix),
        joinsExistingWorkspace: false,
      ),
    ]

    guard form == .full else {
      return candidates
    }

    candidates += [
      Candidate(
        path: .root.appending(literal: "use-cases").appending(literal: "example.yml"),
        text: InitTemplates.example,
        joinsExistingWorkspace: false,
      ),
      Candidate(
        path: .root.appending(literal: "use-case-groups.yml"),
        text: InitTemplates.groups(prefix: prefix),
        joinsExistingWorkspace: false,
      ),
      Candidate(
        path: .root.appending(literal: "use-cases-bridge.yml"),
        text: InitTemplates.bridge,
        joinsExistingWorkspace: true,
      ),
    ]

    return candidates
  }

  /// Whether a regular file is at the path. Anything else there is in the way.
  private func exists(
    _ path: WorkspacePath,
    in folder: URL,
  ) throws(InitError) -> Bool {
    let kind: FileEntryKind?

    do {
      kind = try fileSystem.kindOfItem(at: folder.appendingPathComponent(path.text))
    } catch {
      throw .invalidWorkspace(problems: [error.description])
    }

    switch kind {
    case nil:
      return false
    case .file?:
      return true
    case .directory?:
      throw .obstructed(
        path: path.text,
        reason: "it is a folder, not a file",
      )
    case .symlink?:
      throw .obstructed(
        path: path.text,
        reason: "it is a symlink, not a file",
      )
    case .other?:
      throw .obstructed(
        path: path.text,
        reason: "it is not a regular file",
      )
    }
  }
}
