/// The verification facts a proof carries. Both times are the result record's
/// `created_at` as it was — absent from the event when the record had none.
struct ProofVerification {
  let commandIdentifier: JSONValue
  let startedAt: JSONValue?
}

/// Every hash prove recomputes for a bound row — never taken from a result
/// record — in the TypeScript's order: row, both policies, the context hash
/// with the bindings, then the binding set.
struct RecomputedRow {
  let rowIdentifier: String
  let rowHash: String
  let verificationPolicyHash: String
  let approvalPolicyHash: String
  let inputs: BoundRowInputs
  let bindingSetHash: String

  init(
    _ target: TargetRow,
    prepared: ScanPreparation,
    context: ResolvedWorkspaceContext,
    contextRoot: String,
    files: some MarkerFileSystem,
  ) throws(MarkerCommandError) {
    rowIdentifier = target.status.rowIdentifier
    rowHash = RowHash.compute(.object(target.loaded.fields))
    do throws(CodeUnitCanonicalJSONError) {
      verificationPolicyHash = try PolicyHash
        .verificationPolicyHash(target.loaded.verificationPolicy)
      approvalPolicyHash = try PolicyHash.approvalPolicyHash(target.loaded.approvalPolicy)
    } catch {
      throw .canonicalJSON(error)
    }
    inputs = try BoundRowInputs(
      target,
      prepared: prepared,
      context: context,
      contextRoot: contextRoot,
      files: files,
    )
    bindingSetHash = try inputs.bindingSetHash(rowIdentifier)
  }

  var hashes: (rowHash: String, bindingSetHash: String) {
    (rowHash, bindingSetHash)
  }
}

/// Everything one proof event is built from.
struct ProofEventContents {
  let eventIdentifier: String
  let createdAt: String
  let row: RecomputedRow
  let verification: ProofVerification
  let producer: ProveProducer?
  let authority: JSONValue?
}

/// Build, chain, sign and append one proof event (`buildProofEvent`,
/// `readLedgerTail`, `signEvent`, `appendJsonlLine`).
enum ProofEventAppend {
  /// The chain fields are read from the ledger as it is NOW, so each row of a
  /// sweep chains onto the one appended before it, and they are inside the
  /// event before signing, so the signature covers them. The append is the
  /// read-modify-rewrite of ``MarkerCommandFiles/appendJSONLine(_:toPath:files:)``.
  static func append(
    _ contents: ProofEventContents,
    evidencePath: String,
    signingKey: ProveSigningKey,
    files: some MarkerFileSystem,
  ) throws(MarkerCommandError) {
    let ledger: String
    do throws(FileAccessError) {
      ledger = try files.readText(atPath: evidencePath) ?? ""
    } catch {
      throw .fileAccess(error)
    }
    let lines = EvidenceLedger.read(ledger).lines
    var previousEntryHash = EvidenceLedgerChain.genesisEntryHash
    if let last = lines.last {
      do throws(CodeUnitCanonicalJSONError) {
        previousEntryHash = try EvidenceLedgerChain.entryHash(last.value)
      } catch {
        throw .canonicalJSON(error)
      }
    }
    let unsigned = event(contents, entryIndex: lines.count, previousEntryHash: previousEntryHash)
    let signed: JSONObject
    do throws(ProofSignatureError) {
      signed = try ProofSignature.sign(
        unsigned,
        privateKeyPEM: signingKey.privateKeyPEM,
        keyIdentifier: signingKey.keyIdentifier,
      )
    } catch {
      throw .proofSignature(error)
    }
    do throws(FileAccessError) {
      try MarkerCommandFiles.appendJSONLine(
        JSONWriter.encode(.object(signed)),
        toPath: evidencePath,
        files: files,
      )
    } catch {
      throw .fileAccess(error)
    }
  }

  /// The unsigned event in the TypeScript's key order. `producer.kind` is
  /// always the trusted constant; the authority is embedded only when truthy.
  static func event(
    _ contents: ProofEventContents,
    entryIndex: Int,
    previousEntryHash: String,
  ) -> JSONObject {
    var event = JSONObject([
      ("schema", .string(MarkerConstants.evidenceSchemaIdentifier)),
      ("event_type", .string("row_proof_passed")),
      ("event_id", .string(contents.eventIdentifier)),
      ("created_at", .string(contents.createdAt)),
      ("producer", producer(contents.producer)),
      ("row", .object(JSONObject([
        ("row_id", .string(contents.row.rowIdentifier)),
        ("row_hash_id", .string(MarkerConstants.rowHashIdentifier)),
        ("row_hash", .string(contents.row.rowHash)),
        ("verification_policy_hash", .string(contents.row.verificationPolicyHash)),
        ("approval_policy_hash", .string(contents.row.approvalPolicyHash)),
      ]))),
      ("bindings", .object(JSONObject([
        ("binding_set_hash_id", .string(MarkerConstants.bindingSetHashIdentifier)),
        ("binding_set_hash", .string(contents.row.bindingSetHash)),
        ("span_canon_id", .string(MarkerConstants.spanCanonicalizerIdentifier)),
        ("items", .array(contents.row.inputs.bindings.map(bindingItem))),
      ]))),
      ("verification", verification(contents)),
      ("entry_index", .number(Double(entryIndex))),
      ("previous_entry_hash", .string(previousEntryHash)),
    ])
    if JavaScriptValue.isTruthy(contents.authority) {
      event["authority"] = contents.authority
    }
    return event
  }

  private static func producer(_ supplied: ProveProducer?) -> JSONValue {
    .object(JSONObject([
      ("kind", .string(EvidenceLedger.trustedProducerKind)),
      ("id", .string(supplied?.identifier ?? "ci/use-cases-prover")),
      ("version", .string(supplied?.version ?? ProductVersion.version)),
      ("ci_run_id", .string(supplied?.runIdentifier ?? "local")),
      ("repo", .string(supplied?.repository ?? "unknown/unknown")),
      ("commit", .string(supplied?.commit ?? String(repeating: "0", count: 40))),
    ]))
  }

  private static func bindingItem(_ binding: CurrentBindingRecord) -> JSONValue {
    .object(JSONObject([
      ("binding_slug", .string(binding.bindingSlug)),
      ("row_id", .string(binding.rowIdentifier)),
      ("file_path", .string(binding.filePath)),
      ("extent_kind", .string(binding.extentKind.rawValue)),
      ("recognizer_id", .string(binding.recognizerIdentifier)),
      ("span_canon_id", .string(binding.spanCanonicalizerIdentifier)),
      ("span_sha256", .string(binding.span.sha256)),
      ("span_start_line", .number(Double(binding.span.startLine))),
      ("span_end_line", .number(Double(binding.span.endLine))),
    ]))
  }

  private static func verification(_ contents: ProofEventContents) -> JSONValue {
    var block = JSONObject([
      ("command_id", contents.verification.commandIdentifier),
      ("result", .string(EvidenceLedger.passResult)),
    ])
    block["started_at"] = contents.verification.startedAt
    block["completed_at"] = contents.verification.startedAt
    block["artifacts"] = .array([])
    block["context_hash_id"] = .string(VerificationContextHash.identifier)
    block["context_hash"] = .string(contents.row.inputs.contextHash)
    return .object(block)
  }
}
