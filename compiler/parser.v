// parser.v — recursive-descent parser for the VuurRaaf language.
//
// Grammar (informal):
//   program  := fn*
//   fn       := 'fn' IDENT '(' [IDENT (',' IDENT)*] ')' block
//   block    := '{' stmt* '}'
//   stmt     := 'let' IDENT '=' expr
//             | IDENT '=' expr
//             | postfix '=' expr            (a[i] = v)
//             | 'if' cond block ['else' ('if' ... | block)]
//             | 'match' expr '{' (expr block | 'else' block)* '}'
//             | 'while' cond block
//             | 'for' IDENT 'in' range block        (range := expr '..' expr | expr '...' expr)
//             | 'for' IDENT 'in' expr block          (iterate an array)
//             | 'break' | 'continue'
//             | 'return' [expr]
//             | 'assert' expr
//             | expr
//   cond     := ['('] expr [')']   // parens optional
//   expr     := or ('or' or)*
//   or       := and ('and' and)*
//   and      := eq (('=='|'!=') eq)*
//   eq       := rel (('<'|'<='|'>'|'>=') rel)*
//   rel      := add (('+'|'-') add)*
//   add      := mul (('*'|'/'|'%') mul)*
//   mul      := ('not'|'-') mul | primary
//   primary  := INT | STR | 'true' | 'false' | IDENT ['(' args ')'] | '(' expr ')'
module compiler

pub enum ExprKind {
	int_lit
	str_lit
	bool_lit
	ident
	array_lit
	index
	unary
	binary
	call
}

pub struct Expr {
pub mut:
	kind  ExprKind
	int_v i64
	str_v string
	name  string
	op    TokKind
	left  &Expr = unsafe { nil }
	right &Expr = unsafe { nil }
	elems []Expr
	args  []Expr
	line  int
}

pub enum StmtKind {
	expr_stmt
	let_stmt
	assign_stmt
	index_assign
	if_stmt
	match_stmt
	while_stmt
	for_range_stmt
	for_in_stmt
	break_stmt
	continue_stmt
	ret_stmt
	assert_stmt
}

// MatchArm is a single `value { body }` arm of a match statement.
pub struct MatchArm {
pub mut:
	val  Expr
	body []Stmt
}

pub struct Stmt {
pub mut:
	kind      StmtKind
	target    string
	expr      Expr
	cond      Expr
	base      Expr // index_assign: the indexed expression
	idx       Expr // index_assign: the index expression
	body      []Stmt
	els       []Stmt
	arms      []MatchArm // match_stmt: the arms (val + body)
	has_else  bool       // match_stmt: a trailing else arm exists
	els_body  []Stmt     // match_stmt: body of the else arm
	has_val   bool
	inclusive bool // for_range_stmt: `..` (false) vs `...` (true)
	line      int
}

pub struct FnDecl {
pub mut:
	name   string
	params []string
	body   []Stmt
	line   int
}

pub struct Program {
pub mut:
	fns []FnDecl
}

pub fn parse(toks []Tok) !Program {
	mut p := Parser{ toks: toks }
	return p.parse_program()
}

struct Parser {
mut:
	toks []Tok
	pos  int
}

fn (mut p Parser) cur() Tok {
	if p.pos < p.toks.len {
		return p.toks[p.pos]
	}
	return p.toks[p.toks.len - 1]
}

fn (mut p Parser) advance() Tok {
	t := p.cur()
	if p.pos < p.toks.len - 1 {
		p.pos++
	}
	return t
}

fn (mut p Parser) expect(k TokKind, what string) !Tok {
	t := p.cur()
	if t.kind != k {
		return error('expected ${what}, got "${t.lit}" at line ${t.line}')
	}
	return p.advance()
}

// parse_cond parses a condition, accepting either `if cond {` or `if (cond) {`.
fn (mut p Parser) parse_cond() !Expr {
	if p.cur().kind == .lparen {
		p.advance()
		e := p.parse_expr()!
		p.expect(.rparen, "')'")!
		return e
	}
	return p.parse_expr()!
}

fn (mut p Parser) parse_program() !Program {
	mut prog := Program{}
	for p.cur().kind != .eof {
		prog.fns << p.parse_fn()!
	}
	if prog.fns.len == 0 {
		return error('no functions found in source')
	}
	return prog
}

fn (mut p Parser) parse_fn() !FnDecl {
	fn_tok := p.expect(.kw_fn, "'fn'")!
	name := p.expect(.ident, 'function name')!
	p.expect(.lparen, "'('")!
	mut params := []string{}
	if p.cur().kind != .rparen {
		for {
			params << p.expect(.ident, 'parameter name')!.lit
			if p.cur().kind == .comma {
				p.advance()
				continue
			}
			break
		}
	}
	p.expect(.rparen, "')'")!
	body := p.parse_block()!
	return FnDecl{ name: name.lit, params: params, body: body, line: fn_tok.line }
}

fn (mut p Parser) parse_block() ![]Stmt {
	p.expect(.lbrace, "'{'")!
	mut stmts := []Stmt{}
	for p.cur().kind != .rbrace {
		if p.cur().kind == .eof {
			return error('unexpected end of file inside block (missing "}")')
		}
		stmts << p.parse_stmt()!
	}
	p.expect(.rbrace, "'}'")!
	return stmts
}

fn (mut p Parser) parse_stmt() !Stmt {
	t := p.cur()
	match t.kind {
		.kw_let {
			p.advance()
			name := p.expect(.ident, 'variable name')!
			p.expect(.assign, "'='")!
			e := p.parse_expr()!
			return Stmt{ kind: .let_stmt, target: name.lit, expr: e, line: t.line }
		}		.kw_if {
			return p.parse_if(t)!
		}
		.kw_match {
			p.advance()
			subject := p.parse_expr()!
			p.expect(.lbrace, "'{'")!
			mut arms := []MatchArm{}
			mut has_else := false
			mut els_body := []Stmt{}
			for p.cur().kind != .rbrace {
				if p.cur().kind == .eof {
					return error('unexpected end of file inside match (missing "}")')
				}
				if p.cur().kind == .kw_else {
					p.advance()
					els_body = p.parse_block()!
					has_else = true
					continue
				}
				val := p.parse_expr()!
				body := p.parse_block()!
				arms << MatchArm{ val: val, body: body }
			}
			p.expect(.rbrace, "'}'")!
			return Stmt{ kind: .match_stmt, expr: subject, arms: arms, has_else: has_else, els_body: els_body, line: t.line }
		}
		.kw_while {
			p.advance()
			cond := p.parse_cond()!
			body := p.parse_block()!
			return Stmt{ kind: .while_stmt, cond: cond, body: body, line: t.line }
		}
		.kw_for {
			p.advance()
			name := p.expect(.ident, 'loop variable')!
			p.expect(.kw_in, "'in'")!
			first := p.parse_expr()!
			if p.cur().kind == .dotdot || p.cur().kind == .dotdotdot {
				inclusive := p.cur().kind == .dotdotdot
				p.advance()
				end := p.parse_expr()!
				body := p.parse_block()!
				return Stmt{ kind: .for_range_stmt, target: name.lit, expr: first, cond: end, inclusive: inclusive, body: body, line: t.line }
			}
			body := p.parse_block()!
			return Stmt{ kind: .for_in_stmt, target: name.lit, expr: first, body: body, line: t.line }
		}
		.kw_return {
			p.advance()
			mut e := Expr{}
			has_val := p.cur().kind != .rbrace
			if has_val {
				e = p.parse_expr()!
			}
			return Stmt{ kind: .ret_stmt, expr: e, has_val: has_val, line: t.line }
		}
		.kw_break {
			p.advance()
			return Stmt{ kind: .break_stmt, line: t.line }
		}
		.kw_continue {
			p.advance()
			return Stmt{ kind: .continue_stmt, line: t.line }
		}		.kw_assert {
			p.advance()
			mut e := Expr{}
			if p.cur().kind == .lparen {
				p.advance()
				e = p.parse_expr()!
				p.expect(.rparen, "')'")!
			} else {
				e = p.parse_expr()!
			}
			return Stmt{ kind: .assert_stmt, expr: e, line: t.line }
		}
		.ident {
			p.advance()
			if p.cur().kind == .assign {
				p.advance()
				e := p.parse_expr()!
				return Stmt{ kind: .assign_stmt, target: t.lit, expr: e, line: t.line }
			}
			if p.cur().kind == .lbracket {
				// a[i] = v  or  a[i] (expression statement)
				e := p.parse_index_chain(t)!
				if p.cur().kind == .assign {
					p.advance()
					rhs := p.parse_expr()!
					return Stmt{ kind: .index_assign, base: *e.left, idx: *e.right, expr: rhs, line: t.line }
				}
				return Stmt{ kind: .expr_stmt, expr: e, line: t.line }
			}
			e := p.parse_call_or_ident(t)!
			return Stmt{ kind: .expr_stmt, expr: e, line: t.line }
		}
		.kw_print, .kw_println {
			p.advance()
			e := p.parse_call(t)!
			return Stmt{ kind: .expr_stmt, expr: e, line: t.line }
		}
		else {
			return error('unexpected token "${t.lit}" at line ${t.line}')
		}
	}
}

// parse_if parses `if cond block ['else' ('if' ... | block)]`. An `else if`
// chain is represented by putting the nested if-statement in the else list,
// so codegen needs no special casing.
fn (mut p Parser) parse_if(t Tok) !Stmt {
	p.advance()
	cond := p.parse_cond()!
	body := p.parse_block()!
	mut els := []Stmt{}
	if p.cur().kind == .kw_else {
		p.advance()
		if p.cur().kind == .kw_if {
			els << p.parse_if(p.cur())!
		} else {
			els = p.parse_block()!
		}
	}
	return Stmt{ kind: .if_stmt, cond: cond, body: body, els: els, line: t.line }
}

// bin_node allocates a binary-operator node. It takes copies of the operands
// so that `&l`/`&r` target fresh heap objects (taking the address of a local
// that is later reassigned would create a self-referential node).
fn bin_node(op TokKind, left Expr, right Expr, line int) Expr {
	mut l := left
	mut r := right
	return Expr{ kind: .binary, op: op, left: &l, right: &r, line: line }
}

fn unary_node(op TokKind, operand Expr, line int) Expr {
	mut o := operand
	return Expr{ kind: .unary, op: op, right: &o, line: line }
}

// index_node builds `base[idx]`.
fn index_node(base Expr, idx Expr, line int) Expr {
	mut b := base
	mut i := idx
	return Expr{ kind: .index, left: &b, right: &i, line: line }
}

fn (mut p Parser) parse_expr() !Expr {
	return p.parse_or()!
}

fn (mut p Parser) parse_or() !Expr {
	mut e := p.parse_and()!
	for p.cur().kind == .kw_or {
		op := p.advance()
		rhs := p.parse_and()!
		e = bin_node(op.kind, e, rhs, op.line)
	}
	return e
}

fn (mut p Parser) parse_and() !Expr {
	mut e := p.parse_eq()!
	for p.cur().kind == .kw_and {
		op := p.advance()
		rhs := p.parse_eq()!
		e = bin_node(op.kind, e, rhs, op.line)
	}
	return e
}

fn (mut p Parser) parse_eq() !Expr {
	mut e := p.parse_rel()!
	for p.cur().kind == .eq_eq || p.cur().kind == .not_eq {
		op := p.advance()
		rhs := p.parse_rel()!
		e = bin_node(op.kind, e, rhs, op.line)
	}
	return e
}

fn (mut p Parser) parse_rel() !Expr {
	mut e := p.parse_add()!
	for p.cur().kind == .lt || p.cur().kind == .le || p.cur().kind == .gt || p.cur().kind == .ge {
		op := p.advance()
		rhs := p.parse_add()!
		e = bin_node(op.kind, e, rhs, op.line)
	}
	return e
}

fn (mut p Parser) parse_add() !Expr {
	mut e := p.parse_mul()!
	for p.cur().kind == .plus || p.cur().kind == .minus {
		op := p.advance()
		rhs := p.parse_mul()!
		e = bin_node(op.kind, e, rhs, op.line)
	}
	return e
}

fn (mut p Parser) parse_mul() !Expr {
	mut e := p.parse_unary()!
	for p.cur().kind == .star || p.cur().kind == .slash || p.cur().kind == .percent {
		op := p.advance()
		rhs := p.parse_unary()!
		e = bin_node(op.kind, e, rhs, op.line)
	}
	return e
}

fn (mut p Parser) parse_unary() !Expr {
	t := p.cur()
	if t.kind == .kw_not || t.kind == .minus {
		p.advance()
		e := p.parse_unary()!
		return unary_node(t.kind, e, t.line)
	}
	return p.parse_postfix()!
}

// parse_postfix handles indexing: `base[expr]`, possibly chained `a[i][j]`.
fn (mut p Parser) parse_postfix() !Expr {
	mut e := p.parse_primary()!
	for p.cur().kind == .lbracket {
		p.advance()
		idx := p.parse_expr()!
		p.expect(.rbracket, "']'")!
		e = index_node(e, idx, e.line)
	}
	return e
}

// parse_index_chain is like parse_postfix but starts from an already-consumed
// identifier token (used for statements like `a[i] = v`).
fn (mut p Parser) parse_index_chain(t Tok) !Expr {
	mut e := Expr{ kind: .ident, name: t.lit, line: t.line }
	for p.cur().kind == .lbracket {
		p.advance()
		idx := p.parse_expr()!
		p.expect(.rbracket, "']'")!
		e = index_node(e, idx, t.line)
	}
	return e
}

fn (mut p Parser) parse_primary() !Expr {
	t := p.cur()
	match t.kind {
		.int_lit {
			p.advance()
			return Expr{ kind: .int_lit, int_v: t.lit.i64(), line: t.line }
		}
		.str_lit {
			p.advance()
			return Expr{ kind: .str_lit, str_v: t.lit, line: t.line }
		}
		.kw_true {
			p.advance()
			return Expr{ kind: .bool_lit, int_v: 1, line: t.line }
		}
		.kw_false {
			p.advance()
			return Expr{ kind: .bool_lit, int_v: 0, line: t.line }
		}
		.lparen {
			p.advance()
			e := p.parse_expr()!
			p.expect(.rparen, "')'")!
			return e
		}
		.lbracket {
			p.advance()
			mut elems := []Expr{}
			if p.cur().kind != .rbracket {
				for {
					elems << p.parse_expr()!
					if p.cur().kind == .comma {
						p.advance()
						continue
					}
					break
				}
			}
			p.expect(.rbracket, "']'")!
			return Expr{ kind: .array_lit, elems: elems, line: t.line }
		}
		.ident {
			p.advance()
			return p.parse_call_or_ident(t)!
		}
		.kw_print, .kw_println {
			p.advance()
			return p.parse_call(t)!
		}
		else {
			return error('unexpected token "${t.lit}" at line ${t.line}')
		}
	}
}

fn (mut p Parser) parse_call_or_ident(t Tok) !Expr {
	if p.cur().kind == .lparen {
		return p.parse_call(t)!
	}
	return Expr{ kind: .ident, name: t.lit, line: t.line }
}

fn (mut p Parser) parse_call(name Tok) !Expr {
	p.expect(.lparen, "'('")!
	mut args := []Expr{}
	if p.cur().kind != .rparen {
		for {
			args << p.parse_expr()!
			if p.cur().kind == .comma {
				p.advance()
				continue
			}
			break
		}
	}
	p.expect(.rparen, "')'")!
	return Expr{ kind: .call, name: name.lit, args: args, line: name.line }
}
