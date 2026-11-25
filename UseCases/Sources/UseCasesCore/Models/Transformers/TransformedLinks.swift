/// The links the link transformers of the bridge settings returned, checked and placed, and what
/// they said about them (chapter 10 §11).
public struct TransformedLinks: Equatable, Sendable {
  let findings: LinkFindings

  /// What a workspace gets when no link transformer is configured: no links, nothing said.
  public static let none = TransformedLinks(findings: .empty)
}
