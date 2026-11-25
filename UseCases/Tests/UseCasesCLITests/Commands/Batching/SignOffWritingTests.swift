import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

/// The commands hand what they planned to the writer they are given, and answer what it answers.
struct SignOffWritingTests {
  private let workspace: StatusWorkspace
  private let spy = SpySignOffWriting(answering: .done("the writer answered"))

  init() throws {
    workspace = try StatusWorkspace()
  }

  private func run(_ arguments: [String]) async -> CommandResult {
    await CommandLineRunner(
      loader: WorkspaceLoader(),
      signOffWriter: spy,
      workingDirectory: workspace.folder.url,
    ).run(arguments: arguments)
  }

  @Test
  func `apply hands its files to the writer and prints the writer's answer`() async throws {
    try workspace.folder.write("batch.yml", "remove: [shop.pay.gift]\n")

    let result = await run(["apply", "--file", "batch.yml", "--dry-run"])
    let requests = await spy.asked()

    #expect(result.outputLines == ["the writer answered"])
    #expect(requests == [
      .init(
        paths: ["use-cases/pay.yml"],
        root: workspace.folder.url.lastPathComponent,
        command: "apply",
        dryRun: true,
        reportsDryRun: true,
      ),
    ])
  }

  @Test
  func `approve hands its files to the writer and prints the writer's answer`() async {
    let result = await run(["approve", "shop.pay.card", "--by", "Sam"])
    let requests = await spy.asked()

    #expect(result.outputLines == ["the writer answered"])
    #expect(requests.map(\.command) == ["approve"])
    #expect(requests.map(\.paths) == [["use-cases/pay.yml"]])
    #expect(requests.map(\.dryRun) == [false])
  }

  @Test
  func `a request the planner refuses never reaches the writer`() async {
    let result = await run(["approve", "shop.pay.nope", "--by", "Sam"])
    let requests = await spy.asked()

    #expect(result.exitCode == 2)
    #expect(requests.isEmpty)
  }
}
