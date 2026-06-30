// Physical line splitting with both JS-char and UTF-8 byte offsets.
//
// Shared by the explicit-span scanner (which needs UTF-8 byte offsets for span
// byte ranges, spec 4.4) and the Swift function recognizer (which lexes in
// JS-char space but must report UTF-8 byte offsets, spec 9.3). Both consumers
// split lines identically, so line index `i` denotes the same physical line in
// either coordinate system.

export interface PhysicalLine {
  text: string; // line content, terminator excluded
  charStart: number; // JS string index of the first char of the line
  charEnd: number; // JS string index just past the line terminator
  byteStart: number; // UTF-8 byte offset of the first byte of the line
  byteEnd: number; // UTF-8 byte offset just past the line terminator
}

// Split content into physical lines with char and UTF-8 byte offsets. Handles
// LF, CR and CRLF terminators; a file ending in a terminator does not yield a
// trailing empty line, while an interior blank line is preserved.
export function splitPhysicalLines(content: string): PhysicalLine[] {
  const lines: PhysicalLine[] = [];
  const n = content.length;
  let pos = 0;
  let byteStart = 0;
  while (pos < n) {
    let eol = pos;
    while (eol < n && content[eol] !== "\n" && content[eol] !== "\r") {
      eol += 1;
    }
    const text = content.slice(pos, eol);
    let termLen = 0;
    if (eol < n) {
      termLen = content[eol] === "\r" && content[eol + 1] === "\n" ? 2 : 1;
    }
    const charStart = pos;
    const charEnd = eol + termLen;
    const textBytes = Buffer.byteLength(text, "utf8");
    // CR / LF / CRLF are all ASCII, so terminator bytes == terminator length.
    const byteEnd = byteStart + textBytes + termLen;
    lines.push({ text, charStart, charEnd, byteStart, byteEnd });
    byteStart = byteEnd;
    pos = charEnd;
  }
  return lines;
}

// Map a JS-char position to the index of the physical line that contains it.
// Returns -1 if the position is past the end of the content. A position that
// falls on a line terminator belongs to the line it terminates.
export function lineIndexOfChar(lines: ReadonlyArray<PhysicalLine>, charPos: number): number {
  for (let i = 0; i < lines.length; i += 1) {
    if (charPos >= lines[i].charStart && charPos < lines[i].charEnd) {
      return i;
    }
  }
  return -1;
}
