// tokens.v — token types for the VuurRaaf lexer.
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
	plus_eq
	minus_eq
	star_eq
	slash_eq
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
	kw_const
}

pub struct Tok {
pub:
	kind TokKind
	lit  string
	line int
}
