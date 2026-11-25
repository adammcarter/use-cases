@testable import UseCasesCLI

/// A surface that answers the way the test says.
struct MockCommandSurface: CommandSurfacing {
  let reply: CommandResult?

  func answer(to arguments: [String]) -> CommandResult? {
    reply
  }
}
