/// Finds the command whose token path is the longest prefix of the arguments
/// (packages/cli/src/command/dispatch.ts `matchCommand`).
enum CommandMatcher {
  static func match(
    _ arguments: [String],
    in commands: [CommandSpecification],
  ) -> CommandSpecification? {
    var best: CommandSpecification?
    for command in commands where command.path.count <= arguments.count {
      guard command.path.elementsEqual(arguments.prefix(command.path.count)) else {
        continue
      }
      if command.path.count > (best?.path.count ?? 0) {
        best = command
      }
    }
    return best
  }
}
