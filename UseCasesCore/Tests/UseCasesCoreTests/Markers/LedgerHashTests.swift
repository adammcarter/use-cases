import Testing
@testable import UseCasesCore

/// The hashes written into proof events: the binding-set hash, the policy
/// hashes and the row hash. A different byte here silently invalidates every
/// proof already in a ledger, so each is pinned to what the TypeScript wrote.
struct LedgerHashTests {
  private func members(_ entry: JSONValue) throws -> [BindingSetMember] {
    let items = try #require(MarkersLedgerFixtures.parsed(entry, "bindings_text").arrayValue)
    return try items.map { item in
      try #require(BindingSetMember(json: item))
    }
  }

  @Test(arguments: MarkersLedgerGoldenCorpus.bindingSetHashCaseNames)
  func `the binding-set hash is the TypeScript's, byte for byte`(caseName: String) throws {
    let entry = try MarkersLedgerFixtures.entry(caseName, in: "binding_set_hash")
    let rowIdentifier = try MarkersLedgerFixtures.string(entry, "row_id")
    let bindings = try members(entry)

    let material = BindingSetHash.material(rowIdentifier: rowIdentifier, bindings: bindings)

    #expect(try CodeUnitCanonicalJSON.encode(material)
      == MarkersLedgerFixtures.string(entry, "material"))
    #expect(try BindingSetHash.compute(rowIdentifier: rowIdentifier, bindings: bindings)
      == MarkersLedgerFixtures.string(entry, "hash"))
  }

  @Test
  func `a binding item missing a hashed field is not a member`() {
    let item = JSONValue.object(JSONObject([("binding_slug", .string("a.b"))]))

    #expect(BindingSetMember(json: item) == nil)
    #expect(BindingSetMember(json: .string("a.b")) == nil)
  }

  @Test(arguments: MarkersLedgerGoldenCorpus.policyHashCaseNames)
  func `the policy hashes are the TypeScript's, byte for byte`(caseName: String) throws {
    let entry = try MarkersLedgerFixtures.entry(caseName, in: "policy_hash")
    let policy = try MarkersLedgerFixtures.parsed(entry, "text")

    #expect(try PolicyHash.compute(policy) == MarkersLedgerFixtures.string(entry, "policy_hash"))
    #expect(try PolicyHash.verificationPolicyHash(policy)
      == MarkersLedgerFixtures.string(entry, "verification_policy_hash"))
    #expect(try PolicyHash.approvalPolicyHash(policy)
      == MarkersLedgerFixtures.string(entry, "approval_policy_hash"))
  }

  /// The row hash reuses the SEMANTIC hash — locale-collated key order — not
  /// the code-unit canonical JSON every other marker hash uses.
  @Test
  func `the row hash is the TypeScript's, byte for byte`() throws {
    for entry in try MarkersLedgerFixtures.section("row_hash") {
      let row = try MarkersLedgerFixtures.parsed(entry, "text")

      #expect(
        try RowHash.compute(row) == MarkersLedgerFixtures.string(entry, "row_hash"),
        "\(entry["name"]?.stringValue ?? "")",
      )
    }
  }

  @Test
  func `a non-finite number has no policy hash`() {
    let policy = JSONValue.object(JSONObject([("limit", .number(.infinity))]))

    #expect(throws: CodeUnitCanonicalJSONError.nonFiniteNumber) {
      try PolicyHash.compute(policy)
    }
  }

  @Test
  func `the ledger entry hash over every parsed line is the TypeScript's`() throws {
    for entry in try MarkersLedgerFixtures.section("evidence_ledger") {
      let text = try MarkersLedgerFixtures.string(entry, "text")
      let lines = EvidenceLedger.read(text).lines
      let expected = try #require(entry["entry_hashes"]?.arrayValue)

      #expect(lines.count == expected.count)
      for (line, hash) in zip(lines, expected) {
        if let message = hash["throws"]?.stringValue {
          #expect(throws: CodeUnitCanonicalJSONError.nonFiniteNumber) {
            try EvidenceLedgerChain.entryHash(line.value)
          }
          #expect(message == CodeUnitCanonicalJSONError.nonFiniteNumber.message)
        } else {
          #expect(try EvidenceLedgerChain.entryHash(line.value) == hash["value"]?.stringValue)
        }
      }
    }
  }

  @Test
  func `the genesis entry hash is sixty four zeros`() throws {
    #expect(try EvidenceLedgerChain.genesisEntryHash
      == MarkersLedgerFixtures.root()["genesis_entry_hash"]?.stringValue)
  }
}
