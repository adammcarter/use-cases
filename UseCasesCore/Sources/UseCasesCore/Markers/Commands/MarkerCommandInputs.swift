/// The loaded rows, the use-case matrix they came from, and their ids.
public struct LoadedMarkerRows: Sendable {
  /// Each addressable use case as a marker row, in matrix order.
  public let rows: [FreshnessInputRow]
  /// The rows' ids. Row ids are schema-constrained to ASCII, so a Swift `Set`
  /// keyed by canonical equivalence cannot merge two distinct ids.
  public let rowIdentifiers: Set<String>
  public let snapshot: MatrixSnapshot
}

/// Shared inputs for the marker command cores (shared.ts): the marker rows, the
/// product source walk, and the small path and key helpers every command uses.
///
/// Everything here is deterministic given its inputs; the filesystem arrives
/// through ``MarkerFileSystem``.
public enum MarkerCommandInputs {
  /// Directory names never walked for markers: VCS and dependency directories,
  /// the data directory, agent session state, and common build output. `.build`
  /// and `DerivedData` are NOT here, because they are not in the TypeScript.
  public static let defaultSkipDirectories: [String] = [
    ".git",
    ".claude",
    "node_modules",
    ".use-cases",
    "dist",
    "dist-ts",
    "build",
    "out",
    "coverage",
    ".next",
    ".turbo",
    ".svelte-kit",
  ]

  /// A child directory carrying one of these is its own workspace, whose
  /// markers name ITS rows, so the walk does not enter it.
  public static let workspaceConfigurationFiles: [String] = ["use-cases.yml", "use-cases.yaml"]

  private static let skippedDirectoryNames = Set(defaultSkipDirectories.map(CodeUnitKey.init))

  /// `loadMarkerRows`: each addressable use case with a `row_id` alias and both
  /// policies forced present (null when the row omits one), so the policy
  /// hashes never meet an absent policy. A variant family stays ONE row.
  ///
  /// The Swift loader needs the schema registry the TypeScript loader finds
  /// for itself.
  public static func loadMarkerRows(
    context: ResolvedWorkspaceContext,
    registry: SchemaRegistry,
  ) throws(UseCaseMatrixError) -> LoadedMarkerRows {
    let snapshot = try UseCaseMatrixLoader.load(context: context, registry: registry)
    // `{ ...value, row_id, verification_policy, approval_policy }`: a member
    // the row already has keeps its position, a new one goes last. A row the
    // schema let through always has a string id and string variant keys, so
    // none is dropped here.
    let rows = snapshot.addressableUseCases.compactMap { useCase in
      var fields = useCase.value
      fields["row_id"] = useCase.value["id"] ?? .null
      fields["verification_policy"] = useCase.value["verification_policy"] ?? .null
      fields["approval_policy"] = useCase.value["approval_policy"] ?? .null
      return FreshnessInputRow(fields: fields)
    }
    return LoadedMarkerRows(
      rows: rows,
      rowIdentifiers: Set(rows.map(\.rowIdentifier)),
      snapshot: snapshot,
    )
  }

  /// `rowVariants`: a family row's declared variants, stably sorted by `key`
  /// in UTF-16 code-unit order (JavaScript `<`); empty for an ordinary row.
  public static func rowVariants(_ row: FreshnessInputRow) -> [JSONValue] {
    guard let variants = row.fields["variants"]?.arrayValue else {
      return []
    }
    return variants.enumerated()
      .sorted { left, right in
        let leftKey = left.element["key"]?.stringValue ?? ""
        let rightKey = right.element["key"]?.stringValue ?? ""
        if JavaScriptString.precedes(leftKey, rightKey) {
          return true
        }
        if JavaScriptString.precedes(rightKey, leftKey) {
          return false
        }
        return left.offset < right.offset
      }
      .map(\.element)
  }

  /// `findRow`: the first row whose id is `rowIdentifier` code unit for code
  /// unit.
  public static func findRow(
    _ rows: [FreshnessInputRow],
    rowIdentifier: String,
  ) -> FreshnessInputRow? {
    rows.first { row in
      JavaScriptString.identical(row.rowIdentifier, rowIdentifier)
    }
  }

  /// `collectSourceInputs`: every file under `productRoot` that has a comment
  /// prefix, keyed by its posix path relative to the root and sorted by that
  /// path in code-unit order.
  ///
  /// Symlinks are never followed. A directory named in
  /// ``defaultSkipDirectories``, one whose path is in `skipPaths`, and a child
  /// directory holding a workspace config are skipped — the root's own config
  /// never is. A directory that cannot be LISTED is silently skipped; any
  /// other read failure, including the nested-workspace probe's, is raised.
  public static func collectSourceInputs(
    productRoot: String,
    files: some MarkerFileSystem,
    configuration: CommentPrefixConfiguration? = nil,
    skipPaths: [String] = [],
  ) throws(FileAccessError) -> [ScanInput] {
    var walk = SourceWalk(
      productRoot: productRoot,
      configuration: configuration,
      skipPaths: Set(skipPaths.map(CodeUnitKey.init)),
    )
    try walk.visit(productRoot, files: files)
    return walk.inputs.enumerated()
      .sorted { left, right in
        if JavaScriptString.precedes(left.element.filePath, right.element.filePath) {
          return true
        }
        if JavaScriptString.precedes(right.element.filePath, left.element.filePath) {
          return false
        }
        return left.offset < right.offset
      }
      .map(\.element)
  }

  /// `toPosix`: every backslash code unit becomes a slash.
  public static func toPosix(_ path: String) -> String {
    CodeUnits.string(path.utf16.map { unit in
      unit == CodeUnits.reverseSolidus ? CodeUnits.solidus : unit
    })
  }

  /// `resolveUnderRoot`: an absolute value as is, otherwise `join(root, value)`.
  public static func resolveUnderRoot(
    _ root: String,
    _ value: String,
  ) -> String {
    NodePath.isAbsolute(value) ? value : NodePath.join(root, value)
  }

  /// `singleKeyResolver`: v1 trusts exactly one key, so any key id resolves to
  /// it — unless `keyIdentifier` pins the one id it answers.
  public static func singleKeyResolver(
    publicKey: String,
    keyIdentifier: String? = nil,
  ) -> PublicKeyResolver {
    { requestedKeyIdentifier, _ in
      if let keyIdentifier, !JavaScriptString.identical(requestedKeyIdentifier, keyIdentifier) {
        return nil
      }
      return publicKey
    }
  }

  /// `registeredBindingsForRow`: a row's current bindings whose slugs the
  /// registry knows (spec 7: C(row)). Slugs are ASCII by the slug grammar.
  public static func registeredBindingsForRow(
    _ bindings: [CurrentBindingRecord],
    rowIdentifier: String,
    registeredSlugs: Set<String>,
  ) -> [CurrentBindingRecord] {
    bindings.filter { binding in
      JavaScriptString.identical(binding.rowIdentifier, rowIdentifier)
        && registeredSlugs.contains(binding.bindingSlug)
    }
  }

  /// The recursive walk behind ``collectSourceInputs(productRoot:files:configuration:skipPaths:)``.
  private struct SourceWalk {
    let productRoot: String
    let configuration: CommentPrefixConfiguration?
    let skipPaths: Set<CodeUnitKey>
    var inputs: [ScanInput] = []

    mutating func visit(
      _ directory: String,
      files: some MarkerFileSystem,
    ) throws(FileAccessError) {
      let entries: [MarkerDirectoryEntry]
      do throws(FileAccessError) {
        entries = try files.listDirectory(atPath: directory)
      } catch {
        return
      }
      for entry in entries {
        if entry.isSymbolicLink {
          continue
        }
        let full = NodePath.join(directory, entry.name)
        if entry.isDirectory {
          if MarkerCommandInputs.skippedDirectoryNames.contains(CodeUnitKey(entry.name))
            || skipPaths.contains(CodeUnitKey(full))
          {
            continue
          }
          if try isNestedWorkspace(full, files: files) {
            continue
          }
          try visit(full, files: files)
          continue
        }
        if !entry.isFile {
          continue
        }
        let relativePath = MarkerCommandInputs.toPosix(NodePath.relative(
          from: productRoot,
          to: full,
        ))
        guard let contents = try files.readText(atPath: full) else {
          continue
        }
        guard CommentPrefix.resolve(
          filePath: relativePath,
          configuration: configuration,
          contents: contents,
        ) != nil else {
          continue
        }
        inputs.append(ScanInput(filePath: relativePath, contents: contents))
      }
    }

    //: @use-case:lifecycle.signals.nested_workspace_is_not_scanned
    /// A config is detected by READING it, as the TypeScript does, so a probe
    /// that fails for a reason other than absence is raised.
    private func isNestedWorkspace(
      _ directory: String,
      files: some MarkerFileSystem,
    ) throws(FileAccessError) -> Bool {
      for name in MarkerCommandInputs.workspaceConfigurationFiles
        where try files.readText(atPath: NodePath.join(directory, name)) != nil
      {
        return true
      }
      return false
    }
    //: @use-case:end lifecycle.signals.nested_workspace_is_not_scanned
  }
}
