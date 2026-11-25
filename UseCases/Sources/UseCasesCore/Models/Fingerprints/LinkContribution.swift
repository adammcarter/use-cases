/// One binding of an implementation or route collection and every region it holds (chapter 11
/// §33). Several marker regions of one identity are one binding.
struct LinkContribution: Equatable, Sendable {
  let binding: BindingIdentifier
  let kind: LinkContributionKind
  let regions: [LinkRegionContribution]
}
