import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

/// The commands that write hand what they planned to the write they are given, and answer what it
/// answers: nothing reaches the files.
struct CommandLineRunnerWriteTests {
  private let spy = SpyPlanCarrying()

  private func runner(
    in folder: URL,
    hooks: (any HookPlanning)? = nil,
  ) -> CommandLineRunner {
    CommandLineRunner(
      loader: WorkspaceLoader(),
      write: spy,
      hooks: hooks,
      program: ProgramPath(installedAt: "/opt/use-cases/bin/use-cases"),
      workingDirectory: folder,
    )
  }

  @Test
  func `save hands its files to the write, to confirm what it changed`() async throws {
    let workspace = try StatusWorkspace()
    try workspace.folder.write("sent.yml", "id: shop.pay.crypto\ntitle: Pay with crypto\n")

    let result = await runner(in: workspace.folder.url).run(
      arguments: ["save", "--file", "sent.yml"],
    )

    #expect(result.outputLines.first == "saved: shop.pay.crypto (added)")
    #expect(
      await spy.asked() == [
        .plan(paths: ["use-cases/pay.yml"], alongside: [], confirms: true, dryRun: false),
      ],
    )
  }

  @Test
  func `remove hands its files to the write, to confirm what it changed`() async throws {
    let workspace = try StatusWorkspace()

    _ = await runner(in: workspace.folder.url).run(arguments: ["remove", "shop.pay.gift"])

    #expect(
      await spy.asked() == [
        .plan(paths: ["use-cases/pay.yml"], alongside: [], confirms: true, dryRun: false),
      ],
    )
  }

  @Test
  func `approve hands its files to the write, to confirm what it changed`() async throws {
    let workspace = try StatusWorkspace()

    _ = await runner(in: workspace.folder.url).run(
      arguments: ["approve", "shop.pay.card", "--by", "Sam", "--dry-run"],
    )

    #expect(
      await spy.asked() == [
        .plan(paths: ["use-cases/pay.yml"], alongside: [], confirms: true, dryRun: true),
      ],
    )
  }

  @Test
  func `init hands its files and its hooks to the write`() async throws {
    let place = try InitFolder()
    try place.folder.write(".git/HEAD", "ref: refs/heads/main\n")

    _ = await runner(
      in: place.url,
      hooks: place.clone(),
    ).run(arguments: ["init", "--no-input", "--hooks", "commit"])

    #expect(
      await spy.asked() == [
        .plan(
          paths: [
            "use-cases.yml", "use-cases/example.yml", "use-case-groups.yml",
            "use-cases-bridge.yml", ".gitignore",
          ],
          alongside: [".git"],
          confirms: false,
          dryRun: false,
        ),
      ],
    )
  }

  @Test
  func `hooks hands its hook files to the write alone, under the workspace lock`() async throws {
    let place = try InitFolder()
    try place.folder.write("use-cases.yml", "schema_version: 1\nroot: true\n")
    try place.folder.write(".git/HEAD", "ref: refs/heads/main\n")

    _ = await runner(
      in: place.url,
      hooks: place.clone(),
    ).run(arguments: ["hooks", "add", "commit"])

    #expect(
      await spy.asked() == [
        .only(
          folders: [".git"],
          lockingIn: place.url.lastPathComponent,
          dryRun: false,
        ),
      ],
    )
  }
}
