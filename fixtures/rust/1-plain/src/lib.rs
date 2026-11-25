//! Tokenizer for a small arithmetic expression language.

mod token;

pub use token::{Token, TokenKind};

#[derive(Debug, PartialEq, Eq)]
pub struct LexError {
    pub offset: usize,
    pub found: char,
}

pub fn tokenize(input: &str) -> Result<Vec<Token>, LexError> {
    let mut tokens = Vec::new();
    let chars: Vec<(usize, char)> = input.char_indices().collect();
    let mut i = 0;
    while i < chars.len() {
        let (offset, c) = chars[i];
        if c.is_whitespace() {
            i += 1;
            continue;
        }
        if c.is_ascii_digit() || (c == '.' && next_is_digit(&chars, i)) {
            let start = i;
            while i < chars.len() && (chars[i].1.is_ascii_digit() || chars[i].1 == '.') {
                i += 1;
            }
            let text: String = chars[start..i].iter().map(|(_, c)| *c).collect();
            tokens.push(Token::new(TokenKind::Number(text), offset));
            continue;
        }
        if c.is_alphabetic() || c == '_' {
            let start = i;
            while i < chars.len() && (chars[i].1.is_alphanumeric() || chars[i].1 == '_') {
                i += 1;
            }
            let text: String = chars[start..i].iter().map(|(_, c)| *c).collect();
            tokens.push(Token::new(TokenKind::Ident(text), offset));
            continue;
        }
        let kind = match c {
            '+' => TokenKind::Plus,
            '-' => TokenKind::Minus,
            '*' => TokenKind::Star,
            '/' => TokenKind::Slash,
            '(' => TokenKind::LParen,
            ')' => TokenKind::RParen,
            other => return Err(LexError { offset, found: other }),
        };
        tokens.push(Token::new(kind, offset));
        i += 1;
    }
    Ok(tokens)
}

fn next_is_digit(chars: &[(usize, char)], i: usize) -> bool {
    chars.get(i + 1).map(|(_, c)| c.is_ascii_digit()).unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kinds(input: &str) -> Vec<TokenKind> {
        tokenize(input).unwrap().into_iter().map(|t| t.kind).collect()
    }

    #[test]
    fn empty_input_has_no_tokens() {
        assert!(tokenize("").unwrap().is_empty());
        assert!(tokenize("   \t\n").unwrap().is_empty());
    }

    #[test]
    fn numbers_include_decimals() {
        assert_eq!(kinds("3.14 .5"), vec![TokenKind::Number("3.14".into()), TokenKind::Number(".5".into())]);
    }

    #[test]
    fn identifiers_may_contain_underscores_and_digits() {
        assert_eq!(kinds("rate_2"), vec![TokenKind::Ident("rate_2".into())]);
    }

    #[test]
    fn unknown_characters_report_their_offset() {
        assert_eq!(tokenize("1 + $"), Err(LexError { offset: 4, found: '$' }));
    }

    #[test]
    #[ignore = "unicode operators are not supported yet"]
    fn multiplication_sign_is_an_operator() {
        assert_eq!(kinds("2 × 3").len(), 3);
    }
}
