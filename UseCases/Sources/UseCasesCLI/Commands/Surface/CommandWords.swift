/// The words of a command line that decide what it asks for before any command reads it: the
/// command's name, and whether help or JSON was asked for. The value of `--workspace` is not a
/// command's name.
struct CommandWords {
  /// The first word that is not an option or an option's value.
  let command: String?

  let asksForHelp: Bool
  let asksForJSON: Bool

  init(_ arguments: [String]) {
    var words: [String] = []
    var asksForHelp = false
    var asksForJSON = false
    var index = 0

    while index < arguments.count {
      let argument = arguments[index]
      index += 1

      if argument == "--" {
        break
      }

      if argument == "--workspace" {
        index += 1
      } else if argument == "--help" || argument == "-h" {
        asksForHelp = true
      } else if argument == "--json" {
        asksForJSON = true
      } else if !argument.hasPrefix("-") {
        words.append(argument)
      }
    }

    command = words.first
    self.asksForHelp = asksForHelp
    self.asksForJSON = asksForJSON
  }
}
