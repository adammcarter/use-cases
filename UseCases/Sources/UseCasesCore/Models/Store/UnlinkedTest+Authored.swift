extension UnlinkedTest {
  /// Reads one `unlinked_tests` entry of a version 1 manifest. `file` and `line` may be `null`.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    let file: String? = if case .null? = object.value(for: "file") {
      nil
    } else {
      try object.optionalString("file")
    }
    let line: Int? = if case .null? = object.value(for: "line") {
      nil
    } else {
      try object.optionalInteger("line")
    }

    try self.init(
      test: object.requiredString("test"),
      file: file,
      line: line,
      status: object.requiredChoice(
        "status",
        as: Verdict.self,
      ),
    )
  }
}
