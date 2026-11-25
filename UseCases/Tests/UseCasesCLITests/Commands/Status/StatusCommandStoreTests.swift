import Testing
@testable import UseCasesCLI

/// The store's line under `status` and the `prune` hint (chapter 16 §9, §18).
struct StatusCommandStoreTests {
  private let workspace: StatusWorkspace

  init() throws {
    workspace = try StatusWorkspace()
  }

  private func storeLines(_ arguments: [String]) async -> [String] {
    await workspace.run(arguments).outputLines.filter { line in
      line.hasPrefix("results: ")
    }
  }

  @Test
  func `a store with no run has no line and no store in json`() async throws {
    #expect(await storeLines(["status"]).isEmpty)
    #expect(try await workspace.run(["status", "--json"]).document()["store"] == nil)
  }

  @Test
  func `the line counts the runs and their size, and names no prune when none is superseded`(
  ) async throws {
    await workspace.recordEverythingPassing()

    let output = await workspace.run(["status"]).outputLines
    let store = try await workspace.run(["status", "--json"]).document()["store"]

    #expect(output.contains { line in
      line.hasPrefix("results: 6 runs · ") && line.hasSuffix(" KB")
    })
    #expect(!output.contains { line in
      line.contains("prune")
    })
    #expect(store?["runs"] == .integer(6))
    #expect(store?["superseded"] == .integer(0))
  }

  @Test
  func `superseded runs are counted, and prune is the hint when nothing else wants it`(
  ) async throws {
    await workspace.recordEverythingPassing()
    await workspace.record("shop.pay.card", "pass")

    let output = await workspace.run(["status"]).outputLines
    let store = try await workspace.run(["status", "--json"]).document()["store"]

    #expect(output.last == "→ use-cases prune   to remove 1 superseded run")
    #expect(output.dropLast().last?.hasPrefix("results: 7 runs · ") == true)
    #expect(output.dropLast().last?.hasSuffix(" · 1 superseded") == true)
    #expect(store?["superseded"] == .integer(1))
  }

  @Test
  func `a use case that needs a look keeps the hint`() async {
    await workspace.recordEverythingPassing()
    await workspace.record("shop.pay.card", "fail")

    let output = await workspace.run(["status"]).outputLines

    #expect(output.last == "→ use-cases status shop.pay.card   to see why")
    #expect(output.dropLast().last?.hasSuffix(" · 1 superseded") == true)
  }

  @Test(arguments: [["status", "shop.pay.card"], ["status", "--gate"]])
  func `the detail view and the gate have no store line`(arguments: [String]) async {
    await workspace.recordEverythingPassing()

    #expect(await storeLines(arguments).isEmpty)
  }
}
