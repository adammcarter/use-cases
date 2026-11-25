import Testing
@testable import UseCasesCLI

struct GuideCheckTests {
  private func findings(_ text: String) async throws -> GuideCheck.Findings {
    try await GuideCheck.current().findings(in: text)
  }

  @Test
  func `a command and a flag that do not exist are problems`() async throws {
    let found =
      try await findings("run `use-cases scan --everything`, or `use-cases status --gate`")

    #expect(found.problems == ["`use-cases scan` is not a command", "--everything is not a flag"])
    #expect(found.gaps.isEmpty)
  }

  @Test
  func `a flag of another command is a problem, even when some command has it`() async throws {
    let found = try await findings("`use-cases status --like`")

    #expect(found.problems == ["`use-cases status` has no --like"])
  }

  @Test
  func `flags and commands of this build are real`() async throws {
    let found = try await findings("""
    `use-cases search --like use-cases/x.yml --page-size 5` and `use-cases verify --start`, then
    `use-cases docs --next TOKEN`, and `use-cases apply --file F --approved-by Sam`.
    `use-cases approve --all --by Sam` too. `--exact` and `--json` work anywhere.
    """)

    #expect(found == GuideCheck.Findings())
  }

  @Test
  func `a bare double dash before a word that starts with a minus is no flag`() async throws {
    let found = try await findings(#"put `--` before it: `use-cases search -- "-zoom double"`"#)

    #expect(found == GuideCheck.Findings())
  }

  @Test
  func `git's own no-verify, named as git's, is real`() async throws {
    let found =
      try await findings("`git commit --no-verify` and `git push --no-verify` skip a hook once")

    #expect(found == GuideCheck.Findings())
  }

  @Test
  func `no-verify that is not git's, and a made-up flag on a git line, are still problems`()
    async throws
  {
    let found = try await findings("`use-cases hooks add commit --no-verify`, `git commit --bogus`")

    #expect(found.problems == [
      "`use-cases hooks` has no --no-verify", "--bogus is not a flag", "--no-verify is not a flag",
    ])
  }

  @Test
  func `a flag of the design that is not built is a gap, not a problem`() throws {
    let check = GuideCheck(
      builtFlags: ["status": ["--gate"]],
      designedFlags: ["--gate", "--future"],
      fileNames: [],
    )

    let found = try check.findings(in: "`--gate` and `--future`")

    #expect(found.problems.isEmpty)
    #expect(found.gaps == ["--future is not built yet"])
  }

  @Test
  func `prose that happens to say use-cases is not a command`() async throws {
    let found = try await findings("Every use-cases folder and every use cases file.")

    #expect(found == GuideCheck.Findings())
  }

  @Test
  func `a command in a fenced block is read as one in a code span`() async throws {
    let found = try await findings("```text\nuse-cases scan\nuse-cases search words\n```\n")

    #expect(found.problems == ["`use-cases scan` is not a command"])
  }

  @Test(arguments: [
    "`use-cases.yml`", "`use-case-groups.yml`", "`use-cases-bridge.yml`", "`use-cases/refunds.yml`",
    "`.use-cases/runs/x/results.jsonl`", "AGENTS.md",
  ])
  func `a file the tool reads, writes or has a person write is real`(text: String) async throws {
    #expect(try await findings(text) == GuideCheck.Findings())
  }

  @Test
  func `any other file is a problem, and a file of the design is a gap`() async throws {
    let found = try await findings("see `notes.yml`, `use-cases.yaml` and docs/phases.md.")

    #expect(found.problems == [
      "notes.yml is not a file the tool reads or writes",
      "use-cases.yaml is not a file the tool reads or writes",
    ])
    #expect(found.gaps == ["docs/phases.md is a file of the design, not of the tool"])
  }

  @Test(arguments: [
    (
      "run `use_cases_teleport` with `query` set to the draft",
      "`use_cases_teleport` is not a tool the server offers",
    ),
    (
      "| `use_cases_search` | `use-cases search` | `query`, `radius` |",
      "`use_cases_search` takes no `radius`",
    ),
    (
      "`use_cases_status` with `gate` true and `colour` red.",
      "`use_cases_status` takes no `colour`",
    ),
    (
      "The `use_cases_docs` tool takes `query` or `topic`.",
      "`use_cases_docs` takes no `topic`",
    ),
    (
      "Every tool also takes `workspace`.",
      "`use_cases_docs` does not take `workspace`, unlike the page says",
    ),
  ])
  func `a tool the server does not offer, or an argument a tool does not take, is a problem`(
    text: String,
    problem: String,
  ) async throws {
    #expect(try await findings(text).problems == [problem])
  }

  @Test
  func `the tools, their arguments and their values are read from the catalogue the server serves`(
  ) async throws {
    let found = try await findings("""
    | `use_cases_verify_tests` | `use-cases verify` | `step` (`run`, `start`), `only`, `run_id` |
    `use_cases_render` with `kind` `brief` and the proposal as `input`: the cards. Then
    `use_cases_render` returns `text`, and `use_cases_show` reads `approval` `approved`.
    Every tool but `use_cases_docs` takes `workspace`. A scope may set `use_cases_dir`.
    """)

    #expect(found == GuideCheck.Findings())
  }

  @Test
  func `the command tree is read from the real help of each command`() async throws {
    let check = try await GuideCheck.current()

    #expect(try check.findings(in: "`use-cases status --dry-run`").problems.count == 1)
    #expect(try check.findings(in: "`use-cases init --dry-run --hooks x`").problems.isEmpty)
    #expect(try check.findings(in: "`use-cases status --gate --strict --group g`").problems.isEmpty)
  }
}
