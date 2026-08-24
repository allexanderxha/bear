// lexer.v — tokenizer for the VuurRaaf source language (.vr).
module compiler

pub enum TokKind {
	eof
	ident
	int_lit
	str_lit
	lparen
	rparen
	lbrace
	rbrace
	lbracket
	rbracket
	comma
	dot
	colon
	plus
	minus
	star
	slash
	percent
	eq_eq
	not_eq
	lt
	le
	gt
	ge
	assign
	dotdot
	dotdotdot
	kw_fn
	kw_struct
	kw_let
	kw_if
	kw_else
	kw_while
	kw_for
	kw_in
	kw_match
	kw_break
	kw_continue
	kw_return
	kw_true
	kw_false
	kw_and
	kw_or
	kw_not
	kw_print
	kw_println
	kw_assert
	kw_import
	kw_enum
}

pub struct Tok {
pub:
	kind TokKind
	lit  string
	line int
}

pub fn tokenize(src string) ![]Tok {
	mut l := Lexer{ src: src }
	mut toks := []Tok{}
	for {
		t := l.next()!
		toks << t
		if t.kind == .eof {
			break
		}
	}
	return toks
}

struct Lexer {
mut:
	src  string
	pos  int
	line int
}

fn (mut l Lexer) peek() u8 {
	if l.pos >= l.src.len {
		return 0
	}
	return l.src[l.pos]
}

fn (mut l Lexer) peek2() u8 {
	if l.pos + 1 >= l.src.len {
		return 0
	}
	return l.src[l.pos + 1]
}

fn (mut l Lexer) advance() u8 {
	c := l.src[l.pos]
	l.pos++
	if c == `\n` {
		l.line++
	}
	return c
}

fn (mut l Lexer) next() !Tok {
	// skip whitespace and // comments
	for l.pos < l.src.len {
		c := l.peek()
		if c == ` ` || c == `\t` || c == `\r` || c == `\n` {
			l.advance()
			continue
		}
		if c == `/` && l.peek2() == `/` {
			for l.pos < l.src.len && l.peek() != `\n` {
				l.advance()
			}
			continue
		}
		break
	}
	line := l.line
	if l.pos >= l.src.len {
		return Tok{ kind: .eof, lit: '', line: line }
	}
	c := l.peek()
	match c {
		`(` {
			l.advance()
			return Tok{ kind: .lparen, lit: '(', line: line }
		}
		`)` {
			l.advance()
			return Tok{ kind: .rparen, lit: ')', line: line }
		}
		`{` {
			l.advance()
			return Tok{ kind: .lbrace, lit: '{', line: line }
		}
		`}` {
			l.advance()
			return Tok{ kind: .rbrace, lit: '}', line: line }
		}
		`[` {
			l.advance()
			return Tok{ kind: .lbracket, lit: '[', line: line }
		}
		`]` {
			l.advance()
			return Tok{ kind: .rbracket, lit: ']', line: line }
		}
		`.` {
			l.advance()
			if l.peek() == `.` {
				l.advance()
				if l.peek() == `.` {
					l.advance()
					return Tok{ kind: .dotdotdot, lit: '...', line: line }
				}
				return Tok{ kind: .dotdot, lit: '..', line: line }
			}
			return Tok{ kind: .dot, lit: '.', line: line }
		}
		`,` {
			l.advance()
			return Tok{ kind: .comma, lit: ',', line: line }
		}
		`:` {
			l.advance()
			return Tok{ kind: .colon, lit: ':', line: line }
		}
		`+` {
			l.advance()
			return Tok{ kind: .plus, lit: '+', line: line }
		}
		`-` {
			l.advance()
			return Tok{ kind: .minus, lit: '-', line: line }
		}
		`*` {
			l.advance()
			return Tok{ kind: .star, lit: '*', line: line }
		}
		`/` {
			l.advance()
			return Tok{ kind: .slash, lit: '/', line: line }
		}
		`%` {
			l.advance()
			return Tok{ kind: .percent, lit: '%', line: line }
		}
		`=` {
			l.advance()
			if l.peek() == `=` {
				l.advance()
				return Tok{ kind: .eq_eq, lit: '==', line: line }
			}
			return Tok{ kind: .assign, lit: '=', line: line }
		}
		`!` {
			l.advance()
			if l.peek() == `=` {
				l.advance()
				return Tok{ kind: .not_eq, lit: '!=', line: line }
			}
			return error('unexpected character "!" at line ${line} (did you mean "not"?)')
		}
		`<` {
			l.advance()
			if l.peek() == `=` {
				l.advance()
				return Tok{ kind: .le, lit: '<=', line: line }
			}
			return Tok{ kind: .lt, lit: '<', line: line }
		}
		`>` {
			l.advance()
			if l.peek() == `=` {
				l.advance()
				return Tok{ kind: .ge, lit: '>=', line: line }
			}
			return Tok{ kind: .gt, lit: '>', line: line }
		}
		`"` {
			return l.lex_string(line)!
		}
		`0`...`9` {
			return l.lex_number(line)
		}
		else {
			if (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || c == `_` {
				return l.lex_ident(line)
			}
			return error('unexpected character "${c.ascii_str()}" at line ${line}')
		}
	}
}

fn (mut l Lexer) lex_number(line int) Tok {
	start := l.pos
	for l.pos < l.src.len && l.peek() >= `0` && l.peek() <= `9` {
		l.advance()
	}
	return Tok{ kind: .int_lit, lit: l.src[start..l.pos], line: line }
}

fn (mut l Lexer) lex_ident(line int) Tok {
	start := l.pos
	for l.pos < l.src.len {
		c := l.peek()
		if (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`) || c == `_` {
			l.advance()
		} else {
			break
		}
	}
	lit := l.src[start..l.pos]
	kind := match lit {
		'fn' { TokKind.kw_fn }
		'struct' { TokKind.kw_struct }
		'let' { TokKind.kw_let }
		'if' { TokKind.kw_if }
		'else' { TokKind.kw_else }
		'while' { TokKind.kw_while }
		'for' { TokKind.kw_for }
		'in' { TokKind.kw_in }
		'match' { TokKind.kw_match }
		'break' { TokKind.kw_break }
		'continue' { TokKind.kw_continue }
		'return' { TokKind.kw_return }
		'true' { TokKind.kw_true }
		'false' { TokKind.kw_false }
		'and' { TokKind.kw_and }
		'or' { TokKind.kw_or }
		'not' { TokKind.kw_not }
		'print' { TokKind.kw_print }
		'println' { TokKind.kw_println }
		'assert' { TokKind.kw_assert }
		'import' { TokKind.kw_import }
		'enum' { TokKind.kw_enum }
		else { TokKind.ident }
	}
	return Tok{ kind: kind, lit: lit, line: line }
}

fn (mut l Lexer) lex_string(line int) !Tok {
	l.advance() // opening quote
	mut s := ''
	for l.pos < l.src.len {
		c := l.advance()
		if c == `"` {
			return Tok{ kind: .str_lit, lit: s, line: line }
		}
		if c == `\\` {
			if l.pos >= l.src.len {
				break
			}
			e := l.advance()
			match e {
				`n` {
					s += '\n'
				}
				`t` {
					s += '\t'
				}
				`"` {
					s += '"'
				}
				`\\` {
					s += '\\'
				}
				else {
					return error('invalid escape \\${e.ascii_str()} at line ${line}')
				}
			}
			continue
		}
		s += c.ascii_str()
	}
	return error('unterminated string at line ${line}')
}
