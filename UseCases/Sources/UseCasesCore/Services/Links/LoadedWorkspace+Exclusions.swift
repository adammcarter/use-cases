extension LoadedWorkspace {
  /// What discovery leaves out, as discovery applies it: the built-in exclusions and the root's
  /// `discovery.exclude` (chapter 04 "Discovery exclusions").
  var discoveryContext: DiscoveryContext {
    DiscoveryContext(
      rootDirectory: root,
      builtInExcludes: DefaultDiscoveryExclusions.patterns,
      configuredExcludes: scopes.first?.configuration.rootSettings?.discoveryExclusions ?? [],
    )
  }
}
