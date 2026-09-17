import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

extension ShowcaseFixtures {
  /// A recorded step run through the Swift port: its result as wire JSON, or
  /// the error it threw.
  static func run(
    _ step: JSONValue,
    plans: JSONValue?,
    workspace: UseCasesFixtures.Workspace,
    context: ResolvedWorkspaceContext,
  ) throws -> Result<JSONValue, ShowcaseError> {
    let runner = try ShowcaseStepRunner(
      step: step,
      plans: plans,
      workspace: workspace,
      context: context,
    )
    do {
      return try .success(runner.perform())
    } catch let error as ShowcaseError {
      return .failure(error)
    }
  }

  /// `appendFileSync(path, text)`, creating the run directory first.
  static func appendRaw(
    _ text: String,
    toPath path: String,
  ) throws {
    let directory = (path as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: path) {
      FileManager.default.createFile(atPath: path, contents: nil)
    }
    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    defer {
      try? handle.close()
    }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
  }
}

/// One recorded step's arguments, and the Swift call each operation names.
struct ShowcaseStepRunner {
  let operation: String
  let arguments: JSONValue
  let recorder: ShowcaseRecorder
  let runIdentifier: String
  let recording: ShowcaseRecording
  let plans: JSONValue?
  let workspace: UseCasesFixtures.Workspace
  let context: ResolvedWorkspaceContext

  init(
    step: JSONValue,
    plans: JSONValue?,
    workspace: UseCasesFixtures.Workspace,
    context: ResolvedWorkspaceContext,
  ) throws {
    operation = try UseCasesFixtures.string(step, "op")
    let arguments = step["args"] ?? .object(JSONObject())
    self.arguments = arguments
    recorder = try ShowcaseRecorder(clock: ShowcaseFixtures.FixedClock(
      milliseconds: #require(step["clock_ms"]?.numberValue),
    ))
    runIdentifier = arguments["run_id"]?.stringValue ?? ""
    recording = try ShowcaseRecording(
      context: context,
      actorType: #require(ShowcaseActorType(rawValue: arguments["actor_type"]?
          .stringValue ?? "agent")),
      hostSurface: arguments["host_surface"]?.stringValue ?? "codex.cli",
      idempotencyKey: arguments["idempotency_key"]?.stringValue ?? "",
      recordedAt: arguments["recorded_at"]?.stringValue,
    )
    self.plans = plans
    self.workspace = workspace
    self.context = context
  }

  private func string(_ key: String) throws -> String {
    try UseCasesFixtures.string(arguments, key)
  }

  func perform() throws -> JSONValue {
    switch operation {
    case "load_plan_file", "start", "write_raw", "read", "replay", "binding":
      try performRunLevel()
    case "approve", "reject":
      try performApproval()
    case "pause", "resume", "epoch", "finish":
      try performRunEvent()
    default:
      try performItemEvent()
    }
  }

  private func performRunLevel() throws -> JSONValue {
    switch operation {
    case "load_plan_file":
      return try .object(PlanBinding.loadPlanFile(atPath: workspace.absolute(string("path"))))
    case "start":
      let plan = try #require(plans?[string("plan")]?.objectValue)
      let mode = try #require(ShowcaseControlMode(
        rawValue: arguments["control_mode"]?.stringValue ?? "agent_led",
      ))
      let acknowledgement = arguments["known_gap_acknowledgement"].map { value in
        ShowcaseKnownGapAcknowledgement(gaps: value["gaps"]?.arrayValue?
          .compactMap(\.stringValue) ?? [])
      }
      return try recorder.start(
        plan: plan,
        controlMode: mode,
        knownGapAcknowledgement: acknowledgement,
        recording: recording,
      ).jsonValue
    case "write_raw":
      let path = ShowcaseLedger.ledgerPath(context: context, runIdentifier: runIdentifier)
      try ShowcaseFixtures.appendRaw(string("text"), toPath: path)
      return .null
    case "read":
      return try ShowcaseLedger.read(context: context, runIdentifier: runIdentifier).jsonValue
    case "replay":
      return try ShowcaseReplay.replay(
        context: context,
        runIdentifier: runIdentifier,
        trust: ShowcaseFixtures.resolvers(arguments),
      ).jsonValue
    default:
      return try .object(ApprovalBinding.binding(context: context, runIdentifier: runIdentifier))
    }
  }

  private func performApproval() throws -> JSONValue {
    let request = try ShowcaseApprovalRequest(
      runIdentifier: runIdentifier,
      statement: string("statement"),
      approvalToken: arguments["token"],
      resolvers: ShowcaseFixtures.resolvers(arguments),
      nowMilliseconds: arguments["now_ms"]?.numberValue,
      recording: recording,
    )
    guard operation == "approve" else {
      return try recorder.reject(request).jsonValue
    }
    let decision = try #require(ShowcaseApprovalDecision(rawValue: string("decision")))
    return try recorder.approve(request, decision: decision).jsonValue
  }

  private func performRunEvent() throws -> JSONValue {
    switch operation {
    case "pause":
      try recorder.pause(
        runIdentifier: runIdentifier,
        reason: string("reason"),
        recording: recording,
      )
      .jsonValue
    case "resume":
      try recorder.resume(
        runIdentifier: runIdentifier,
        reason: string("reason"),
        recording: recording,
      )
      .jsonValue
    case "epoch":
      try recorder.startEpoch(
        runIdentifier: runIdentifier,
        reason: #require(ShowcaseEpochReason(rawValue: string("reason"))),
        staleItemIdentifiers: arguments["stale_item_ids"]?.arrayValue?
          .compactMap(\.stringValue) ?? [],
        recording: recording,
      ).jsonValue
    default:
      try recorder.finish(runIdentifier: runIdentifier, recording: recording).jsonValue
    }
  }

  private func performItemEvent() throws -> JSONValue {
    switch operation {
    case "observation":
      return try recorder.recordObservation(
        runIdentifier: runIdentifier,
        planItemIdentifier: string("plan_item_id"),
        text: string("text"),
        recording: recording,
      ).jsonValue
    case "action":
      return try recorder.recordAction(
        runIdentifier: runIdentifier,
        planItemIdentifier: string("plan_item_id"),
        action: #require(arguments["action"]?.objectValue),
        recording: recording,
      ).jsonValue
    case "verdict":
      return try recorder.recordVerdict(
        runIdentifier: runIdentifier,
        planItemIdentifier: string("plan_item_id"),
        verdict: #require(ShowcaseVerdict(rawValue: string("verdict"))),
        observationEventIdentifiers: arguments["observation_event_ids"]?.arrayValue?
          .compactMap(\.stringValue) ?? [],
        recording: recording,
      ).jsonValue
    case "failure_decision":
      return try recorder.recordFailureDecision(
        runIdentifier: runIdentifier,
        verdictEventIdentifier: string("verdict_event_id"),
        decision: #require(ShowcaseFailureDecision(rawValue: string("decision"))),
        reason: string("reason"),
        recording: recording,
      ).jsonValue
    case "correct":
      return try recorder.correctVerdict(
        runIdentifier: runIdentifier,
        targetEventIdentifier: string("target_event_id"),
        correctedVerdict: #require(ShowcaseVerdict(rawValue: string("corrected_verdict"))),
        reason: string("reason"),
        recording: recording,
      ).jsonValue
    default:
      Issue.record("unknown step \(operation)")
      return .null
    }
  }
}
