/// The repository state an envelope was produced against.
///
/// Every field is present on the wire; the placeholder values are frozen until
/// the row that teaches the CLI to read git.
public struct WorkspaceSnapshot: Sendable, Equatable {
  public let repositoryIdentifier: String
  public let versionControlSystem: String
  public let headRevision: String
  public let isDirty: Bool
  public let workingTreeDigest: String
  public let componentIdentifier: String
  public let capturedAt: String

  public init(
    repositoryIdentifier: String,
    versionControlSystem: String,
    headRevision: String,
    isDirty: Bool,
    workingTreeDigest: String,
    componentIdentifier: String,
    capturedAt: String,
  ) {
    self.repositoryIdentifier = repositoryIdentifier
    self.versionControlSystem = versionControlSystem
    self.headRevision = headRevision
    self.isDirty = isDirty
    self.workingTreeDigest = workingTreeDigest
    self.componentIdentifier = componentIdentifier
    self.capturedAt = capturedAt
  }

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("repository_id", .string(repositoryIdentifier)),
      ("vcs", .string(versionControlSystem)),
      ("head_revision", .string(headRevision)),
      ("dirty", .bool(isDirty)),
      ("working_tree_digest", .string(workingTreeDigest)),
      ("component_id", .string(componentIdentifier)),
      ("captured_at", .string(capturedAt)),
    ]))
  }
}
