import Foundation

/// The names node gives errno values and signals on this platform: libuv's
/// `uv_err_name` and node's `signo_string`.
enum CapsuleSystemNames {
  static func errorName(_ errorNumber: Int32) -> String {
    errorNames[errorNumber] ?? "Unknown system error -\(errorNumber)"
  }

  static func signalName(_ signal: Int32) -> String {
    signalNames[signal] ?? ""
  }

  private static let errorNames: [Int32: String] = [
    EPERM: "EPERM",
    ENOENT: "ENOENT",
    EIO: "EIO",
    E2BIG: "E2BIG",
    ENOEXEC: "ENOEXEC",
    EBADF: "EBADF",
    EAGAIN: "EAGAIN",
    ENOMEM: "ENOMEM",
    EACCES: "EACCES",
    EFAULT: "EFAULT",
    ENOTDIR: "ENOTDIR",
    EISDIR: "EISDIR",
    EINVAL: "EINVAL",
    EMFILE: "EMFILE",
    ETXTBSY: "ETXTBSY",
    ELOOP: "ELOOP",
    ENAMETOOLONG: "ENAMETOOLONG",
  ]

  private static let signalNames: [Int32: String] = [
    SIGHUP: "SIGHUP",
    SIGINT: "SIGINT",
    SIGQUIT: "SIGQUIT",
    SIGILL: "SIGILL",
    SIGTRAP: "SIGTRAP",
    SIGABRT: "SIGABRT",
    SIGEMT: "SIGEMT",
    SIGFPE: "SIGFPE",
    SIGKILL: "SIGKILL",
    SIGBUS: "SIGBUS",
    SIGSEGV: "SIGSEGV",
    SIGSYS: "SIGSYS",
    SIGPIPE: "SIGPIPE",
    SIGALRM: "SIGALRM",
    SIGTERM: "SIGTERM",
    SIGURG: "SIGURG",
    SIGSTOP: "SIGSTOP",
    SIGTSTP: "SIGTSTP",
    SIGCONT: "SIGCONT",
    SIGCHLD: "SIGCHLD",
    SIGTTIN: "SIGTTIN",
    SIGTTOU: "SIGTTOU",
    SIGIO: "SIGIO",
    SIGXCPU: "SIGXCPU",
    SIGXFSZ: "SIGXFSZ",
    SIGVTALRM: "SIGVTALRM",
    SIGPROF: "SIGPROF",
    SIGWINCH: "SIGWINCH",
    SIGINFO: "SIGINFO",
    SIGUSR1: "SIGUSR1",
    SIGUSR2: "SIGUSR2",
  ]
}
