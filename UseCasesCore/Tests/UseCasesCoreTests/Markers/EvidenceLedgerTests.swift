import Testing
@testable import UseCasesCore

/// The signed evidence ledger (evidenceLedger.ts): per-event rules, the whole
/// ledger with append-only discipline, and the tamper-evident hash chain.
struct EvidenceLedgerTests {
  private func validation(
    _ entry: JSONValue,
  ) throws -> Result<EvidenceLedgerValidation, EvidenceLedgerError> {
    let text = try MarkersLedgerFixtures.string(entry, "text")
    let resolver = try MarkersLedgerFixtures.resolver(#require(entry["resolver"]))
    let rows = entry["rows"]?.arrayValue.map { values in
      Set(values.compactMap(\.stringValue))
    }
    let base = entry["base"]?.stringValue
    do throws(EvidenceLedgerError) {
      return try .success(EvidenceLedger.validate(
        text: text,
        publicKeyResolver: resolver,
        baseReferenceOldText: base,
        yamlRowIdentifiers: rows,
      ))
    } catch {
      return .failure(error)
    }
  }

  @Test(arguments: MarkersLedgerGoldenCorpus.evidenceLedgerCaseNames)
  func `a ledger validates exactly as the TypeScript's did`(caseName: String) throws {
    let entry = try MarkersLedgerFixtures.entry(caseName, in: "evidence_ledger")
    let outcome = try #require(entry["outcome"])

    switch try validation(entry) {
    case let .failure(error):
      #expect(outcome["throws"]?.stringValue == error.message)
    case let .success(result):
      let expected = try #require(outcome["value"], "the TypeScript threw instead")
      #expect(.bool(result.isValid) == expected["ok"])
      #expect(try LedgerComparison.wire(.array(result.errors.map(\.jsonValue)))
        == LedgerComparison.wire(#require(expected["errors"])))
      #expect(result.events.map { $0["event_id"] ?? .null } == expected["event_ids"]?.arrayValue)
      #expect(.bool(result.appendOnly) == expected["append_only"])
      #expect(try MarkersLedgerFixtures.wire(result.summary.jsonValue)
        == MarkersLedgerFixtures.wire(#require(expected["summary"])))
      #expect(.bool(EvidenceLedger.errorsAreKeyResolutionOnly(result.errors))
        == expected["key_resolution_only"])
    }
  }

  /// The chain is asserted in full for every ledger: `verified_entries` and the
  /// errors are what tell a code-unit entry hash from a merged-key one.
  @Test(arguments: MarkersLedgerGoldenCorpus.evidenceLedgerCaseNames)
  func `the hash chain verifies exactly as the TypeScript's did`(caseName: String) throws {
    let entry = try MarkersLedgerFixtures.entry(caseName, in: "evidence_ledger")
    let lines = try EvidenceLedger.read(MarkersLedgerFixtures.string(entry, "text")).lines
    let chain = try #require(entry["chain"])

    let result: Result<LedgerChainResult, CodeUnitCanonicalJSONError>
    do throws(CodeUnitCanonicalJSONError) {
      result = try .success(EvidenceLedgerChain.verify(lines))
    } catch {
      result = .failure(error)
    }

    switch result {
    case let .failure(error):
      #expect(chain["throws"]?.stringValue == error.message)
    case let .success(verified):
      #expect(try MarkersLedgerFixtures.wire(verified.jsonValue)
        == MarkersLedgerFixtures.wire(#require(chain["value"])))
    }
  }

  @Test
  func `canonically equivalent keys keep a chained ledger intact`() throws {
    let entry = try MarkersLedgerFixtures.entry(
      "chain_entry_hash_over_equivalent_keys",
      in: "evidence_ledger",
    )
    let lines = try EvidenceLedger.read(MarkersLedgerFixtures.string(entry, "text")).lines

    let result = try EvidenceLedgerChain.verify(lines)

    #expect(result.verifiedEntries == 2)
    #expect(result.errors.isEmpty)
  }

  @Test
  func `the evidence and chain error codes are frozen`() {
    #expect(EvidenceErrorCode.allCases.map(\.rawValue) == [
      "JSON_PARSE_ERROR",
      "EVIDENCE_SCHEMA_INVALID",
      "SIGNATURE_MISSING",
      "SIGNATURE_ALG_UNSUPPORTED",
      "UNKNOWN_KEY_ID",
      "BAD_SIGNATURE",
      "PRODUCER_NOT_TRUSTED",
      "VERIFICATION_NOT_PASS",
      "BINDING_SET_HASH_MISMATCH",
      "EVIDENCE_ROW_MISSING",
      "APPEND_ONLY_VIOLATION",
    ])
    #expect(LedgerChainErrorCode.allCases.map(\.rawValue) == [
      "UCM_LEDGER_CHAIN_BROKEN",
      "UCM_LEDGER_INDEX_GAP",
      "UCM_LEDGER_DUPLICATE_INDEX",
    ])
    #expect(EvidenceLedger.trustedProducerKind == "trusted-ci-prover")
    #expect(EvidenceLedger.passResult == "pass")
  }

  @Test
  func `only a missing key is a key-resolution-only failure`() {
    let error = { (code: EvidenceErrorCode) in
      EvidenceError(code: code, line: 1, message: "m")
    }

    #expect(EvidenceLedger.errorsAreKeyResolutionOnly([]))
    #expect(EvidenceLedger.errorsAreKeyResolutionOnly([
      error(.signatureMissing),
      error(.unknownKeyIdentifier),
    ]))
    #expect(EvidenceLedger.errorsAreKeyResolutionOnly([
      error(.unknownKeyIdentifier),
      error(.badSignature),
    ]) == false)
  }

  @Test
  func `a single event reports its own errors and is returned only when valid`() throws {
    let entry = try MarkersLedgerFixtures.entry("one_valid_event", in: "evidence_ledger")
    let text = try MarkersLedgerFixtures.string(entry, "text")
    let value = try #require(EvidenceLedger.read(text).lines.first?.value)
    let pem = try MarkersLedgerFixtures.pem("primary", "public_pem")

    let valid = try EvidenceLedger.validateEvent(value, line: 7, publicKeyResolver: { _, _ in pem })
    let unknown = try EvidenceLedger.validateEvent(
      value,
      line: nil,
      publicKeyResolver: { _, _ in nil },
    )

    #expect(valid.isValid)
    #expect(valid.event == value)
    #expect(unknown.event == nil)
    #expect(unknown.errors.map(\.code) == [.unknownKeyIdentifier])
    #expect(unknown.errors.first?.line == nil)
  }
}
