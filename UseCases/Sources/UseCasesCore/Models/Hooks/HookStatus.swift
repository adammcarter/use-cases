/// One hook as this clone has it, or as it will have it once a request is carried out.
public struct HookStatus: Equatable, Sendable {
  public let name: HookName
  public let state: HookState

  /// Says what one hook is.
  public init(
    name: HookName,
    state: HookState,
  ) {
    self.name = name
    self.state = state
  }
}
