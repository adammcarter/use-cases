public struct ImpactCommandOptions {
  public var context: ResolvedWorkspaceContext
  public var productRoot: String
  public var bindingsPath: String
  public var evidencePath: String
  public var publicKeyResolver: PublicKeyResolver
  public var generatedAt: String
  public var commentConfiguration: CommentPrefixConfiguration?
  /// The repository the diff runs in; the product root when nil.
  public var repositoryWorkingDirectory: String?
  /// Compare the working tree against this ref instead of HEAD.
  public var base: String?
  /// Compare the index against HEAD instead of the working tree.
  public var staged: Bool

  public init(
    context: ResolvedWorkspaceContext,
    productRoot: String,
    bindingsPath: String,
    evidencePath: String,
    publicKeyResolver: @escaping PublicKeyResolver,
    generatedAt: String,
  ) {
    self.context = context
    self.productRoot = productRoot
    self.bindingsPath = bindingsPath
    self.evidencePath = evidencePath
    self.publicKeyResolver = publicKeyResolver
    self.generatedAt = generatedAt
    commentConfiguration = nil
    repositoryWorkingDirectory = nil
    base = nil
    staged = false
  }
}

/// A bound behaviour whose file changed with a hunk overlapping its span.
public struct ImpactedBinding: Equatable, Sendable {
  public let rowIdentifier: String
  public let bindingSlug: String
  public let file: String
  public let span: LineRange
  public let overlappingRanges: [LineRange]

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("row_id", .string(rowIdentifier)),
      ("binding_slug", .string(bindingSlug)),
      ("file", .string(file)),
      ("span", span.jsonValue),
      ("overlapping_ranges", .array(overlappingRanges.map(\.jsonValue))),
    ]))
  }
}

/// A bound behaviour whose file changed with no hunk overlapping its span.
public struct TouchedBinding: Equatable, Sendable {
  public let rowIdentifier: String
  public let bindingSlug: String
  public let file: String
  public let span: LineRange

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("row_id", .string(rowIdentifier)),
      ("binding_slug", .string(bindingSlug)),
      ("file", .string(file)),
      ("span", span.jsonValue),
    ]))
  }
}

public enum BrokenBindingReason: String, Equatable, Sendable {
  case deleted
  case renamed
}

/// A bound behaviour whose file was deleted or renamed.
public struct BrokenBinding: Equatable, Sendable {
  public let rowIdentifier: String
  public let bindingSlug: String
  /// The path the marked code lived at: the rename destination for a marker
  /// that moved with its file, else the base-ref path.
  public let file: String
  public let reason: BrokenBindingReason

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("row_id", .string(rowIdentifier)),
      ("binding_slug", .string(bindingSlug)),
      ("file", .string(file)),
      ("reason", .string(reason.rawValue)),
    ]))
  }
}

public struct ImpactCommandResult: Equatable, Sendable {
  /// `IMPACT_REPORT_SCHEMA_ID`.
  public static let schemaIdentifier = "ucase-impact-report-v1"

  public let exitCode: Int
  public let base: String
  public let changedFiles: [ChangedFile]
  public let impacted: [ImpactedBinding]
  public let touched: [TouchedBinding]
  public let brokenBindings: [BrokenBinding]
  public let summary: String
  public let errors: [MarkerCommandFailure]

  public var isOK: Bool {
    exitCode == 0
  }

  /// The object `fail` builds: its literal's members in order, then
  /// `exit_code`, which the spread adds last.
  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("schema", .string(Self.schemaIdentifier)),
      ("command", .string("impact")),
      ("ok", .bool(isOK)),
      ("base", .string(base)),
      ("changed_files", .array(changedFiles.map(\.jsonValue))),
      ("impacted", .array(impacted.map(\.jsonValue))),
      ("touched", .array(touched.map(\.jsonValue))),
      ("broken_bindings", .array(brokenBindings.map(\.jsonValue))),
      ("summary", .string(summary)),
      ("errors", .array(errors.map(\.jsonValue))),
      ("exit_code", .number(Double(exitCode))),
    ]))
  }
}

/// `runImpactCommand` (0.2.0 F2): the advisory, read-only change-impact lens.
/// Which bound behaviours does the current git change touch? It never derives
/// or changes a verdict and never writes.
public enum ImpactCommand {
  /// A missing base ref or a directory outside git is a result with exit code
  /// 1, not a throw. The scan pipeline's own failures are thrown. `impact`
  /// names no run key, so the scan it reads looks in `runKeyLocation`'s
  /// default; the local tier never reaches this result.
  public static func run(
    _ options: ImpactCommandOptions,
    files: some MarkerFileSystem = LocalTextFiles(),
    registry: SchemaRegistry,
    gitRunner: some GitRunning = GitProcessRunner(),
    runKeyLocation: RunKeyLocation = .process,
  ) throws(MarkerCommandError) -> ImpactCommandResult {
    let repositoryDirectory = options.repositoryWorkingDirectory ?? options.productRoot
    // Read-only reuse of the freshness pipeline, for the materialized bindings
    // only: feature mode, no base ref.
    let prepared = try ScanCommand.prepare(
      scanOptions(options),
      files: files,
      registry: registry,
      gitRunner: gitRunner,
      runKeyLocation: runKeyLocation,
    )

    let diff: CollectedDiff
    do throws(GitError) {
      diff = try GitDiff.collectChangedFiles(
        base: options.base,
        staged: options.staged,
        workingDirectory: repositoryDirectory,
        runner: gitRunner,
      )
    } catch {
      return gitDiffFailure(error)
    }

    var classification = ImpactClassification(diff: diff)
    for row in prepared.status.rows {
      for binding in row.currentBindings {
        classification.classify(binding, rowIdentifier: row.rowIdentifier)
      }
    }
    let reader = BaseReferenceScanner(
      reference: options.base ?? "HEAD",
      repositoryDirectory: repositoryDirectory,
      runner: gitRunner,
      commentConfiguration: options.commentConfiguration,
    )
    classification.broken += reader.brokenBindings(
      missing: prepared.status.rows.flatMap { row in
        row.missingRegisteredBindingSlugs.map { slug in
          (row.rowIdentifier, slug)
        }
      },
      removedOldPaths: classification.removedOldPaths,
    )

    return ImpactCommandResult(
      exitCode: 0,
      base: diff.base,
      changedFiles: diff.files,
      impacted: classification.impacted,
      touched: classification.touched,
      brokenBindings: classification.broken,
      summary: classification.summary,
      errors: [],
    )
  }

  private static func scanOptions(_ options: ImpactCommandOptions) -> ScanCommandOptions {
    var scanOptions = ScanCommandOptions(
      context: options.context,
      productRoot: options.productRoot,
      bindingsPath: options.bindingsPath,
      evidencePath: options.evidencePath,
      policyMode: .feature,
      publicKeyResolver: options.publicKeyResolver,
      generatedAt: options.generatedAt,
    )
    scanOptions.commentConfiguration = options.commentConfiguration
    scanOptions.repositoryWorkingDirectory = options.repositoryWorkingDirectory
    return scanOptions
  }

  /// `fail({ exit_code: 1, errors })`: every other member at its default, the
  /// base "HEAD" whatever ref was asked for.
  private static func gitDiffFailure(_ error: GitError) -> ImpactCommandResult {
    ImpactCommandResult(
      exitCode: 1,
      base: "HEAD",
      changedFiles: [],
      impacted: [],
      touched: [],
      brokenBindings: [],
      summary: "",
      errors: [MarkerCommandFailure(code: "GIT_DIFF_FAILED", message: error.message)],
    )
  }
}

/// The diff indexed by path, and each present binding sorted into BROKEN (its
/// file is a rename destination), IMPACTED (a hunk overlaps its span) or
/// TOUCHED (its file changed, no hunk overlaps). Paths are keyed by code unit,
/// as a JavaScript Map keys them.
private struct ImpactClassification {
  var changedByPath = OrderedStringMap<ChangedFile>()
  /// Deleted paths, and the source of each rename, where the marked code used
  /// to live.
  var removedOldPaths = OrderedStringMap<BrokenBindingReason>()
  var renameDestinations = OrderedStringSet()
  var impacted: [ImpactedBinding] = []
  var touched: [TouchedBinding] = []
  var broken: [BrokenBinding] = []

  init(diff: CollectedDiff) {
    for file in diff.files {
      changedByPath[file.change.file] = file
      if file.change.change == .deleted {
        removedOldPaths[file.change.file] = .deleted
      } else if file.change.change == .renamed, let oldFile = file.change.oldFile,
                !oldFile.isEmpty
      {
        removedOldPaths[oldFile] = .renamed
        renameDestinations.insert(file.change.file)
      }
    }
  }

  /// `buildSummary`: lowercase, order-stable, for humans.
  var summary: String {
    var parts = ["\(impacted.count) behaviour\(impacted.count == 1 ? "" : "s") impacted"]
    if !touched.isEmpty {
      parts.append("\(touched.count) touched")
    }
    if !broken.isEmpty {
      parts.append("\(broken.count) binding\(broken.count == 1 ? "" : "s") broken by your changes")
    }
    return parts.joined(separator: ", ")
  }

  mutating func classify(
    _ binding: CurrentBindingRecord,
    rowIdentifier: String,
  ) {
    let span = LineRange(startLine: binding.span.startLine, endLine: binding.span.endLine)
    if renameDestinations.contains(binding.filePath) {
      broken.append(BrokenBinding(
        rowIdentifier: rowIdentifier,
        bindingSlug: binding.bindingSlug,
        file: binding.filePath,
        reason: .renamed,
      ))
      return
    }
    guard let changed = changedByPath[binding.filePath], changed.change.change != .deleted else {
      return
    }
    let overlapping = changed.ranges.filter { range in
      GitDiff.rangesOverlap(span, range)
    }
    if overlapping.isEmpty {
      touched.append(TouchedBinding(
        rowIdentifier: rowIdentifier,
        bindingSlug: binding.bindingSlug,
        file: binding.filePath,
        span: span,
      ))
    } else {
      impacted.append(ImpactedBinding(
        rowIdentifier: rowIdentifier,
        bindingSlug: binding.bindingSlug,
        file: binding.filePath,
        span: span,
        overlappingRanges: overlapping,
      ))
    }
  }
}

/// Reads a removed path's pre-change content at the base ref (else HEAD) and
/// scans it for the markers that vanished with it.
private struct BaseReferenceScanner<Runner: GitRunning> {
  let reference: String
  let repositoryDirectory: String
  let runner: Runner
  let commentConfiguration: CommentPrefixConfiguration?

  /// `classifyBrokenBindings`: a registered slug whose marker vanished because
  /// its file was deleted or renamed away, attributed to that path. Unreadable
  /// or empty base content is skipped.
  func brokenBindings(
    missing: [(rowIdentifier: String, bindingSlug: String)],
    removedOldPaths: OrderedStringMap<BrokenBindingReason>,
  ) -> [BrokenBinding] {
    guard !missing.isEmpty, !removedOldPaths.isEmpty else {
      return []
    }
    var missingBySlug = OrderedStringMap<String>()
    for item in missing {
      missingBySlug[item.bindingSlug] = item.rowIdentifier
    }

    var broken: [BrokenBinding] = []
    for (oldPath, reason) in removedOldPaths.pairs {
      if missingBySlug.isEmpty {
        break
      }
      guard let baseText = baseText(oldPath), !baseText.isEmpty else {
        continue
      }
      let scan = MarkerScanner.scanFiles(
        [ScanInput(filePath: oldPath, contents: baseText)],
        configuration: commentConfiguration,
      )
      for binding in scan.bindings {
        guard let rowIdentifier = missingBySlug[binding.bindingSlug] else {
          continue
        }
        broken.append(BrokenBinding(
          rowIdentifier: rowIdentifier,
          bindingSlug: binding.bindingSlug,
          file: oldPath,
          reason: reason,
        ))
        missingBySlug[binding.bindingSlug] = nil
      }
    }
    return broken
  }

  private func baseText(_ path: String) -> String? {
    do throws(GitError) {
      return try AppendOnly.readBaseReferenceFile(
        baseReference: reference,
        path: path,
        workingDirectory: repositoryDirectory,
        runner: runner,
      )
    } catch {
      return nil
    }
  }
}
