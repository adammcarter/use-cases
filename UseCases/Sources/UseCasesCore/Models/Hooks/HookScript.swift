/// The script of one hook, written for one workspace (chapter 18 §3), and how Use Cases knows a
/// hook file is its own.
///
/// The script runs `use-cases` when the PATH has it; otherwise the `use-cases` that added the
/// hook, whose full path the script remembers; otherwise it stops the commit or push and says
/// why. A hook never passes without checking.
struct HookScript: Equatable {
  let hook: HookName

  /// The workspace root relative to the top of the git work tree, where git runs hooks.
  let workspace: String

  /// The workspace as a command line takes it. A folder that starts with `-` would be read as an
  /// option, so it is written from the current folder.
  private var argument: String {
    workspace.hasPrefix("-") ? "./" + workspace : workspace
  }

  /// The script, remembering `program` as the `use-cases` that added it.
  func text(program: String) -> String {
    let word = ShellWord.quoting(program)

    return parts.beforeProgram + word + parts.betweenPrograms + word + parts.afterPrograms
  }

  /// The one line that runs the check, to add to a hook that is not ours.
  var line: String {
    "use-cases --workspace \(ShellWord.doubleQuoting(argument)) \(hook.arguments)"
  }

  /// Whether `text` is exactly the script this workspace's hook is, whichever `use-cases` added
  /// it: only the path it remembers may differ, and it is the same in both places.
  func isOurs(_ text: String) -> Bool {
    let before = parts.beforeProgram.unicodeScalars
    let between = parts.betweenPrograms.unicodeScalars
    let scalars = text.unicodeScalars[...]

    guard
      scalars.starts(with: before),
      let first = ShellWord.reading(scalars.dropFirst(before.count)),
      first.rest.starts(with: between),
      let second = ShellWord.reading(first.rest.dropFirst(between.count))
    else {
      return false
    }

    return first.word.isExactlyEqual(to: second.word)
      && second.rest.elementsEqual(parts.afterPrograms.unicodeScalars)
  }

  /// The script around the two places that hold the remembered path.
  private struct Parts {
    let beforeProgram: String
    let betweenPrograms: String
    let afterPrograms: String
  }

  private var parts: Parts {
    let name = hook.rawValue
    let flags = "--workspace \(ShellWord.doubleQuoting(argument)) \(hook.arguments)"

    let before = [
      "#!/bin/sh",
      "# Added by `use-cases hooks add \(name)`; `use-cases hooks remove \(name)` takes it out.",
      "# `git \(name) --no-verify` skips it once.",
      "if command -v use-cases >/dev/null 2>&1; then",
      "  exec use-cases \(flags)",
      "fi",
      "if [ -e ",
    ]

    let after = [
      " \(flags)",
      "fi",
      "echo \"use-cases isn't installed here, so this hook can't check your use cases.\" >&2",
      "echo \"Install it, re-run 'use-cases hooks add \(name)', or skip it once: "
        + "git \(name) --no-verify\" >&2",
      "exit 1",
      "",
    ]

    return Parts(
      beforeProgram: before.joined(separator: "\n"),
      betweenPrograms: " ]; then\n  exec ",
      afterPrograms: after.joined(separator: "\n"),
    )
  }
}
