/// The first and last line of a link, counted from 1.
struct LineRange: Encodable, Equatable {
  let start: Int
  let end: Int
}
