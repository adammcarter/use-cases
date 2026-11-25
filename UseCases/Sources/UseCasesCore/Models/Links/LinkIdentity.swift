/// The binding a link belongs to: its use case, its route when it is a validation link, and its
/// binding id (chapter 05 "Derived marker identities").
///
/// One identity has one source (chapter 08 "Binding ID uniqueness"): a manual binding or markers,
/// never both. Many marker regions may share one identity.
struct LinkIdentity: Hashable, Sendable {
  let useCase: UseCaseIdentifier

  /// The route of a validation link; `nil` for an implementation link.
  let route: RouteIdentifier?
  let binding: BindingIdentifier

  /// Placement is the role: a link under a route is a validation link.
  var role: LinkRole {
    route == nil ? .implementation : .validation
  }

  /// `<use-case-id>#[<route-id>.]<binding-id>`: the front of a link key.
  var keyPrefix: String {
    guard let route else {
      return "\(useCase.text)#\(binding.text)"
    }

    return "\(useCase.text)#\(route.text).\(binding.text)"
  }

  /// How a message names the binding.
  var subject: String {
    guard let route else {
      return "binding '\(binding.text)' of use case '\(useCase.text)'"
    }

    return "binding '\(binding.text)' of route '\(route.text)' of use case '\(useCase.text)'"
  }
}
