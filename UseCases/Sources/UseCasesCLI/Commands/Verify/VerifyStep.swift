/// The step of `use-cases verify` a command line asks for (chapter 13 §2).
enum VerifyStep: String, CaseIterable {
  case start
  case finish
  case run
  case abort

  /// The flag that asks for the step.
  var flag: String {
    "--\(rawValue)"
  }
}
