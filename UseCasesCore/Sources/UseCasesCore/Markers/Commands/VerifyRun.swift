/// One verify invocation's state after its targets are known: the records it
/// mints, the rows that overclaimed, and the spec errors it surfaced.
struct VerifyRun {
  let options: VerifyCommandOptions
  let prepared: ScanPreparation
  let contextRoot: String
  private(set) var results: [VerificationResultRecord] = []
  private(set) var overclaimedRows: [String] = []
  private(set) var errors: [MarkerCommandFailure] = []

  // MARK: - Dry run

  //: @use-case:lifecycle.signals.verify_can_be_previewed
  /// Resolve exactly what a real run would execute, and stop: nothing is
  /// spawned, written or minted, and a variant family that would block
  /// previews as blocked.
  mutating func plan(_ targets: [String]) -> VerifyCommandResult {
    var planned: [VerifyPlannedRow] = []
    for rowIdentifier in targets {
      guard let target = TargetRow(rowIdentifier, in: prepared) else {
        continue
      }
      guard target.status.status != .invalid else {
        planned.append(VerifyPlannedRow(
          rowIdentifier: rowIdentifier,
          verifierIdentifier: nil,
          command: nil,
          disposition: .invalid,
        ))
        continue
      }
      let keys = VerifyVariants.keys(target.loaded)
      let tokenMissing = familyTokenMissing(target, keys: keys)
      for unit in VerifyUnit.units(rowIdentifier, variantKeys: keys) {
        planned += planUnit(unit, target: target, tokenMissing: tokenMissing)
      }
    }
    return VerifyCommandResult(exitCode: 0, planned: planned, errors: errors)
  }

  //: @use-case:end lifecycle.signals.verify_can_be_previewed

  private func planUnit(
    _ unit: VerifyUnit,
    target: TargetRow,
    tokenMissing: Bool,
  ) -> [VerifyPlannedRow] {
    let resolutions = resolve(target, variantKey: unit.variantKey)
    let blocked = { (identifier: String?) in
      [VerifyPlannedRow(
        rowIdentifier: unit.recordRowIdentifier,
        verifierIdentifier: identifier,
        command: nil,
        disposition: .blocked,
      )]
    }
    guard !resolutions.isEmpty, let verifiers = VerifyVariants.resolved(resolutions) else {
      return blocked(VerifyVariants.blockedIdentifier(resolutions))
    }
    if tokenMissing, unit.variantKey != nil {
      return blocked(verifiers.first?.verifierIdentifier)
    }
    return verifiers.map { verifier in
      VerifyPlannedRow(
        rowIdentifier: unit.recordRowIdentifier,
        verifierIdentifier: verifier.verifierIdentifier,
        command: verifier.command,
        disposition: .run,
      )
    }
  }

  // MARK: - Real run

  //: @use-case:lifecycle.signals.variant_fanout
  mutating func verify(
    _ targets: [String],
    files: some MarkerFileSystem,
    spawnRunner: some VerifySpawnRunning,
  ) throws(MarkerCommandError) {
    for rowIdentifier in targets {
      guard let target = TargetRow(rowIdentifier, in: prepared) else {
        continue
      }
      let inputs = try BoundRowInputs(
        target,
        prepared: prepared,
        context: options.context,
        contextRoot: contextRoot,
        files: files,
      )
      let keys = VerifyVariants.keys(target.loaded)
      let tokenMissing = target.status.status != .invalid && familyTokenMissing(target, keys: keys)
      for unit in VerifyUnit.units(rowIdentifier, variantKeys: keys) {
        let base = try UnitBase(
          unit,
          target: target,
          inputs: inputs,
          createdAt: options.generatedAt,
        )
        try results.append(verifyUnit(
          unit,
          base: base,
          target: target,
          tokenMissing: tokenMissing,
          spawnRunner: spawnRunner,
        ))
      }
    }
  }

  //: @use-case:end lifecycle.signals.variant_fanout

  private mutating func verifyUnit(
    _ unit: VerifyUnit,
    base: UnitBase,
    target: TargetRow,
    tokenMissing: Bool,
    spawnRunner: some VerifySpawnRunning,
  ) throws(MarkerCommandError) -> VerificationResultRecord {
    guard target.status.status != .invalid else {
      return base.unrun(.fail, verifierIdentifier: nil)
    }
    let resolutions = resolve(target, variantKey: unit.variantKey)
    guard !resolutions.isEmpty, let verifiers = VerifyVariants.resolved(resolutions) else {
      return base.unrun(.blocked, verifierIdentifier: VerifyVariants.blockedIdentifier(resolutions))
    }
    if unit.variantKey != nil, tokenMissing {
      return base.unrun(.blocked, verifierIdentifier: verifiers.first?.verifierIdentifier)
    }
    var runs: [(verifier: ResolvedVerifier, outcome: VerifySpawnResult)] = []
    for verifier in verifiers {
      do throws(VerifySpawnError) {
        let request = VerifySpawnRequest(
          command: verifier.command,
          workingDirectory: contextRoot,
          timeoutSeconds: verifier.timeoutSeconds,
        )
        try runs.append((verifier, spawnRunner.run(request)))
      } catch {
        throw .verifierSpawn(error)
      }
    }
    let firstFailure = runs.first { run in
      run.outcome.exitCode != 0 || run.outcome.timedOut
    }
    // A resolved row always has at least one verifier, so `runs` is not empty.
    let decisive = firstFailure ?? runs[0]
    let runClass: VerificationRunClass =
      VerifierPresets.isTestSuitePreset(decisive.verifier.preset?.rawValue) ? .suite : .command
    let overclaimed = runClass == .suite
      && JavaScriptString.identical(decisive.verifier.evidenceKind, "live_demo")
    let rowIdentifier = target.status.rowIdentifier
    let alreadyNamed = overclaimedRows.contains { named in
      JavaScriptString.identical(named, rowIdentifier)
    }
    if overclaimed, !alreadyNamed {
      overclaimedRows.append(rowIdentifier)
    }
    return base.ran(
      firstFailure == nil ? .pass : .fail,
      verifier: decisive.verifier,
      outcome: decisive.outcome,
      runClass: runClass,
      overclaimed: overclaimed,
    )
  }

  // MARK: - Attestation and the results ledger

  //: @use-case:lifecycle.signals.local_results_are_attested
  /// Every record, fail and blocked included, carries the HMAC only this
  /// machine's key produces. The key is minted only when there is a record.
  mutating func attest(
    files: some MarkerFileSystem,
    runKeyLocation: RunKeyLocation,
  ) throws(MarkerCommandError) {
    guard !results.isEmpty else {
      return
    }
    let key: String
    do throws(FileAccessError) {
      key = try RunAttestation.resolveLocalRunKey(
        keyPath: options.runKeyPath ?? runKeyLocation.defaultPath,
        files: files,
      )
    } catch {
      throw .fileAccess(error)
    }
    for index in results.indices {
      do throws(CodeUnitCanonicalJSONError) {
        results[index].runAttestation = try RunAttestation.compute(
          record: results[index].fields,
          key: key,
        )
      } catch {
        throw .canonicalJSON(error)
      }
    }
  }

  //: @use-case:end lifecycle.signals.local_results_are_attested

  /// The results ledger written when asked for, and the run's verdict: exit 0
  /// only when every record passed.
  func finish(files: some MarkerFileSystem) throws(MarkerCommandError) -> VerifyCommandResult {
    let outPath = try writeResults(files: files)
    let allPass = results.allSatisfy { record in
      record.status == .pass
    }
    return VerifyCommandResult(
      exitCode: allPass ? 0 : 1,
      results: results,
      outPath: outPath,
      overclaimedRows: overclaimedRows,
      errors: errors,
    )
  }

  /// MERGE into the results ledger, never truncate: a row this run did not
  /// verify keeps its prior line, as its original text; a row it did verify
  /// gets its fresh record. Lines are ordered by row id in code-unit order.
  private func writeResults(files: some MarkerFileSystem) throws(MarkerCommandError) -> String? {
    guard let outPath = options.outPath, !outPath.isEmpty else {
      return nil
    }
    do throws(FileAccessError) {
      let existing = try files.readText(atPath: outPath) ?? ""
      let body = VerificationResultsLedger.merge(existing: existing, records: results)
      try files.writeText(body, toPath: outPath)
    } catch {
      throw .fileAccess(error)
    }
    return outPath
  }

  // MARK: - Shared

  private mutating func familyTokenMissing(
    _ target: TargetRow,
    keys: [String],
  ) -> Bool {
    guard let firstKey = keys.first,
          VerifyVariants.cannotDistinguish(
            target.status.rowIdentifier,
            loaded: target.loaded,
            firstKey: firstKey,
            workspace: options.context.verifiers,
          )
    else {
      return false
    }
    errors.append(VerifyVariants.tokenMissingFailure(target.status.rowIdentifier))
    return true
  }

  private func resolve(
    _ target: TargetRow,
    variantKey: String?,
  ) -> [VerifierResolution] {
    VerifierResolver.resolveRowVerifiers(
      slug: target.status.rowIdentifier,
      variant: variantKey,
      verificationPolicy: target.loaded.verificationPolicy,
      workspace: options.context.verifiers,
    )
  }
}

/// The members every record of one unit shares.
private struct UnitBase {
  let unit: VerifyUnit
  let rowHash: String
  let bindingSetHash: String
  let spanHashes: [String]
  let contextHash: String
  let createdAt: String

  init(
    _ unit: VerifyUnit,
    target: TargetRow,
    inputs: BoundRowInputs,
    createdAt: String,
  ) throws(MarkerCommandError) {
    self.unit = unit
    rowHash = unit.rowHash(target.loaded)
    bindingSetHash = try inputs.bindingSetHash(unit.recordRowIdentifier)
    spanHashes = inputs.spanHashes
    contextHash = inputs.contextHash
    self.createdAt = createdAt
  }

  /// A record for a unit nothing was spawned for.
  func unrun(
    _ status: VerificationStatus,
    verifierIdentifier: String?,
  ) -> VerificationResultRecord {
    record(status, evidenceKind: nil, verifierIdentifier: verifierIdentifier, verifierKind: nil)
  }

  func ran(
    _ status: VerificationStatus,
    verifier: ResolvedVerifier,
    outcome: VerifySpawnResult,
    runClass: VerificationRunClass,
    overclaimed: Bool,
  ) -> VerificationResultRecord {
    record(
      status,
      evidenceKind: verifier.evidenceKind,
      verifierIdentifier: verifier.verifierIdentifier,
      verifierKind: "script",
      exitCode: outcome.exitCode,
      outputHashes: (
        MarkerDigest.sha256(outcome.standardOutput),
        MarkerDigest.sha256(outcome.standardError),
      ),
      runClass: runClass,
      overclaimed: overclaimed,
    )
  }

  private func record(
    _ status: VerificationStatus,
    evidenceKind: String?,
    verifierIdentifier: String?,
    verifierKind: String?,
    exitCode: Int? = nil,
    outputHashes: (String, String)? = nil,
    runClass: VerificationRunClass? = nil,
    overclaimed: Bool? = nil,
  ) -> VerificationResultRecord {
    VerificationResultRecord(
      rowIdentifier: unit.recordRowIdentifier,
      status: status,
      evidenceKind: evidenceKind,
      verifierIdentifier: verifierIdentifier,
      verifierKind: verifierKind,
      exitCode: exitCode,
      rowHash: rowHash,
      bindingSetHash: bindingSetHash,
      spanSHA256s: spanHashes,
      verificationContextHash: contextHash,
      standardOutputSHA256: outputHashes?.0,
      standardErrorSHA256: outputHashes?.1,
      createdAt: createdAt,
      variantKey: unit.variantKey,
      runClass: runClass,
      evidenceKindOverclaimed: overclaimed,
      runAttestation: nil,
    )
  }
}

/// The unsigned results ledger `verify --out` maintains.
enum VerificationResultsLedger {
  //: @use-case:lifecycle.signals.verify_preserves_other_rows
  /// The new file body: every prior line that parses to an object with a
  /// string `row_id` this run did not re-verify (kept as its trimmed text,
  /// duplicates included), then this run's records, stably sorted by row id
  /// in code-unit order. Row ids here are arbitrary file data, so they are
  /// compared as code units.
  static func merge(
    existing: String,
    records: [VerificationResultRecord],
  ) -> String {
    let superseded = Set(records.map { record in
      CodeUnitKey(record.rowIdentifier)
    })
    var merged: [(rowIdentifier: String, line: String)] = []
    for raw in JavaScriptString.split(existing, on: CodeUnits.lineFeed) {
      let line = JavaScriptString.trim(raw)
      guard !line.isEmpty, let rowIdentifier = priorRowIdentifier(line),
            !superseded.contains(CodeUnitKey(rowIdentifier))
      else {
        continue
      }
      merged.append((rowIdentifier, line))
    }
    merged += records.map { record in
      (record.rowIdentifier, JSONWriter.encode(record.jsonValue))
    }
    let ordered = merged.enumerated().sorted { left, right in
      if JavaScriptString.precedes(left.element.rowIdentifier, right.element.rowIdentifier) {
        return true
      }
      if JavaScriptString.precedes(right.element.rowIdentifier, left.element.rowIdentifier) {
        return false
      }
      return left.offset < right.offset
    }
    let body = ordered.map(\.element.line).joined(separator: "\n")
    return body.isEmpty ? "" : body + "\n"
  }

  //: @use-case:end lifecycle.signals.verify_preserves_other_rows

  private static func priorRowIdentifier(_ line: String) -> String? {
    do throws(SchemaError) {
      return try JSONParser.parse(line)["row_id"]?.stringValue
    } catch {
      return nil
    }
  }
}
