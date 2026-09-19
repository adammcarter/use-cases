public struct ValidateLedgerCommandOptions {
  public var context: ResolvedWorkspaceContext
  public var evidencePath: String
  public var bindingsPath: String
  public var publicKeyResolver: PublicKeyResolver
  public var baseReference: String?
  /// Where `git show` runs.
  public var repositoryWorkingDirectory: String?

  public init(
    context: ResolvedWorkspaceContext,
    evidencePath: String,
    bindingsPath: String,
    publicKeyResolver: @escaping PublicKeyResolver,
  ) {
    self.context = context
    self.evidencePath = evidencePath
    self.bindingsPath = bindingsPath
    self.publicKeyResolver = publicKeyResolver
    baseReference = nil
    repositoryWorkingDirectory = nil
  }
}

/// Which ledger an error belongs to.
public enum LedgerErrorScope: String, Equatable, Sendable {
  case evidence
  case registry
}

public struct LedgerErrorReport: Equatable, Sendable {
  public let scope: LedgerErrorScope
  public let code: String
  public let line: Int?
  public let message: String

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("scope", .string(scope.rawValue)),
      ("code", .string(code)),
      ("line", JSONValue.optionalNumber(line)),
      ("message", .string(message)),
    ]))
  }
}

public struct ValidateLedgerCommandResult: Equatable, Sendable {
  public let exitCode: Int
  public let isOK: Bool
  public let evidenceValid: Bool
  public let registryValid: Bool
  public let appendOnly: Bool
  public let proofEventsChecked: Int
  public let registryEventsChecked: Int
  public let chainValid: Bool
  public let chainVerifiedEntries: Int
  public let chainLegacyPrefixCount: Int
  public let errors: [LedgerErrorReport]

  /// The TypeScript result object, in its key order.
  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("exit_code", .number(Double(exitCode))),
      ("ok", .bool(isOK)),
      ("command", .string("validate-ledger")),
      ("evidence_valid", .bool(evidenceValid)),
      ("registry_valid", .bool(registryValid)),
      ("append_only", .bool(appendOnly)),
      ("proof_events_checked", .number(Double(proofEventsChecked))),
      ("registry_events_checked", .number(Double(registryEventsChecked))),
      ("chain", .object(JSONObject([
        ("ok", .bool(chainValid)),
        ("verified_entries", .number(Double(chainVerifiedEntries))),
        ("legacy_prefix_count", .number(Double(chainLegacyPrefixCount))),
      ]))),
      ("errors", .array(errors.map(\.jsonValue))),
    ]))
  }
}

/// `runValidateLedgerCommand` (spec 8.4): the authority on ledger and registry
/// integrity — append-only discipline, schemas, signatures, producer trust, the
/// hash chain, and the registry's slug-to-row mapping. It never mutates, never
/// compares old proof spans to current code, and never derives freshness.
public enum ValidateLedgerCommand {
  public static func run(
    _ options: ValidateLedgerCommandOptions,
    files: some MarkerFileSystem = LocalTextFiles(),
    registry: SchemaRegistry,
    gitRunner: some GitRunning = GitProcessRunner(),
  ) throws(MarkerCommandError) -> ValidateLedgerCommandResult {
    let loaded: LoadedMarkerRows
    do throws(UseCaseMatrixError) {
      loaded = try MarkerCommandInputs.loadMarkerRows(context: options.context, registry: registry)
    } catch {
      throw .useCaseMatrix(error)
    }
    let evidence = try checkEvidence(options, loaded: loaded, files: files, gitRunner: gitRunner)
    let bindings = try checkRegistry(options, loaded: loaded, files: files, gitRunner: gitRunner)

    let isOK = evidence.isValid && bindings.isValid
    return ValidateLedgerCommandResult(
      exitCode: isOK ? 0 : 4,
      isOK: isOK,
      evidenceValid: evidence.isValid,
      registryValid: bindings.isValid,
      appendOnly: evidence.validation.appendOnly && bindings.appendOnly,
      proofEventsChecked: evidence.validation.summary.proofEventsChecked,
      registryEventsChecked: bindings.eventsChecked,
      chainValid: evidence.chain.isValid,
      chainVerifiedEntries: evidence.chain.verifiedEntries,
      chainLegacyPrefixCount: evidence.chain.legacyPrefixCount,
      errors: evidence.errors + bindings.errors,
    )
  }

  private struct EvidenceCheck {
    let validation: EvidenceLedgerValidation
    let chain: LedgerChainResult
    let errors: [LedgerErrorReport]

    var isValid: Bool {
      validation.errors.isEmpty && chain.isValid
    }
  }

  private struct RegistryCheck {
    let errors: [LedgerErrorReport]
    let appendOnly: Bool
    let eventsChecked: Int

    var isValid: Bool {
      errors.isEmpty
    }
  }

  /// Spec 8.4 steps 1, 3, 4 and 6-9, then the tamper-evident hash chain over
  /// the contiguous chained suffix.
  private static func checkEvidence(
    _ options: ValidateLedgerCommandOptions,
    loaded: LoadedMarkerRows,
    files: some MarkerFileSystem,
    gitRunner: some GitRunning,
  ) throws(MarkerCommandError) -> EvidenceCheck {
    let text = try readText(options.evidencePath, files: files)
    var baseText: String?
    if let baseReference = options.baseReference {
      baseText = try readBaseReference(
        baseReference,
        path: options.evidencePath,
        options: options,
        gitRunner: gitRunner,
      )
    }
    let validation: EvidenceLedgerValidation
    do throws(EvidenceLedgerError) {
      validation = try EvidenceLedger.validate(
        text: text,
        publicKeyResolver: options.publicKeyResolver,
        baseReferenceOldText: baseText,
        yamlRowIdentifiers: loaded.rowIdentifiers,
      )
    } catch {
      throw .evidenceLedger(error)
    }
    let chain: LedgerChainResult
    do throws(CodeUnitCanonicalJSONError) {
      chain = try EvidenceLedgerChain.verify(EvidenceLedger.read(text).lines)
    } catch {
      throw .canonicalJSON(error)
    }
    let validationErrors = validation.errors.map { error in
      LedgerErrorReport(
        scope: .evidence,
        code: error.code.rawValue,
        line: error.line,
        message: error.message,
      )
    }
    let chainErrors = chain.errors.map { error in
      LedgerErrorReport(
        scope: .evidence,
        code: error.code.rawValue,
        line: error.line,
        message: error.message,
      )
    }
    return EvidenceCheck(
      validation: validation,
      chain: chain,
      errors: validationErrors + chainErrors,
    )
  }

  /// Spec 8.4 steps 2, 3, 5 and 10-12: the registry, then its append-only
  /// discipline against the base ref.
  private static func checkRegistry(
    _ options: ValidateLedgerCommandOptions,
    loaded: LoadedMarkerRows,
    files: some MarkerFileSystem,
    gitRunner: some GitRunning,
  ) throws(MarkerCommandError) -> RegistryCheck {
    let text = try readText(options.bindingsPath, files: files)
    let validation = BindingRegistry.validate(text: text, yamlRowIdentifiers: loaded.rowIdentifiers)
    var errors = validation.errors.map { error in
      LedgerErrorReport(
        scope: .registry,
        code: error.code.rawValue,
        line: error.line,
        message: error.message,
      )
    }
    var appendOnly = true
    if let baseReference = options.baseReference {
      let oldText = try readBaseReference(
        baseReference,
        path: options.bindingsPath,
        options: options,
        gitRunner: gitRunner,
      )
      if case let .violated(violation) = AppendOnly.check(
        oldLines: AppendOnly.splitJSONLines(oldText),
        newLines: AppendOnly.splitJSONLines(text),
      ) {
        appendOnly = false
        errors.append(LedgerErrorReport(
          scope: .registry,
          code: "APPEND_ONLY_VIOLATION",
          line: violation.index + 1,
          message: violation.message,
        ))
      }
    }
    let eventsChecked = AppendOnly.splitJSONLines(text).count { line in
      !JavaScriptString.trim(line).isEmpty
    }
    return RegistryCheck(errors: errors, appendOnly: appendOnly, eventsChecked: eventsChecked)
  }

  private static func readText(
    _ path: String,
    files: some MarkerFileSystem,
  ) throws(MarkerCommandError) -> String {
    do throws(FileAccessError) {
      return try files.readText(atPath: path) ?? ""
    } catch {
      throw .fileAccess(error)
    }
  }

  private static func readBaseReference(
    _ baseReference: String,
    path: String,
    options: ValidateLedgerCommandOptions,
    gitRunner: some GitRunning,
  ) throws(MarkerCommandError) -> String {
    do throws(GitError) {
      return try AppendOnly.readBaseReferenceFile(
        baseReference: baseReference,
        path: path,
        workingDirectory: options.repositoryWorkingDirectory,
        runner: gitRunner,
      )
    } catch {
      throw .git(error)
    }
  }
}
