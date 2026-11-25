/// How a use case of a proposal fits what already exists (chapter 21 §5): the six words every
/// brief uses, `conflicts` being a choice for the person and so never a fit of the file.
public enum ProposalFit: String, CaseIterable, Sendable {
  /// Nothing like it exists.
  case new

  /// An existing use case gains a scenario or an edge.
  case extends

  /// An existing use case behaves differently from now on.
  case changes

  /// An old use case goes, and this takes its place.
  case replaces

  /// Related, but stays exactly as it is.
  case untouched
}
