import Foundation

/// node's `os.tmpdir()`: `TMPDIR`, else `TMP`, else `TEMP`, else `/tmp`, a
/// trailing `/` removed unless the path is only `/`.
enum NodeOperatingSystem {
  static func temporaryDirectory(environment: [String: String]) -> String {
    let candidates = [environment["TMPDIR"], environment["TMP"], environment["TEMP"]]
    var path = candidates.lazy.compactMap(\.self).first { !$0.isEmpty } ?? "/tmp"
    if path.utf16.count > 1, path.hasSuffix("/") {
      path.removeLast()
    }
    return path
  }
}

/// packages/core/src/durableWrite.ts. It belongs with Foundation/ in spirit;
/// Foundation/ is closed, and the evidence append path is its only caller.
enum DurableWrite {
  //: @use-case:evidence.ledger.crash_durable_ledger_writes
  /// `fsyncBestEffortForTemp`: `fsync`, forgiving EIO, EINVAL, ENOSYS and
  /// ENOTSUP only for a file inside the OS temporary directory, where some
  /// filesystems cannot sync. Anywhere else a failed sync is raised.
  static func synchronizeBestEffortForTemporary(
    descriptor: Int32,
    path: String,
  ) throws(FileAccessError) {
    guard fsync(descriptor) != 0 else {
      return
    }
    let failure = errno
    let temporaryDirectory = NodeOperatingSystem.temporaryDirectory(
      environment: ProcessInfo.processInfo.environment,
    )
    if isBestEffortTemporarySyncFailure(
      errorNumber: failure,
      path: path,
      temporaryDirectory: temporaryDirectory,
    ) {
      return
    }
    throw FileAccessError(errorNumber: failure, operation: "fsync", path: nil)
  }

  //: @use-case:end evidence.ledger.crash_durable_ledger_writes

  static func isBestEffortTemporarySyncFailure(
    errorNumber: Int32,
    path: String,
    temporaryDirectory: String,
  ) -> Bool {
    guard [EIO, EINVAL, ENOSYS, ENOTSUP].contains(errorNumber) else {
      return false
    }
    let relativePath = NodePath.relative(
      from: realPathOrResolved(temporaryDirectory),
      to: realPathOrResolved(path),
    )
    return relativePath.isEmpty
      || (!relativePath.utf16.starts(with: [CodeUnits.fullStop, CodeUnits.fullStop])
        && !NodePath.isAbsolute(relativePath))
  }

  /// `realpathSync(path)`, or `resolve(path)` when that fails.
  private static func realPathOrResolved(_ path: String) -> String {
    if let real = try? NodeFile.realPath(path) {
      return real
    }
    if NodePath.isAbsolute(path) {
      return path
    }
    return NodePath.join(FileManager.default.currentDirectoryPath, path)
  }
}
