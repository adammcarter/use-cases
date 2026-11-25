import Foundation
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesCLI

/// A shop on disk with five use cases, `shop.pay` among them, which is also the start of
/// `shop.pay.card` and `shop.pay.wallet`.
struct LinksWorkspace {
  let folder: TemporaryFolder

  init() throws {
    folder = try TemporaryFolder()

    try folder.write("use-cases.yml", "schema_version: 1\nroot: true\nprefix: shop\n")
    try folder.write("use-cases/top.yml", Self.file(prefix: nil, ["pay"]))
    try folder.write("use-cases/pay.yml", Self.file(prefix: "pay", ["card", "wallet"]))
    try folder.write(
      "use-cases/cart.yml",
      Self.file(
        prefix: "cart",
        ["add", "share"],
        extra: [
          "add": """
              bindings:
                - id: config
                  kind: manual
                  locator: { file: config/cart.yml }\n
          """,
        ],
      ),
    )
    try folder.write("config/cart.yml", "limit: 5\n")
  }

  /// Runs the command line from the workspace root, as a person at a terminal when `isTerminal`,
  /// who types what `prompter` was given when asked. The link transformers it runs are never
  /// cancelled, and take
  /// over no signal.
  func run(
    _ arguments: [String],
    isTerminal: Bool = false,
    prompter: MockPrompter = MockPrompter(),
  ) async -> CommandResult {
    await CommandLineRunner(
      loader: WorkspaceLoader(),
      transformers: TransformerLinkResolver(cancellation: { MockCancellation.never }),
      prompter: prompter,
      isTerminal: isTerminal,
      workingDirectory: folder.url,
    ).run(arguments: arguments)
  }

  /// Writes a program the bridge settings can name, which answers a links job with this response
  /// text. When `keepingRequestAt` is given, the program also copies the request it was given
  /// there, so that a test can read it: a place outside the workspace, which would scan it.
  func writeLinksProgram(
    _ path: String,
    responding response: String,
    keepingRequestAt copy: URL? = nil,
  ) throws {
    let keep = copy.map { copy in
      "cp \"$2\" '\(copy.path)'\n"
    } ?? ""

    try folder.writeProgram(
      path,
      keep + "printf '%s' '\(response)' > \"$3\"\n",
    )
  }

  /// Whether the workspace has a results store at all.
  var hasStore: Bool {
    FileManager.default.fileExists(atPath: folder.url.appendingPathComponent(".use-cases").path)
  }

  /// The text of a file below the workspace root.
  func read(_ path: String) throws -> String {
    try String(
      contentsOf: folder.url.appendingPathComponent(path),
      encoding: .utf8,
    )
  }

  /// A region of code for `identifier`, between its sentinel lines.
  static func marked(
    _ identifier: String,
    _ body: String = "work()",
  ) -> String {
    "// \(MarkerText.sentinel)\(identifier)\n\(body)\n// \(MarkerText.sentinel)end \(identifier)\n"
  }

  private static func file(
    prefix: String?,
    _ locals: [String],
    extra: [String: String] = [:],
  ) -> String {
    let header = prefix.map { prefix in
      "prefix: \(prefix)\n"
    } ?? ""

    return header + "use_cases:\n" + locals.map { local in
      useCase(local) + (extra[local] ?? "")
    }.joined()
  }

  private static func useCase(_ local: String) -> String {
    """
      - id: \(local)
        title: Use case \(local)
        value_tier: core
        intent: It works.
        scenarios:
          - id: works
            when: [x]
            then: [y]
        validation:
          - id: unit-tests
            type: { kind: unit }
            covers: [works]\n
    """
  }
}
