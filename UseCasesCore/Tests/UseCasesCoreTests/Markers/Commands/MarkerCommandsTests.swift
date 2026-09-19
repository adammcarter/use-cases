import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// bind, unbind, rebind and validate-ledger replayed over real workspaces, each
/// step's result and the final bytes and modes of every file compared with what
/// the TypeScript command cores produced for the same steps.
struct MarkerCommandsTests {
  private typealias Fixtures = MarkerCommandsFixtures

  @Test(arguments: MarkerCommandsGoldenCorpus.commandCaseNames)
  func `each command step returns and leaves on disk what the TypeScript did`(
    caseName: String,
  ) throws {
    let entry = try Fixtures.entry(caseName, in: "command_cases")
    let (directory, root) = try Fixtures.temporaryRoot()
    let entries = try #require(entry["entries"]?.arrayValue)
    defer {
      Fixtures.restorePermissions(entries, under: root)
      _ = directory
    }
    try Fixtures.materialize(entries, under: root)
    let workspace = root + "/workspace"
    let ticks = CommandTicks()

    for (index, step) in try #require(entry["steps"]?.arrayValue).enumerated() {
      let kind = try #require(step["kind"]?.stringValue)
      switch kind {
      case "write":
        let path = try #require(step["path"]?.stringValue)
        try Fixtures.materialize(
          [.array([
            .string("file"),
            .string("workspace/" + path),
            #require(step["contents"]),
            .number(step["mode"]?.numberValue ?? 0o644),
          ])],
          under: root,
        )
      case "git":
        let arguments = try #require(step["arguments"]?.arrayValue).compactMap(\.stringValue)
        _ = try GitProcessRunner().run(arguments, workingDirectory: workspace)
      default:
        let actual = try run(
          kind,
          step["options"] ?? .object(JSONObject()),
          workspace: workspace,
          ticks: ticks,
        )
        #expect(
          Fixtures.wire(actual) == Fixtures.wire(step["result"]),
          "\(caseName) step \(index) (\(kind))",
        )
      }
    }

    #expect(
      try Fixtures.wire(Fixtures.snapshot(root)) == Fixtures.wire(entry["tree"]),
      "\(caseName) tree",
    )
  }

  private func run(
    _ kind: String,
    _ options: JSONValue,
    workspace: String,
    ticks: CommandTicks,
  ) throws -> JSONValue {
    let registry = try Fixtures.registry.get()
    let context = try WorkspaceContextResolver.resolve(
      options: ResolveWorkspaceContextOptions(workspaceRoot: workspace),
      registry: registry,
    )
    let bindingsPath = NodePath.join(context.dataRoot, ".use-cases", "bindings.jsonl")
    switch kind {
    case "bind":
      let bind = bindOptions(options, context: context, bindingsPath: bindingsPath, ticks: ticks)
      return try BindCommand.run(bind, registry: registry).jsonValue
    case "unbind":
      var unbind = UnbindCommandOptions(
        context: context,
        productRoot: context.workspaceRoot,
        bindingsPath: bindingsPath,
        rowIdentifier: options["row_id"]?.stringValue ?? "",
        clock: ticks.clock,
        identifierFactory: ticks.identifier,
      )
      unbind.suffix = options["suffix"]?.stringValue
      unbind.reason = options["reason"]?.stringValue
      unbind.dryRun = options["dry_run"]?.boolValue ?? false
      unbind.version = options["version"]?.stringValue
      return try UnbindCommand.run(unbind, registry: registry).jsonValue
    case "rebind":
      let rebind = rebindOptions(
        options,
        context: context,
        bindingsPath: bindingsPath,
        ticks: ticks,
      )
      return try RebindCommand.run(rebind, registry: registry).jsonValue
    default:
      return try validateLedger(
        options,
        context: context,
        bindingsPath: bindingsPath,
        workspace: workspace,
        registry: registry,
      )
    }
  }

  private func bindOptions(
    _ options: JSONValue,
    context: ResolvedWorkspaceContext,
    bindingsPath: String,
    ticks: CommandTicks,
  ) -> BindCommandOptions {
    var bind = BindCommandOptions(
      context: context,
      productRoot: context.workspaceRoot,
      bindingsPath: bindingsPath,
      rowIdentifier: options["row_id"]?.stringValue ?? "",
      file: options["file"]?.stringValue ?? "",
      mode: MarkerMode(rawValue: options["mode"]?.stringValue ?? "") ?? .explicit,
      clock: ticks.clock,
      identifierFactory: ticks.identifier,
    )
    bind.suffix = options["suffix"]?.stringValue
    bind.line = Fixtures.optionalInteger(options, "line")
    bind.startLine = Fixtures.optionalInteger(options, "start_line")
    bind.endLine = Fixtures.optionalInteger(options, "end_line")
    bind.commentPrefix = options["comment_prefix"]?.stringValue
    bind.registerExisting = options["register_existing"]?.boolValue ?? false
    bind.dryRun = options["dry_run"]?.boolValue ?? false
    bind.version = options["version"]?.stringValue
    return bind
  }

  private func rebindOptions(
    _ options: JSONValue,
    context: ResolvedWorkspaceContext,
    bindingsPath: String,
    ticks: CommandTicks,
  ) -> RebindCommandOptions {
    var rebind = RebindCommandOptions(
      context: context,
      productRoot: context.workspaceRoot,
      bindingsPath: bindingsPath,
      rowIdentifier: options["row_id"]?.stringValue ?? "",
      file: options["file"]?.stringValue ?? "",
      mode: MarkerMode(rawValue: options["mode"]?.stringValue ?? "") ?? .explicit,
      clock: ticks.clock,
      identifierFactory: ticks.identifier,
    )
    rebind.suffix = options["suffix"]?.stringValue
    rebind.line = Fixtures.optionalInteger(options, "line")
    rebind.startLine = Fixtures.optionalInteger(options, "start_line")
    rebind.endLine = Fixtures.optionalInteger(options, "end_line")
    rebind.reason = options["reason"]?.stringValue
    rebind.commentPrefix = options["comment_prefix"]?.stringValue
    rebind.dryRun = options["dry_run"]?.boolValue ?? false
    rebind.version = options["version"]?.stringValue
    return rebind
  }

  private func validateLedger(
    _ options: JSONValue,
    context: ResolvedWorkspaceContext,
    bindingsPath: String,
    workspace: String,
    registry: SchemaRegistry,
  ) throws -> JSONValue {
    var validate = ValidateLedgerCommandOptions(
      context: context,
      evidencePath: NodePath.join(context.dataRoot, ".use-cases", "proofs.jsonl"),
      bindingsPath: bindingsPath,
      publicKeyResolver: { _, _ in nil },
    )
    validate.baseReference = options["base_ref"]?.stringValue
    validate.repositoryWorkingDirectory = workspace
    guard let texts = options["base_texts"]?.objectValue else {
      return try ValidateLedgerCommand.run(validate, registry: registry).jsonValue
    }
    var scripted: [String: String] = [:]
    for pair in texts.pairs {
      scripted[pair.key] = pair.value.stringValue
    }
    return try ValidateLedgerCommand.run(
      validate,
      registry: registry,
      gitRunner: ScriptedGitRunner(texts: scripted),
    ).jsonValue
  }
}
