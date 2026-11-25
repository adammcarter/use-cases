/// What a typed id found among the ids there are: the id itself, the one id it starts, several
/// ids it starts, or nothing.
enum PrefixMatch<Item> {
  case found(Item)
  case several([String])
  case none
}
