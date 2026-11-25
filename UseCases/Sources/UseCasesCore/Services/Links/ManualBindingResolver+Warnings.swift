extension ManualBindingResolver {
  /// What a link that resolved has to say: it points at excluded content, or selects no bytes.
  func warnings(
    about link: ResolvedLink,
    locator: ManualLocator,
    context: DiscoveryContext,
  ) -> [Diagnostic] {
    var found: [Diagnostic] = []

    if let exclusion = context.exclusion(covering: link.path) {
      found.append(.pointsAtExcludedContent(link, because: exclusion))
    }

    if link.span.isEmpty {
      found.append(
        locator.range == nil
          ? .emptyWholeFileBinding(link)
          : .emptyBindingRange(link),
      )
    }

    return found
  }
}
