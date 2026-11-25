import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

/// Two writers at once never lose a change: a file that holds anything else than it held when
/// the batch or the sign-off was planned is not written over.
struct SignOffConcurrencyTests {
  private static let refusal = "changed since it was read; run it again"

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

  private func appendNote(to path: String) -> @Sendable () -> Void {
    let file = workspace.folder.url.appendingPathComponent(path)

    return {
      let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
      try? Data((text + "# someone else's change\n").utf8).write(to: file)
    }
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
      signOff: SignOffTools(
        workingDirectory: folder,
        applier: ChangingApplier(
          applier: UseCaseApplier(workingDirectory: folder),
          change: interloper,
        ),
        approver: ChangingApprover(change: interloper),
      ),
      workingDirectory: folder,
    ).run(arguments: arguments)
  }

  /// Runs the command line with something else changing a file as the writer begins.
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

  private func batch(_ text: String) throws -> [String] {
    try workspace.folder.write("batch.yml", text)

    return ["apply", "--file", "batch.yml"]
  }

  // MARK: - Planned, then changed

  @Test
  func `an apply is held to the file as it was read, not as it is when the write begins`()
    async throws
  {
    let arguments = try batch("save:\n  - id: shop.pay.crypto\n    title: Mine\n")

    let result = await runChangedAfterPlanning(
      arguments,
      by: appendNote(to: "use-cases/pay.yml"),
    )

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains(Self.refusal))
    #expect(try !read("use-cases/pay.yml").contains("crypto"))
    #expect(try read("use-cases/pay.yml").hasSuffix("# someone else's change\n"))
  }

  @Test
  func `an apply that removes is held to the file as it was read`() async throws {
    let arguments = try batch("remove: [shop.pay.wallet]\n")

    let result = await runChangedAfterPlanning(
      arguments,
      by: appendNote(to: "use-cases/pay.yml"),
    )

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains(Self.refusal))
    #expect(try read("use-cases/pay.yml").contains("  - id: wallet"))
  }

  @Test
  func `an apply that empties a file is held to the file as it was read, and the file stays`()
    async throws
  {
    _ = await workspace.run(["remove", "shop.cart.add", "--quiet"])
    let arguments = try batch("remove: [shop.cart.share]\n")

    let result = await runChangedAfterPlanning(
      arguments,
      by: appendNote(to: "use-cases/cart.yml"),
    )

    #expect(result.exitCode == 2)
    #expect(try read("use-cases/cart.yml").hasSuffix("# someone else's change\n"))
  }

  @Test
  func `an apply that empties a file and fills it again is held to the file as it was read`()
    async throws
  {
    _ = await workspace.run(["remove", "shop.cart.add", "--quiet"])
    let arguments = try batch(
      "remove: [shop.cart.share]\nsave:\n  - id: shop.cart.again\n    title: Again\n",
    )

    let result = await runChangedAfterPlanning(
      arguments,
      by: appendNote(to: "use-cases/cart.yml"),
    )

    #expect(result.exitCode == 2)
    #expect(try !read("use-cases/cart.yml").contains("again"))
  }

  @Test
  func `an approve is held to the file as it was read, not as it is when the write begins`()
    async throws
  {
    let result = await runChangedAfterPlanning(
      ["approve", "shop.pay.card", "shop.pay.wallet", "--by", "Sam"],
      by: appendNote(to: "use-cases/pay.yml"),
    )

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains(Self.refusal))
    #expect(try !read("use-cases/pay.yml").contains("approved:"))
    #expect(try read("use-cases/pay.yml").hasSuffix("# someone else's change\n"))
  }

  @Test
  func `an approve of everything is held to every file as it was read`() async throws {
    let result = await runChangedAfterPlanning(
      ["approve", "--all", "--by", "Sam"],
      by: appendNote(to: "use-cases/cart.yml"),
    )

    #expect(result.exitCode == 2)
    #expect(try !read("use-cases/cart.yml").contains("approved:"))
    #expect(try !read("use-cases/pay.yml").contains("approved:"))
  }

  // MARK: - Changed as the write begins

  @Test
  func `an apply of a file someone changed as the write began is refused`() async throws {
    let arguments = try batch("save:\n  - id: shop.pay.crypto\n    title: Mine\n")

    let result = await runInterrupted(
      arguments,
      by: appendNote(to: "use-cases/pay.yml"),
    )

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains(Self.refusal))
    #expect(try !read("use-cases/pay.yml").contains("crypto"))
  }

  @Test
  func `an approve of a file someone changed as the write began is refused`() async throws {
    let result = await runInterrupted(
      ["approve", "shop.pay.card", "--by", "Sam"],
      by: appendNote(to: "use-cases/pay.yml"),
    )

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains(Self.refusal))
    #expect(try !read("use-cases/pay.yml").contains("approved:"))
  }

  @Test
  func `files nobody touched are written as before`() async throws {
    let arguments = try batch("remove: [shop.pay.wallet]\n")

    let applied = await runChangedAfterPlanning(
      arguments,
      by: {},
    )
    let approved = await runChangedAfterPlanning(
      ["approve", "shop.pay.card", "--by", "Sam"],
      by: {},
    )

    #expect(applied.exitCode == 0)
    #expect(approved.exitCode == 0)
    #expect(try !read("use-cases/pay.yml").contains("  - id: wallet"))
    #expect(try read("use-cases/pay.yml").contains("approved:"))
  }

  // MARK: - Two at once

  @Test
  func `two applies to one file at once never lose a change`() async throws {
    let folder = workspace.folder.url

    for round in 0 ..< 12 {
      try workspace.folder.write("one.yml", Self.batch("one\(round)"))
      try workspace.folder.write("two.yml", Self.batch("two\(round)"))

      async let first = Self.run(["apply", "--file", "one.yml"], in: folder)
      async let second = Self.run(["apply", "--file", "two.yml"], in: folder)
      let results = await [first, second]
      let text = try read("use-cases/pay.yml")

      for (result, local) in zip(results, ["one\(round)", "two\(round)"]) {
        if result.exitCode == 0 {
          #expect(text.contains("- id: \(local)\n"), "applied \(local), and lost it")
        } else {
          #expect(result.standardError.contains(Self.refusal))
        }
      }
    }
  }

  @Test
  func `two approves of one file at once never lose a sign-off`() async throws {
    let folder = workspace.folder.url

    for round in 0 ..< 12 {
      async let first = Self.run(["approve", "shop.pay.card", "--by", "One\(round)"], in: folder)
      async let second = Self.run(["approve", "shop.pay.wallet", "--by", "Two\(round)"], in: folder)
      let results = await [first, second]
      let text = try read("use-cases/pay.yml")

      for (result, name) in zip(results, ["One\(round)", "Two\(round)"]) {
        if result.exitCode == 0 {
          #expect(text.contains("by: \(name)\n"), "approved by \(name), and lost it")
        } else {
          #expect(result.standardError.contains(Self.refusal))
        }
      }

      try Self.withdraw(from: workspace.folder, "use-cases/pay.yml")
    }
  }

  private static func run(
    _ arguments: [String],
    in folder: URL,
  ) async -> CommandResult {
    await CommandLineRunner(
      loader: WorkspaceLoader(),
      workingDirectory: folder,
    ).run(arguments: arguments)
  }

  private static func batch(_ local: String) -> String {
    "save:\n  - id: shop.pay.\(local)\n    title: \(local)\n"
  }

  /// Takes the sign-offs out of a file, so that the next round signs off again.
  private static func withdraw(
    from folder: TemporaryFolder,
    _ path: String,
  ) throws {
    let file = folder.url.appendingPathComponent(path)
    let kept = try String(contentsOf: file, encoding: .utf8)
      .components(separatedBy: "\n")
      .filter { line in
        !line.contains("approved:") && !line.hasPrefix("      by: ") && !line
          .hasPrefix("      \"on\"")
          && !line.hasPrefix("      behaviour")
      }

    try folder.write(path, kept.joined(separator: "\n"))
  }
}
