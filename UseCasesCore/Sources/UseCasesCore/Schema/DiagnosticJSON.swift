/// The wire form of a ``Diagnostic``, in the frozen key order.
///
/// `Diagnostic` already encodes itself correctly through `Codable`, but the key
/// ORDER it asks for is lost by Foundation's encoder — so the envelope builds
/// its diagnostics through this instead (see ``JSONWriter``).
extension Diagnostic {
  var jsonValue: JSONValue {
    var object = JSONObject()
    object["code"] = .string(code)
    object["severity"] = .string(severity.rawValue)
    object["message"] = .string(message)
    object["source_path"] = sourcePath.map(JSONValue.string) ?? .null
    object["json_pointer"] = jsonPointer.map(JSONValue.string) ?? .null
    if let sourceSpan {
      object["source_span"] = .object(JSONObject([
        ("start", .object(JSONObject([
          ("line", .number(Double(sourceSpan.start.line))),
          ("column", .number(Double(sourceSpan.start.column))),
        ]))),
        ("end", .object(JSONObject([
          ("line", .number(Double(sourceSpan.end.line))),
          ("column", .number(Double(sourceSpan.end.column))),
        ]))),
      ]))
    }
    object["entity_id"] = entityIdentifier.map(JSONValue.string) ?? .null
    object["related_ids"] = .array(relatedIdentifiers.map(JSONValue.string))
    return .object(object)
  }
}
