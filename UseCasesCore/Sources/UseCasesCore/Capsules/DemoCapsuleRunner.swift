import Foundation

/// Performs a capsule as a showcase run
/// (packages/core/src/capsules/runCapsule.ts).
///
/// Three things reach outside: command steps run as real processes through
/// the spawner, the clock names the idempotency key when the caller gives
/// none, and the environment is the one allowlisted variables are copied from.
public struct DemoCapsuleRunner: Sendable {
  /// Only these variables reach a command, and only when defined.
  static let allowlistedVariables = [
    "PATH",
    "HOME",
    "TMPDIR",
    "TEMP",
    "TMP",
    "SystemRoot",
    "WINDIR",
  ]
  static let largestTimeoutMilliseconds = 300_000.0

  let registry: SchemaRegistry
  let spawner: any CapsuleCommandSpawning
  let clock: any CapsuleClock
  let environment: [String: String]

  public init(
    registry: SchemaRegistry,
    spawner: any CapsuleCommandSpawning = CapsuleProcessSpawner(),
    clock: any CapsuleClock = SystemCapsuleClock(),
    environment: [String: String] = ProcessInfo.processInfo.environment,
  ) {
    self.registry = registry
    self.spawner = spawner
    self.clock = clock
    self.environment = environment
  }

  /// `runDemoCapsule`: blocked — nothing written — unless the capsule plans
  /// completely, every item was selected, commands are permitted when asked
  /// for, their working directories stay inside the workspace and the timeout
  /// is in range. Otherwise the run is started, every step recorded, and the
  /// run finished when nothing is pending or failing.
  public func run(_ options: DemoCapsuleRunOptions) throws(DemoCapsuleError)
    -> DemoCapsuleRunResult
  {
    let identifier = options.capsuleIdentifier
    let planned = try DemoCapsulePlanner.plan(
      context: options.context,
      capsuleIdentifier: identifier,
      registry: registry,
    )
    guard planned.outcome == .generated,
          let capsule = planned.capsule,
          let planResult = planned.planResult,
          let plan = planResult.plan
    else {
      return .blocked(
        capsuleIdentifier: identifier,
        planResult: planned.planResult,
        diagnostics: planned.diagnostics,
      )
    }
    switch try prepare(options, capsule: capsule, plan: plan, diagnostics: planned.diagnostics) {
    case let .blocked(diagnostics):
      return .blocked(
        capsuleIdentifier: identifier,
        planResult: planResult,
        diagnostics: diagnostics,
      )
    case let .ready(steps, workingDirectories):
      var performance = try DemoCapsulePerformance(
        runner: self,
        options: options,
        plan: plan,
        steps: steps,
        workingDirectories: workingDirectories,
      )
      return try performance.perform(
        capsule: capsule.definition,
        planResult: planResult,
        diagnostics: planned.diagnostics,
      )
    }
  }

  private enum Preparation {
    case blocked([Diagnostic])
    case ready(steps: [DemoCapsulePlannedStep], workingDirectories: [String])
  }

  /// Every check that can block the run, in the TypeScript's order.
  private func prepare(
    _ options: DemoCapsuleRunOptions,
    capsule: LoadedDemoCapsule,
    plan: PresentationPlan,
    diagnostics: [Diagnostic],
  ) throws(DemoCapsuleError) -> Preparation {
    let identifier = options.capsuleIdentifier
    guard plan.isComplete else {
      return .blocked([Diagnostic(
        code: "capsule.plan_incomplete",
        message: "Capsule plan must be complete before it can be performed.",
        entityIdentifier: identifier,
      )] + diagnostics)
    }
    let steps: [DemoCapsulePlannedStep]
    switch Self.plannedSteps(capsule.definition, plan: plan) {
    case let .failure(missing):
      return .blocked(missing.diagnostics)
    case let .success(planned):
      steps = planned
    }
    let commandSteps = steps.filter { $0.command != nil }
    let hasCommands = options.isExecutingCommands && !commandSteps.isEmpty
    if hasCommands, !capsule.definition.isCommandExecutionPermitted {
      return .blocked([Diagnostic(
        code: "capsule.command_execution_not_permitted",
        message: "Capsule does not permit command execution.",
        sourcePath: capsule.path,
        entityIdentifier: identifier,
      )])
    }
    var directories: [String] = []
    if options.isExecutingCommands {
      switch try Self.workingDirectories(commandSteps, context: options.context) {
      case let .failure(escapes):
        return .blocked(escapes.diagnostics)
      case let .success(resolved):
        directories = resolved
      }
    }
    let timeout = options.commandTimeoutMilliseconds
    if hasCommands, !timeout.isFinite || timeout <= 0 || timeout > Self.largestTimeoutMilliseconds {
      return .blocked([Diagnostic(
        code: "capsule.command_timeout_invalid",
        message: "Command timeout must be between 1 and 300000 milliseconds.",
        sourcePath: capsule.path,
        entityIdentifier: identifier,
      )])
    }
    return .ready(steps: steps, workingDirectories: directories)
  }
}
