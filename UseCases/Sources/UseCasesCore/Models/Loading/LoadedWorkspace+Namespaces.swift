extension LoadedWorkspace {
  /// Every scope with its namespace, in the order of ``scopes``.
  var scopeNamespaces: [ScopeNamespace] {
    let byDirectory = Dictionary(
      uniqueKeysWithValues: scopes.map { scope in
        (scope.discovered.directory, scope)
      },
    )

    return scopes.map { scope in
      var chain = [scope]
      var current = scope

      while let parent = current.discovered.parent, let above = byDirectory[parent] {
        chain.append(above)
        current = above
      }

      return ScopeNamespace(
        scope: scope,
        segments: chain.reversed().flatMap { scope in
          scope.configuration.prefix?.segments ?? []
        },
      )
    }
  }
}
