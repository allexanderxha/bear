// parser.v — recursive-descent parser for the VuurRaaf language.
//
// Grammar (informal):
//   program  := (struct | fn)*
//   struct   := 'struct' IDENT '{' [IDENT (',' IDENT)*] '}'
//   fn       := 'fn' [ '(' IDENT IDENT ')' ] IDENT '(' [IDENT (',' IDENT)*] ')' block
//   block    := '{' stmt* '}'
//   stmt     := 'let' IDENT '=' expr
//             | IDENT '=' expr
//             | postfix '=' expr            (a[i] = v, a.b = v)
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
//             | '{' [IDENT ':' expr (',' IDENT ':' expr)*] '}'   (anonymous struct literal)
//             | IDENT '{' IDENT ':' expr ... '}'                  (typed struct literal)
//   postfix  := primary ('.' IDENT ['(' args ')'] | '[' expr ']')*
//             ('.' IDENT '(' ... ')' is a method call; everything else field access)
module compiler

pub enum ExprKind {
	int_lit
	str_lit
	bool_lit
	ident
	array_lit
	struct_lit
	index
	field
	method_call
	unary
	binary
	call
}

// StructField is one `name: value` entry of a struct literal.
pub struct StructField {
pub mut:
	name string
	val  Expr
}

pub struct Expr {
pub mut:
	kind   ExprKind
	int_v  i64
	str_v  string
	name   string // ident/call name, or the field name of a `.field` access
	op     TokKind
	left   &Expr = unsafe { nil }
	right  &Expr = unsafe { nil }
	elems  []Expr
	fields []StructField // struct_lit: the named fields
	args   []Expr
	line   int
}

pub enum StmtKind {
	expr_stmt
	let_stmt
	assign_stmt
	index_assign
	field_assign
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

// StructDecl is a `struct Name { a, b }` declaration.
pub struct StructDecl {
pub mut:
	name   string
	fields []string
	line   int
}

pub struct FnDecl {
pub mut:
	name      string
	recv_name string // method receiver local name ('' for plain functions)
	recv_type string // method receiver struct type ('' for plain functions)
	params    []string
	body      []Stmt
	line      int
}

pub struct Program {
pub mut:
	fns     []FnDecl
	structs []StructDecl
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
		if p.cur().kind == .kw_struct {
			prog.structs << p.parse_struct_decl()!
		} else {
			prog.fns << p.parse_fn()!
		}
	}
	if prog.fns.len == 0 {
		return error('no functions found in source')
	}
	return prog
}

// parse_struct_decl parses `struct Name { a, b, c }`.
fn (mut p Parser) parse_struct_decl() !StructDecl {
	t := p.expect(.kw_struct, "'struct'")!
	name := p.expect(.ident, 'struct name')!
	p.expect(.lbrace, "'{'")!
	mut fields := []string{}
	if p.cur().kind != .rbrace {
		for {
			fields << p.expect(.ident, 'field name')!.lit
			if p.cur().kind == .comma {
				p.advance()
				continue
			}
			break
		}
	}
	p.expect(.rbrace, "'}'")!
	return StructDecl{ name: name.lit, fields: fields, line: t.line }
}

// parse_fn parses `fn name(params) { }` or a method `fn (p Type) name(params) { }`.
fn (mut p Parser) parse_fn() !FnDecl {
	fn_tok := p.expect(.kw_fn, "'fn'")!
	mut recv_name := ''
	mut recv_type := ''
	if p.cur().kind == .lparen {
		// method: fn (p Type) name(...)
		p.advance()
		recv_name = p.expect(.ident, 'receiver name')!.lit
		recv_type = p.expect(.ident, 'receiver type')!.lit
		p.expect(.rparen, "')'")!
	}
	name := p.expect(.ident, 'function name')!
	params := p.parse_params()!
	body := p.parse_block()!
	return FnDecl{ name: name.lit, recv_name: recv_name, recv_type: recv_type, params: params, body: body, line: fn_tok.line }
}

// parse_params parses `(a, b, c)` — the parameter list of a function.
fn (mut p Parser) parse_params() ![]string {
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
	return params
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
			mut e := Expr{}
			if p.cur().kind == .lparen {
				// a call statement: foo(args), optionally chained foo().x
				e = p.parse_call(t)!
				e = p.parse_postfix_tail(e)!
			} else {
				e = p.parse_postfix_tail(Expr{ kind: .ident, name: t.lit, line: t.line })!
			}
			if p.cur().kind == .assign {
				// assignment to an ident, an index, or a field
				p.advance()
				rhs := p.parse_expr()!
				match e.kind {
					.ident {
						return Stmt{ kind: .assign_stmt, target: e.name, expr: rhs, line: t.line }
					}
					.index {
						return Stmt{ kind: .index_assign, base: *e.left, idx: *e.right, expr: rhs, line: t.line }
					}
					.field {
						return Stmt{ kind: .field_assign, base: *e.left, target: e.name, expr: rhs, line: t.line }
					}
					else {
						return error('cannot assign to this expression (line ${t.line})')
					}
				}
			}
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

// field_node builds `base.name`.
fn field_node(base Expr, name string, line int) Expr {
	mut b := base
	return Expr{ kind: .field, left: &b, name: name, line: line }
}

// method_node builds `base.name(args)`.
fn method_node(recv Expr, name string, args []Expr, line int) Expr {
	mut r := recv
	return Expr{ kind: .method_call, left: &r, name: name, args: args, line: line }
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

// parse_postfix handles postfix operators after a primary: indexing
// `a[i]` (chainable `a[i][j]`) and field access `a.b` (chainable `a.b.c`),
// in any mix: `a[i].b`, `a.b[i]`, ...
fn (mut p Parser) parse_postfix() !Expr {
	mut e := p.parse_primary()!
	return p.parse_postfix_tail(e)!
}

// parse_postfix_tail continues a postfix chain from an already-parsed base.
// It takes the base by value (Expr only holds pointers to heap-allocated
// child nodes) and returns the extended chain. A `.name(` is a method call
// (the receiver is the expression the dot was applied to); `.name` without
// parens is plain field access.
fn (mut p Parser) parse_postfix_tail(e Expr) !Expr {
	mut cur := e
	for {
		if p.cur().kind == .lbracket {
			p.advance()
			idx := p.parse_expr()!
			p.expect(.rbracket, "']'")!
			cur = index_node(cur, idx, cur.line)
			continue
		}
		if p.cur().kind == .dot {
			p.advance()
			name := p.expect(.ident, 'field name')!
			f := field_node(cur, name.lit, cur.line)
			if p.cur().kind == .lparen {
				args := p.parse_args()!
				cur = method_node(*f.left, f.name, args, f.line)
			} else {
				cur = f
			}
			continue
		}
		break
	}
	return cur
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
		.lbrace {
			// anonymous struct literal: { name: expr, ... }
			fields := p.parse_struct_fields()!
			return Expr{ kind: .struct_lit, name: '', fields: fields, line: t.line }
		}
		.ident {
			p.advance()
			if p.cur().kind == .lbrace && p.looks_like_struct_lit() {
				// typed struct literal: Name{ name: expr, ... } — only when the
				// brace clearly opens a field list (`{ ident :`), so `if x {` and
				// match arms like `x { ... }` still parse as blocks
				fields := p.parse_struct_fields()!
				return Expr{ kind: .struct_lit, name: t.lit, fields: fields, line: t.line }
			}
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
	args := p.parse_args()!
	return Expr{ kind: .call, name: name.lit, args: args, line: name.line }
}

// parse_args parses `(e1, e2, ...)` and returns the argument expressions.
fn (mut p Parser) parse_args() ![]Expr {
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
	return args
}

// parse_struct_fields parses `{ name: expr, ... }` and returns the fields.
fn (mut p Parser) parse_struct_fields() ![]StructField {
	p.expect(.lbrace, "'{'")!
	mut fields := []StructField{}
	if p.cur().kind != .rbrace {
		for {
			name := p.expect(.ident, 'field name')!
			p.expect(.colon, "':'")!
			val := p.parse_expr()!
			fields << StructField{ name: name.lit, val: val }
			if p.cur().kind == .comma {
				p.advance()
				continue
			}
			break
		}
	}
	p.expect(.rbrace, "'}'")!
	return fields
}

// looks_like_struct_lit reports whether the current token (`{`) opens a typed
// struct literal: the tokens after the brace must be `ident :`.
fn (mut p Parser) looks_like_struct_lit() bool {
	if p.pos + 2 >= p.toks.len {
		return false
	}
	return p.toks[p.pos + 1].kind == .ident && p.toks[p.pos + 2].kind == .colon
}
