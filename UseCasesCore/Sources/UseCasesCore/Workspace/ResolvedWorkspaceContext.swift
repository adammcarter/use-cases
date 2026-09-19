/// What the caller asked for when resolving a workspace. Everything is
/// optional; each answer records in ``WorkspaceProvenance`` where it came from.
public struct ResolveWorkspaceContextOptions: Sendable, Equatable {
  public let workspaceRoot: String?
  public let dataRootOverride: String?
  public let component: String?
  public let pluginRoot: String?

  public init(
    workspaceRoot: String? = nil,
    dataRootOverride: String? = nil,
    component: String? = nil,
    pluginRoot: String? = nil,
  ) {
    self.workspaceRoot = workspaceRoot
    self.dataRootOverride = dataRootOverride
    self.component = component
    self.pluginRoot = pluginRoot
  }
}

/// Where the workspace root came from.
public enum WorkspaceRootProvenance: String, Sendable, Equatable {
  case explicit
  case currentDirectory = "cwd"
}

/// Where the data root came from.
public enum DataRootProvenance: String, Sendable, Equatable {
  case override
  case workspaceConfig = "workspace_config"
  case `default`
}

/// Where the use-cases root came from.
public enum UseCasesRootProvenance: String, Sendable, Equatable {
  case workspaceConfig = "workspace_config"
  case `default`
}

/// Where the component id came from.
public enum ComponentIdentifierProvenance: String, Sendable, Equatable {
  case option
  case workspaceConfig = "workspace_config"
  case `default`
}

/// Which input decided each resolved root. Carried so a later row can explain
/// an answer without re-deriving it.
public struct WorkspaceProvenance: Sendable, Equatable {
  public let workspaceRoot: WorkspaceRootProvenance
  public let dataRoot: DataRootProvenance
  public let useCasesRoot: UseCasesRootProvenance
  public let componentIdentifier: ComponentIdentifierProvenance

  public init(
    workspaceRoot: WorkspaceRootProvenance,
    dataRoot: DataRootProvenance,
    useCasesRoot: UseCasesRootProvenance,
    componentIdentifier: ComponentIdentifierProvenance,
  ) {
    self.workspaceRoot = workspaceRoot
    self.dataRoot = dataRoot
    self.useCasesRoot = useCasesRoot
    self.componentIdentifier = componentIdentifier
  }
}

/// Every root a command works against, and where each one came from.
public struct ResolvedWorkspaceContext: Sendable, Equatable {
  /// The checkout carrying `.claude-plugin/plugin.json`.
  public let pluginRoot: String

  /// The repository the command is pointed at.
  public let workspaceRoot: String

  /// The directory workspace data hangs off, `data_root` resolved.
  public let dataRoot: String

  /// Where use-case files live, always inside ``dataRoot``.
  public let useCasesRoot: String

  /// The component whose rows this command sees.
  public let componentIdentifier: String

  /// `"use-cases.yml"` when the workspace has a config, nil when it has none.
  public let configPath: String?

  /// The config's verifiers, normalized for the verifier resolver.
  public let verifiers: ResolvedWorkspaceVerifiers

  /// The optional release-gate requirement; nil means no requirement.
  public let releaseGate: WorkspaceReleaseGate?

  /// The optional approval trust anchor; nil means none is pinned.
  public let approvalTrust: WorkspaceApprovalTrust?

  /// Which input decided each root.
  public let provenance: WorkspaceProvenance

  /// Whatever validating the config reported.
  public let diagnostics: [Diagnostic]

  public init(
    pluginRoot: String,
    workspaceRoot: String,
    dataRoot: String,
    useCasesRoot: String,
    componentIdentifier: String,
    configPath: String?,
    verifiers: ResolvedWorkspaceVerifiers,
    releaseGate: WorkspaceReleaseGate?,
    approvalTrust: WorkspaceApprovalTrust?,
    provenance: WorkspaceProvenance,
    diagnostics: [Diagnostic],
  ) {
    self.pluginRoot = pluginRoot
    self.workspaceRoot = workspaceRoot
    self.dataRoot = dataRoot
    self.useCasesRoot = useCasesRoot
    self.componentIdentifier = componentIdentifier
    self.configPath = configPath
    self.verifiers = verifiers
    self.releaseGate = releaseGate
    self.approvalTrust = approvalTrust
    self.provenance = provenance
    self.diagnostics = diagnostics
  }
}
