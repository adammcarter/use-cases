import Foundation
import UseCasesCore
@testable import UseCasesCLI

/// The shop of the acceptance suite's `status` tests on disk: five READY use cases under
/// `shop.pay` (card has a second route that does not gate), `shop.cart.add` READY and
/// `shop.cart.share` a DRAFT.
/// Verdicts are put in the store by the real `record` command.
struct StatusWorkspace {
  let folder: TemporaryFolder

  init(root: String = "schema_version: 1\nroot: true\nprefix: shop\n") throws {
    folder = try TemporaryFolder()

    try folder.write("use-cases.yml", root)
    try folder.write(
      "use-cases/pay.yml",
      "prefix: pay\nuse_cases:\n" + ["card", "wallet", "refund", "voucher", "gift"].map { local in
        Self.useCase(
          local,
          extraRoute: local == "card" ? Self.nonGatingRoute : "",
        )
      }.joined(),
    )
    try folder.write(
      "use-cases/cart.yml",
      "prefix: cart\nuse_cases:\n" + Self.useCase("share", isDraft: true) + Self.useCase("add"),
    )
  }

  /// Runs the command line from the workspace root.
  func run(_ arguments: [String]) async -> CommandResult {
    await CommandLineRunner(
      loader: WorkspaceLoader(),
      workingDirectory: folder.url,
    ).run(arguments: arguments)
  }

  /// Records a verdict for a route of a use case.
  func record(
    _ useCase: String,
    _ status: String,
    route: String = "check",
  ) async {
    let result = await run(["record", useCase, route, status, "--quiet"])

    precondition(result.exitCode == 0, result.standardError)
  }

  /// Changes the words of a use case's intent, which makes its verdicts stale.
  func editIntent(of local: String) throws {
    let path = "use-cases/pay.yml"
    let text = try String(
      contentsOf: folder.url.appendingPathComponent(path),
      encoding: .utf8,
    )

    try folder.write(
      path,
      text.replacingOccurrences(
        of: "    intent: \(local).\n",
        with: "    intent: \(local), changed.\n",
      ),
    )
  }

  /// card failed (its non-gating route passes), wallet error, refund stale, voucher incomplete,
  /// gift unverified, cart.add verified, cart.share draft.
  func recordEveryState() async throws {
    await record("shop.pay.card", "fail")
    await record("shop.pay.card", "pass", route: "extra")
    await record("shop.pay.wallet", "error")
    await record("shop.pay.refund", "pass")
    try editIntent(of: "refund")
    await record("shop.pay.voucher", "incomplete")
    await record("shop.cart.add", "pass")
  }

  /// A verified verdict for every READY use case.
  func recordEverythingPassing() async {
    for useCase in ["card", "wallet", "refund", "voucher", "gift"] {
      await record("shop.pay.\(useCase)", "pass")
    }

    await record("shop.cart.add", "pass")
  }

  private static let nonGatingRoute = """
        - id: extra
          type: { kind: acceptance }
          covers: [s]
          gates_verification: false
          procedure:
            steps: [Look again.]\n
  """

  private static func useCase(
    _ local: String,
    isDraft: Bool = false,
    extraRoute: String = "",
  ) -> String {
    let tier = isDraft ? "" : "    value_tier: core\n"

    return """
      - id: \(local)
        title: \(local.capitalized)
    \(tier)    intent: \(local).
        scenarios:
          - id: s
            when: [x]
            then: [y]
        validation:
          - id: check
            type: { kind: acceptance }
            covers: [s]
            procedure:
              steps: [Check it.]\n
    """ + extraRoute
  }
}
