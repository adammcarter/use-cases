/// What a capsule run is asked to do (`DemoCapsuleRunOptions`).
public struct DemoCapsuleRunOptions: Sendable {
  public var context: ResolvedWorkspaceContext
  public var capsuleIdentifier: String
  public var isExecutingCommands: Bool
  /// Never `user`; the TypeScript's type excludes it.
  public var actorType: ShowcaseActorType
  public var hostSurface: String
  /// Nil derives one from the capsule id and the clock.
  public var idempotencyKey: String?
  public var recordedAt: String
  /// Any number, as a caller may pass one; only 1 through 300,000 runs.
  public var commandTimeoutMilliseconds: Double

  public init(
    context: ResolvedWorkspaceContext,
    capsuleIdentifier: String,
    isExecutingCommands: Bool = false,
    actorType: ShowcaseActorType = .agent,
    hostSurface: String = "codex.cli",
    idempotencyKey: String? = nil,
    recordedAt: String = "2026-06-25T12:00:00.000Z",
    commandTimeoutMilliseconds: Double = 30000,
  ) {
    self.context = context
    self.capsuleIdentifier = capsuleIdentifier
    self.isExecutingCommands = isExecutingCommands
    self.actorType = actorType
    self.hostSurface = hostSurface
    self.idempotencyKey = idempotencyKey
    self.recordedAt = recordedAt
    self.commandTimeoutMilliseconds = commandTimeoutMilliseconds
  }
}
