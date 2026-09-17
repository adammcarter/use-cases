import Foundation

// Regenerates `Sources/UseCasesCore/Schema/EmbeddedSchemas.swift` from the 27
// frozen schema files in `schemas/v1`, and
// `Sources/UseCasesCore/Markers/EmbeddedMarkerSchemas.swift` from the three
// INTERNAL marker validator schemas in `packages/core/src/markers/schemas`.
//
//   swift UseCasesCore/Scripts/generate-embedded-schemas.swift
//
// Written in Swift rather than Python for one reason: the escaping it emits has
// to be Swift's, and a Swift script produces it under the same rules the
// compiler will read it back with.
//
// `EmbeddedSchemasTests` and `EmbeddedMarkerSchemasTests` assert the committed
// files still carry the exact bytes of every file on disk, so a schema edit
// without a regeneration fails the suite rather than shipping a stale copy
// (ADR 0007 decision 8).
//
// The marker schemas are NOT published: they never join `SchemaRegistry` or
// `schema list`, which stay the frozen 27. Their source lives under `packages/`,
// which the final ladder step deletes; at that point the generated file becomes
// the source of truth and the drift test's input has to move.
//
// This comment sits BELOW the import deliberately: swiftformat is configured
// with `--header strip`, which deletes a comment block that opens the file.

let scriptURL = URL(fileURLWithPath: #filePath)
let packageRoot = scriptURL
  .deletingLastPathComponent() // Scripts
  .deletingLastPathComponent() // UseCasesCore
let repositoryRoot = packageRoot.deletingLastPathComponent()
let schemasDirectory = repositoryRoot.appendingPathComponent("schemas/v1", isDirectory: true)
let targetURL = packageRoot
  .appendingPathComponent("Sources/UseCasesCore/Schema/EmbeddedSchemas.swift")
let markerSchemasDirectory = repositoryRoot
  .appendingPathComponent("packages/core/src/markers/schemas", isDirectory: true)
let markerTargetURL = packageRoot
  .appendingPathComponent("Sources/UseCasesCore/Markers/EmbeddedMarkerSchemas.swift")

/// One string literal the Swift compiler reads back as the exact bytes given.
func swiftStringLiteral(_ text: String) -> String {
  var literal = "\""
  for scalar in text.unicodeScalars {
    switch scalar {
    case "\\":
      literal += "\\\\"
    case "\"":
      literal += "\\\""
    case "\n":
      literal += "\\n"
    case "\r":
      literal += "\\r"
    case "\t":
      literal += "\\t"
    case "\0":
      literal += "\\0"
    default:
      if scalar.value < 0x20 || scalar.value == 0x7F {
        literal += String(format: "\\u{%02x}", scalar.value)
      } else {
        literal.unicodeScalars.append(scalar)
      }
    }
  }
  return literal + "\""
}

/// One dictionary entry per schema file in `directory`, sorted by name so the
/// output is deterministic. Read from the directory so the frozen order in
/// `SchemaRegistry` is never duplicated here: the test checks the key set.
func dictionaryEntries(in directory: URL) throws -> (entries: [String], count: Int) {
  let fileNames = try FileManager.default
    .contentsOfDirectory(atPath: directory.path)
    .filter { name in
      name.hasSuffix(".schema.json")
    }
    .sorted()
  var entries: [String] = []
  for fileName in fileNames {
    let contents = try String(
      contentsOf: directory.appendingPathComponent(fileName),
      encoding: .utf8,
    )
    entries.append(
      "    \(swiftStringLiteral(fileName)): \(swiftStringLiteral(contents)),",
    )
  }
  return (entries, fileNames.count)
}

let (entries, schemaCount) = try dictionaryEntries(in: schemasDirectory)
let (markerEntries, markerSchemaCount) = try dictionaryEntries(in: markerSchemasDirectory)

let source = """
// swiftlint:disable single_line_closure_body line_length
// A generated data file: each schema below is one string literal, and the
// regex-based lint rules read its contents as if they were code.
// Generated from `schemas/v1` — DO NOT EDIT BY HAND.
//
// ADR 0007 decision 3 ships ONE downloadable binary per platform, so the frozen
// schema files travel INSIDE it: a shipped binary runs inside a user's own
// project, where there is nothing above it to walk up to.
//
// Regenerate with `swift UseCasesCore/Scripts/generate-embedded-schemas.swift`.
// `EmbeddedSchemasTests` fails the suite when this file drifts from disk.
enum EmbeddedSchemas {
  /// Every published schema file, keyed by file name, byte for byte as it is
  /// committed under `schemas/v1`.
  static let byFileName: [String: String] = [
\(entries.joined(separator: "\n"))
  ]
}

// swiftlint:enable single_line_closure_body line_length

"""

let markerSource = """
// swiftlint:disable single_line_closure_body line_length
// A generated data file: each schema below is one string literal, and the
// regex-based lint rules read its contents as if they were code.
// Generated from `packages/core/src/markers/schemas` — DO NOT EDIT BY HAND.
//
// The INTERNAL marker validator schemas (binding registry events, proof events,
// freshness status). They are not published: they never appear in
// `SchemaRegistry` or `schema list`, whose 27 ids are frozen contract.
//
// Regenerate with `swift UseCasesCore/Scripts/generate-embedded-schemas.swift`.
// `EmbeddedMarkerSchemasTests` fails the suite when this file drifts from disk.
enum EmbeddedMarkerSchemas {
  /// Every marker schema file, keyed by file name, byte for byte as it is
  /// committed under `packages/core/src/markers/schemas`.
  static let byFileName: [String: String] = [
\(markerEntries.joined(separator: "\n"))
  ]
}

// swiftlint:enable single_line_closure_body line_length

"""

try source.write(to: targetURL, atomically: true, encoding: .utf8)
try markerSource.write(to: markerTargetURL, atomically: true, encoding: .utf8)
FileHandle.standardError.write(
  Data("Wrote \(targetURL.path) (\(schemaCount) schemas)\n".utf8),
)
FileHandle.standardError.write(
  Data("Wrote \(markerTargetURL.path) (\(markerSchemaCount) marker schemas)\n".utf8),
)
