/// The JSON type of a tool argument, which is what an agent can send.
enum ToolArgumentType: Equatable, Sendable {
  case string
  case integer
  case boolean
  case stringList
  case object
  case objectList
}
