import ArgumentParser

/// The options every command takes (chapter 16 §2). They work before the command's name and
/// after it.
struct GlobalOptions: ParsableArguments {
  @Flag(
    name: .long,
    help: "Write one JSON document to stdout.",
  )
  var json = false

  @Flag(
    name: .long,
    help: "Leave out the hint line.",
  )
  var quiet = false

  @Option(
    name: .long,
    help: "The workspace root, instead of finding it.",
  )
  var workspace: String?
}
