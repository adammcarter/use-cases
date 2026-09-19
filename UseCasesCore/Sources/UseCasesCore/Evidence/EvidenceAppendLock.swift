import Foundation

extension EvidenceAppender {
  static let lockTimeoutMilliseconds: Double = 30000
  static let lockPollMilliseconds = 25

  /// `withEvidenceAppendLock`: take the lock directory, run `work`, remove the
  /// lock directory whatever `work` did.
  ///
  /// Ported as the TypeScript has it: `mkdir` failing for ANY reason other
  /// than EEXIST reports a timeout at once, and the deadline is checked only
  /// after an EEXIST, with `>` — a wait that lands exactly on the deadline
  /// polls once more.
  func withAppendLock<Value: Sendable>(
    context: ResolvedWorkspaceContext,
    _ work: () async throws(EvidenceEventError) -> Value,
  ) async throws(EvidenceEventError) -> Value {
    let lockPath = NodePath.join(
      EvidenceLedgerReader.evidenceRoot(context: context),
      ".locks/append.lock",
    )
    do throws(FileAccessError) {
      try NodeFile.makeDirectories(atPath: WorkspacePath.dirname(lockPath))
    } catch {
      throw .fileAccess(error)
    }
    let deadline = await clock.now() + Self.lockTimeoutMilliseconds
    while mkdir(lockPath, 0o777) != 0 {
      let failure = errno
      guard failure == EEXIST else {
        throw .lockTimeout
      }
      guard await clock.now() <= deadline else {
        throw .lockTimeout
      }
      await clock.sleep(milliseconds: Self.lockPollMilliseconds)
    }

    let outcome: Result<Value, EvidenceEventError>
    do throws(EvidenceEventError) {
      outcome = try await .success(work())
    } catch {
      outcome = .failure(error)
    }
    do throws(FileAccessError) {
      try LedgerAppend.removeRecursively(atPath: lockPath)
    } catch {
      throw .fileAccess(error)
    }
    return try outcome.get()
  }
}

/// The two filesystem operations the append path adds to ``NodeFile``.
enum LedgerAppend {
  /// `openSync(path, "a")`, one `writeSync` of `line`,
  /// `fsyncBestEffortForTemp`, `closeSync`. A short write is not retried, as
  /// `writeSync` does not retry it.
  static func appendLine(
    _ line: String,
    toPath path: String,
  ) throws(FileAccessError) {
    let descriptor = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o666)
    guard descriptor >= 0 else {
      throw FileAccessError(errorNumber: errno, operation: "open", path: path)
    }
    defer {
      close(descriptor)
    }
    let bytes = Array(line.utf8)
    let written = bytes.withUnsafeBytes { raw in
      write(descriptor, raw.baseAddress, raw.count)
    }
    guard written >= 0 else {
      throw FileAccessError(errorNumber: errno, operation: "write", path: nil)
    }
    try DurableWrite.synchronizeBestEffortForTemporary(descriptor: descriptor, path: path)
  }

  /// `rmSync(path, { recursive: true, force: true })`: a missing path is
  /// fine; a directory goes with everything in it.
  static func removeRecursively(atPath path: String) throws(FileAccessError) {
    var status = stat()
    guard lstat(path, &status) == 0 else {
      let failure = errno
      guard failure == ENOENT else {
        throw FileAccessError(errorNumber: failure, operation: "rm", path: path)
      }
      return
    }
    if status.st_mode & S_IFMT == S_IFDIR {
      for name in try NodeFile.directoryNames(atPath: path) {
        try removeRecursively(atPath: NodePath.join(path, name))
      }
      guard rmdir(path) == 0 else {
        throw FileAccessError(errorNumber: errno, operation: "rm", path: path)
      }
      return
    }
    guard unlink(path) == 0 else {
      throw FileAccessError(errorNumber: errno, operation: "rm", path: path)
    }
  }
}
