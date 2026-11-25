/// Reduces validations of the bridge settings to the digest `start.json` keeps (chapter 12 §11),
/// so `verify --finish` can tell whether they changed since `--start`.
protocol ValidationsDigesting: Sendable {
  /// The SHA-256 of the validations, in the order given, with every setting the file wrote.
  func digest(of validations: [BridgeValidation]) -> String
}
