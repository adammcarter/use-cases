/// Why a request was refused: the `error.kind` of a `--json` document (chapter 16 §5).
enum RefusalKind: String, Equatable {
  /// The command line itself is wrong.
  case usage

  /// The workspace is INVALID.
  case invalid

  /// A valid request that cannot proceed now.
  case refused

  /// The results store cannot be read or written safely.
  case storage

  /// The request was stopped by SIGINT or SIGTERM (chapter 16 §6). Not a refusal: it exits 130,
  /// not 2.
  case cancelled
}
