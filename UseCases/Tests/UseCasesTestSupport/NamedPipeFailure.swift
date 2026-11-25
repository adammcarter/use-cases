/// A named pipe that could not be made or opened: the call that failed, on which path, and the
/// system's error number.
public struct NamedPipeFailure: Error, Equatable {
  public let call: String
  public let path: String
  public let errorNumber: Int32
}
