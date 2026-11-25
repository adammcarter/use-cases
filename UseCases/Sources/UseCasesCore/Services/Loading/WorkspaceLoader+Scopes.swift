import Foundation

extension WorkspaceLoader {
  /// The scopes discovery found, each with its configuration. Discovery read the files for
  /// their settings only; the prefix and the rest are read here, by the same reader.
  func loadScopes(
    of discovery: WorkspaceDiscovery,
    root: WorkspaceRoot,
    configurationLoader: any ScopeConfigurationLoading,
    diagnostics: inout [Diagnostic],
  ) -> [LoadedScope] {
    var scopes: [LoadedScope] = []

    for discovered in discovery.scopeTree.scopes {
      let text: String

      do {
        text = try fileSystem.readText(at: root.location(of: discovered.configuration))
      } catch {
        diagnostics += Diagnostic.configuration(
          discovered.configuration,
          refused: .unreadable(error),
        )
        continue
      }

      do {
        try scopes.append(
          LoadedScope(
            discovered: discovered,
            configuration: configurationLoader.load(
              fromText: text,
              at: discovered.configuration,
            ),
          ),
        )
      } catch {
        diagnostics += Diagnostic.configuration(
          discovered.configuration,
          refused: .invalid(error),
        )
      }
    }

    return scopes
  }
}
