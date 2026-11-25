extension AuthoredObject {
  /// Every manual binding under the key; an absent list is an empty one.
  func manualBindings(_ key: String) throws(AuthoredShapeError) -> [ManualBinding] {
    var bindings: [ManualBinding] = []

    for object in try objects(key) {
      try bindings.append(ManualBinding(authored: object))
    }

    return bindings
  }
}
