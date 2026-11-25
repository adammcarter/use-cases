/// Something under `reports/` that cannot be digested as the bytes of a report: a symlink, a pipe
/// or another file that is not a regular file, or a file that cannot be read. It is never followed
/// and never makes sealing fail; it is a run error that names it (chapter 12 §15).
struct UnusableReportEntry: Equatable, Sendable {
  /// The path from `reports/`, such as `unit-tests/latest`.
  let path: String

  /// What is wrong with it, ready to follow the path in a sentence.
  let reason: String

  /// `reports/unit-tests/latest is not a regular file ...`
  var message: String {
    "\(StoreLayout.reportsFolder)/\(path) \(reason)"
  }

  /// The validation whose folder holds it: the first name of the path, when the path has more
  /// than one.
  var validation: String? {
    let names = path.splitOnScalar("/")

    return names.count > 1 ? names[0] : nil
  }

  /// The run error: the validation's id and then what is wrong.
  var runError: String {
    guard let validation else {
      return message
    }

    return "\(validation): \(message)"
  }
}
