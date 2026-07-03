pub fn eval(expr: &str) -> Option<String> {
    let expr = expr.trim();
    if expr.is_empty() { return None }
    let tokens = tokenize(expr)?;
    let mut slice = tokens.as_slice();
    let result = parse_expr(&mut slice)?;
    if !slice.is_empty() { return None }
    Some(format_result(result))
}

#[derive(Clone, Debug)]
enum Token {
    Num(f64),
    Add, Sub, Mul, Div,
    LParen, RParen,
}

fn tokenize(s: &str) -> Option<Vec<Token>> {
    let mut tokens = Vec::new();
    let mut chars = s.chars().peekable();
    while let Some(&c) = chars.peek() {
        if c.is_whitespace() { chars.next(); continue }
        if c.is_ascii_digit() || c == '.' {
            let mut num = String::new();
            while let Some(&c) = chars.peek() {
                if c.is_ascii_digit() || c == '.' { num.push(c); chars.next(); }
                else { break }
            }
            tokens.push(Token::Num(num.parse().ok()?));
        } else {
            match c {
                '+' => tokens.push(Token::Add),
                '-' => tokens.push(Token::Sub),
                '*' => tokens.push(Token::Mul),
                '/' => tokens.push(Token::Div),
                '(' => tokens.push(Token::LParen),
                ')' => tokens.push(Token::RParen),
                _ => return None,
            }
            chars.next();
        }
    }
    Some(tokens)
}

fn parse_expr(tokens: &mut &[Token]) -> Option<f64> {
    let mut left = parse_term(tokens)?;
    while let Some(token) = tokens.first() {
        match token {
            Token::Add => { *tokens = &tokens[1..]; left += parse_term(tokens)?; }
            Token::Sub => { *tokens = &tokens[1..]; left -= parse_term(tokens)?; }
            _ => break,
        }
    }
    Some(left)
}

fn parse_term(tokens: &mut &[Token]) -> Option<f64> {
    let mut left = parse_factor(tokens)?;
    while let Some(token) = tokens.first() {
        match token {
            Token::Mul => { *tokens = &tokens[1..]; left *= parse_factor(tokens)?; }
            Token::Div => { *tokens = &tokens[1..]; let right = parse_factor(tokens)?; if right == 0.0 { return None } left /= right; }
            _ => break,
        }
    }
    Some(left)
}

fn parse_factor(tokens: &mut &[Token]) -> Option<f64> {
    if let Some(Token::LParen) = tokens.first() {
        *tokens = &tokens[1..];
        let val = parse_expr(tokens)?;
        if !matches!(tokens.first(), Some(Token::RParen)) { return None }
        *tokens = &tokens[1..];
        Some(val)
    } else if let Some(Token::Sub) = tokens.first() {
        *tokens = &tokens[1..];
        Some(-parse_factor(tokens)?)
    } else {
        match tokens.first()? {
            Token::Num(n) => { *tokens = &tokens[1..]; Some(*n) }
            _ => None,
        }
    }
}

fn format_result(n: f64) -> String {
    if n.fract() == 0.0 && n.is_finite() {
        format!("{}", n as i64)
    } else if n.is_infinite() {
        "Infinity".into()
    } else if n.is_nan() {
        "NaN".into()
    } else {
        format!("{:.6}", n).trim_end_matches('0').trim_end_matches('.').to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn basic() { assert_eq!(eval("1+2"), Some("3".into())); }
    #[test]
    fn complex() { assert_eq!(eval("2 * (3 + 4)"), Some("14".into())); }
    #[test]
    fn div() { assert_eq!(eval("10/3"), Some("3.333333".into())); }
    #[test]
    fn neg() { assert_eq!(eval("-5+3"), Some("-2".into())); }
    #[test]
    fn invalid() { assert_eq!(eval("1/0"), None); }
}
