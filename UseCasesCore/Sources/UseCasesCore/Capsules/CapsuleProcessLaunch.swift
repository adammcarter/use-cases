import Foundation

/// A started child and the parent's ends of its stdout and stderr, or the
/// errno `posix_spawn` refused it with.
struct CapsuleProcessLaunch {
  /// Why the child never started.
  struct Failure: Error {
    let errorNumber: Int32
  }

  let processIdentifier: pid_t
  let standardOutput: Int32
  let standardError: Int32

  /// libuv's `NAME_MAX` check on a name it searches `PATH` for.
  private static let longestName = 255
  /// libuv's `_PATH_DEFPATH`.
  private static let defaultSearchPath = "/usr/bin:/bin"
  /// How much each stream's socket pair holds, so one read can deliver a whole
  /// ``CapsuleOutputCapture/readChunkBytes`` chunk as node's does.
  ///
  /// macOS gives a `socketpair` 8 KiB by default (`net.local.stream.recvspace`),
  /// which caps every read at 8 KiB. node's output past `maxBuffer` KEEPS the
  /// read that crossed the limit, so the chunk size is observable: with 8 KiB
  /// reads a 1,200,000-byte stream records 1 MiB + 8,192 bytes where node
  /// records 1 MiB + 65,536, and every digest past the limit differs. Measured
  /// against node 26 and pinned by `CapsuleProcessSpawnerTests`.
  private static let streamBufferBytes = Int32(CapsuleOutputCapture.readChunkBytes)

  /// Start the child as libuv's `uv__spawn_and_init_child_posix_spawn` does.
  static func start(_ request: CapsuleSpawnRequest) -> Result<CapsuleProcessLaunch, Failure> {
    var pairs: [[Int32]] = []
    defer {
      for pair in pairs {
        close(pair[1])
      }
    }
    for _ in 0 ..< 3 {
      var descriptors: [Int32] = [0, 0]
      guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
        for pair in pairs {
          close(pair[0])
        }
        return .failure(Failure(errorNumber: errno))
      }
      // Close-on-exec, so no other child spawned meanwhile holds them open;
      // the child's own copies are made by dup2, which clears the flag.
      for descriptor in descriptors {
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
      }
      // A pair that cannot take node's buffer size would read in 8 KiB chunks
      // and silently record different bytes past `maxBuffer`, so it fails the
      // start outright rather than degrading.
      guard let errorNumber = enlarge(descriptors) else {
        pairs.append(descriptors)
        continue
      }
      for descriptor in descriptors {
        close(descriptor)
      }
      for pair in pairs {
        close(pair[0])
      }
      return .failure(Failure(errorNumber: errorNumber))
    }
    // The parent never writes to stdin: closing its end is the end of input.
    close(pairs[0][0])

    switch spawn(request, childDescriptors: pairs.map { $0[1] }) {
    case let .success(processIdentifier):
      return .success(CapsuleProcessLaunch(
        processIdentifier: processIdentifier,
        standardOutput: pairs[1][0],
        standardError: pairs[2][0],
      ))
    case let .failure(failure):
      close(pairs[1][0])
      close(pairs[2][0])
      return .failure(failure)
    }
  }

  /// Give both ends of a pair node's read size in both directions, or the
  /// errno that refused it.
  private static func enlarge(_ descriptors: [Int32]) -> Int32? {
    var size = streamBufferBytes
    let length = socklen_t(MemoryLayout<Int32>.size)
    for descriptor in descriptors {
      for option in [SO_RCVBUF, SO_SNDBUF] {
        guard setsockopt(descriptor, SOL_SOCKET, option, &size, length) == 0 else {
          return errno
        }
      }
    }
    return nil
  }

  /// The file as given when it holds `/`; otherwise the `PATH` search.
  private static func spawn(
    _ request: CapsuleSpawnRequest,
    childDescriptors: [Int32],
  ) -> Result<pid_t, Failure> {
    let attempt = { (path: String) in
      spawnOnce(path: path, request: request, childDescriptors: childDescriptors)
    }
    if request.executable.utf8.contains(UInt8(ascii: "/")) {
      return attempt(request.executable)
    }
    guard request.executable.utf8.count <= longestName else {
      return .failure(Failure(errorNumber: ENAMETOOLONG))
    }
    let pathEntry = request.environment.first { entry in
      entry.hasPrefix("PATH=")
    }
    let search = pathEntry.map { entry in
      String(entry.dropFirst(5))
    } ?? defaultSearchPath
    var hasSeenPermissionDenied = false
    var lastFailure = Failure(errorNumber: ENOENT)
    for entry in search.split(separator: ":", omittingEmptySubsequences: false) {
      let path = entry.isEmpty ? request.executable : entry + "/" + request.executable
      switch attempt(path) {
      case let .success(processIdentifier):
        return .success(processIdentifier)
      case let .failure(failure) where [EACCES, ENOENT, ENOTDIR].contains(failure.errorNumber):
        hasSeenPermissionDenied = hasSeenPermissionDenied || failure.errorNumber == EACCES
        lastFailure = failure
      case let .failure(failure):
        return .failure(failure)
      }
    }
    return .failure(hasSeenPermissionDenied ? Failure(errorNumber: EACCES) : lastFailure)
  }

  private static func spawnOnce(
    path: String,
    request: CapsuleSpawnRequest,
    childDescriptors: [Int32],
  ) -> Result<pid_t, Failure> {
    var actions: posix_spawn_file_actions_t?
    var attributes: posix_spawnattr_t?
    posix_spawn_file_actions_init(&actions)
    posix_spawnattr_init(&attributes)
    defer {
      posix_spawn_file_actions_destroy(&actions)
      posix_spawnattr_destroy(&attributes)
    }
    for (target, source) in childDescriptors.enumerated() {
      posix_spawn_file_actions_adddup2(&actions, source, Int32(target))
    }
    posix_spawn_file_actions_addchdir_np(&actions, request.workingDirectory)
    var defaults = sigset_t()
    sigfillset(&defaults)
    sigdelset(&defaults, SIGKILL)
    sigdelset(&defaults, SIGSTOP)
    var mask = sigset_t()
    sigemptyset(&mask)
    posix_spawnattr_setsigdefault(&attributes, &defaults)
    posix_spawnattr_setsigmask(&attributes, &mask)
    posix_spawnattr_setflags(
      &attributes,
      Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT),
    )

    let arguments = ([request.executable] + request.arguments).map { argument in
      strdup(argument)
    } + [nil]
    let environment = request.environment.map { entry in
      strdup(entry)
    } + [nil]
    defer {
      for pointer in arguments + environment {
        free(pointer)
      }
    }
    var processIdentifier: pid_t = 0
    var result: Int32
    repeat {
      result = posix_spawn(&processIdentifier, path, &actions, &attributes, arguments, environment)
    } while result == EINTR
    return result == 0 ? .success(processIdentifier) : .failure(Failure(errorNumber: result))
  }
}
