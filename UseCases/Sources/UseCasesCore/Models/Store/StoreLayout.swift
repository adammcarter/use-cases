/// Where everything lives under a workspace root (chapter 12 §2). The reader and the writers of
/// the store share these names.
enum StoreLayout {
  static let storeFolder = ".use-cases"
  static let runsFolder = "runs"
  static let runOrderFile = "run-order.json"

  static let manifestFile = "run.json"
  static let startFile = "start.json"
  static let resultsFile = "results.jsonl"
  static let completionFile = "completion.json"
  static let reportsFolder = "reports"
  static let outputsFolder = "outputs"

  /// What a run command printed, inside `outputs/<validation-id>/` (chapter 12 §15).
  static let consoleFile = "console.txt"
  static let attachmentsFolder = "attachments"

  /// The per-run lock (chapter 12 §18), at the root of the run's folder: never inside `reports/`
  /// or `outputs/`, which hold only what is sealed.
  static let runLockFile = ".lock"

  /// A folder in `runs/` whose name starts like this is a run being published, not a run
  /// (chapter 12 §11). The writers build their temporary folders with this prefix.
  static let temporaryRunPrefix = ".tmp-"

  /// The store's own place, relative to the workspace root.
  static var storeLocation: String {
    storeFolder
  }

  /// `.use-cases/runs`
  static var runsLocation: String {
    "\(storeFolder)/\(runsFolder)"
  }

  /// `.use-cases/runs/<id>`
  static func location(of run: RunIdentifier) -> String {
    "\(runsLocation)/\(run.text)"
  }

  /// The names of the folders down to a blob inside its run, and the blob's own name:
  /// `attachments`, `sha256` and the first two digits; then the remaining 62.
  static func attachmentNames(digest: String) -> (folders: [String], blob: String) {
    (
      folders: [
        attachmentsFolder,
        "sha256",
        String(digest.unicodeScalars.prefix(2)),
      ],
      blob: String(digest.unicodeScalars.dropFirst(2)),
    )
  }

  /// Where a blob is kept inside its run: `attachments/sha256/<first two>/<remaining 62>`.
  static func attachmentPath(digest: String) -> String {
    let names = attachmentNames(digest: digest)

    return (names.folders + [names.blob]).joined(separator: "/")
  }
}
