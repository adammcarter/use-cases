import Testing

struct RecipeCommandsTests {
  private func commands(_ text: String) throws -> [[String]] {
    try RecipeCommands.arguments(in: text)
  }

  @Test
  func `a command ends at a pipe, a semicolon, an ampersand or the end of the line`() throws {
    #expect(try commands("- run: use-cases verify --run") == [["verify", "--run"]])
    #expect(
      try commands("use-cases verify --start --json | jq -r '.run_id'") == [
        ["verify", "--start", "--json"],
      ],
    )
    #expect(
      try commands("use-cases verify --run; use-cases status --gate && echo done") == [
        ["verify", "--run"],
        ["status", "--gate"],
      ],
    )
  }

  @Test
  func `words are split as a shell splits them, so a flag after a comma or a quote is read`()
    throws
  {
    #expect(
      try commands("use-cases verify --only unit,ui --bogus") == [
        ["verify", "--only", "unit,ui", "--bogus"],
      ],
    )
    #expect(
      try commands(#"use-cases record shop.pay.card check pass "checked on staging" --bogus"#)
        == [["record", "shop.pay.card", "check", "pass", "checked on staging", "--bogus"]],
    )
  }

  @Test
  func `a command inside a command substitution ends before the pipe or the parenthesis`()
    throws
  {
    #expect(
      try commands(
        #"echo "report=$(use-cases verify --start --json | jq -r '.reports["unit-tests"]')" >> x"#,
      ) == [["verify", "--start", "--json"]],
    )
    #expect(try commands("RUN=$(use-cases verify --start)") == [["verify", "--start"]])
  }

  @Test
  func `variables and placeholders stand for one word`() throws {
    #expect(
      try commands(
        #"use-cases verify --finish --run-id "$RUN_ID" <run id> ${{ needs.start.outputs.run_id }}"#,
      ) == [["verify", "--finish", "--run-id", "x", "x", "x"]],
    )
  }

  @Test
  func `prose around a command in a text block or a code span is not part of it`() throws {
    #expect(
      try commands("```text\nuse-cases verify --run        run the tests\n```\n")
        == [["verify", "--run"]],
    )
    #expect(
      try commands(
        "```text\nthen use-cases verify --finish --run-id <run id>, then use-cases status\n```",
      )
        == [["verify", "--finish", "--run-id", "x"], ["status"]],
    )
    #expect(
      try commands("See `use-cases status --gate` for the gate.") == [["status", "--gate"]],
    )
  }

  @Test
  func `a name that only begins with the program's name is not a command`() throws {
    #expect(try commands("use-cases-bridge.yml and .use-cases/runs and use-cases.yml").isEmpty)
    #expect(try commands("use-cases verifying things").isEmpty)
  }
}
