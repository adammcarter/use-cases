import Foundation

/// Plans the `.use-cases/` line of `.gitignore` (chapter 17 §6): the results store is generated
/// and not committed.
struct GitignorePlanner: GitignorePlanning {
  /// What the plan comes to: the outcome, the write when there is one, and what to tell.
  struct Plan: Equatable {
    let outcome: GitignoreOutcome
    let change: FileChange?
    let notes: [String]
  }

  /// The line `init` writes.
  static let line = ".use-cases/"

  private static let excluding: Set = [".use-cases", ".use-cases/", "/.use-cases", "/.use-cases/"]
  private static let name = ".gitignore"

  private let fileSystem: any FileSystemReading

  init(fileSystem: any FileSystemReading) {
    self.fileSystem = fileSystem
  }

  /// The line is added when the folder has a `.git` (a folder, or the file a worktree or a
  /// submodule has) or a `.gitignore`, and no line already excludes the store.
  func plan(for root: URL) throws(InitError) -> Plan {
    let ignore = root.appendingPathComponent(Self.name)
    let existing = try kind(of: ignore)
    let hasGit = try kind(of: root.appendingPathComponent(".git")) != nil

    guard existing != nil || hasGit else {
      return skipped(note: noVersionControlNote(for: root))
    }

    switch existing {
    case nil:
      return added(
        to: [],
        action: .create,
      )
    case .file?:
      return edit(ignore)
    case .directory?, .symlink?, .other?:
      return skipped(note: "\(Self.name) is not a regular file: add \(Self.line) to it yourself")
    }
  }

  private func edit(_ ignore: URL) -> Plan {
    let bytes: [UInt8]

    do {
      bytes = try fileSystem.readBytes(at: ignore)
    } catch {
      return skipped(note: "\(Self.name) cannot be read: add \(Self.line) to it yourself")
    }

    let lines = (String(bytes: bytes, encoding: .utf8) ?? "")
      .split(
        omittingEmptySubsequences: false,
        whereSeparator: \.isNewline,
      )
      .map { line in
        line.trimmingCharacters(in: CharacterSet(charactersIn: " \r"))
      }

    guard !lines.contains(where: Self.excluding.contains) else {
      return Plan(
        outcome: .present,
        change: nil,
        notes: [],
      )
    }

    return added(
      to: bytes,
      action: .replace,
    )
  }

  /// The existing bytes and the line after them, on a line of its own.
  private func added(
    to bytes: [UInt8],
    action: FileChangeAction,
  ) -> Plan {
    let separator: [UInt8] = bytes.isEmpty || bytes.last == 0x0A ? [] : [0x0A]

    return Plan(
      outcome: .added,
      change: FileChange(
        action: action,
        path: .root.appending(literal: Self.name),
        bytes: bytes + separator + Array((Self.line + "\n").utf8),
      ),
      notes: [],
    )
  }

  private func skipped(note: String) -> Plan {
    Plan(
      outcome: .skipped,
      change: nil,
      notes: [note],
    )
  }

  /// Names git when the workspace sits in a subfolder of a git repository, which needs the line
  /// in that repository's `.gitignore`.
  private func noVersionControlNote(for root: URL) -> String {
    var folder = root

    while folder.path != "/" {
      folder = folder.deletingLastPathComponent()

      if (try? fileSystem.kindOfItem(at: folder.appendingPathComponent(".git"))) != nil {
        return "this folder is inside the git repository at \(folder.path): add \(Self.line) "
          + "to that repository's \(Self.name) so the results store is not committed"
      }
    }

    return "no version control found here: exclude \(Self.line) from whatever you use, so the "
      + "results store is not committed"
  }

  private func kind(of location: URL) throws(InitError) -> FileEntryKind? {
    do {
      return try fileSystem.kindOfItem(at: location)
    } catch {
      throw .obstructed(
        path: location.path,
        reason: error.description,
      )
    }
  }
}
