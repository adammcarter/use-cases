/// What resolving every route's resources found.
struct ResourceResolution: Equatable, Sendable {
  var byRoute: [RouteKey: ResolvedResources] = [:]
  var diagnostics: [Diagnostic] = []

  /// Warnings that never block.
  var warnings: [Diagnostic] = []
}
