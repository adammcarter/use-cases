/// The order-sensitive fold behind ``BindingRegistry/validate(_:yamlRowIdentifiers:)``.
struct RegistryFold {
  var errors: [RegistryError] = []
  var events: [RegistryEvent] = []
  var registry = MaterializedRegistry()
  /// Where each LIVE slug was registered, for the row check after the fold.
  var registeredAtLine = OrderedStringMap<Int>()

  mutating func apply(_ entry: RegistryLine) {
    let schema = MarkerSchemaValidation.validateBindingRegistryEvent(entry.value)
    guard schema.isValid, let event = Self.event(from: entry.value) else {
      errors.append(RegistryError(
        code: .registrySchemaInvalid,
        line: entry.line,
        message: "registry event failed schema: \(schema.joinedMessage)",
      ))
      return
    }
    let slug = event.bindingSlug
    let row = event.rowIdentifier
    let prefix = MarkerSlug.split(slug)?.rowIdentifier
    guard let prefix, JavaScriptString.identical(prefix, row) else {
      errors.append(RegistryError(
        code: .slugPrefixMismatch,
        line: entry.line,
        message: "binding_slug \(slug) has row prefix \(prefix ?? "<invalid>") "
          + "but row_id is \(row)",
        bindingSlug: slug,
        rowIdentifier: row,
      ))
      return
    }
    switch event.eventType {
    case .bindingReleased:
      release(event, line: entry.line)
    case .bindingRegistered:
      register(event, line: entry.line)
    }
  }

  private mutating func release(
    _ event: RegistryEvent,
    line: Int,
  ) {
    guard registry.rowIdentifier(forSlug: event.bindingSlug) != nil else {
      errors.append(RegistryError(
        code: .releaseWithoutRegistration,
        line: line,
        message: "binding_slug \(event.bindingSlug) is not currently registered, "
          + "so it cannot be released",
        bindingSlug: event.bindingSlug,
        rowIdentifier: event.rowIdentifier,
      ))
      return
    }
    registry.release(event.bindingSlug)
    registeredAtLine[event.bindingSlug] = nil
    events.append(event)
  }

  private mutating func register(
    _ event: RegistryEvent,
    line: Int,
  ) {
    let slug = event.bindingSlug
    let row = event.rowIdentifier
    if let existing = registry.rowIdentifier(forSlug: slug) {
      let conflicting = !JavaScriptString.identical(existing, row)
      errors.append(RegistryError(
        code: conflicting ? .slugRowConflict : .duplicateRegistration,
        line: line,
        message: conflicting
          ? "binding_slug \(slug) already registered to \(existing); cannot reassign to \(row)"
          : "binding slug \(slug) is already registered; re-point it with `use-cases rebind` "
          + "or release it with `use-cases unbind`",
        bindingSlug: slug,
        rowIdentifier: row,
      ))
      return
    }
    registry.register(slug, to: row)
    registeredAtLine[slug] = line
    events.append(event)
  }

  /// The typed essentials of a schema-valid event.
  private static func event(from value: JSONValue) -> RegistryEvent? {
    guard let typeText = value["event_type"]?.stringValue,
          let eventType = RegistryEventType(rawValue: typeText),
          let row = value["row_id"]?.stringValue,
          let slug = value["binding_slug"]?.stringValue
    else {
      return nil
    }
    return RegistryEvent(eventType: eventType, rowIdentifier: row, bindingSlug: slug, json: value)
  }
}
