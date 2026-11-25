import Foundation
import Testing
@testable import UseCasesCore

struct DiscoveryContextTests {
  private let rootDirectory = URL(fileURLWithPath: "/work/space")

  private func context(excludes: [String]) throws -> DiscoveryContext {
    try DiscoveryContext(
      rootDirectory: rootDirectory,
      builtInExcludes: [],
      configuredExcludes: excludes.map { text in
        try PathPattern(validating: text)
      },
    )
  }

  @Test(arguments: [
    (".", "/work/space"),
    ("a", "/work/space/a"),
    ("a/b.yml", "/work/space/a/b.yml"),
  ])
  func `a workspace path is found below the root folder`(
    path: String,
    expected: String,
  ) throws {
    let located = try context(excludes: []).url(for: .at(path))

    #expect(located.path == expected)
  }

  @Test(
    arguments: [
      ("build/**", "build", true),
      ("build/**", "build/x/y", true),
      ("build", "build/x", true),
      ("**/vendor", "a/vendor/x", true),
      ("build", "builds", false),
      ("build/out", "build", false),
      ("*.yml", "a.yml", true),
      ("*.yml", "sub/a.yml", false),
    ],
  )
  func `a path is excluded when a pattern matches it or a folder above it`(
    pattern: String,
    path: String,
    expected: Bool,
  ) throws {
    let excluded = try context(excludes: [pattern]).isExcluded(.at(path))

    #expect(excluded == expected)
  }

  @Test
  func `with no patterns nothing is excluded`() throws {
    #expect(try !context(excludes: []).isExcluded(.at(".git")))
  }

  @Test
  func `the pattern that covers a path is named, and the built-in ones are told apart`() throws {
    let context = try DiscoveryContext(
      rootDirectory: rootDirectory,
      builtInExcludes: [PathPattern(validating: "**/.git/**")],
      configuredExcludes: [PathPattern(validating: "build/**"), PathPattern(validating: ".git")],
    )

    #expect(
      try context.exclusion(covering: .at("a/.git/x"))
        == ExclusionMatch(pattern: "**/.git/**", isBuiltIn: true),
    )
    #expect(
      try context.exclusion(covering: .at("build/out"))
        == ExclusionMatch(pattern: "build/**", isBuiltIn: false),
    )
    #expect(try context.exclusion(covering: .at("src")) == nil)
  }

  @Test
  func `a match names the pattern in the words of its source`() {
    #expect(
      ExclusionMatch(pattern: "build/**", isBuiltIn: false)
        .subject == "discovery.exclude 'build/**'",
    )
    #expect(
      ExclusionMatch(pattern: "**/.git/**", isBuiltIn: true).subject
        == "the built-in exclusion '**/.git/**'",
    )
  }
}
