use exprlex::{tokenize, TokenKind};

#[test]
fn full_expression_keeps_order_and_offsets() {
    let tokens = tokenize("(price + 2) * qty").unwrap();
    let offsets: Vec<usize> = tokens.iter().map(|t| t.offset).collect();
    assert_eq!(offsets, vec![0, 1, 7, 9, 10, 12, 14]);
    assert_eq!(tokens[0].kind, TokenKind::LParen);
    assert_eq!(tokens[6].kind, TokenKind::Ident("qty".into()));
}

#[test]
fn operators_need_no_spaces() {
    assert_eq!(tokenize("1+2-3*4/5").unwrap().len(), 9);
}
