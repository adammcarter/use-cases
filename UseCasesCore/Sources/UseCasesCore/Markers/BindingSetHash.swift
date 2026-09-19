/// One binding as the binding-set hash sees it: exactly the seven hashed
/// fields (spec 4.5 rules 2–6). Line numbers, markers and proof status are
/// never part of it (rules 7–10).
public struct BindingSetMember: Equatable, Sendable {
  public let bindingSlug: String
  public let rowIdentifier: String
  public let filePath: String
  public let extentKind: String
  public let recognizerIdentifier: String
  public let spanCanonicalizerIdentifier: String
  public let spanSHA256: String

  public init(
    bindingSlug: String,
    rowIdentifier: String,
    filePath: String,
    extentKind: String,
    recognizerIdentifier: String,
    spanCanonicalizerIdentifier: String,
    spanSHA256: String,
  ) {
    self.bindingSlug = bindingSlug
    self.rowIdentifier = rowIdentifier
    self.filePath = filePath
    self.extentKind = extentKind
    self.recognizerIdentifier = recognizerIdentifier
    self.spanCanonicalizerIdentifier = spanCanonicalizerIdentifier
    self.spanSHA256 = spanSHA256
  }

  /// The hashed fields of a binding item as written in a proof event; any
  /// other member of the item is ignored. Nil when a hashed field is not a
  /// string.
  public init?(json: JSONValue) {
    guard let bindingSlug = json["binding_slug"]?.stringValue,
          let rowIdentifier = json["row_id"]?.stringValue,
          let filePath = json["file_path"]?.stringValue,
          let extentKind = json["extent_kind"]?.stringValue,
          let recognizerIdentifier = json["recognizer_id"]?.stringValue,
          let spanCanonicalizerIdentifier = json["span_canon_id"]?.stringValue,
          let spanSHA256 = json["span_sha256"]?.stringValue
    else {
      return nil
    }
    self.init(
      bindingSlug: bindingSlug,
      rowIdentifier: rowIdentifier,
      filePath: filePath,
      extentKind: extentKind,
      recognizerIdentifier: recognizerIdentifier,
      spanCanonicalizerIdentifier: spanCanonicalizerIdentifier,
      spanSHA256: spanSHA256,
    )
  }

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("binding_slug", .string(bindingSlug)),
      ("row_id", .string(rowIdentifier)),
      ("file_path", .string(filePath)),
      ("extent_kind", .string(extentKind)),
      ("recognizer_id", .string(recognizerIdentifier)),
      ("span_canon_id", .string(spanCanonicalizerIdentifier)),
      ("span_sha256", .string(spanSHA256)),
    ]))
  }
}

/// `binding_set_hash = sha256(canonical_json(binding_set_material))`
/// (bindingSetHash.ts, spec 4.5).
public enum BindingSetHash {
  /// `{ schema, row_id, bindings }`, with the bindings sorted by slug in
  /// UTF-16 code-unit order (rule 1). Swift's own `String` ordering is
  /// canonical equivalence, under which `"é"` and `"e\u{301}"` are EQUAL; the
  /// TypeScript's `<` is not. Equal slugs keep their input order, as
  /// JavaScript's stable sort keeps them.
  public static func material(
    rowIdentifier: String,
    bindings: [BindingSetMember],
  ) -> JSONValue {
    let sorted = bindings.enumerated().sorted { left, right in
      if JavaScriptString.precedes(left.element.bindingSlug, right.element.bindingSlug) {
        return true
      }
      if JavaScriptString.precedes(right.element.bindingSlug, left.element.bindingSlug) {
        return false
      }
      return left.offset < right.offset
    }
    return .object(JSONObject([
      ("schema", .string(MarkerConstants.bindingSetHashIdentifier)),
      ("row_id", .string(rowIdentifier)),
      ("bindings", .array(sorted.map(\.element.jsonValue))),
    ]))
  }

  public static func compute(
    rowIdentifier: String,
    bindings: [BindingSetMember],
  ) throws(CodeUnitCanonicalJSONError) -> String {
    try CodeUnitCanonicalJSON.sha256(material(rowIdentifier: rowIdentifier, bindings: bindings))
  }
}
