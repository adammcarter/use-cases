import Testing
@testable import UseCasesCore

struct HookScriptTests {
  private static let program = "/opt/use-cases/bin/use-cases"

  /// The script of chapter 18 §3, byte for byte.
  private static let commitScript = """
  #!/bin/sh
  # Added by `use-cases hooks add commit`; `use-cases hooks remove commit` takes it out.
  # `git commit --no-verify` skips it once.
  if command -v use-cases >/dev/null 2>&1; then
    exec use-cases --workspace "." validate --quiet
  fi
  if [ -e /opt/use-cases/bin/use-cases ]; then
    exec /opt/use-cases/bin/use-cases --workspace "." validate --quiet
  fi
  echo "use-cases isn't installed here, so this hook can't check your use cases." >&2
  echo "Install it, re-run 'use-cases hooks add commit', or skip it once: \
  git commit --no-verify" >&2
  exit 1

  """

  /// The same script for the push moment: only the moment and the check differ.
  private static let pushScript = """
  #!/bin/sh
  # Added by `use-cases hooks add push`; `use-cases hooks remove push` takes it out.
  # `git push --no-verify` skips it once.
  if command -v use-cases >/dev/null 2>&1; then
    exec use-cases --workspace "." status --gate --quiet
  fi
  if [ -e /opt/use-cases/bin/use-cases ]; then
    exec /opt/use-cases/bin/use-cases --workspace "." status --gate --quiet
  fi
  echo "use-cases isn't installed here, so this hook can't check your use cases." >&2
  echo "Install it, re-run 'use-cases hooks add push', or skip it once: git push --no-verify" >&2
  exit 1

  """

  private static func script(
    _ hook: HookName,
    in workspace: String = ".",
  ) -> HookScript {
    HookScript(
      hook: hook,
      workspace: workspace,
    )
  }

  // MARK: - The bytes

  @Test
  func `the commit hook is the script of the chapter, byte for byte`() {
    #expect(
      Array(Self.script(.commit).text(program: Self.program).utf8) == Array(Self.commitScript.utf8),
    )
  }

  @Test
  func `the push hook checks the gate and tells push where the commit hook tells commit`() {
    #expect(
      Array(Self.script(.push).text(program: Self.program).utf8) == Array(Self.pushScript.utf8),
    )
  }

  @Test
  func `a workspace below the top of the work tree is named from the top`() {
    let text = Self.script(.commit, in: "services/pay").text(program: Self.program)

    #expect(text.contains("  exec use-cases --workspace \"services/pay\" validate --quiet\n"))
    #expect(text.contains("  exec /opt/use-cases/bin/use-cases --workspace \"services/pay\" "))
  }

  @Test
  func `a program with a space is quoted in both places`() {
    let text = Self.script(.commit).text(program: "/my tools/use-cases")

    #expect(text.contains("if [ -e '/my tools/use-cases' ]; then\n"))
    #expect(text.contains("  exec '/my tools/use-cases' --workspace"))
  }

  @Test
  func `the one line for a hook that is not ours runs the same check`() {
    #expect(Self.script(.commit).line == "use-cases --workspace \".\" validate --quiet")
    #expect(
      Self.script(.push, in: "a\"b")
        .line == "use-cases --workspace \"a\\\"b\" status --gate --quiet",
    )
  }

  // MARK: - A folder with an odd name

  @Test
  func `a folder that starts with a dash is written from the current folder`() {
    let text = Self.script(.commit, in: "-ws").text(program: Self.program)

    #expect(text.contains("  exec use-cases --workspace \"./-ws\" validate --quiet\n"))
    #expect(text.contains("  exec /opt/use-cases/bin/use-cases --workspace \"./-ws\" "))
    #expect(
      Self.script(.push, in: "-ws").line == "use-cases --workspace \"./-ws\" status --gate --quiet",
    )
  }

  @Test(arguments: ["a-ws", "services/-ws", "./x", "ws-"])
  func `only a name that starts with a dash is given a dot`(workspace: String) {
    #expect(Self.script(.commit, in: workspace).line.contains("--workspace \"\(workspace)\" "))
  }

  @Test
  func `the script of a folder that starts with a dash is still ours`() {
    let script = Self.script(.commit, in: "-ws")

    #expect(script.isOurs(script.text(program: Self.program)))
  }

  @Test(arguments: [
    ("`\u{301};touch PWNED;`\u{301}", "\\`\u{301};touch PWNED;\\`\u{301}"),
    ("$\u{301}(id)", "\\$\u{301}(id)"),
    ("a\"\u{301}b", "a\\\"\u{301}b"),
  ])
  func `a folder name with a mark after a backtick, dollar or quote cannot run anything`(
    name: String,
    escaped: String,
  ) {
    let script = Self.script(.commit, in: name)

    #expect(script.line == "use-cases --workspace \"\(escaped)\" validate --quiet")
    #expect(script.text(program: Self.program).contains("--workspace \"\(escaped)\" validate"))
  }

  @Test
  func `a program with a quote and a mark after it is remembered and is still ours`() {
    let script = Self.script(.commit)
    let text = script.text(program: "/it'\u{301}s/use-cases")

    #expect(text.contains("if [ -e '/it'\\''\u{301}s/use-cases' ]; then\n"))
    #expect(script.isOurs(text))
  }

  // MARK: - Ours

  @Test(arguments: HookName.allCases)
  func `a script is ours whichever program added it`(hook: HookName) {
    let script = Self.script(hook)

    for program in [
      Self.program,
      "/opt/other/use-cases",
      "/my tools/use-cases",
      "/it's/use-cases",
    ] {
      #expect(script.isOurs(script.text(program: program)))
    }
  }

  @Test
  func `a script quoted another way is still ours`() {
    let script = Self.script(.commit)
    let text = script.text(program: "/it's/use-cases")
      .replacingOccurrences(of: "'/it'\\''s/use-cases'", with: "'/it'\"'\"'s/use-cases'")

    #expect(script.isOurs(text))
  }

  @Test
  func `a script that remembers two different programs is not ours`() {
    let script = Self.script(.commit)
    let text = script.text(program: "/a/use-cases")
      .replacingOccurrences(of: "exec /a/use-cases", with: "exec /b/use-cases")

    #expect(!script.isOurs(text))
  }

  @Test(arguments: [
    ("validate --quiet", "validate"),
    ("fi\n", "fi\nfi\n"),
    ("exit 1\n", "exit 1\necho more\n"),
    ("exit 1\n", "exit 1"),
    ("#!/bin/sh\n", "#!/bin/bash\n"),
    ("--no-verify\" >&2", "--no-verify\" >&2 "),
  ])
  func `any other change makes the hook someone's own`(
    original: String,
    edited: String,
  ) {
    let script = Self.script(.commit)
    let text = script.text(program: Self.program)
      .replacingOccurrences(of: original, with: edited)

    #expect(text != script.text(program: Self.program))
    #expect(!script.isOurs(text))
  }

  @Test
  func `a hook for another workspace or another moment is not ours`() {
    let text = Self.script(.commit).text(program: Self.program)

    #expect(!Self.script(.commit, in: "services/pay").isOurs(text))
    #expect(!Self.script(.push).isOurs(text))
  }

  @Test(arguments: ["", "#!/bin/sh\n", "echo mine\n"])
  func `a file that is something else is not ours`(text: String) {
    #expect(!Self.script(.commit).isOurs(text))
  }
}
