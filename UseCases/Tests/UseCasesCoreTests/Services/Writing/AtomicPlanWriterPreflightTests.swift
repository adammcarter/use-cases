import Foundation
import Testing
@testable import UseCasesCore

struct AtomicPlanWriterPreflightTests {
  private let directory: TemporaryDirectory

  init() throws {
    directory = try TemporaryDirectory()
  }

  private func exists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: directory.location(of: path).path)
  }

  @Test
  func `every change of the plan is put to the preflight it was given, in order`() async throws {
    let preflight = SpyChangeChecking()
    let writer = AtomicPlanWriter(
      fileSystem: LocalFileSystem(),
      preflight: preflight,
    )

    try writer.apply(
      WritePlan.making([.create("a.yml", "one"), .create("b.yml", "two")]),
      in: directory.url,
    )

    #expect(await preflight.asked() == ["a.yml", "b.yml"])
    #expect(exists("a.yml") && exists("b.yml"))
  }

  @Test
  func `a change the preflight refuses writes nothing, whatever the files allow`() async throws {
    let preflight = SpyChangeChecking(refusing: .exists(path: "b.yml"))
    let writer = AtomicPlanWriter(
      fileSystem: LocalFileSystem(),
      preflight: preflight,
    )

    #expect(throws: PlanWritingError.exists(path: "b.yml")) {
      try writer.apply(
        WritePlan.making([.create("a.yml", "one"), .create("b.yml", "two")]),
        in: directory.url,
      )
    }
    #expect(await preflight.asked() == ["a.yml"])
    #expect(!exists("a.yml") && !exists("b.yml"))
  }
}
