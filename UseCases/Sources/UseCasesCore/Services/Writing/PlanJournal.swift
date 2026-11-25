import Foundation

/// What a plan being written has done so far, so that all of it can be undone or, when the plan
/// is through, tidied: the folders it made, the staged files and backups it left beside targets,
/// and the swaps it has made.
struct PlanJournal {
  /// One change made to a target, and how to take it back.
  enum Swap {
    /// A new name was made; taking it back removes it.
    case created(URL)

    /// A file was replaced and its original kept as `backup`.
    case replaced(
      URL,
      backup: URL,
    )

    /// A file was taken away and kept as `backup`.
    case deleted(
      URL,
      backup: URL,
    )
  }

  private var folders: [URL] = []
  private var leftovers: [URL] = []
  private var swaps: [Swap] = []

  /// A folder the plan made; undoing removes it again when it is empty.
  mutating func madeFolder(_ folder: URL) {
    folders.append(folder)
  }

  /// A staged file or a backup that is not wanted once the plan is through, however it ends.
  mutating func left(_ file: URL) {
    leftovers.append(file)
  }

  mutating func swapped(_ swap: Swap) {
    swaps.append(swap)
  }

  /// The plan went through: the backups and anything staged and not used go.
  func finish() {
    for file in leftovers {
      PlanFiles.discard(file)
    }

    for swap in swaps {
      switch swap {
      case let .created(file):
        PlanFiles.flushFolder(file.deletingLastPathComponent())
      case let .replaced(file, _), let .deleted(file, _):
        PlanFiles.flushFolder(file.deletingLastPathComponent())
      }
    }
  }

  /// The plan failed: every swap is taken back, newest first, every staged file and backup goes,
  /// and so does every folder it made. Nothing here can fail the failure it is undoing.
  func undo() {
    for swap in swaps.reversed() {
      switch swap {
      case let .created(file):
        PlanFiles.discard(file)
      case let .replaced(file, backup), let .deleted(file, backup):
        try? PlanFiles.move(
          backup,
          to: file,
        )
      }
    }

    for file in leftovers {
      PlanFiles.discard(file)
    }

    for folder in folders.reversed() {
      PlanFiles.removeFolder(folder)
    }
  }
}
