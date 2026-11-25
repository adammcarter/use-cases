import Foundation
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesCLI

struct InitCommandWizardTests {
  private static let formQuestion = "Full setup, or minimal? [full] "
  private static let prefixQuestion = "Root prefix? (blank for none) "
  private static let hooksQuestion = "Add hooks? commit / push / both / none [none] "

  private let place: InitFolder

  init() throws {
    place = try InitFolder()
    try place.folder.write(".git/HEAD", "ref: refs/heads/main\n")
  }

  private func run(
    _ arguments: [String] = ["init"],
    answers: [String],
    clone: HookPlanner? = nil,
    cancellation: any CancellationScoping = ObservedCancellationScope(
      makeObserver: {
        MockCancellation.never
      },
    ),
  ) async -> (result: CommandResult, transcript: [String]) {
    let prompter = MockPrompter(answers: answers)

    let result = await place.run(
      arguments,
      isTerminal: true,
      prompter: prompter,
      hooks: clone ?? place.clone(),
      cancellation: cancellation,
    )

    return await (result, prompter.transcript)
  }

  private var outsideGit: HookPlanner {
    HookPlanner(git: MockGitInspector(failing: .notAGitRepository(folder: place.realPath)))
  }

  private func hook(_ event: String) -> URL {
    place.url.appendingPathComponent(".git/hooks/\(event)")
  }

  // MARK: - The answers decide

  @Test
  func `the answers decide the files, the prefix and the hooks`() async throws {
    let (result, transcript) = await run(answers: ["minimal", "shop", "both"])

    #expect(result.exitCode == 0)
    #expect(transcript == [Self.formQuestion, Self.prefixQuestion, Self.hooksQuestion])
    #expect(try place.snapshot().keys.sorted() == [
      ".git/HEAD", ".git/hooks/pre-commit", ".git/hooks/pre-push", ".gitignore", "use-cases.yml",
    ])
    #expect(try place.read("use-cases.yml").contains("\nprefix: shop\n"))
  }

  @Test
  func `blank answers are a full setup with no prefix and no hooks`() async throws {
    let (result, _) = await run(answers: ["", "", ""])

    #expect(result.exitCode == 0)
    #expect(try place.snapshot().keys.contains("use-cases/example.yml"))
    #expect(try !place.read("use-cases.yml").contains("\nprefix:"))
    #expect(!FileManager.default.fileExists(atPath: hook("pre-commit").path))
    #expect(!FileManager.default.fileExists(atPath: hook("pre-push").path))
  }

  @Test
  func `numbers and starts answer too`() async throws {
    let (result, _) = await run(answers: ["2", "", "p"])

    #expect(result.exitCode == 0)
    #expect(try place.snapshot().keys.sorted() == [
      ".git/HEAD", ".git/hooks/pre-push", ".gitignore", "use-cases.yml",
    ])
  }

  @Test
  func `a person at a terminal sees the same files and next step as a script`() async {
    let (result, _) = await run(answers: ["minimal", "", "commit"])

    #expect(
      result.outputLines == [
        "created  use-cases.yml",
        "added    .use-cases/ to .gitignore",
        "added    the commit hook (use-cases validate)",
        "→ use-cases status",
      ],
    )
  }

  // MARK: - Flags answer in advance

  @Test
  func `each flag answers its question, and only hooks is left`() async {
    let (result, transcript) = await run(
      ["init", "--minimal", "--prefix", "shop"],
      answers: [""],
    )

    #expect(result.exitCode == 0)
    #expect(transcript == [Self.hooksQuestion])
  }

  @Test
  func `hooks named by the flag leave the form and the prefix`() async {
    let (result, transcript) = await run(
      ["init", "--hooks", "commit"],
      answers: ["minimal", ""],
    )

    #expect(result.exitCode == 0)
    #expect(transcript == [Self.formQuestion, Self.prefixQuestion])
    #expect(FileManager.default.fileExists(atPath: hook("pre-commit").path))
  }

  @Test
  func `every flag given leaves nothing to ask`() async {
    let (result, transcript) = await run(
      ["init", "--minimal", "--prefix", "shop", "--hooks", "push"],
      answers: [],
    )

    #expect(result.exitCode == 0)
    #expect(transcript.isEmpty)
  }

  @Test
  func `an existing workspace is asked only about hooks`() async {
    _ = await place.run(["init", "--minimal", "--prefix", "shop"])

    let (result, transcript) = await run(answers: ["push"])

    #expect(result.exitCode == 0)
    #expect(transcript == [Self.hooksQuestion])
    #expect(FileManager.default.fileExists(atPath: hook("pre-push").path))
  }

  @Test
  func `hooks are asked about only inside a git repository`() async {
    let (result, transcript) = await run(
      answers: ["minimal", ""],
      clone: outsideGit,
    )

    #expect(result.exitCode == 0)
    #expect(transcript == [Self.formQuestion, Self.prefixQuestion])
  }

  @Test
  func `git that cannot be run asks no question about hooks and refuses nothing`() async {
    let (result, transcript) = await run(
      answers: ["minimal", ""],
      clone: HookPlanner(git: MockGitInspector(failing: .gitUnavailable(reason: "none"))),
    )

    #expect(result.exitCode == 0)
    #expect(transcript == [Self.formQuestion, Self.prefixQuestion])
  }

  // MARK: - Asking again

  @Test
  func `an answer that is not one is told and asked again`() async {
    let (result, transcript) = await run(answers: ["huge", "minimal", "", "x", "none"])

    #expect(result.exitCode == 0)
    #expect(transcript.count == 7)
    #expect(transcript[1] == "  pick a number, a word, or an unambiguous start of one")
    #expect(transcript[5] == "  pick a number, a word, or an unambiguous start of one")
  }

  @Test
  func `a prefix off the grammar is told why and asked again`() async throws {
    let (result, transcript) = await run(answers: ["full", "Shop", "shop", ""])

    #expect(result.exitCode == 0)
    #expect(transcript[2].contains("'Shop' is not a valid prefix"))
    #expect(transcript[3] == Self.prefixQuestion)
    #expect(try place.read("use-cases.yml").contains("\nprefix: shop\n"))
  }

  // MARK: - Refusals and the end of the input

  @Test
  func `every refusal comes before the first question`() async throws {
    _ = await place.run(["init", "--minimal"])
    try place.folder.write("services/pay/keep.txt", "x")
    let before = try place.snapshot()

    let (inside, insideTranscript) = await run(
      ["init", "--workspace", "services/pay"],
      answers: ["minimal", "", "both"],
    )
    let (different, differentTranscript) = await run(
      ["init", "--prefix", "other"],
      answers: ["both"],
    )
    let (badName, badNameTranscript) = await run(
      ["init", "--hooks", "merge"],
      answers: ["both"],
    )
    let (badPrefix, badPrefixTranscript) = await run(
      ["init", "--prefix", "Shop"],
      answers: ["both"],
    )

    #expect([inside, different, badName, badPrefix].map(\.exitCode) == [2, 2, 2, 2])
    #expect(insideTranscript.isEmpty)
    #expect(differentTranscript.isEmpty)
    #expect(badNameTranscript.isEmpty)
    #expect(badPrefixTranscript.isEmpty)
    #expect(try place.snapshot() == before)
  }

  @Test
  func `git that cannot be run is a refusal before the first question when hooks are named`()
    async throws
  {
    let (result, transcript) = await run(
      ["init", "--hooks", "commit"],
      answers: ["minimal", ""],
      clone: HookPlanner(git: MockGitInspector(failing: .gitUnavailable(reason: "none"))),
    )

    #expect(result.exitCode == 2)
    #expect(transcript.isEmpty)
    #expect(try place.snapshot().keys.sorted() == [".git/HEAD"])
  }

  @Test(arguments: [0, 1, 2, 3])
  func `the end of the input is exit 2 whenever it comes, and writes nothing`(
    answered: Int,
  ) async throws {
    let answers = Array(["minimal", "shop", "both"].prefix(answered))

    let (result, _) = await run(answers: answers)

    #expect(result.exitCode == (answered == 3 ? 0 : 2))

    if answered < 3 {
      #expect(result.standardError.contains("input ended"))
      #expect(result.standardOutput.isEmpty)
      #expect(try place.snapshot().keys.sorted() == [".git/HEAD"])
    }
  }

  // MARK: - Dry run and cancellation

  @Test
  func `a dry run asks, and writes nothing`() async throws {
    let before = try place.snapshot()

    let (result, transcript) = await run(
      ["init", "--dry-run"],
      answers: ["minimal", "", "both"],
    )

    #expect(result.exitCode == 0)
    #expect(transcript.count == 3)
    #expect(result.outputLines.last == "would add     the push hook (use-cases status --gate)")
    #expect(try place.snapshot() == before)
  }

  @Test
  func `a request cancelled while it was being asked writes nothing`() async throws {
    let (result, _) = await run(
      answers: ["minimal", "", "both"],
      cancellation: ObservedCancellationScope(
        makeObserver: {
          MockCancellation.always
        },
      ),
    )

    #expect(result.exitCode == 130)
    #expect(try place.snapshot().keys.sorted() == [".git/HEAD"])
  }
}
