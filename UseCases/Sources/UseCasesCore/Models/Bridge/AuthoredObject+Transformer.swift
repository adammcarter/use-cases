extension AuthoredObject {
  func requiredTransformer(_ key: String) throws(AuthoredShapeError) -> TransformerReference {
    let text = try requiredString(key)

    do {
      return try TransformerReference(text: text)
    } catch {
      throw .invalidPath(
        location: location(of: key),
        error,
      )
    }
  }
}
