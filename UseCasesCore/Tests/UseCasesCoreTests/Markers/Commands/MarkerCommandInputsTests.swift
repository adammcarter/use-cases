import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// The command cores' shared inputs (shared.ts): the source walk, the marker
/// rows, and the path and key helpers.
struct MarkerCommandInputsTests {
  private typealias Fixtures = MarkerCommandsFixtures

  @Test(arguments: MarkerCommandsGoldenCorpus.collectCaseNames)
  func `the product source walk keeps and skips what the TypeScript's does`(
    caseName: String,
  ) throws {
    let entry = try Fixtures.entry(caseName, in: "collect_source_inputs")
    let (directory, root) = try Fixtures.temporaryRoot()
    let entries = try #require(entry["entries"]?.arrayValue)
    defer {
      Fixtures.restorePermissions(entries, under: root)
      _ = directory
    }
    try Fixtures.materialize(entries, under: root)
    let options = try #require(entry["options"])
    let skipPaths = (options["skip_paths"]?.arrayValue ?? []).compactMap(\.stringValue)
      .map { root + "/" + $0 }

    let actual: JSONValue
    do throws(FileAccessError) {
      let inputs = try MarkerCommandInputs.collectSourceInputs(
        productRoot: root + "/workspace",
        files: LocalTextFiles(),
        configuration: MarkersFixtures.configuration(options),
        skipPaths: skipPaths,
      )
      actual = .object(JSONObject([("inputs", .array(inputs.map { input in
        .object(JSONObject([
          ("file_path", .string(input.filePath)),
          ("contents", .string(input.contents)),
        ]))
      }))]))
    } catch {
      actual = .object(JSONObject([("throws", .string(error.code))]))
    }

    #expect(Fixtures.wire(actual) == Fixtures.wire(entry["result"]))
  }

  @Test
  func `marker rows are the matrix's use cases with a row id and both policies`() throws {
    let entry = try Fixtures.entry("two_rows_one_family", in: "load_marker_rows")
    let (directory, root) = try Fixtures.temporaryRoot()
    try Fixtures.materialize(#require(entry["entries"]?.arrayValue), under: root)
    let registry = try Fixtures.registry.get()
    let context = try WorkspaceContextResolver.resolve(
      options: ResolveWorkspaceContextOptions(workspaceRoot: root + "/workspace"),
      registry: registry,
    )

    let loaded = try MarkerCommandInputs.loadMarkerRows(context: context, registry: registry)

    let rows = loaded.rows.map { row in
      JSONValue.object(row.fields)
    }
    #expect(Fixtures.wire(.array(rows)) == Fixtures.wire(entry["rows"]))
    #expect(try loaded.rowIdentifiers == Set(MarkersFixtures.strings(entry, "row_ids")))
    let variants = loaded.rows.map { row in
      JSONValue.array(MarkerCommandInputs.rowVariants(row))
    }
    #expect(Fixtures.wire(.array(variants)) == Fixtures.wire(entry["variants"]))
    #expect(MarkerCommandInputs.findRow(loaded.rows, rowIdentifier: "checkout.apply_coupon")?
      .rowIdentifier == "checkout.apply_coupon")
    #expect(MarkerCommandInputs.findRow(loaded.rows, rowIdentifier: "checkout.missing") == nil)
    _ = directory
  }

  @Test
  func `a row id is found only by its exact code units`() throws {
    let policies: [(String, JSONValue)] = [
      ("verification_policy", .null),
      ("approval_policy", .null),
    ]
    let composed = try #require(FreshnessInputRow(fields: JSONObject([(
      "row_id",
      .string("caf\u{E9}")
    )] + policies)))

    #expect(MarkerCommandInputs.findRow([composed], rowIdentifier: "caf\u{E9}") != nil)
    #expect(MarkerCommandInputs.findRow([composed], rowIdentifier: "cafe\u{301}") == nil)
  }

  @Test
  func `paths are made posix and resolved under a root as node does`() throws {
    let paths = try #require(Fixtures.root()["paths"])
    for entry in try #require(paths["to_posix"]?.arrayValue) {
      #expect(try MarkerCommandInputs
        .toPosix(#require(entry["input"]?.stringValue)) == entry["output"]?.stringValue)
    }
    for entry in try #require(paths["resolve_under_root"]?.arrayValue) {
      #expect(try MarkerCommandInputs.resolveUnderRoot(
        #require(entry["root"]?.stringValue),
        #require(entry["value"]?.stringValue),
      ) == entry["output"]?.stringValue)
    }
  }

  @Test
  func `a single trusted key resolves any key id unless one is pinned`() {
    let open = MarkerCommandInputs.singleKeyResolver(publicKey: "PEM")
    let pinned = MarkerCommandInputs.singleKeyResolver(publicKey: "PEM", keyIdentifier: "caf\u{E9}")

    #expect(open("anything", nil) == "PEM")
    #expect(pinned("caf\u{E9}", nil) == "PEM")
    #expect(pinned("cafe\u{301}", nil) == nil)
    #expect(pinned("other", "2026-01-01T00:00:00.000Z") == nil)
  }

  @Test
  func `a row's registered bindings are its scanned bindings the registry knows`() {
    let token = "//: @use-" + "case:"
    let source = [
      token + "shop.pay", "func pay() {}", "",
      token + "shop.pay#second", "func second() {}", "",
      token + "shop.refund", "func refund() {}", "",
    ].joined(separator: "\n")
    let bindings = MarkerScanner.scanFile(filePath: "Shop.swift", contents: source).bindings

    let registered = MarkerCommandInputs.registeredBindingsForRow(
      bindings,
      rowIdentifier: "shop.pay",
      registeredSlugs: ["shop.pay#second", "shop.refund"],
    )

    #expect(bindings.count == 3)
    #expect(registered.map(\.bindingSlug) == ["shop.pay#second"])
  }
}
