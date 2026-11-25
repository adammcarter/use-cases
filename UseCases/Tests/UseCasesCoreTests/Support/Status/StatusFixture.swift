import Foundation
import Testing
@testable import UseCasesCore

/// A workspace on disk with the real recorder to put verdicts in its store and the real judge to
/// read them back.
struct StatusFixture {
  let recording: RecorderFixture

  var workspace: WorkspaceFixture {
    recording.freshness.workspace
  }

  init(
    root: String = FreshnessSamples.root(),
    definitions: String = FreshnessSamples.definitions(),
  ) throws {
    recording = try RecorderFixture(definitions: definitions)

    try workspace.write(
      "use-cases.yml",
      root,
    )
  }

  /// Records a verdict for a route of `app.toggle` against the workspace as it is now.
  func record(
    _ route: String,
    _ status: String = "pass",
    useCase: String = FreshnessSamples.useCase,
  ) throws {
    _ = try recording.recorder.commit(
      recording.plan(
        useCase,
        route,
        status,
      ),
    )
  }

  /// Rewrites the sample definition file.
  func rewrite(_ definitions: String) throws {
    try workspace.write(
      "use-cases/toggle.yml",
      definitions,
    )
  }

  func write(
    _ path: String,
    _ text: String,
  ) throws {
    try workspace.write(
      path,
      text,
    )
  }

  /// The workspace judged as it is on disk now.
  func status(using judge: StatusJudge = StatusJudge()) throws -> WorkspaceStatus {
    let loaded = try workspace.loaded()

    return try judge.judge(
      loaded,
      links: LinkResolver().resolveLinks(in: loaded),
    )
  }

  /// The one use case of the sample workspace, as judged now.
  func useCase(_ identifier: String = FreshnessSamples.useCase) throws -> UseCaseStatus {
    try #require(
      status().useCases.first { useCase in
        useCase.identifier == identifier
      },
    )
  }

  /// A sealed run's folder, written as an unfinished one: manifest and log, no marker.
  func startRun(_ number: Int) throws {
    let identifier = StoreFixture.identifier(number)
    let folder = StoreFixture.folder(identifier)

    try write(
      "\(folder)/run.json",
      StoreSamples.manifest(runIdentifier: identifier).json,
    )
    try write(
      "\(folder)/results.jsonl",
      "",
    )
  }
}
