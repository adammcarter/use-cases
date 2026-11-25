/// What makes a binding's earlier verification stale (chapter 04 "Freshness policy").
enum BindingIdentityMode: String, CaseIterable, Sendable {
  /// The same bound content stays fresh even if its locator moves.
  case content

  /// A moved locator makes the earlier verification stale too.
  case contentAndLocator = "content-and-locator"
}
