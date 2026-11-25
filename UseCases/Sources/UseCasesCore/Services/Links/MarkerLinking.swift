/// Turns marker regions into links to the use cases they name (chapter 08 "Markers").
protocol MarkerLinking: Sendable {
  /// A link for every region whose use case exists, and whose route does when it names one; a
  /// warning for every region that names none. Pairing has already been judged, so a region for
  /// an unknown use case is a warning, never a problem.
  func links(
    for regions: [FileRegion],
    among useCases: [LoadedUseCase],
  ) -> LinkFindings
}
