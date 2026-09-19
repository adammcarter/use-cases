/// The digests and workflow snapshot that pin a plan to its inputs, and the
/// plan id (packages/core/src/presentation/snapshot.ts).
///
/// Digests hash the TypeScript's own in-memory objects, so their member names
/// are the TypeScript's: camelCase integrity, snake_case rows and aggregates.
enum PresentationSnapshot {
  /// `matrixDigest`.
  static func matrixDigest(_ matrix: MatrixSnapshot) -> String {
    SemanticHash.compute(.object(JSONObject([
      ("complete", .bool(matrix.isComplete)),
      ("integrity", .object(JSONObject([
        ("state", .string(matrix.integrity.state.rawValue)),
        ("populated", .bool(matrix.integrity.isPopulated)),
        ("blockingDiagnosticCount", .number(Double(matrix.integrity.blockingDiagnosticCount))),
      ]))),
      ("use_cases", .array(matrix.addressableUseCases.map { useCase in
        .object(JSONObject([
          ("id", .string(useCase.identifier)),
          ("semantic_hash", .string(useCase.semanticHash)),
          ("source_path", .string(useCase.source.path)),
        ]))
      })),
    ])))
  }

  /// `evidenceDigest`: the aggregates with a target among `useCaseIdentifiers`.
  static func evidenceDigest(
    _ evidence: EvidenceSnapshot,
    useCaseIdentifiers: [String],
  ) -> String {
    let identifiers = Set(useCaseIdentifiers.map(CodeUnitKey.init))
    let aggregates = evidence.aggregates
      .filter { aggregate in
        aggregate.targetLinks.contains { target in
          guard let identifier = target["use_case_id"]?.stringValue else {
            return false
          }
          return identifiers.contains(CodeUnitKey(identifier))
        }
      }
      .map { aggregate in
        JSONValue.object(JSONObject([
          ("evidence_id", .string(aggregate.evidenceIdentifier)),
          ("status", .string(aggregate.status.rawValue)),
          ("event_ids", .array(aggregate.eventIdentifiers.map(JSONValue.string))),
          ("target_links", .array(aggregate.targetLinks)),
          ("freshness_inputs", .object(aggregate.freshnessInputs)),
        ]))
      }
    return SemanticHash.compute(.object(JSONObject([
      ("complete", .bool(evidence.isComplete)),
      ("integrity", .object(JSONObject([
        ("state", .string(evidence.integrity.state.rawValue)),
        ("unknownScopeDamage", .bool(evidence.integrity.hasUnknownScopeDamage)),
        ("invalidAggregateCount", .number(Double(evidence.integrity.invalidAggregateCount))),
        ("tornTailCount", .number(Double(evidence.integrity.tornTailCount))),
      ]))),
      ("aggregates", .array(aggregates)),
    ])))
  }

  /// `workflowSnapshot`: `use-cases.yml` read as TEXT, not YAML — the first
  /// line starting `default_workflow_mode:` followed by optional whitespace
  /// (newlines included) and `[a-z_]+` gives the mode. A read that fails
  /// escapes, as node's does.
  static func workflowSnapshot(
    context: ResolvedWorkspaceContext,
  ) throws(FileAccessError) -> WorkflowSnapshot {
    let path = WorkspacePath.absolute("use-cases.yml", relativeTo: context.workspaceRoot)
    guard NodeFile.exists(atPath: path) else {
      return WorkflowSnapshot(effectiveMode: "continuous", source: .default)
    }
    let source = try NodeFile.readText(atPath: path)
    let match = workflowModeMatch(in: Array(source.utf16))
    return WorkflowSnapshot(
      effectiveMode: match.mode ?? "continuous",
      source: match.hasKey ? .workspaceConfig : .default,
    )
  }

  /// `/^default_workflow_mode:/m` and `/^default_workflow_mode:\s*([a-z_]+)/m`
  /// over UTF-16 code units: `^` after a start, LF, CR, U+2028 or U+2029, and
  /// the first line whose capture succeeds.
  static func workflowModeMatch(in units: [UInt16]) -> (hasKey: Bool, mode: String?) {
    let key = Array("default_workflow_mode:".utf16)
    var hasKey = false
    for start in lineStarts(units) where units[start...].starts(with: key) {
      hasKey = true
      var position = start + key.count
      while position < units.count, CodeUnits.isJavaScriptWhitespace(units[position]) {
        position += 1
      }
      let captureStart = position
      while position < units.count, isLowercaseLetterOrUnderscore(units[position]) {
        position += 1
      }
      if position > captureStart {
        return (true, CodeUnits.string(units[captureStart ..< position]))
      }
    }
    return (hasKey, nil)
  }

  /// `planId`: `plan.<mode>.` then `generatedAt` lower-cased, every run of
  /// anything but `[a-z0-9]` made one `_`, and `_` trimmed from both ends.
  static func planIdentifier(
    mode: PresentationMode,
    generatedAt: String,
  ) -> String {
    var slug = String.UnicodeScalarView()
    var inRun = false
    for scalar in generatedAt.lowercased().unicodeScalars {
      if ("a" ... "z").contains(scalar) || ("0" ... "9").contains(scalar) {
        slug.append(scalar)
        inRun = false
      } else if !inRun {
        slug.append("_")
        inRun = true
      }
    }
    let trimmed = String(slug).utf16.drop { $0 == underscore }.reversed().drop { $0 == underscore }
      .reversed()
    return "plan.\(mode.rawValue).\(CodeUnits.string(Array(trimmed)))"
  }

  private static let underscore = UInt16(UInt8(ascii: "_"))

  private static func lineStarts(_ units: [UInt16]) -> [Int] {
    var starts = [0]
    for (index, unit) in units.enumerated() where [0x0A, 0x0D, 0x2028, 0x2029].contains(unit) {
      starts.append(index + 1)
    }
    return starts
  }

  private static func isLowercaseLetterOrUnderscore(_ unit: UInt16) -> Bool {
    CodeUnits.isLowercaseASCIILetter(unit) || unit == underscore
  }
}
