import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// The keyless run attestation: an HMAC-SHA256 over a verification-result
/// record's canonical JSON, keyed by a secret that lives on the machine.
struct RunAttestationTests {
  @Test(arguments: MarkersLedgerGoldenCorpus.computeAttestationCaseNames)
  func `the attestation is node's HMAC, byte for byte`(caseName: String) throws {
    let entry = try MarkersLedgerFixtures.entry(caseName, in: "compute_attestation")
    let record = try #require(MarkersLedgerFixtures.parsed(entry, "record_text").objectValue)
    let key = try MarkersLedgerFixtures.string(entry, "key")

    #expect(try RunAttestation.compute(record: record, key: key)
      == MarkersLedgerFixtures.string(entry, "attestation"))
  }

  @Test(arguments: MarkersLedgerGoldenCorpus.verifyAttestationCaseNames)
  func `verification accepts and refuses what the TypeScript does`(caseName: String) throws {
    let entry = try MarkersLedgerFixtures.entry(caseName, in: "verify_attestation")
    let record = try #require(MarkersLedgerFixtures.parsed(entry, "record_text").objectValue)
    let key = entry["key"]?.stringValue

    #expect(try RunAttestation.verify(record: record, key: key) == entry["verified"]?.boolValue)
  }

  @Test
  func `the default key path is the TypeScript's for every environment`() throws {
    for entry in try MarkersLedgerFixtures.section("run_key_path") {
      var environment: [String: String] = [:]
      for pair in try #require(entry["environment"]?.objectValue).pairs {
        environment[pair.key] = pair.value.stringValue
      }

      #expect(
        try RunAttestation.defaultRunKeyPath(
          environment: environment,
          homeDirectory: MarkersLedgerFixtures.string(entry, "home_directory"),
        ) == MarkersLedgerFixtures.string(entry, "path"),
        "\(entry["name"]?.stringValue ?? "")",
      )
    }
  }

  @Test
  func `resolving mints a key on first use and reuses it after`() throws {
    let directory = try TemporaryDirectory()
    let keyPath = directory.url.appendingPathComponent("home/.use-cases/run-key").path
    let files = LocalTextFiles()

    let minted = try RunAttestation.resolveLocalRunKey(keyPath: keyPath, files: files)

    #expect(minted.utf8.count == 64)
    #expect(minted.allSatisfy { character in
      "0123456789abcdef".contains(character)
    })
    #expect(try String(contentsOfFile: keyPath, encoding: .utf8) == "\(minted)\n")
    #expect(try RunAttestation.resolveLocalRunKey(keyPath: keyPath, files: files) == minted)
    #expect(try RunAttestation.readLocalRunKey(keyPath: keyPath, files: files) == minted)
  }

  @Test(arguments: ["", "not a key\n", String(repeating: "A", count: 64)])
  func `a malformed key file is replaced, never raised`(contents: String) throws {
    let directory = try TemporaryDirectory()
    let keyFile = try directory.writeFile("run-key", contents: contents)
    let replacement = String(repeating: "c", count: 64)

    #expect(try RunAttestation
      .readLocalRunKey(keyPath: keyFile.path, files: LocalTextFiles()) == nil)
    let resolved = try RunAttestation.resolveLocalRunKey(
      keyPath: keyFile.path,
      files: LocalTextFiles(),
      mintKey: { replacement },
    )

    #expect(resolved == replacement)
    #expect(try String(contentsOf: keyFile, encoding: .utf8) == "\(replacement)\n")
  }

  @Test
  func `a key surrounded by whitespace is read trimmed`() throws {
    let directory = try TemporaryDirectory()
    let key = String(repeating: "ab", count: 32)
    let keyFile = try directory.writeFile("run-key", contents: "\u{FEFF} \(key)\n\u{2028}")

    #expect(try RunAttestation
      .readLocalRunKey(keyPath: keyFile.path, files: LocalTextFiles()) == key)
  }

  @Test
  func `reading never mints a key`() throws {
    let directory = try TemporaryDirectory()
    let keyPath = directory.url.appendingPathComponent("absent/run-key").path

    #expect(try RunAttestation.readLocalRunKey(keyPath: keyPath, files: LocalTextFiles()) == nil)
    #expect(FileManager.default.fileExists(atPath: keyPath) == false)
  }

  @Test
  func `a key path that cannot be read raises node's error`() throws {
    let directory = try TemporaryDirectory()

    let error = #expect(throws: FileAccessError.self) {
      try RunAttestation.readLocalRunKey(keyPath: directory.url.path, files: LocalTextFiles())
    }
    #expect(error?.code == "EISDIR")
    #expect(error?.message == "EISDIR: illegal operation on a directory, read")
  }

  /// The TypeScript reads before it writes, so a path beneath a FILE fails on
  /// the read (`open`), exactly as node's does.
  @Test
  func `a key path beneath a file raises node's read error`() throws {
    let directory = try TemporaryDirectory()
    let blocker = try directory.writeFile("blocker", contents: "")
    let keyPath = blocker.appendingPathComponent("sub/run-key").path

    let error = #expect(throws: FileAccessError.self) {
      try RunAttestation.resolveLocalRunKey(keyPath: keyPath, files: LocalTextFiles())
    }
    #expect(error?.code == "ENOTDIR")
    #expect(error?.message == "ENOTDIR: not a directory, open '\(keyPath)'")
  }

  @Test
  func `a key that cannot be written raises node's mkdir error`() throws {
    let directory = try TemporaryDirectory()
    let locked = try directory.makeDirectory("locked")
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
    }
    let keyPath = locked.appendingPathComponent("sub/run-key").path
    let nestedKeyPath = locked.appendingPathComponent("a/b/run-key").path

    let error = #expect(throws: FileAccessError.self) {
      try RunAttestation.resolveLocalRunKey(keyPath: keyPath, files: LocalTextFiles())
    }
    let nested = #expect(throws: FileAccessError.self) {
      try RunAttestation.resolveLocalRunKey(keyPath: nestedKeyPath, files: LocalTextFiles())
    }
    #expect(error?.code == "EACCES")
    #expect(error?.message == "EACCES: permission denied, mkdir '\(locked.path)/sub'")
    // node names the directory that was ASKED for, not the component that failed.
    #expect(nested?.message == "EACCES: permission denied, mkdir '\(locked.path)/a/b'")
  }

  @Test
  func `a rename onto a directory raises node's rename error`() throws {
    let directory = try TemporaryDirectory()
    let target = try directory.makeDirectory("occupied")
    try directory.writeFile("occupied/inside", contents: "")

    let error = #expect(throws: FileAccessError.self) {
      try LocalTextFiles().writeText("x", toPath: target.path)
    }
    let renamePrefix = "EISDIR: illegal operation on a directory, rename '\(target.path).tmp-"
    #expect(error?.code == "EISDIR")
    #expect(error?.message.hasPrefix(renamePrefix) == true)
    #expect(error?.message.hasSuffix("' -> '\(target.path)'") == true)
  }

  @Test
  func `writing replaces an existing file atomically and leaves no temp file behind`() throws {
    let directory = try TemporaryDirectory()
    let target = try directory.writeFile("dir/key", contents: "old")

    try LocalTextFiles().writeText("new\n", toPath: target.path)

    #expect(try String(contentsOf: target, encoding: .utf8) == "new\n")
    #expect(try FileManager.default
      .contentsOfDirectory(atPath: target.deletingLastPathComponent().path)
      == ["key"])
  }

  @Test
  func `a record with a non-finite number has no attestation`() {
    let record = JSONObject([("n", .number(.nan))])

    #expect(throws: CodeUnitCanonicalJSONError.nonFiniteNumber) {
      try RunAttestation.compute(record: record, key: String(repeating: "0", count: 64))
    }
  }
}
