import ArgumentParser

/// The option every command that writes files you own takes (chapter 16 §17).
struct DryRunOptions: ParsableArguments {
  @Flag(
    name: .long,
    help: "Check the change and say what would be written, and write nothing.",
  )
  var dryRun = false
}
