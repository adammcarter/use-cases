/// Where a command ran: the roots it resolved and the snapshot it saw.
public struct CliContext: Sendable, Equatable {
  public let workspaceRoot: String
  public let dataRoot: String
  public let componentIdentifier: String
  public let workspaceSnapshot: WorkspaceSnapshot

  public init(
    workspaceRoot: String,
    dataRoot: String,
    componentIdentifier: String,
    workspaceSnapshot: WorkspaceSnapshot,
  ) {
    self.workspaceRoot = workspaceRoot
    self.dataRoot = dataRoot
    self.componentIdentifier = componentIdentifier
    self.workspaceSnapshot = workspaceSnapshot
  }

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("workspace_root", .string(workspaceRoot)),
      ("data_root", .string(dataRoot)),
      ("component_id", .string(componentIdentifier)),
      ("workspace_snapshot", workspaceSnapshot.jsonValue),
    ]))
  }
}
