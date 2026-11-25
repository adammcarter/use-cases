import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Starts a command with `posix_spawn` (chapter 14 §6 to §9, ADR 036): directly, with no shell;
/// in a session of its own, which makes it the leader of its own process group; with no controlling
/// terminal, so a tool that opens `/dev/tty` fails at once and is not stopped on SIGTTIN; in its
/// working folder; with stdin from `/dev/null`, or from the descriptor a caller gives; stdout and
/// stderr into the capture; signal handling back to the default with nothing blocked; and no
/// descriptor of this process open in it but the lifeline it is given, if any
/// (``ProcessLifeline``).
/// The environment is this process's, with the lifeline's variable named for the lifeline it is
/// given, or left out when it is given none.
struct ProcessLauncher: ProcessLaunching {
  #if canImport(Darwin)
    private typealias Attributes = posix_spawnattr_t?
    private typealias Actions = posix_spawn_file_actions_t?
    private static var emptyAttributes: Attributes {
      nil
    }

    private static var emptyActions: Actions {
      nil
    }
  #else
    private typealias Attributes = posix_spawnattr_t
    private typealias Actions = posix_spawn_file_actions_t
    private static var emptyAttributes: Attributes {
      posix_spawnattr_t()
    }

    private static var emptyActions: Actions {
      posix_spawn_file_actions_t()
    }
  #endif

  func launch(
    arguments: [String],
    workingDirectory: URL,
    capture: any ConsoleCapturing,
  ) throws(ProcessSupervisingError) -> pid_t {
    try launch(
      arguments: arguments,
      workingDirectory: workingDirectory,
      streams: ProcessStreams(
        input: nil,
        output: capture.descriptor,
        error: capture.descriptor,
      ),
    )
  }

  /// Starts the command as ``launch(arguments:workingDirectory:capture:)`` does, with its three
  /// streams as given: an input read from where `streams` says (nothing, `/dev/null`, when it
  /// says none), and stdout and stderr each to a descriptor of its own.
  func launch(
    arguments: [String],
    workingDirectory: URL,
    streams: ProcessStreams,
  ) throws(ProcessSupervisingError) -> pid_t {
    guard !arguments.isEmpty else {
      throw .couldNotLaunch(reason: "the command is empty")
    }

    try Self.requireFolder(workingDirectory.path)

    guard
      let argumentVector = CStringArray(arguments),
      let environment = CStringArray(
        Self.environment(
          of: ProcessInfo.processInfo.environment,
          lifeline: streams.lifeline,
        ),
      ),
      let program = argumentVector.pointers.first.flatMap(\.self)
    else {
      throw .couldNotLaunch(reason: "the command could not be copied for launching")
    }

    defer {
      argumentVector.release()
      environment.release()
    }

    var attributes = Self.emptyAttributes
    var actions = Self.emptyActions

    try Self.check(posix_spawnattr_init(&attributes))
    defer {
      posix_spawnattr_destroy(&attributes)
    }

    try Self.check(posix_spawn_file_actions_init(&actions))
    defer {
      posix_spawn_file_actions_destroy(&actions)
    }

    try Self.configure(&attributes)
    try Self.configure(
      &actions,
      workingDirectory: workingDirectory.path,
      streams: streams,
    )

    var processIdentifier: pid_t = 0

    // `posix_spawnp` looks a bare name up in this process's PATH; a name with a slash is
    // resolved from the working folder, because the folder is entered before the program starts.
    try Self.check(
      posix_spawnp(
        &processIdentifier,
        program,
        &actions,
        &attributes,
        argumentVector.pointers,
        environment.pointers,
      ),
    )

    return processIdentifier
  }

  /// `base` as `KEY=value` entries, with the lifeline's variable naming the descriptor a lifeline
  /// is handed as, and no such variable when there is none.
  static func environment(
    of base: [String: String],
    lifeline: Int32?,
  ) -> [String] {
    var entries = base
    entries[ProcessLifeline.variable] = lifeline == nil ? nil : String(ProcessLifeline.descriptor)

    return entries.map { entry in
      "\(entry.key)=\(entry.value)"
    }
  }

  /// The system calls report their failure as the error number itself, and 0 for success.
  private static func check(_ code: Int32) throws(ProcessSupervisingError) {
    guard code == 0 else {
      throw .couldNotLaunch(reason: String(cString: strerror(code)))
    }
  }

  /// A working folder that is missing would otherwise read as a missing command, which is a
  /// different mistake.
  private static func requireFolder(_ path: String) throws(ProcessSupervisingError) {
    var information = stat()

    guard stat(path, &information) == 0 else {
      throw .couldNotLaunch(
        reason: "working folder \(path): \(String(cString: strerror(errno)))",
      )
    }

    guard information.st_mode & S_IFMT == S_IFDIR else {
      throw .couldNotLaunch(reason: "working folder \(path): \(String(cString: strerror(ENOTDIR)))")
    }
  }

  #if canImport(Darwin)
    private static let newSession = POSIX_SPAWN_SETSID
  #else
    // glibc's POSIX_SPAWN_SETSID (spawn.h): its header shows it only under _GNU_SOURCE, which
    // Swift's Glibc module does not define.
    private static let newSession: Int32 = 0x80
  #endif

  private static func configure(_ attributes: inout Attributes) throws(ProcessSupervisingError) {
    var everySignal = sigset_t()
    var noSignal = sigset_t()
    sigfillset(&everySignal)
    sigemptyset(&noSignal)

    try check(posix_spawnattr_setsigdefault(&attributes, &everySignal))
    try check(posix_spawnattr_setsigmask(&attributes, &noSignal))

    // A session leader is the leader of a new process group of its own ID; asking for a process
    // group as well would fail, a session leader not being allowed to change group.
    var flags = Int16(newSession | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)

    #if canImport(Darwin)
      // Everything not named in the file actions is closed at exec.
      flags |= Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)
    #endif

    try check(posix_spawnattr_setflags(&attributes, flags))
  }

  private static func configure(
    _ actions: inout Actions,
    workingDirectory: String,
    streams: ProcessStreams,
  ) throws(ProcessSupervisingError) {
    try check(posix_spawn_file_actions_addchdir_np(&actions, workingDirectory))

    if let input = streams.input {
      try check(posix_spawn_file_actions_adddup2(&actions, input, 0))
    } else {
      try check(posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0))
    }

    try check(posix_spawn_file_actions_adddup2(&actions, streams.output, 1))
    try check(posix_spawn_file_actions_adddup2(&actions, streams.error, 2))

    // Last, so that a descriptor the streams were using at this number is read before it is
    // replaced.
    if let lifeline = streams.lifeline {
      try check(posix_spawn_file_actions_adddup2(&actions, lifeline, ProcessLifeline.descriptor))
    }

    #if !canImport(Darwin)
      // No close-everything-else flag here: the system closes every descriptor from 3 up, in
      // the command only, when it starts it, so one opened by another thread meanwhile is closed
      // too.
      try check(
        posix_spawn_file_actions_addclosefrom_np(
          &actions,
          streams.lifeline == nil ? 3 : ProcessLifeline.descriptor + 1,
        ),
      )
    #endif
  }
}
