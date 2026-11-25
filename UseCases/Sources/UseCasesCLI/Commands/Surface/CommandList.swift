/// What `use-cases` and `use-cases --help` print: the command list of chapter 16 §2 (§7).
enum CommandList {
  static let text = """
  use-cases: the behaviour your code promises, and the proof it keeps that promise.

  use-cases                                    same as use-cases --help
  use-cases --help | --version

  use-cases validate                           are the files right? runs no test, writes nothing
  use-cases status [<use case or prefix>]      every use case, worst first; one use case in detail
                   [--group G] [--state S,…]   filters
                   [--gate [--strict]]         does anything block?
  use-cases verify --start | --finish | --run | --abort    get verdicts from tests
                   [--only V,…] [--run-id ID]
  use-cases record <use case> <route> <status> [message] [--attach F…]
  use-cases record --interactive [--attach F…]  asks for each value
  use-cases links [<use case or prefix>]       which code each use case is tied to
  use-cases search [words] | --like F|-       find use cases, best match first, in pages
                   [--under P] [--group G] [--tier T,…] [--state S,…] [--in FIELDS]
                   [--exact] [--full] [--page-size N]   |   --next TOKEN
  use-cases show <use case>                    one use case, whole
  use-cases save --file F|- [--dry-run]        create or replace one use case, whole
  use-cases remove <use case> [--dry-run]      take one use case out
  use-cases apply --file F|- [--approved-by NAME] [--dry-run]
                                               a batch, all or nothing
  use-cases approve <use case>… | --all --by NAME [--dry-run]
                                               record a sign-off of each promise as it reads now
  use-cases init [--minimal] [--prefix P] [--hooks H] [--no-input] [--dry-run]
                                               set up a repository; asks, in a terminal
  use-cases hooks [add | remove commit|push] [--dry-run]
                                               opt-in git hooks for this clone
  use-cases prune [--dry-run]                  remove runs status no longer uses; a person's call
  use-cases render intent|brief|proposal|results --file F|-
                                               a canonical layout for the person
  use-cases docs [<guide> | words]             the guides that ship with this version
                 [--exact] [--page-size N]  |  --next TOKEN
  use-cases mcp                                the MCP server an agent's host starts

  every command:  --json   one JSON document on stdout
                  --quiet  no hint line
                  --workspace DIR   the workspace root, instead of finding it

  use-cases <command> --help                   the flags of one command
  """
}
