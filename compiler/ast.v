// ast.v — abstract syntax tree types for the VuurRaaf language.
module compiler

pub enum ExprKind {
	int_lit
	float_lit
	str_lit
	bool_lit
	none_lit
	ident
	array_lit
	struct_lit
	index
	field
	method_call
	slice
	unary
	anon_fn
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
	kind    ExprKind
	int_v   i64
	float_v f64
	str_v   string
	name   string // ident/call name, or the field name of a `.field` access
	op     TokKind
	left   &Expr = unsafe { nil }
	right  &Expr = unsafe { nil }
	extra  &Expr = unsafe { nil } // slice: end index expression
	elems  []Expr
	fields []StructField // struct_lit: the named fields
	args     []Expr
	type_args []string // call: explicit generic type arguments (first[int](...))
	fparams  []string // anon_fn: parameter names
	fdefaults []Expr  // anon_fn: default values (parallel to fparams)
	fhas_defs []bool  // anon_fn: which params have defaults
	fvariadic bool    // anon_fn: last param is variadic
	fn_body  []Stmt   // anon_fn: function body
	line     int
}

pub enum StmtKind {
	expr_stmt
	let_stmt
	destruct_stmt
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
	try_stmt
	throw_stmt
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
	idx_target string // for_in_stmt: index variable name (empty when unused)
	destruct_targets []string // destruct_stmt: names to bind
	destruct_field   bool     // destruct_stmt: struct ({ a, b }) vs array ([a, b])
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
	name       string
	type_params []string // generic type parameters (fn first[T, U](...) { ... })
	recv_name  string // method receiver local name ('' for plain functions)
	recv_type  string // method receiver struct type ('' for plain functions)
	params    []string
	defaults  []Expr // parallel to params; empty Expr{} when no default
	has_defs  []bool // parallel to params: whether a default exists
	variadic  bool   // last param is variadic (nums...)
	body      []Stmt
	line      int
}

pub struct ImportDecl {
pub mut:
	path string // the file to load (module name for bare `import os`)
	name string // module name ('' for quoted file imports: flat merge)
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

// InterfaceDecl is an `interface Name { method1(); method2() type }` declaration.
// Methods are stored as (name, return_type) pairs. The interface is satisfied
// by any struct that implements all listed methods (structural/duck typing).
pub struct InterfaceDecl {
pub mut:
	name    string
	methods []InterfaceMethod
	line    int
}

pub struct InterfaceMethod {
pub mut:
	name string
	line int
}

pub struct Program {
pub mut:
	fns        []FnDecl
	structs    []StructDecl
	enums      []EnumDecl
	imports    []ImportDecl
	consts     []ConstDecl
	interfaces []InterfaceDecl
}
