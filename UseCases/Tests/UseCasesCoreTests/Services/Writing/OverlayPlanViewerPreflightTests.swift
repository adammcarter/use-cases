import Foundation
import Testing
@testable import UseCasesCore

struct OverlayPlanViewerPreflightTests {
  private let directory: TemporaryDirectory

  init() throws {
    directory = try TemporaryDirectory()
  }

  @Test
  func `every change of the plan is put to the preflight it was given, in order`() async throws {
    let preflight = SpyChangeChecking()
    let viewer = OverlayPlanViewer(
      fileSystem: LocalFileSystem(),
      preflight: preflight,
    )

    _ = try viewer.view(
      showing: WritePlan.making([.create("a.yml", "one"), .create("b.yml", "two")]),
      in: directory.url,
    )

    #expect(await preflight.asked() == ["a.yml", "b.yml"])
  }

  @Test
  func `a change the preflight refuses is refused by the view, whatever the files allow`()
    throws
  {
    let viewer = OverlayPlanViewer(
      fileSystem: LocalFileSystem(),
      preflight: SpyChangeChecking(refusing: .missing(path: "a.yml")),
    )

    #expect(throws: PlanWritingError.missing(path: "a.yml")) {
      try viewer.view(
        showing: WritePlan.making([.create("a.yml", "one")]),
        in: directory.url,
      )
    }
  }
}
