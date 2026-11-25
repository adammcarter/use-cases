extension LinkResolution {
  /// The empty marked regions among the warnings, each with the use case it marks, in report
  /// order. A warning is matched to its link by file, line and binding, never by reading its text
  /// for an id.
  var emptyMarkerRegions: [EmptyMarkerRegion] {
    warnings.compactMap { warning in
      guard warning.code == .emptyMarkerRegion else {
        return nil
      }

      let marked = links.first { link in
        link.source == .marker
          && link.path == warning.file
          && link.startLine == warning.position?.line
          && warning.message.isExactlyEqual(
            to: Diagnostic.emptyMarkerRegionMessage(link.identity.keyPrefix),
          )
      }

      return marked.map { link in
        EmptyMarkerRegion(
          useCase: link.useCase,
          diagnostic: warning,
        )
      }
    }
  }
}
