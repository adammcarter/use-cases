import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

/// Two writers at once never lose a change: a file that holds anything else than it held when
/// the change was planned is not written over.
struct EditConcurrencyTests {
  private let workspace: StatusWorkspace

  init() throws {
    workspace = try StatusWorkspace()
  }

  private func read(_ path: String) throws -> String {
    try String(
      contentsOf: workspace.folder.url.appendingPathComponent(path),
      encoding: .utf8,
    )
  }

  /// Runs the command line with something else changing `use-cases/pay.yml` just before it
  /// writes.
  private func runInterrupted(
    _ arguments: [String],
    by interloper: @escaping @Sendable () -> Void,
  ) async -> CommandResult {
    await CommandLineRunner(
      loader: WorkspaceLoader(),
      writer: ChangingPlanWriting(change: interloper),
      workingDirectory: workspace.folder.url,
    ).run(arguments: arguments)
  }

  private func appendNote(to path: String) -> @Sendable () -> Void {
    let file = workspace.folder.url.appendingPathComponent(path)

    return {
      let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
      try? Data((text + "# someone else's change\n").utf8).write(to: file)
    }
  }

  // @use-case:edit.save#swift-tests.concurrent
  @Test
  func `a save of a file someone changed since it was read is refused and keeps their change`()
    async throws
  {
    try workspace.folder.write(
      "sent.yml",
      "id: shop.pay.wallet\ntitle: Mine\nvalue_tier: core\nintent: wallet.\n"
        + "scenarios:\n  - id: s\n    when: [x]\n    then: [y]\nvalidation:\n  - id: check\n"
        + "    type: { kind: acceptance }\n    covers: [s]\n    procedure:\n"
        + "      steps: [Check it.]\n",
    )

    let result = await runInterrupted(
      ["--json", "save", "--file", "sent.yml"],
      by: appendNote(to: "use-cases/pay.yml"),
    )
    let document = try result.document()

    #expect(result.exitCode == 2)
    #expect(document["error"]?["kind"] == .string("refused"))
    #expect(document["error"]?["message"] ==
      .string("use-cases/pay.yml changed since it was read; run it again"))
    #expect(try read("use-cases/pay.yml").hasSuffix("# someone else's change\n"))
    #expect(try !read("use-cases/pay.yml").contains("title: Mine"))
  }

  // @use-case:end edit.save#swift-tests.concurrent

  @Test
  func `a use case added to a file someone changed since it was read is refused`() async throws {
    try workspace.folder.write("sent.yml", "id: shop.pay.crypto\ntitle: Mine\n")

    let result = await runInterrupted(
      ["save", "--file", "sent.yml"],
      by: appendNote(to: "use-cases/pay.yml"),
    )

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("changed since it was read; run it again"))
    #expect(try !read("use-cases/pay.yml").contains("crypto"))
  }

  @Test
  func `a remove of a file someone changed since it was read is refused and keeps their change`()
    async throws
  {
    let result = await runInterrupted(
      ["remove", "shop.pay.wallet"],
      by: appendNote(to: "use-cases/pay.yml"),
    )

    #expect(result.exitCode == 2)
    #expect(result
      .standardError == "error: use-cases/pay.yml changed since it was read; run it again\n")
    #expect(try read("use-cases/pay.yml").contains("  - id: wallet"))
    #expect(try read("use-cases/pay.yml").hasSuffix("# someone else's change\n"))
  }

  @Test
  func `removing the last use case of a file someone changed is refused, and the file stays`()
    async throws
  {
    _ = await workspace.run(["remove", "shop.cart.add", "--quiet"])

    let result = await runInterrupted(
      ["remove", "shop.cart.share"],
      by: appendNote(to: "use-cases/cart.yml"),
    )

    #expect(result.exitCode == 2)
    #expect(try read("use-cases/cart.yml").hasSuffix("# someone else's change\n"))
  }

  /// Runs the command line with something else changing a file after the command planned its
  /// change and before it hands it over to be written.
  private func runChangedAfterPlanning(
    _ arguments: [String],
    by interloper: @escaping @Sendable () -> Void,
  ) async -> CommandResult {
    let folder = workspace.folder.url

    return await CommandLineRunner(
      loader: WorkspaceLoader(),
      edit: EditTools(
        workingDirectory: folder,
        saver: ChangingSaver(
          saver: UseCaseSaver(workingDirectory: folder),
          change: interloper,
        ),
        remover: ChangingRemover(change: interloper),
      ),
      workingDirectory: folder,
    ).run(arguments: arguments)
  }

  @Test
  func `a save is held to the file as it was read, not as it is when the write begins`()
    async throws
  {
    try workspace.folder.write("sent.yml", "id: shop.pay.crypto\ntitle: Mine\n")

    let result = await runChangedAfterPlanning(
      ["save", "--file", "sent.yml"],
      by: appendNote(to: "use-cases/pay.yml"),
    )

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("changed since it was read; run it again"))
    #expect(try !read("use-cases/pay.yml").contains("crypto"))
  }

  @Test
  func `a remove is held to the file as it was read, not as it is when the write begins`()
    async throws
  {
    let result = await runChangedAfterPlanning(
      ["remove", "shop.pay.wallet"],
      by: appendNote(to: "use-cases/pay.yml"),
    )

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("changed since it was read; run it again"))
    #expect(try read("use-cases/pay.yml").contains("  - id: wallet"))
  }

  @Test
  func `a file nobody touched is written as before`() async throws {
    let result = await runInterrupted(
      ["remove", "shop.pay.wallet"],
      by: {},
    )

    #expect(result.exitCode == 0)
    #expect(try !read("use-cases/pay.yml").contains("  - id: wallet"))
  }

  @Test
  func `a dry run does not make the results folder`() async {
    _ = await workspace.run(["remove", "shop.pay.wallet", "--dry-run"])

    #expect(!FileManager.default
      .fileExists(atPath: workspace.folder.url.appendingPathComponent(".use-cases/write.lock")
        .path))
  }

  // @use-case:edit.save#swift-tests.concurrent
  @Test
  func `two saves to one file at once never lose a change`() async throws {
    let folder = workspace.folder.url

    for round in 0 ..< 12 {
      try workspace.folder.write("one.yml", Self.definition("wallet", title: "One \(round)"))
      try workspace.folder.write("two.yml", Self.definition("card", title: "Two \(round)"))

      async let first = Self.run(["save", "--file", "one.yml"], in: folder)
      async let second = Self.run(["save", "--file", "two.yml"], in: folder)
      let results = await [first, second]
      let text = try read("use-cases/pay.yml")

      for (result, title) in zip(results, ["One \(round)", "Two \(round)"]) {
        if result.exitCode == 0 {
          #expect(text.contains("title: \(title)\n"), "saved \(title), and lost it")
        } else {
          #expect(result.standardError.contains("changed since it was read; run it again"))
        }
      }
    }
  }

  // @use-case:end edit.save#swift-tests.concurrent

  private static func run(
    _ arguments: [String],
    in folder: URL,
  ) async -> CommandResult {
    await CommandLineRunner(
      loader: WorkspaceLoader(),
      workingDirectory: folder,
    ).run(arguments: arguments)
  }

  private static func definition(
    _ local: String,
    title: String,
  ) -> String {
    "id: shop.pay.\(local)\ntitle: \(title)\nvalue_tier: core\nintent: \(local).\n"
      + "scenarios:\n  - id: s\n    when: [x]\n    then: [y]\nvalidation:\n  - id: check\n"
      + "    type: { kind: acceptance }\n    covers: [s]\n    procedure:\n"
      + "      steps: [Check it.]\n"
  }
}
