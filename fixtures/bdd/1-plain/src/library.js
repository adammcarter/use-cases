export const LOAN_DAYS = 14;
export const MAX_LOANS = 3;
export const FINE_PER_DAY = 20; // pence

const DAY = 24 * 60 * 60 * 1000;

export class LoanError extends Error {}

export class Library {
  constructor() {
    this.books = new Map();
    this.loans = [];
  }

  addBook(isbn, title, copies = 1) {
    this.books.set(isbn, { isbn, title, copies });
    return this;
  }

  available(isbn) {
    const book = this.books.get(isbn);
    if (!book) return 0;
    return book.copies - this.loans.filter((loan) => loan.isbn === isbn).length;
  }

  loansFor(member) {
    return this.loans.filter((loan) => loan.member === member);
  }

  borrow(member, isbn, today) {
    if (!this.books.has(isbn)) throw new LoanError(`unknown book ${isbn}`);
    if (this.loansFor(member).length >= MAX_LOANS) {
      throw new LoanError(`${member} already has ${MAX_LOANS} books`);
    }
    if (this.available(isbn) === 0) throw new LoanError(`no copies of ${isbn} left`);
    const loan = { member, isbn, due: new Date(today.getTime() + LOAN_DAYS * DAY) };
    this.loans.push(loan);
    return loan;
  }

  giveBack(member, isbn, today) {
    const index = this.loans.findIndex((loan) => loan.member === member && loan.isbn === isbn);
    if (index === -1) throw new LoanError(`${member} has not borrowed ${isbn}`);
    const [loan] = this.loans.splice(index, 1);
    return { fine: fineFor(loan.due, today) };
  }
}

export function fineFor(due, returned) {
  const late = Math.ceil((returned.getTime() - due.getTime()) / DAY);
  return late > 0 ? late * FINE_PER_DAY : 0;
}
