/// A target row's scan status and loaded row, found by exact id.
struct TargetRow {
  let status: FreshnessRow
  let loaded: FreshnessInputRow

  init?(
    _ rowIdentifier: String,
    in prepared: ScanPreparation,
  ) {
    let status = prepared.status.rows.first { row in
      JavaScriptString.identical(row.rowIdentifier, rowIdentifier)
    }
    guard let status,
          let loaded = MarkerCommandInputs.findRow(
            prepared.loaded.rows,
            rowIdentifier: rowIdentifier,
          )
    else {
      return nil
    }
    self.status = status
    self.loaded = loaded
  }
}

/// What verify and prove both recompute for a bound row, so a verify record
/// and a proof agree byte for byte: its registered bindings, their span hashes
/// in code-unit order, and the family-level verification context hash.
struct BoundRowInputs {
  let bindings: [CurrentBindingRecord]
  let spanHashes: [String]
  let contextHash: String

  init(
    _ target: TargetRow,
    prepared: ScanPreparation,
    context: ResolvedWorkspaceContext,
    contextRoot: String,
    files: some MarkerFileSystem,
  ) throws(MarkerCommandError) {
    bindings = MarkerCommandInputs.registeredBindingsForRow(
      prepared.scan.bindings,
      rowIdentifier: target.status.rowIdentifier,
      registeredSlugs: Set(target.status.knownBindingSlugs),
    )
    spanHashes = JavaScriptString.sorted(bindings.map(\.span.sha256))
    do throws(VerificationContextHashError) {
      contextHash = try VerificationContextHash.computeForRow(
        slug: target.status.rowIdentifier,
        verificationPolicy: target.loaded.verificationPolicy,
        rootDirectory: contextRoot,
        files: files,
        workspaceVerifiers: context.verifiers,
      )
    } catch {
      throw .verificationContextHash(error)
    }
  }

  func bindingSetHash(_ rowIdentifier: String) throws(MarkerCommandError) -> String {
    do throws(CodeUnitCanonicalJSONError) {
      return try BindingSetHash.compute(
        rowIdentifier: rowIdentifier,
        bindings: bindings.map(\.setMember),
      )
    } catch {
      throw .canonicalJSON(error)
    }
  }
}

/// One record a row produces: the row itself, or one declared variant of a
/// family, keyed `<family>::<key>`.
struct VerifyUnit {
  let recordRowIdentifier: String
  let variantKey: String?

  /// The family's units, one per variant in key order; an ordinary row's one.
  static func units(
    _ rowIdentifier: String,
    variantKeys: [String],
  ) -> [VerifyUnit] {
    guard !variantKeys.isEmpty else {
      return [VerifyUnit(recordRowIdentifier: rowIdentifier, variantKey: nil)]
    }
    return variantKeys.map { key in
      VerifyUnit(recordRowIdentifier: rowIdentifier + "::" + key, variantKey: key)
    }
  }

  /// The row hash of this unit: a variant hashes the family row with its own
  /// record id and key, and without the `variants` list.
  func rowHash(_ loaded: FreshnessInputRow) -> String {
    guard let variantKey else {
      return RowHash.compute(.object(loaded.fields))
    }
    var projection = loaded.fields
    projection["row_id"] = .string(recordRowIdentifier)
    projection["variant_key"] = .string(variantKey)
    projection["variants"] = nil
    return RowHash.compute(.object(projection))
  }
}

/// The variant-family rules verify applies.
enum VerifyVariants {
  /// The declared variant keys, in `rowVariants` order.
  static func keys(_ row: FreshnessInputRow) -> [String] {
    MarkerCommandInputs.rowVariants(row).compactMap { variant in
      variant["key"]?.stringValue
    }
  }

  /// A family whose resolved commands are identical with and without
  /// `{variant}` cannot tell its variants apart: one process would "prove"
  /// every one. Judged from the first key; blocked resolutions are their own
  /// failure and never this one.
  static func cannotDistinguish(
    _ rowIdentifier: String,
    loaded: FreshnessInputRow,
    firstKey: String,
    workspace: ResolvedWorkspaceVerifiers,
  ) -> Bool {
    let withVariant = VerifierResolver.resolveRowVerifiers(
      slug: rowIdentifier,
      variant: firstKey,
      verificationPolicy: loaded.verificationPolicy,
      workspace: workspace,
    )
    guard !withVariant.isEmpty, resolved(withVariant) != nil else {
      return false
    }
    let without = VerifierResolver.resolveRowVerifiers(
      slug: rowIdentifier,
      verificationPolicy: loaded.verificationPolicy,
      workspace: workspace,
    )
    return withVariant.enumerated().allSatisfy { index, resolution in
      guard case let .resolved(verifier) = resolution, index < without.count,
            case let .resolved(counterpart) = without[index]
      else {
        return false
      }
      return verifier.command.count == counterpart.command.count
        && zip(verifier.command, counterpart.command).allSatisfy(JavaScriptString.identical)
    }
  }

  static func tokenMissingFailure(_ rowIdentifier: String) -> MarkerCommandFailure {
    MarkerCommandFailure(
      code: "VARIANT_TOKEN_MISSING",
      message: "verifier for variant family '\(rowIdentifier)' has no {variant} token, "
        + "so it cannot distinguish variants; add {variant} to its command",
    )
  }

  /// Every resolution's verifier, or nil when any is blocked.
  static func resolved(_ resolutions: [VerifierResolution]) -> [ResolvedVerifier]? {
    var verifiers: [ResolvedVerifier] = []
    for resolution in resolutions {
      guard case let .resolved(verifier) = resolution else {
        return nil
      }
      verifiers.append(verifier)
    }
    return verifiers
  }

  /// The first blocked resolution's id, if any is blocked.
  static func blockedIdentifier(_ resolutions: [VerifierResolution]) -> String? {
    for case let .blocked(verifier) in resolutions {
      return verifier.verifierIdentifier
    }
    return nil
  }
}
