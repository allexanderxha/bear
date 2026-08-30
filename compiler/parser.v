// parser.v — recursive-descent parser for the VuurRaaf language.
//
// Grammar (informal):
//   program  := import* (struct | enum | const | fn)*
//   import   := 'import' STRING | 'import' IDENT
//   struct   := 'struct' IDENT '{' [field (',' field)*] '}'   (field := IDENT [Type] | IDENT '?' Type)
//   enum     := 'enum' IDENT '{' [IDENT (',' IDENT)*] '}'
//   const    := 'const' IDENT '=' expr
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
		return error('expected ${what}, got "${t.lit}" at line ${t.line}, col ${t.col}')
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
	// imports come first
	for p.cur().kind == .kw_import {
		prog.imports << p.parse_import()!
	}
	// then top-level declarations
	for p.cur().kind != .eof {
		match p.cur().kind {
			.kw_struct { prog.structs << p.parse_struct_decl()! }
			.kw_enum { prog.enums << p.parse_enum_decl()! }
			.kw_const { prog.consts << p.parse_const_decl()! }
			.kw_interface { prog.interfaces << p.parse_interface_decl()! }
			.kw_fn { prog.fns << p.parse_fn()! }
			else { return error('unexpected token "${p.cur().lit}" at line ${p.cur().line}, col ${p.cur().col}') }
		}
	}
	if prog.fns.len == 0 {
		return error('no functions found in source')
	}
	return prog
}

// parse_struct_decl parses `struct Name { x int, y int, tag ?string, w }`.
// Each field is `name` (dynamically typed) or `name Type`; a leading `?` on
// the type marks it optional (also accepting `none`). Fields may be separated
// by commas or newlines.
fn (mut p Parser) parse_struct_decl() !StructDecl {
	t := p.expect(.kw_struct, "'struct'")!
	name := p.expect(.ident, 'struct name')!
	p.expect(.lbrace, "'{'")!
	mut fields := []string{}
	mut field_types := []string{}
	if p.cur().kind != .rbrace {
		for {
			fields << p.expect(.ident, 'field name')!.lit
			if p.cur().kind == .question {
				p.advance()
				field_types << '?' + p.expect(.ident, 'type name')!.lit
			} else if p.cur().kind == .ident {
				field_types << p.advance().lit
			} else {
				field_types << ''
			}
			if p.cur().kind == .comma {
				p.advance()
				continue
			}
			if p.cur().kind != .rbrace {
				// newline-separated field
				continue
			}
			break
		}
	}
	p.expect(.rbrace, "'}'")!
	return StructDecl{ name: name.lit, fields: fields, field_types: field_types, line: t.line }
}

// parse_import parses `import "path/to/file.vr"` (flat file merge) or a
// bare module name like `import os` (namespaced stdlib/vendor module).
fn (mut p Parser) parse_import() !ImportDecl {
	t := p.expect(.kw_import, "'import'")!
	if p.cur().kind == .str_lit {
		path := p.advance().lit
		return ImportDecl{ path: path, line: t.line }
	}
	name := p.expect(.ident, 'module name')!.lit
	return ImportDecl{ name: name, path: name, line: t.line }
}

// parse_enum_decl parses `enum Name { variant1 variant2 ... }`.
// Variants are separated by commas or newlines.
fn (mut p Parser) parse_enum_decl() !EnumDecl {
	t := p.expect(.kw_enum, "'enum'")!
	name := p.expect(.ident, 'enum name')!
	p.expect(.lbrace, "'{'")!
	mut variants := []string{}
	if p.cur().kind != .rbrace {
		for {
			variants << p.expect(.ident, 'variant name')!.lit
			if p.cur().kind == .comma {
				p.advance()
				continue
			}
			if p.cur().kind != .rbrace {
				// expect another variant (newline-separated)
				continue
			}
			break
		}
	}
	p.expect(.rbrace, "'}'")!
	return EnumDecl{ name: name.lit, variants: variants, line: t.line }
}

// parse_const_decl parses `const NAME = expr`.
fn (mut p Parser) parse_const_decl() !ConstDecl {
	t := p.expect(.kw_const, "'const'")!
	name := p.expect(.ident, 'constant name')!
	p.expect(.assign, "'='")!
	value := p.parse_expr()!
	return ConstDecl{ name: name.lit, value: value, line: t.line }
}

// parse_interface_decl parses `interface Name { method1() method2() ... }`.
// Methods may optionally be followed by `()` (any parameter list is ignored)
// and are separated by commas or newlines.
fn (mut p Parser) parse_interface_decl() !InterfaceDecl {
	t := p.expect(.kw_interface, "'interface'")!
	name := p.expect(.ident, 'interface name')!
	p.expect(.lbrace, "'{'")!
	mut methods := []InterfaceMethod{}
	if p.cur().kind != .rbrace {
		for {
			mname := p.expect(.ident, 'method name')!
			if p.cur().kind == .lparen {
				p.advance()
				for p.cur().kind != .rparen {
					if p.cur().kind == .eof {
						return error('unexpected end of file in interface method (line ${mname.line})')
					}
					p.advance()
				}
				p.expect(.rparen, "')'")!
			}
			methods << InterfaceMethod{ name: mname.lit, line: mname.line }
			if p.cur().kind == .comma {
				p.advance()
				continue
			}
			if p.cur().kind != .rbrace {
				continue
			}
			break
		}
	}
	p.expect(.rbrace, "'}'")!
	return InterfaceDecl{ name: name.lit, methods: methods, line: t.line }
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
	// generic type parameters: fn first[T, U](arr) { ... } — captured so the
	// type checker can validate call sites; the VM is dynamically typed, so
	// they erase to a single function at runtime
	mut type_params := []string{}
	if p.cur().kind == .lbracket {
		p.advance()
		for p.cur().kind != .rbracket {
			tp := p.expect(.ident, 'type parameter')!.lit
			if tp in type_params {
				return error('duplicate type parameter "${tp}" in function ${name.lit} (line ${name.line}, col ${name.col})')
			}
			type_params << tp
			if p.cur().kind == .comma {
				p.advance()
			}
		}
		p.expect(.rbracket, "']'")!
	}
	params, defaults, has_defs, variadic := p.parse_params()!
	body := p.parse_block()!
	return FnDecl{
		name: name.lit
		type_params: type_params
		recv_name: recv_name
		recv_type: recv_type
		params: params
		defaults: defaults
		has_defs: has_defs
		variadic: variadic
		body: body
		line: fn_tok.line
	}
}

// parse_params parses `(a, b, c = expr, rest...)` — the parameter list of a
// function. Returns the names, the default-value expressions (parallel array,
// empty Expr{} when no default), whether each has a default, and whether the
// last parameter is variadic.
fn (mut p Parser) parse_params() !([]string, []Expr, []bool, bool) {
	p.expect(.lparen, "'('")!
	mut params := []string{}
	mut defaults := []Expr{}
	mut has_defs := []bool{}
	mut variadic := false
	if p.cur().kind != .rparen {
		for {
			name_tok := p.expect(.ident, 'parameter name')!
			name := name_tok.lit
			if p.cur().kind == .dotdotdot {
				// variadic parameter: `rest...` (must be last)
				p.advance()
				params << name
				defaults << Expr{}
				has_defs << false
				variadic = true
				if p.cur().kind == .comma {
					return error('a variadic parameter must be last (line ${name_tok.line})')
				}
				break
			}
			mut def := Expr{}
			mut has_def := false
			if p.cur().kind == .assign {
				p.advance()
				def = p.parse_expr()!
				has_def = true
			}
			params << name
			defaults << def
			has_defs << has_def
			if p.cur().kind == .comma {
				p.advance()
				continue
			}
			break
		}
	}
	p.expect(.rparen, "')'")!
	return params, defaults, has_defs, variadic
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
		.kw_let, .kw_mut {
			mutable := t.kind == .kw_mut
			p.advance()
			// mutable with destructuring is not supported (kept simple); `let {
			// a, b } = x` and `let [a, b] = x` stay immutable-style bindings
			if p.cur().kind == .lbrace || p.cur().kind == .lbracket {
				is_field := p.cur().kind == .lbrace
				p.advance()
				mut names := []string{}
				mut closing := TokKind.rbracket
				if is_field {
					closing = .rbrace
				}
				if p.cur().kind != closing {
					for {
						names << p.expect(.ident, 'binding name')!.lit
						if p.cur().kind == .comma {
							p.advance()
							continue
						}
						break
					}
				}
				p.expect(closing, "']' or '}'")!
				p.expect(.assign, "'='")!
				e := p.parse_expr()!
				return Stmt{ kind: .destruct_stmt, expr: e, destruct_targets: names, destruct_field: is_field, line: t.line }
			}
			name := p.expect(.ident, 'variable name')!
			p.expect(.assign, "'='")!
			e := p.parse_expr()!
			return Stmt{ kind: .let_stmt, target: name.lit, expr: e, mutable: mutable, line: t.line }
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
				// range arm: `1..10 {}` or `1...10 {}` — matches when the subject
				// falls within [start, end] (both ends inclusive)
				if p.cur().kind == .dotdot || p.cur().kind == .dotdotdot {
					inclusive := p.cur().kind == .dotdotdot
					p.advance()
					end := p.parse_expr()!
					body := p.parse_block()!
					arms << MatchArm{ val: val, body: body, is_range: true, range_end: end, inclusive: inclusive }
					continue
				}
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
			mut idx_name := ''
			mut val_name := name.lit
			if p.cur().kind == .comma {
				// for i, v in arr { ... }
				p.advance()
				idx_name = name.lit
				val_name = p.expect(.ident, 'loop value variable')!.lit
			}
			p.expect(.kw_in, "'in'")!
			first := p.parse_expr()!
			if p.cur().kind == .dotdot || p.cur().kind == .dotdotdot {
				inclusive := p.cur().kind == .dotdotdot
				p.advance()
				end := p.parse_expr()!
				body := p.parse_block()!
				return Stmt{ kind: .for_range_stmt, target: val_name, expr: first, cond: end, inclusive: inclusive, body: body, line: t.line }
			}
			body := p.parse_block()!
			return Stmt{ kind: .for_in_stmt, target: val_name, idx_target: idx_name, expr: first, body: body, line: t.line }
		}
		.kw_defer {
			p.advance()
			inner := p.parse_stmt()!
			return Stmt{ kind: .defer_stmt, body: [inner], line: t.line }
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
		.kw_try {
			p.advance()
			return p.parse_try_stmt(t)!
		}
		.kw_throw {
			p.advance()
			e := p.parse_expr()!
			return Stmt{ kind: .throw_stmt, expr: e, line: t.line }
		}
		.ident {
			p.advance()
			// generic type args in statement position: first[int](...)
			mut type_args := []string{}
			if p.cur().kind == .lbracket && p.looks_like_generic_args() {
				type_args = p.parse_type_args()!
			}
			mut e := Expr{}
			if p.cur().kind == .lparen {
				// a call statement: foo(args), optionally chained foo().x
				e = p.parse_call(t, type_args)!
				e = p.parse_postfix_tail(e)!
			} else if type_args.len > 0 {
				return error('generic type arguments on a non-call "${t.lit}" (line ${t.line}, col ${t.col})')
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
		// compound assignment: x += expr, a[i] += expr, a.b += expr
		if p.cur().kind == .plus_eq || p.cur().kind == .minus_eq || p.cur().kind == .star_eq || p.cur().kind == .slash_eq {
			op_tok := p.advance()
			rhs := p.parse_expr()!
			bin_op := match op_tok.kind {
				.plus_eq { TokKind.plus }
				.minus_eq { TokKind.minus }
				.star_eq { TokKind.star }
				.slash_eq { TokKind.slash }
				else { return error('unexpected compound operator (line ${t.line})') }
			}
			// desugar: LHS op= RHS  →  LHS = LHS op RHS
			match e.kind {
				.ident {
					full_rhs := bin_node(bin_op, e, rhs, op_tok.line)
					return Stmt{ kind: .assign_stmt, target: e.name, expr: full_rhs, line: t.line }
				}
				.index {
					full_rhs := bin_node(bin_op, e, rhs, op_tok.line)
					return Stmt{ kind: .index_assign, base: *e.left, idx: *e.right, expr: full_rhs, line: t.line }
				}
				.field {
					full_rhs := bin_node(bin_op, e, rhs, op_tok.line)
					return Stmt{ kind: .field_assign, base: *e.left, target: e.name, expr: full_rhs, line: t.line }
				}
				else {
					return error('cannot use compound assignment on this expression (line ${t.line})')
				}
			}
		}
		return Stmt{ kind: .expr_stmt, expr: e, line: t.line }
		}
		else {
			return error('unexpected token "${t.lit}" at line ${t.line}, col ${t.col}')
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

// parse_try_stmt parses `try { body } catch ident { body }`.
fn (mut p Parser) parse_try_stmt(t Tok) !Stmt {
	body := p.parse_block()!
	p.expect(.kw_catch, "'catch'")!
	catch_var := p.expect(.ident, 'error variable')!.lit
	catch_body := p.parse_block()!
	return Stmt{
		kind: .try_stmt
		body: body
		target: catch_var
		els: catch_body
		line: t.line
	}
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

// slice_node builds `base[start..end]`.
// end uses -1 as sentinel for "open-ended" (slice to end).
fn slice_node(base Expr, start Expr, end Expr, _inclusive bool, line int) Expr {
	mut b := base
	mut s := start
	mut e := end
	return Expr{ kind: .slice, left: &b, right: &s, extra: &e, line: line }
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
	mut e := p.parse_bitor()!
	for p.cur().kind == .kw_and {
		op := p.advance()
		rhs := p.parse_bitor()!
		e = bin_node(op.kind, e, rhs, op.line)
	}
	return e
}

// parse_bitor handles `|` (bitwise OR).
fn (mut p Parser) parse_bitor() !Expr {
	mut e := p.parse_bitxor()!
	for p.cur().kind == .pipe {
		op := p.advance()
		rhs := p.parse_bitxor()!
		e = bin_node(op.kind, e, rhs, op.line)
	}
	return e
}

// parse_bitxor handles `^` (bitwise XOR).
fn (mut p Parser) parse_bitxor() !Expr {
	mut e := p.parse_bitand()!
	for p.cur().kind == .caret {
		op := p.advance()
		rhs := p.parse_bitand()!
		e = bin_node(op.kind, e, rhs, op.line)
	}
	return e
}

// parse_bitand handles `&` (bitwise AND).
fn (mut p Parser) parse_bitand() !Expr {
	mut e := p.parse_eq()!
	for p.cur().kind == .amp {
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
	mut e := p.parse_shift()!
	for p.cur().kind == .lt || p.cur().kind == .le || p.cur().kind == .gt || p.cur().kind == .ge || p.cur().kind == .kw_in {
		op := p.advance()
		rhs := p.parse_shift()!
		e = bin_node(op.kind, e, rhs, op.line)
	}
	return e
}

// parse_shift handles `<<` and `>>` (bitwise shift).
fn (mut p Parser) parse_shift() !Expr {
	mut e := p.parse_add()!
	for p.cur().kind == .lt_lt || p.cur().kind == .gt_gt {
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
	if t.kind == .kw_not || t.kind == .minus || t.kind == .tilde {
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
			if p.cur().kind == .dotdot || p.cur().kind == .dotdotdot {
				// arr[start..end] or arr[start..] slicing
				p.advance()
				if p.cur().kind == .rbracket {
					// arr[start..] — slice to end
					p.advance()
					cur = slice_node(cur, idx, Expr{ kind: .int_lit, int_v: -1, line: cur.line }, false, cur.line)
				} else {
					end := p.parse_expr()!
					p.expect(.rbracket, "']'")!
					cur = slice_node(cur, idx, end, false, cur.line)
				}
			} else {
				p.expect(.rbracket, "']'")!
				cur = index_node(cur, idx, cur.line)
			}
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
		.float_lit {
			p.advance()
			return Expr{ kind: .float_lit, float_v: t.lit.f64(), line: t.line }
		}
		.str_lit {
			p.advance()
			return Expr{ kind: .str_lit, str_v: t.lit, line: t.line }
		}
		.str_interp {
			p.advance()
			return p.parse_str_interp(t)!
		}
		.kw_true {
			p.advance()
			return Expr{ kind: .bool_lit, int_v: 1, line: t.line }
		}
		.kw_false {
			p.advance()
			return Expr{ kind: .bool_lit, int_v: 0, line: t.line }
		}
		.kw_none {
			p.advance()
			return Expr{ kind: .none_lit, line: t.line }
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
		.kw_fn {
			// anonymous function expression: fn(params) { body }
			p.advance()
			return p.parse_anon_fn(t)!
		}
		else {
			return error('unexpected token "${t.lit}" at line ${t.line}, col ${t.col}')
		}
	}
}

fn (mut p Parser) parse_call_or_ident(t Tok) !Expr {
	// generic type args: first[int](...) — captured for the type checker;
	// only treated as type args when [ is followed by idents then ] then (
	mut type_args := []string{}
	if p.cur().kind == .lbracket && p.looks_like_generic_args() {
		type_args = p.parse_type_args()!
	}
	if p.cur().kind == .lparen {
		return p.parse_call(t, type_args)!
	}
	if type_args.len > 0 {
		return error('generic type arguments on a non-call "${t.lit}" (line ${t.line}, col ${t.col})')
	}
	return Expr{ kind: .ident, name: t.lit, line: t.line }
}

// parse_type_args parses `[int, string]` into a list of type names.
fn (mut p Parser) parse_type_args() ![]string {
	p.advance() // consume '['
	mut args := []string{}
	for p.cur().kind != .rbracket {
		args << p.expect(.ident, 'type argument')!.lit
		if p.cur().kind == .comma {
			p.advance()
		}
	}
	p.expect(.rbracket, "']'")!
	return args
}

fn (mut p Parser) parse_call(name Tok, type_args []string) !Expr {
	args := p.parse_args()!
	return Expr{ kind: .call, name: name.lit, type_args: type_args, args: args, line: name.line }
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

// parse_struct_fields parses `{ name: expr, ... }` or `{ "key": expr, ... }` and returns the fields.
fn (mut p Parser) parse_struct_fields() ![]StructField {
	p.expect(.lbrace, "'{'")!
	mut fields := []StructField{}
	if p.cur().kind != .rbrace {
		for {
			// field name can be an identifier or a string literal (for maps)
			mut fname := ''
			if p.cur().kind == .str_lit {
				fname = p.advance().lit
			} else {
				fname = p.expect(.ident, 'field name')!.lit
			}
			p.expect(.colon, "':'")!
			val := p.parse_expr()!
			fields << StructField{ name: fname, val: val }
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
	// typed struct literal: `{ ident :` or map literal: `{ "key" :`
	return (p.toks[p.pos + 1].kind == .ident || p.toks[p.pos + 1].kind == .str_lit) && p.toks[p.pos + 2].kind == .colon
}

// looks_like_generic_args checks if `[` starts generic type args like `[T]` or `[T, U]`
// rather than array indexing. It peeks ahead to see `ident ... ] (`.
fn (mut p Parser) looks_like_generic_args() bool {
	// current token must be lbracket (the caller already checked this)
	if p.pos + 2 >= p.toks.len {
		return false
	}
	// must start with an ident after the [
	if p.toks[p.pos + 1].kind != .ident {
		return false
	}
	// scan forward: ident, comma, ident, ..., rbracket, then lparen
	mut i := p.pos + 2
	for i < p.toks.len && p.toks[i].kind != .rbracket {
		if p.toks[i].kind != .ident && p.toks[i].kind != .comma {
			return false
		}
		i++
	}
	if i >= p.toks.len {
		return false
	}
	// p.toks[i] should be rbracket
	if i + 1 >= p.toks.len {
		return false
	}
	return p.toks[i + 1].kind == .lparen
}

// parse_str_interp handles string interpolation: "hello ${name} ${age}".
// It splits the raw string into alternating text/expression parts and builds
// a chain of + concatenations so the compiler needs no special handling.
fn (mut p Parser) parse_str_interp(t Tok) !Expr {
	parts := split_str_interp(t.lit)
	// parts alternates: text, expr, text, expr, ..., text
	if parts.len == 1 {
		return Expr{ kind: .str_lit, str_v: parts[0], line: t.line }
	}
	// build the first string part
	mut result := Expr{ kind: .str_lit, str_v: parts[0], line: t.line }
	mut i := 1
	for i < parts.len {
		// parts[i] is an expression — tokenise and parse it
		expr_src := parts[i]
		expr_toks := tokenize(expr_src)!
		mut ep := Parser{ toks: expr_toks }
		expr := ep.parse_expr()!
		result = bin_node(.plus, result, expr, t.line)
		i++
		// parts[i] is the next text fragment
		if i < parts.len {
			if parts[i].len > 0 {
				str_e := Expr{ kind: .str_lit, str_v: parts[i], line: t.line }
				result = bin_node(.plus, result, str_e, t.line)
			}
			i++
		}
	}
	return result
}

// parse_anon_fn parses an anonymous function expression: `fn(params) { body }`.
fn (mut p Parser) parse_anon_fn(t Tok) !Expr {
	params, defaults, has_defs, variadic := p.parse_params()!
	body := p.parse_block()!
	return Expr{
		kind: .anon_fn
		fparams: params
		fdefaults: defaults
		fhas_defs: has_defs
		fvariadic: variadic
		fn_body: body
		line: t.line
	}
}

// split_str_interp splits an interpolated string at ${...} boundaries.
// Returns alternating [text, expr, text, expr, ..., text] fragments.
fn split_str_interp(s string) []string {
	mut parts := []string{}
	mut i := 0
	mut current := ''
	for i < s.len {
		if s[i] == `$` && i + 1 < s.len && s[i + 1] == `{` {
		parts << current
		current = ''
		i += 2
		mut depth := 1
		mut expr := ''
		for i < s.len && depth > 0 {
			if s[i] == `{` {
				depth++
			} else if s[i] == `}` {
				depth--
			}
			if depth > 0 {
				expr += s[i].ascii_str()
			}
			i++
		}
		parts << expr
	} else {
		current += s[i].ascii_str()
		i++
	}
}
	parts << current
	return parts
}
