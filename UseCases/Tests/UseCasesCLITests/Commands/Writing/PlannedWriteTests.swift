import Foundation
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesCLI

struct PlannedWriteTests {
  private let place: InitFolder

  init() throws {
    place = try InitFolder()
  }

  private func plan(_ form: InitForm = .full) throws -> InitPlan {
    try WorkspaceInitializer().plan(
      InitRequest(
        folder: place.url,
        form: form,
        prefix: nil,
      ),
    )
  }

  private func write(
    writer: any PlanWriting = AtomicPlanWriter(),
    cancellation: any CancellationScoping = ObservedCancellationScope(
      makeObserver: {
        NoCancellation()
      },
    ),
  ) -> PlannedWrite {
    PlannedWrite(
      viewer: OverlayPlanViewer(),
      writer: writer,
      transformers: MockTransformerLinks.none,
      cancellation: cancellation,
    )
  }

  @Test
  func `a plan is checked through a view, and then written once`() async throws {
    let plan = try plan()
    let log = place.scratch.url.appendingPathComponent("log")

    let outcome = try await write(writer: SpyPlanWriting(log: log)).carryOut(
      plan.writes,
      in: plan.root,
      dryRun: false,
    )

    #expect(outcome == .written)
    #expect(try place.snapshot().keys.count == 4)
    #expect(SpyPlanWriting(log: log).applied == [place.realPath])
  }

  @Test
  func `a dry run checks the plan and writes nothing, anywhere`() async throws {
    let plan = try plan()
    let log = place.scratch.url.appendingPathComponent("log")

    let outcome = try await write(writer: SpyPlanWriting(log: log)).carryOut(
      plan.writes,
      in: plan.root,
      dryRun: true,
    )

    #expect(outcome == .previewed)
    #expect(try place.snapshot().isEmpty)
    #expect(SpyPlanWriting(log: log).applied.isEmpty)
  }

  @Test
  func `a plan that would leave the workspace invalid is refused and writes nothing`()
    async throws
  {
    try place.folder.write("use-cases.yml", "schema_version: 1\nroot: true\n")
    try place.folder.write("use-case-groups.yml", InitFolder.unknownIdGroups)
    let plan = try plan()
    let before = try place.snapshot()

    await #expect(throws: PlannedWriteError.self) {
      try await write().carryOut(
        plan.writes,
        in: plan.root,
        dryRun: false,
      )
    }

    #expect(try place.snapshot() == before)
  }

  @Test
  func `a plan the workspace it leaves does not bear out is refused, and writes nothing`()
    async throws
  {
    let plan = try plan()
    let before = try place.snapshot()

    await #expect(throws: PlannedWriteError.diverges("not what was meant")) {
      try await write().carryOut(
        plan.writes,
        in: plan.root,
        confirming: { _ in
          "not what was meant"
        },
        dryRun: false,
      )
    }

    #expect(try place.snapshot() == before)
  }

  @Test
  func `a plan the workspace it leaves bears out is written`() async throws {
    let plan = try plan()

    let outcome = try await write().carryOut(
      plan.writes,
      in: plan.root,
      confirming: { workspace in
        workspace.summary.useCases == 1 ? nil : "the example is missing"
      },
      dryRun: false,
    )

    #expect(outcome == .written)
  }

  @Test
  func `a plan with nothing in it still refuses an invalid workspace`() async throws {
    try place.folder.write("use-cases.yml", "schema_version: 1\nroot: true\n")
    try place.folder.write("use-cases/bad.yml", "use_cases:\n  - id: bad\n    surprise: true\n")
    let plan = try plan(.minimal)

    #expect(plan.writes.isEmpty)
    await #expect(throws: PlannedWriteError.self) {
      try await write().carryOut(
        plan.writes,
        in: plan.root,
        dryRun: false,
      )
    }
  }

  @Test
  func `a plan with nothing in it is written as nothing`() async throws {
    try place.folder.write("use-cases.yml", "schema_version: 1\nroot: true\n")
    let plan = try plan(.minimal)

    let outcome = try await write().carryOut(
      plan.writes,
      in: plan.root,
      dryRun: false,
    )

    #expect(outcome == .written)
  }

  // MARK: - Writes beside the workspace

  private func hooksWrite() async throws -> FolderWrite {
    try await place.clone().plan(
      HooksRequest(
        root: place.url,
        action: .add,
        names: [.commit],
        program: "/opt/use-cases/bin/use-cases",
      ),
    ).writes
  }

  @Test
  func `writes beside the workspace never load it, and an invalid one does not stop them`()
    async throws
  {
    try place.folder.write("use-cases.yml", "schema_version: 1\nroot: true\n")
    try place.folder.write("use-cases/bad.yml", "use_cases:\n  - id: bad\n    surprise: true\n")
    try place.folder.write(".git/HEAD", "x")

    let outcome = try await write().carryOut(
      only: [hooksWrite()],
      lockingIn: place.url,
      dryRun: false,
    )

    #expect(outcome == .written)
    #expect(try place.snapshot().keys.contains(".git/hooks/pre-commit"))
  }

  @Test
  func `a dry run of writes beside the workspace writes nothing`() async throws {
    try place.folder.write(".git/HEAD", "x")
    let before = try place.snapshot()

    let outcome = try await write().carryOut(
      only: [hooksWrite()],
      lockingIn: place.url,
      dryRun: true,
    )

    #expect(outcome == .previewed)
    #expect(try place.snapshot() == before)
  }

  @Test
  func `nothing to write beside the workspace is written without a claim`() async throws {
    let outcome = try await write(
      cancellation: ObservedCancellationScope(
        makeObserver: {
          MockCancellation.always
        },
      ),
    ).carryOut(
      only: [],
      lockingIn: place.url,
      dryRun: false,
    )

    #expect(outcome == .written)
  }

  @Test
  func `writes beside the workspace written after a cancellation was seen are not written`()
    async throws
  {
    try place.folder.write(".git/HEAD", "x")
    let scope = ObservedCancellationScope(
      makeObserver: {
        MockCancellation.always
      },
    )
    await scope.begin()

    let outcome = try await write(cancellation: scope).carryOut(
      only: [hooksWrite()],
      lockingIn: place.url,
      dryRun: false,
    )

    #expect(outcome == .cancelled)
    #expect(try place.snapshot().keys.sorted() == [".git/HEAD"])
  }

  @Test
  func `the workspace and what is beside it are written together, the workspace first`()
    async throws
  {
    try place.folder.write(".git/HEAD", "x")
    let plan = try plan(.minimal)
    let log = place.scratch.url.appendingPathComponent("log")

    let outcome = try await write(writer: SpyPlanWriting(log: log)).carryOut(
      plan.writes,
      in: plan.root,
      alongside: [hooksWrite()],
      dryRun: false,
    )

    #expect(outcome == .written)
    #expect(SpyPlanWriting(log: log).applied == [
      place.realPath,
      place.realPath + "/.git",
    ])
    #expect(try place.snapshot().keys.contains("use-cases.yml"))
  }

  @Test
  func `an invalid workspace stops what is written beside it too`() async throws {
    try place.folder.write("use-cases.yml", "schema_version: 1\nroot: true\n")
    try place.folder.write("use-case-groups.yml", InitFolder.unknownIdGroups)
    try place.folder.write(".git/HEAD", "x")
    let plan = try plan()
    let before = try place.snapshot()

    await #expect(throws: PlannedWriteError.self) {
      try await write().carryOut(
        plan.writes,
        in: plan.root,
        alongside: [hooksWrite()],
        dryRun: false,
      )
    }

    #expect(try place.snapshot() == before)
  }
}
