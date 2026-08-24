// ast.v — abstract syntax tree types for the VuurRaaf language.
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

pub struct ImportDecl {
pub mut:
	path string
	line int
}

// EnumDecl is an `enum Name { variant1 variant2 ... }` declaration.
pub struct EnumDecl {
pub mut:
	name     string
	variants []string
	line     int
}

// ConstDecl is a `const NAME = value` declaration.
pub struct ConstDecl {
pub mut:
	name  string
	value Expr
	line  int
}

pub struct Program {
pub mut:
	fns     []FnDecl
	structs []StructDecl
	enums   []EnumDecl
	imports []ImportDecl
	consts  []ConstDecl
}
