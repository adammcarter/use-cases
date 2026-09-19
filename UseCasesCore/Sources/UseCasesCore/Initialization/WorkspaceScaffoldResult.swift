/// What `scaffoldWorkspace` was asked to do.
public struct WorkspaceScaffoldOptions: Sendable {
  /// Absolute, or relative to the working directory.
  public var repositoryRoot: String
  /// nil is `generic`.
  public var template: InitializationTemplate?
  /// nil derives the component from the repository directory's name.
  public var component: String?
  /// Overwrite an existing use-cases.yml.
  public var force: Bool
  /// The day written into the AGENTS.md decision; nil asks the clock.
  public var today: String?

  public init(
    repositoryRoot: String,
    template: InitializationTemplate? = nil,
    component: String? = nil,
    force: Bool = false,
    today: String? = nil,
  ) {
    self.repositoryRoot = repositoryRoot
    self.template = template
    self.component = component
    self.force = force
    self.today = today
  }
}

/// The verifier the scaffolded `verifiers.default` points at.
public struct ScaffoldDefaultVerifier: Sendable, Equatable {
  public enum Kind: String, Sendable {
    case preset
    case script
  }

  public let identifier: String
  public let kind: Kind
  public let preset: String?
  public let command: [String]?

  var jsonValue: JSONValue {
    var object = JSONObject([
      ("id", .string(identifier)),
      ("kind", .string(kind.rawValue)),
    ])
    if let preset {
      object["preset"] = .string(preset)
    }
    if let command {
      object["command"] = .array(command.map(JSONValue.string))
    }
    return .object(object)
  }
}

/// The once-per-repository decision recorded in AGENTS.md.
public struct AgentsMarkdownOutcome: Sendable, Equatable {
  public enum Status: String, Sendable {
    case created
    case appended
    case alreadyRecorded = "already_recorded"
  }

  public enum Decision: String, Sendable {
    case agreed = "yes"
    case declined = "no"
    case unknown
  }

  public let status: Status
  public let decision: Decision
}

/// Where the git hooks landed and whether core.hooksPath now points at them.
public struct GitHooksOutcome: Sendable, Equatable {
  public let hooksDirectory: String
  public let isHooksPathSet: Bool
  public let extended: [String]
}

/// `ScaffoldWorkspaceResult`.
public struct WorkspaceScaffoldResult: Sendable, Equatable {
  public enum Status: String, Sendable {
    case created
    case blocked
  }

  public let status: Status
  public let template: InitializationTemplate
  public let componentIdentifier: String
  public let defaultVerifier: ScaffoldDefaultVerifier
  public let createdFiles: [String]
  public let agentsMarkdown: AgentsMarkdownOutcome?
  public let gitHooks: GitHooksOutcome?
  public let nextSteps: [String]
  public let diagnostics: [Diagnostic]

  /// The wire form, in the TypeScript's key order.
  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("schema_version", .number(1)),
      ("status", .string(status.rawValue)),
      ("template", .string(template.rawValue)),
      ("component_id", .string(componentIdentifier)),
      ("default_verifier", defaultVerifier.jsonValue),
      ("created_files", .array(createdFiles.map(JSONValue.string))),
      ("agents_md", agentsMarkdown.map { outcome in
        .object(JSONObject([
          ("status", .string(outcome.status.rawValue)),
          ("decision", .string(outcome.decision.rawValue)),
        ]))
      } ?? .null),
      ("git_hooks", gitHooks.map { hooks in
        .object(JSONObject([
          ("hooks_dir", .string(hooks.hooksDirectory)),
          ("hooks_path_set", .bool(hooks.isHooksPathSet)),
          ("extended", .array(hooks.extended.map(JSONValue.string))),
        ]))
      } ?? .null),
      ("next_steps", .array(nextSteps.map(JSONValue.string))),
      ("diagnostics", .array(diagnostics.map(\.jsonValue))),
    ]))
  }
}
