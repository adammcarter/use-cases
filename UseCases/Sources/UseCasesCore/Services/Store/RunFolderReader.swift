import Foundation

/// Reads one run folder: the marker first, then everything the marker seals (chapter 12 §22).
struct RunFolderReader: RunFolderReading {
  /// The version of each file this core reads in full. A greater version is read through its
  /// envelope only (chapter 12 §25).
  static let supportedVersion = 1

  let access: any StoreFileAccessing
  let hasher: any Hashing
  let checks: StoreChecks

  func readRun(
    _ identifier: RunIdentifier,
    in workspace: URL,
  ) -> RunOutcome {
    let folder = StoreFile(workspace: workspace)
      .appending(StoreLayout.runsFolder)
      .appending(identifier.text)
    let marker = folder.appending(StoreLayout.completionFile)

    var log = StoreProblemLog()
    guard let sealed = log.attempt({ () throws(StoreProblem) in try isSealed(marker) }) else {
      return .damaged(log.problems)
    }
    guard sealed else {
      return .unfinished(UnfinishedRun(identifier: identifier))
    }
    guard
      let completion = log.attempt({ () throws(StoreProblem) in
        try readCompletion(
          marker,
          of: identifier,
        )
      })
    else {
      return .damaged(log.problems)
    }

    return readSealedRun(
      folder: folder,
      completion: completion,
      log: &log,
    )
  }

  /// A marker that is a file seals the run. A marker that is anything else is corruption, not an
  /// unsealed run (chapter 12 §24).
  private func isSealed(_ marker: StoreFile) throws(StoreProblem) -> Bool {
    switch try access.kind(of: marker) {
    case nil:
      false
    case .file?:
      true
    case .directory?, .symlink?, .other?:
      throw .corrupt(marker.location, "it is not a regular file")
    }
  }

  private func readSealedRun(
    folder: StoreFile,
    completion: RunCompletion,
    log: inout StoreProblemLog,
  ) -> RunOutcome {
    let manifest = log.attempt { () throws(StoreProblem) in
      try readManifest(
        folder.appending(StoreLayout.manifestFile),
        completion: completion,
      )
    }
    let results = log.attempt { () throws(StoreProblem) in
      try readResults(
        folder.appending(StoreLayout.resultsFile),
        completion: completion,
      )
    }
    _ = log.attempt { () throws(StoreProblem) in
      try checkSealedFiles(
        in: folder,
        completion: completion,
        manifest: manifest.flatMap(\.self),
      )
    }

    guard log.isClean, let manifest, let results else {
      return .damaged(log.problems)
    }

    return .sealed(StoredRun(
      identifier: completion.identifier,
      completion: completion,
      manifest: manifest,
      results: results,
      findings: findings(
        in: folder,
        completion: completion,
        results: results,
      ),
    ))
  }

  func digest(of bytes: [UInt8]) -> String {
    hasher.sha256Hex(of: bytes)
  }
}
