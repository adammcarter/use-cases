/// What a marker names: a use case and one of its bindings, or one of its routes' bindings
/// (chapter 05 "Derived marker identities").
///
/// ```text
/// <use-case-id>#<binding-id>             an implementation link
/// <use-case-id>#<route-id>.<binding-id>  a validation link for that route
/// ```
///
/// Reading a target judges the grammar only. Whether the use case or the route exists is for
/// whoever knows the use cases.
struct MarkerTarget: Hashable, Sendable, CustomStringConvertible {
  let useCase: UseCaseIdentifier

  /// The route a validation marker names; `nil` for an implementation marker.
  let route: RouteIdentifier?
  let binding: BindingIdentifier

  /// Reads the id written after a sentinel, refusing anything off the marker grammar.
  init(parsing text: String) throws(MarkerTargetError) {
    guard !text.isEmpty else {
      throw .empty
    }

    let halves = text.split(
      separator: "#",
      omittingEmptySubsequences: false,
    )

    guard halves.count >= 2 else {
      throw .missingSeparator
    }

    guard halves.count == 2 else {
      throw .severalSeparators
    }

    let pieces = halves[1].split(
      separator: ".",
      omittingEmptySubsequences: false,
    )

    guard pieces.count <= 2 else {
      throw .tooManyPiecesAfterSeparator
    }

    do {
      useCase = try UseCaseIdentifier(validating: String(halves[0]))
    } catch {
      throw .invalidUseCase(error)
    }

    if pieces.count == 2 {
      do {
        route = try RouteIdentifier(validating: String(pieces[0]))
      } catch {
        throw .invalidRoute(error)
      }
    } else {
      route = nil
    }

    do {
      binding = try BindingIdentifier(validating: String(pieces[pieces.count - 1]))
    } catch {
      throw .invalidBinding(error)
    }
  }

  /// The id as it is written in a marker.
  var text: String {
    guard let route else {
      return "\(useCase.text)#\(binding.text)"
    }

    return "\(useCase.text)#\(route.text).\(binding.text)"
  }

  var description: String {
    text
  }
}
