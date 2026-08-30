// tokens.v — token types for the VuurRaaf lexer.
module compiler

pub enum TokKind {
	eof
	ident
	int_lit
	float_lit
	str_lit
	str_interp
	lparen
	rparen
	lbrace
	rbrace
	lbracket
	rbracket
	comma
	dot
	colon
	question
	plus
	minus
	star
	slash
	percent
	amp
	pipe
	caret
	tilde
	lt_lt
	gt_gt
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
	kw_mut
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
	kw_none
	kw_and
	kw_or
	kw_not
	kw_assert
	kw_import
	kw_enum
	kw_const
	kw_interface
	kw_try
	kw_catch
	kw_defer
	kw_throw
}

pub struct Tok {
pub:
	kind TokKind
	lit  string
	line int
	col  int // 1-based column within the line
}
