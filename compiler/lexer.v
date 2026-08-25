// lexer.v — tokenizer for the VuurRaaf source language (.vr).
module compiler

pub fn tokenize(src string) ![]Tok {
	// a script may start with a shebang line (#!...) so it can be executed
	// directly (e.g. `#!/usr/bin/env vr`). Drop it, but keep the trailing
	// newline so error line numbers stay aligned with the file on disk.
	mut s := src
	if s.starts_with('#!') {
		nl := s.index('\n') or { s.len }
		s = s[nl..]
	}
	mut l := Lexer{ src: s, line: 1 }
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
	src        string
	pos        int
	line       int
	line_start int // byte offset where the current line begins
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
		l.line_start = l.pos
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
	col := l.pos - l.line_start + 1 // 1-based column
	if l.pos >= l.src.len {
		return Tok{ kind: .eof, lit: '', line: line, col: col }
	}
	c := l.peek()
	match c {
		`(` {
			l.advance()
			return Tok{ kind: .lparen, lit: '(', line: line, col: col }
		}
		`)` {
			l.advance()
			return Tok{ kind: .rparen, lit: ')', line: line, col: col }
		}
		`{` {
			l.advance()
			return Tok{ kind: .lbrace, lit: '{', line: line, col: col }
		}
		`}` {
			l.advance()
			return Tok{ kind: .rbrace, lit: '}', line: line, col: col }
		}
		`[` {
			l.advance()
			return Tok{ kind: .lbracket, lit: '[', line: line, col: col }
		}
		`]` {
			l.advance()
			return Tok{ kind: .rbracket, lit: ']', line: line, col: col }
		}
		`.` {
			l.advance()
			if l.peek() == `.` {
				l.advance()
				if l.peek() == `.` {
					l.advance()
					return Tok{ kind: .dotdotdot, lit: '...', line: line, col: col }
				}
				return Tok{ kind: .dotdot, lit: '..', line: line, col: col }
			}
			return Tok{ kind: .dot, lit: '.', line: line, col: col }
		}
		`,` {
			l.advance()
			return Tok{ kind: .comma, lit: ',', line: line, col: col }
		}
		`:` {
			l.advance()
			return Tok{ kind: .colon, lit: ':', line: line, col: col }
		}
		`+` {
			l.advance()
			if l.peek() == `=` {
				l.advance()
				return Tok{ kind: .plus_eq, lit: '+=', line: line, col: col }
			}
			return Tok{ kind: .plus, lit: '+', line: line, col: col }
		}
		`-` {
			l.advance()
			if l.peek() == `=` {
				l.advance()
				return Tok{ kind: .minus_eq, lit: '-=', line: line, col: col }
			}
			return Tok{ kind: .minus, lit: '-', line: line, col: col }
		}
		`*` {
			l.advance()
			if l.peek() == `=` {
				l.advance()
				return Tok{ kind: .star_eq, lit: '*=', line: line, col: col }
			}
			return Tok{ kind: .star, lit: '*', line: line, col: col }
		}
		`/` {
			l.advance()
			if l.peek() == `=` {
				l.advance()
				return Tok{ kind: .slash_eq, lit: '/=', line: line, col: col }
			}
			return Tok{ kind: .slash, lit: '/', line: line, col: col }
		}
		`%` {
			l.advance()
			return Tok{ kind: .percent, lit: '%', line: line, col: col }
		}
		`&` {
			l.advance()
			return Tok{ kind: .amp, lit: '&', line: line, col: col }
		}
		`|` {
			l.advance()
			return Tok{ kind: .pipe, lit: '|', line: line, col: col }
		}
		`^` {
			l.advance()
			return Tok{ kind: .caret, lit: '^', line: line, col: col }
		}
		`~` {
			l.advance()
			return Tok{ kind: .tilde, lit: '~', line: line, col: col }
		}
		`=` {
			l.advance()
			if l.peek() == `=` {
				l.advance()
				return Tok{ kind: .eq_eq, lit: '==', line: line, col: col }
			}
			return Tok{ kind: .assign, lit: '=', line: line, col: col }
		}
		`!` {
			l.advance()
			if l.peek() == `=` {
				l.advance()
				return Tok{ kind: .not_eq, lit: '!=', line: line, col: col }
			}
			return error('unexpected character "!" at line ${line}, col ${col} (did you mean "not"?)')
		}
		`<` {
			l.advance()
			if l.peek() == `=` {
				l.advance()
				return Tok{ kind: .le, lit: '<=', line: line, col: col }
			}
			if l.peek() == `<` {
				l.advance()
				return Tok{ kind: .lt_lt, lit: '<<', line: line, col: col }
			}
			return Tok{ kind: .lt, lit: '<', line: line, col: col }
		}
		`>` {
			l.advance()
			if l.peek() == `=` {
				l.advance()
				return Tok{ kind: .ge, lit: '>=', line: line, col: col }
			}
			if l.peek() == `>` {
				l.advance()
				return Tok{ kind: .gt_gt, lit: '>>', line: line, col: col }
			}
			return Tok{ kind: .gt, lit: '>', line: line, col: col }
		}
		`\"` {
			return l.lex_string(line, col)!
		}
		`0`...`9` {
			return l.lex_number(line, col)
		}
		else {
			if (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || c == `_` {
				return l.lex_ident(line, col)
			}
			return error('unexpected character "${c.ascii_str()}" at line ${line}, col ${col}')
		}
	}
}

fn (mut l Lexer) lex_number(line int, col int) Tok {
	start := l.pos
	for l.pos < l.src.len && l.peek() >= `0` && l.peek() <= `9` {
		l.advance()
	}
	mut is_float := false
	// fractional part: `.` followed by a digit (so `1..3` and `1...3` stay ints)
	if l.peek() == `.` && l.pos + 1 < l.src.len && l.peek2() >= `0` && l.peek2() <= `9` {
		is_float = true
		l.advance() // consume `.`
		for l.pos < l.src.len && l.peek() >= `0` && l.peek() <= `9` {
			l.advance()
		}
	}
	// exponent part: e / E followed by optional sign and digits
	if l.peek() == `e` || l.peek() == `E` {
		save := l.pos
		l.advance()
		if l.peek() == `+` || l.peek() == `-` {
			l.advance()
		}
		if l.peek() >= `0` && l.peek() <= `9` {
			is_float = true
			for l.pos < l.src.len && l.peek() >= `0` && l.peek() <= `9` {
				l.advance()
			}
		} else {
			l.pos = save // not an exponent after all
		}
	}
	lit := l.src[start..l.pos]
	if is_float {
		return Tok{ kind: .float_lit, lit: lit, line: line, col: col }
	}
	return Tok{ kind: .int_lit, lit: lit, line: line, col: col }
}

fn (mut l Lexer) lex_ident(line int, col int) Tok {
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
		'const' { TokKind.kw_const }
		'interface' { TokKind.kw_interface }
		'try' { TokKind.kw_try }
		'catch' { TokKind.kw_catch }
		'throw' { TokKind.kw_throw }
		else { TokKind.ident }
	}
	return Tok{ kind: kind, lit: lit, line: line, col: col }
}

fn (mut l Lexer) lex_string(line int, col int) !Tok {
	l.advance() // opening quote
	mut s := ''
	mut has_interp := false
	for l.pos < l.src.len {
		c := l.advance()
		if c == `\"` {
			if has_interp {
				return Tok{ kind: .str_interp, lit: s, line: line, col: col }
			}
			return Tok{ kind: .str_lit, lit: s, line: line, col: col }
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
				`\"` {
					s += '"'
				}
				`\\` {
					s += '\\'
				}
				else {
					return error('invalid escape \\${e.ascii_str()} at line ${line}, col ${col}')
				}
			}
			continue
		}
		if c == `$` && l.peek() == `{` {
			has_interp = true
			s += '\${'
			l.advance() // skip the '{'
			continue
		}
		s += c.ascii_str()
	}
	return error('unterminated string at line ${line}, col ${col}')
}
