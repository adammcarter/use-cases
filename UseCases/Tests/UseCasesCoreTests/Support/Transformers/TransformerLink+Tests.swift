@testable import UseCasesCore

extension TransformerLink {
  /// A link that names a real place in the sample workspace unless the test changes a member. A
  /// member given as `nil` is left out.
  static func sample(
    useCase: String? = "app.toggle",
    route: String? = nil,
    binding: String? = "render",
    role: String? = "implementation",
    file: String? = "src/math.js",
    range: TransformerLinkRange? = nil,
  ) -> TransformerLink {
    TransformerLink(
      useCase: useCase,
      route: route,
      binding: binding,
      role: role,
      file: file,
      range: range,
      text: "{}",
    )
  }
}
