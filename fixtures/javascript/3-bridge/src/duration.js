const UNITS = { d: 86_400_000, h: 3_600_000, m: 60_000, s: 1_000, ms: 1 };
const PART = /(\d+(?:\.\d+)?)\s*(ms|d|h|m|s)/gy;

// @use-case:duration.text.parse#parser
export function parse(text) {
  const input = text.trim();
  if (input === "") throw new SyntaxError("empty duration");
  let total = 0;
  let index = 0;
  PART.lastIndex = 0;
  while (index < input.length) {
    while (input[index] === " ") index++;
    PART.lastIndex = index;
    const match = PART.exec(input);
    if (!match) throw new SyntaxError(`unexpected "${input.slice(index)}"`);
    total += Number(match[1]) * UNITS[match[2]];
    index = PART.lastIndex;
  }
  return Math.round(total);
// @use-case:end duration.text.parse#parser
}

// @use-case:duration.text.format#formatter
export function format(ms) {
  if (!Number.isFinite(ms) || ms < 0) throw new RangeError("duration must be a non-negative number");
  if (ms === 0) return "0s";
  const parts = [];
  let rest = ms;
  for (const unit of ["d", "h", "m", "s"]) {
    const size = UNITS[unit];
    if (rest >= size) {
      parts.push(`${Math.floor(rest / size)}${unit}`);
      rest %= size;
    }
  }
  if (rest > 0) parts.push(`${rest}ms`);
  return parts.join(" ");
// @use-case:end duration.text.format#formatter
}
