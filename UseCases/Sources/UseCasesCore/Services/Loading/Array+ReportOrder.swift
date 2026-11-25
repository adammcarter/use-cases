extension [Diagnostic] {
  /// The diagnostics in the order every report shows them, each once (chapter 09 §27.1). Where
  /// they were found, and in what order, never shows.
  var inReportOrder: [Diagnostic] {
    Set(self).sorted()
  }
}
