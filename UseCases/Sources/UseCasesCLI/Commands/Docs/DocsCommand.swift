import ArgumentParser
import UseCasesCore

/// `use-cases docs` (chapter 16 §16): the guides that ship with this version, listed, shown by
/// name, or searched a section at a time. Needs no workspace and writes nothing.
struct DocsCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: Self.name,
    abstract: "The guides that ship with this version: list them, show one, or search them. "
      + "Needs no workspace.",
  )

  static let name = "docs"

  @OptionGroup
  var global: GlobalOptions

  @Argument(help: "A guide's name to show it, or words to look for in the guides.")
  var words: [String] = []

  @Flag(
    name: .long,
    help: "Only whole words, exactly as typed: no word starts, no typos.",
  )
  var exact = false

  // A text, not a number, so that a value outside 1 to 100 is refused in this command's words.
  @Option(
    name: .long,
    help: "Matches a page, 1 to 100. The default is 20.",
  )
  var pageSize: String?

  @Option(
    name: .long,
    help: "The token of the next page. Passed alone.",
  )
  var next: String?

  /// What the command does: lists the guides, shows one or searches them, through `answerer`.
  func result(answerer: any DocsAnswering) -> CommandResult {
    let request: DocsRequest

    do {
      request = try self.request()
    } catch {
      return .refusal(
        .usage,
        message: error.message,
        command: Self.name,
        json: global.json,
      )
    }

    let answer: DocsAnswer

    do {
      answer = try answerer.answer(request)
    } catch {
      return .refusal(
        error.refusalKind,
        message: error.message,
        command: Self.name,
        json: global.json,
      )
    }

    return report(of: answer)
  }
}
