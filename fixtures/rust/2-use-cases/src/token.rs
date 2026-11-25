#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TokenKind {
    Number(String),
    Ident(String),
    Plus,
    Minus,
    Star,
    Slash,
    LParen,
    RParen,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Token {
    pub kind: TokenKind,
    pub offset: usize,
}

impl Token {
    pub fn new(kind: TokenKind, offset: usize) -> Self {
        Token { kind, offset }
    }
}
