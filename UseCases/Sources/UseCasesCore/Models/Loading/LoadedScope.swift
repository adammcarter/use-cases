/// A scope of a loaded workspace: what discovery found, and its configuration as read.
struct LoadedScope: Equatable, Sendable {
  let discovered: DiscoveredScope
  let configuration: ScopeConfiguration
}
