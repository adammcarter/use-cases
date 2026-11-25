/// The problems found while reading one authored file, gathered so a read reports every
/// independent problem and not only the first (chapter 09 §27).
struct AuthoredFindings {
  let file: WorkspacePath
  private(set) var diagnostics: [Diagnostic] = []

  /// Whether nothing has gone wrong yet.
  var isClean: Bool {
    diagnostics.isEmpty
  }

  /// The problems, in the order every report shows them (chapter 09 §27.1).
  var sorted: [Diagnostic] {
    diagnostics.sorted()
  }

  /// Runs a read. A shape problem is recorded as a finding and gives nil.
  mutating func attempt<Value>(
    _ read: () throws(AuthoredShapeError) -> Value,
  ) -> Value? {
    attemptOptional { () throws(AuthoredShapeError) -> Value? in
      try read()
    }
  }

  /// Runs a read of a field that may be absent. A shape problem is recorded; absent and
  /// refused both give nil.
  mutating func attemptOptional<Value>(
    _ read: () throws(AuthoredShapeError) -> Value?,
  ) -> Value? {
    do {
      return try read()
    } catch {
      add(
        .invalidValue,
        error.description,
      )
      return nil
    }
  }

  mutating func add(
    _ code: DiagnosticCode,
    _ message: String,
  ) {
    diagnostics.append(
      Diagnostic(
        error: code,
        in: file,
        message: message,
      ),
    )
  }

  mutating func add(contentsOf more: [Diagnostic]) {
    diagnostics.append(contentsOf: more)
  }
}
