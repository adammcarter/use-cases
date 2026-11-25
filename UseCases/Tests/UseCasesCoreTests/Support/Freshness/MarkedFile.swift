/// A file that holds one marker region: the marker's target, where the file is, and what is
/// between the sentinel lines.
struct MarkedFile {
  let target: String
  let file: String
  let body: String
}
