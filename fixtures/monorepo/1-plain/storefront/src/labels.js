const SYMBOLS = { GBP: "£", EUR: "€", USD: "$" };

export function formatMoney(pence, currency = "GBP") {
  const symbol = SYMBOLS[currency];
  if (!symbol) throw new RangeError(`unsupported currency ${currency}`);
  const sign = pence < 0 ? "-" : "";
  return `${sign}${symbol}${(Math.abs(pence) / 100).toFixed(2)}`;
}

export function savingsLabel(fullPence, paidPence, currency = "GBP") {
  const saved = fullPence - paidPence;
  if (saved <= 0) return "";
  const percent = Math.round((saved / fullPence) * 100);
  return `You save ${formatMoney(saved, currency)} (${percent}%)`;
}
