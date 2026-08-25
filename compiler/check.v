// check.v — a compile-time type checker for VuurRaaf.
//
// Runs after parsing and before codegen. The language is dynamically typed at
// runtime, so this pass is deliberately conservative: it rejects programs that
// are *provably* wrong (unknown variables, field access on numbers, arithmetic
// on strings, wrong arity on known functions) while leaving genuinely dynamic
// programs (untyped parameters, unknown receiver types, mixed containers, and
// calls to functions defined in other objects) alone. Unresolved function
// names are deferred to the linker, matching the toolchain's separate
// compilation model.
module compiler

import os

enum CType {
	unknown
	int_t
	float_t
	string_t
	bool_t
	none_t
	array_t
	struct_t
	enum_t
	closure_t
}

struct TypeInfo {
	kind CType
	name string // struct/enum type name when statically known
}

struct FnSig {
	min_args      int
	has_defs      []bool
	variadic      bool
	n_type_params int // generic type parameters declared on the function
	returns       TypeInfo
}

struct Checker {
mut:
	types     map[string]TypeInfo // current scope: local name -> type
	mutable   map[string]bool     // local names bound with `mut`, params, loop vars; only these may be reassigned
	fns       map[string]FnSig
	structs   map[string][]string
	enums     map[string][]string
	consts    map[string]TypeInfo
	loop_depth int
	checked   map[string]bool // imported files already checked
	modules   map[string]bool // imported module names (bare `import os`)
}

// check validates a parsed program and returns an error on the first problem.
fn check(prog Program) ! {
	mut c := Checker{}
	// register declarations
	for sd in prog.structs {
		if sd.name in c.structs {
			return error('duplicate struct declaration "${sd.name}" (line ${sd.line})')
		}
		c.structs[sd.name] = sd.fields
	}
	for ed in prog.enums {
		if ed.name in c.enums {
			return error('duplicate enum declaration "${ed.name}" (line ${ed.line})')
		}
		c.enums[ed.name] = ed.variants
	}
	for cd in prog.consts {
		c.consts[cd.name] = TypeInfo{ kind: .int_t }
	}
	for fd in prog.fns {
		if fd.name in c.fns {
			return error('duplicate function "${fd.name}" (line ${fd.line})')
		}
		c.fns[fd.name] = FnSig{ min_args: fd.params.len - def_count(fd), has_defs: fd.has_defs, variadic: fd.variadic, n_type_params: fd.type_params.len }
	}
	// imported files are checked (and their symbols merged) recursively
	for imp in prog.imports {
		if imp.name.len > 0 {
			c.modules[imp.name] = true
		}
		c.check_import(imp.path, imp.name)!
	}
	for fd in prog.fns {
		c.check_fn(fd)!
	}
}

fn def_count(fd FnDecl) int {
	mut n := 0
	for has in fd.has_defs {
		if has {
			n++
		}
	}
	return n
}

fn (mut c Checker) check_import(path string, mod_name string) ! {
	if path in c.checked {
		return
	}
	c.checked[path] = true
	resolved := resolve_import(path) or { return error('cannot read import "${path}"') }
	src := os.read_file(resolved) or { return error('cannot read import "${path}"') }
	prog := parse(tokenize(src)!)!
	// merge declarations from the import (bare modules register their
	// functions under both the bare name and the "mod.fn" name, so internal
	// calls check against the former and program calls against the latter)
	for sd in prog.structs {
		if sd.name !in c.structs {
			c.structs[sd.name] = sd.fields
		}
	}
	for ed in prog.enums {
		if ed.name !in c.enums {
			c.enums[ed.name] = ed.variants
		}
	}
	for cd in prog.consts {
		if cd.name !in c.consts {
			c.consts[cd.name] = TypeInfo{ kind: .int_t }
		}
	}
	for fd in prog.fns {
		if fd.name !in c.fns {
			c.fns[fd.name] = FnSig{ min_args: fd.params.len - def_count(fd), has_defs: fd.has_defs, variadic: fd.variadic, n_type_params: fd.type_params.len }
		}
		if mod_name.len > 0 {
			key := '${mod_name}.${fd.name}'
			if key !in c.fns {
				c.fns[key] = FnSig{ min_args: fd.params.len - def_count(fd), has_defs: fd.has_defs, variadic: fd.variadic, n_type_params: fd.type_params.len }
			}
		}
	}
	for imp in prog.imports {
		c.check_import(imp.path, imp.name)!
	}
	for fd in prog.fns {
		c.check_fn(fd)!
	}
}

fn (mut c Checker) check_fn(fd FnDecl) ! {
	c.types.clear()
	c.loop_depth = 0
	// receiver and parameters are untyped (unknown) — the runtime is dynamic
	if fd.recv_name.len > 0 {
		c.types[fd.recv_name] = TypeInfo{ kind: .struct_t }
		c.mutable[fd.recv_name] = true
	}
	for p in fd.params {
		c.types[p] = TypeInfo{ kind: .unknown }
		// parameters are reassignable: callers pass values, bodies may rewrite
		c.mutable[p] = true
	}
	for st in fd.body {
		c.check_stmt(st)!
	}
}

fn (mut c Checker) check_stmt(st Stmt) ! {
	match st.kind {
		.expr_stmt {
			_ = c.check_expr(st.expr)!
		}
		.let_stmt {
			t := c.check_expr(st.expr)!
			c.types[st.target] = t
			c.mutable[st.target] = st.mutable // false for `let`, true for `mut`
		}
		.destruct_stmt {
			base := c.check_expr(st.expr)!
			for name in st.destruct_targets {
				c.types[name] = if st.destruct_field { TypeInfo{ kind: .unknown } } else { TypeInfo{ kind: .unknown } }
				c.mutable[name] = false
			}
			_ = base
		}
		.assign_stmt {
			if st.target !in c.types {
				return error('unknown variable "${st.target}" (line ${st.line})')
			}
			if !(st.target in c.mutable) || !c.mutable[st.target] {
				return error('cannot reassign immutable "${st.target}" — declare it with `mut` (line ${st.line})')
			}
			_ = c.check_expr(st.expr)!
		}
		.index_assign {
			base := c.check_expr(st.base)!
			_ = c.check_expr(st.idx)!
			c.expect_container(base, 'index assignment', st.line)!
			_ = c.check_expr(st.expr)!
		}
		.field_assign {
			base := c.check_expr(st.base)!
			c.expect_struct_like(base, 'field assignment', st.line)!
			_ = c.check_expr(st.expr)!
		}
		.if_stmt {
			_ = c.check_expr(st.cond)!
			for s in st.body {
				c.check_stmt(s)!
			}
			for s in st.els {
				c.check_stmt(s)!
			}
		}
		.match_stmt {
			_ = c.check_expr(st.expr)!
			for arm in st.arms {
				_ = c.check_expr(arm.val)!
				for s in arm.body {
					c.check_stmt(s)!
				}
			}
			for s in st.els_body {
				c.check_stmt(s)!
			}
		}
		.while_stmt {
			_ = c.check_expr(st.cond)!
			c.loop_depth++
			for s in st.body {
				c.check_stmt(s)!
			}
			c.loop_depth--
		}
		.for_range_stmt {
			start_t := c.check_expr(st.expr)!
			end_t := c.check_expr(st.cond)!
			c.expect_numeric(start_t, 'range start', st.line)!
			c.expect_numeric(end_t, 'range end', st.line)!
			c.types[st.target] = TypeInfo{ kind: .int_t }
			c.mutable[st.target] = true // the loop advances it; bodies may too
			c.loop_depth++
			for s in st.body {
				c.check_stmt(s)!
			}
			c.loop_depth--
		}
		.for_in_stmt {
			// for x in EnumName { ... } iterates the enum's variants
			if st.expr.kind == .ident && st.expr.name in c.enums {
				c.types[st.target] = TypeInfo{ kind: .enum_t, name: st.expr.name }
			} else {
				seq := c.check_expr(st.expr)!
				// iterate enums and arrays; unknown is allowed (dynamic)
				if seq.kind == .int_t || seq.kind == .float_t || seq.kind == .bool_t || seq.kind == .none_t {
					return error('cannot iterate a ${type_name(seq.kind)} (line ${st.line})')
				}
				c.types[st.target] = TypeInfo{ kind: .unknown }
			}
			c.mutable[st.target] = true // loop vars are reassigned by iteration
			if st.idx_target.len > 0 {
				c.types[st.idx_target] = TypeInfo{ kind: .int_t }
				c.mutable[st.idx_target] = true
			}
			c.loop_depth++
			for s in st.body {
				c.check_stmt(s)!
			}
			c.loop_depth--
		}
		.break_stmt, .continue_stmt {
			if c.loop_depth == 0 {
				what := if st.kind == .break_stmt { 'break' } else { 'continue' }
				return error('${what} outside of a loop (line ${st.line})')
			}
		}
		.ret_stmt {
			if st.has_val {
				_ = c.check_expr(st.expr)!
			}
		}
		.assert_stmt {
			_ = c.check_expr(st.expr)!
		}
		.try_stmt {
			c.loop_depth++ // errors unwind through loops; keep depth permissive
			c.loop_depth--
			for s in st.body {
				c.check_stmt(s)!
			}
			c.types[st.target] = TypeInfo{ kind: .string_t }
			for s in st.els {
				c.check_stmt(s)!
			}
		}
		.throw_stmt {
			_ = c.check_expr(st.expr)!
		}
		.defer_stmt {
			for s in st.body {
				c.check_stmt(s)!
			}
		}
	}
}

fn (mut c Checker) check_expr(e Expr) !TypeInfo {
	return match e.kind {
		.int_lit { TypeInfo{ kind: .int_t } }
		.float_lit { TypeInfo{ kind: .float_t } }
		.str_lit { TypeInfo{ kind: .string_t } }
		.bool_lit { TypeInfo{ kind: .bool_t } }
		.none_lit { TypeInfo{ kind: .none_t } }
		.ident {
			if e.name in c.types {
				c.types[e.name]
			} else if e.name in c.consts {
				c.consts[e.name]
			} else if e.name in c.fns {
				// a bare function name used as a value (e.g. the first argument
				// of `spawn`) evaluates to a closure
				TypeInfo{ kind: .unknown }
			} else {
				return error('unknown variable "${e.name}" (line ${e.line})')
			}
		}
		.array_lit {
			for el in e.elems {
				_ = c.check_expr(el)!
			}
			TypeInfo{ kind: .array_t }
		}
		.struct_lit {
			if e.name.len > 0 && e.name in c.structs {
				fields := c.structs[e.name]
				mut seen := map[string]bool{}
				for f in e.fields {
					if f.name !in fields {
						return error('unknown field "${f.name}" for struct ${e.name} (line ${e.line})')
					}
					if f.name in seen {
						return error('duplicate field "${f.name}" in struct literal (line ${e.line})')
					}
					seen[f.name] = true
					_ = c.check_expr(f.val)!
				}
				return TypeInfo{ kind: .struct_t, name: e.name }
			}
			for f in e.fields {
				_ = c.check_expr(f.val)!
			}
			TypeInfo{ kind: .struct_t }
		}
		.index {
			base := c.check_expr(*e.left)!
			_ = c.check_expr(*e.right)!
			c.expect_container(base, 'indexing', e.line)!
			TypeInfo{ kind: .unknown }
		}
		.field {
			// enum variant: Color.red — the base is the enum type name, not a
			// variable, so it must be resolved before check_expr on the base
			if e.left.kind == .ident && e.left.name in c.enums {
				return TypeInfo{ kind: .enum_t, name: e.left.name }
			}
			base := c.check_expr(*e.left)!
			c.expect_struct_like(base, 'field access', e.line)!
			// enum variant on an enum-typed receiver: Color.red  →  enum_t
			if base.kind == .enum_t {
				return TypeInfo{ kind: .enum_t, name: base.name }
			}
			TypeInfo{ kind: .unknown }
		}
	.method_call {
		// module call: os.exists(x) — the receiver is an imported module name
		if e.left.kind == .ident && e.left.name in c.modules {
			for a in e.args {
				_ = c.check_expr(a)!
			}
			key := '${e.left.name}.${e.name}'
			if key in c.fns {
				sig := c.fns[key]
				if !sig.variadic {
					if e.args.len < sig.min_args {
						return error('${key}() expects at least ${sig.min_args} argument(s), got ${e.args.len} (line ${e.line})')
					}
					if e.args.len > sig.has_defs.len {
						return error('${key}() expects at most ${sig.has_defs.len} argument(s), got ${e.args.len} (line ${e.line})')
					}
				}
			}
			return TypeInfo{ kind: .unknown }
		}
		recv := c.check_expr(*e.left)!
		if recv.kind == .int_t || recv.kind == .float_t || recv.kind == .bool_t || recv.kind == .none_t {
			return error('cannot call a method on a ${type_name(recv.kind)} (line ${e.line})')
		}
		for a in e.args {
			_ = c.check_expr(a)!
		}
		TypeInfo{ kind: .unknown }
	}
		.slice {
			base := c.check_expr(*e.left)!
			_ = c.check_expr(*e.right)!
			_ = c.check_expr(*e.extra)!
			if base.kind == .int_t || base.kind == .float_t || base.kind == .bool_t || base.kind == .none_t {
				return error('cannot slice a ${type_name(base.kind)} (line ${e.line})')
			}
			if base.kind == .string_t {
				TypeInfo{ kind: .string_t }
			} else {
				TypeInfo{ kind: .unknown }
			}
		}
		.unary {
			op := c.check_expr(*e.right)!
			match e.op {
				.kw_not { TypeInfo{ kind: .bool_t } }
				.tilde {
					c.expect_int(op, 'bitwise not', e.line)!
					TypeInfo{ kind: .int_t }
				}
				else {
					c.expect_numeric(op, 'unary minus', e.line)!
					op
				}
			}
		}
		.binary {
			c.check_binary(e)!
		}
		.call {
			c.check_call(e)!
		}
		.anon_fn {
			for p in e.fparams {
				c.types[p] = TypeInfo{ kind: .unknown }
			}
			for s in e.fn_body {
				c.check_stmt(s)!
			}
			TypeInfo{ kind: .closure_t }
		}
	}
}

fn (mut c Checker) check_binary(e Expr) !TypeInfo {
	l := c.check_expr(*e.left)!
	r := c.check_expr(*e.right)!
	return match e.op {
		.plus {
			if l.kind == .string_t || r.kind == .string_t {
				return TypeInfo{ kind: .string_t }
			}
			if l.kind == .array_t || r.kind == .array_t {
				return error('cannot add arrays with + (line ${e.line})')
			}
			if l.kind == .struct_t || r.kind == .struct_t {
				return error('cannot add structs with + (line ${e.line})')
			}
			if l.kind == .bool_t || r.kind == .bool_t {
				return error('cannot add a bool with + (line ${e.line})')
			}
			if l.kind == .unknown || r.kind == .unknown {
				return TypeInfo{ kind: .unknown }
			}
			if l.kind == .float_t || r.kind == .float_t {
				return TypeInfo{ kind: .float_t }
			}
			return TypeInfo{ kind: .int_t }
		}
		.minus, .star, .slash, .percent {
			c.expect_numeric(l, 'arithmetic', e.line)!
			c.expect_numeric(r, 'arithmetic', e.line)!
			if l.kind == .float_t || r.kind == .float_t {
				TypeInfo{ kind: .float_t }
			} else {
				TypeInfo{ kind: .int_t }
			}
		}
		.eq_eq, .not_eq {
			TypeInfo{ kind: .bool_t }
		}
		.lt, .le, .gt, .ge {
			if l.kind == .array_t || r.kind == .array_t {
				return error('cannot order arrays (line ${e.line})')
			}
			if l.kind == .struct_t || r.kind == .struct_t {
				return error('cannot order structs (line ${e.line})')
			}
			if l.kind == .bool_t && r.kind == .bool_t {
				return error('cannot order booleans (line ${e.line})')
			}
			if l.kind == .none_t || r.kind == .none_t {
				return error('cannot order a none (line ${e.line})')
			}
			if l.kind != .unknown && r.kind != .unknown && l.kind != r.kind && !(is_num_kind(l.kind) && is_num_kind(r.kind)) {
				return error('cannot compare a ${type_name(l.kind)} and a ${type_name(r.kind)} (line ${e.line})')
			}
			TypeInfo{ kind: .bool_t }
		}
		.kw_and, .kw_or, .kw_in {
			TypeInfo{ kind: .bool_t }
		}
		.amp, .pipe, .caret, .lt_lt, .gt_gt {
			c.expect_int(l, 'bitwise operator', e.line)!
			c.expect_int(r, 'bitwise operator', e.line)!
			TypeInfo{ kind: .int_t }
		}
		else {
			return error('unsupported operator at line ${e.line}')
		}
	}
}

fn (mut c Checker) check_call(e Expr) !TypeInfo {
	// builtin calls
	if e.name == 'len' {
		if e.args.len != 1 {
			return error('len() takes exactly one argument (line ${e.line})')
		}
		t := c.check_expr(e.args[0])!
		if t.kind == .int_t || t.kind == .float_t || t.kind == .bool_t || t.kind == .none_t || t.kind == .closure_t {
			return error('len() on a ${type_name(t.kind)} (line ${e.line})')
		}
		return TypeInfo{ kind: .int_t }
	}
	if e.name == 'push' || e.name == 'insert' || e.name == 'remove' {
		if e.args.len == 0 {
			return error('${e.name}() expects arguments (line ${e.line})')
		}
		seq := c.check_expr(e.args[0])!
		c.expect_container(seq, '${e.name}()', e.line)!
		for a in e.args[1..] {
			_ = c.check_expr(a)!
		}
		return TypeInfo{ kind: .unknown }
	}
	if e.name == 'has' || e.name == 'delete' {
		if e.args.len != 2 {
			return error('${e.name}() takes exactly two arguments (line ${e.line})')
		}
		seq := c.check_expr(e.args[0])!
		c.expect_struct_like(seq, '${e.name}()', e.line)!
		_ = c.check_expr(e.args[1])!
		return TypeInfo{ kind: .unknown }
	}
	if e.name == 'keys' {
		if e.args.len != 1 {
			return error('keys() takes exactly one argument (line ${e.line})')
		}
		seq := c.check_expr(e.args[0])!
		c.expect_struct_like(seq, 'keys()', e.line)!
		return TypeInfo{ kind: .array_t }
	}
	if e.name == 'print' || e.name == 'println' {
		if e.args.len != 1 {
			return error('${e.name}() takes exactly one argument (line ${e.line})')
		}
		_ = c.check_expr(e.args[0])!
		return TypeInfo{ kind: .unknown }
	}
	// host builtins (native) — validate arity from the spec table
	bid, bargc := builtin_spec(e.name)
	if bid >= 0 {
		if e.name == 'spawn' {
			// variadic: a function followed by zero or more arguments
			if e.args.len < 1 {
				return error('spawn() expects a function plus zero or more arguments (line ${e.line})')
			}
			for a in e.args {
				_ = c.check_expr(a)!
			}
			return builtin_result_type(e.name)
		}
		if e.args.len != bargc {
			return error('${e.name}() takes exactly ${bargc} argument(s) (line ${e.line})')
		}
		for a in e.args {
			_ = c.check_expr(a)!
		}
		return builtin_result_type(e.name)
	}
	// closure call: a local holding a function value
	if e.name in c.types && c.types[e.name].kind == .closure_t {
		for a in e.args {
			_ = c.check_expr(a)!
		}
		return TypeInfo{ kind: .unknown }
	}
	// user function — arity is checked only when the signature is known.
	// Unknown names are allowed: this toolchain supports separate compilation,
	// so a call may resolve to a function in another object at link time.
	// Truly missing functions are reported by the linker, not the checker.
	if e.name in c.fns {
		sig := c.fns[e.name]
		// generic type arguments must match the declared type parameters
		if e.type_args.len > 0 && e.type_args.len != sig.n_type_params {
			return error('${e.name}() takes ${sig.n_type_params} type argument(s), got ${e.type_args.len} (line ${e.line})')
		}
		if e.type_args.len == 0 && sig.n_type_params > 0 {
			// calling a generic function without explicit type args is fine —
			// the VM infers from the values at runtime
		}
		if !sig.variadic {
			if e.args.len < sig.min_args {
				return error('${e.name}() expects at least ${sig.min_args} argument(s), got ${e.args.len} (line ${e.line})')
			}
			if e.args.len > sig.has_defs.len {
				return error('${e.name}() expects at most ${sig.has_defs.len} argument(s), got ${e.args.len} (line ${e.line})')
			}
		}
	}
	for a in e.args {
		_ = c.check_expr(a)!
	}
	return TypeInfo{ kind: .unknown }
}

fn builtin_result_type(name string) TypeInfo {
	return match name {
		'abs', 'min', 'max', 'floor', 'ceil', 'round', 'rand_int' { TypeInfo{ kind: .int_t } }
		'pow', 'sqrt', 'rand', 'float', 'time' { TypeInfo{ kind: .float_t } }
		'int' { TypeInfo{ kind: .int_t } }
		'str', 'type', 'lower', 'upper', 'trim', 'getenv', 'read_file' { TypeInfo{ kind: .string_t } }
		'contains', 'starts_with', 'ends_with' { TypeInfo{ kind: .bool_t } }
		'split' { TypeInfo{ kind: .array_t } }
		'join' { TypeInfo{ kind: .string_t } }
		'sort', 'reverse' { TypeInfo{ kind: .array_t } }
		'pop' { TypeInfo{ kind: .unknown } }
		'clone', 'index_of' { TypeInfo{ kind: .unknown } }
		'args', 'keys' { TypeInfo{ kind: .array_t } }
		'len' { TypeInfo{ kind: .int_t } }
		'write_file', 'setenv', 'exit', 'sleep', 'eprint' { TypeInfo{ kind: .unknown } }
		// stdlib: JSON + string formatting
		'json_encode', 'format', 'replace', 'pad', 'pad_left', 'repeat' { TypeInfo{ kind: .string_t } }
		'json_decode', 'split_lines' { TypeInfo{ kind: .unknown } }
		'sb_new', 'sb_add', 'sb_str' { TypeInfo{ kind: .string_t } }
		'sb_len' { TypeInfo{ kind: .int_t } }
		'spawn' { TypeInfo{ kind: .int_t } }
		'spawn_join' { TypeInfo{ kind: .unknown } }
		'cwd', 'json_pretty', 'read_line', 'input' { TypeInfo{ kind: .string_t } }
		'flag_val' { TypeInfo{ kind: .string_t } }
		'flag_has' { TypeInfo{ kind: .int_t } }
		'flag_positional' { TypeInfo{ kind: .array_t } }
		'type_info' { TypeInfo{ kind: .struct_t } }
		'range' { TypeInfo{ kind: .array_t } }
		'build_is_dir' { TypeInfo{ kind: .int_t } }
		// build-module builtins (.vrmm)
		'build_compile', 'build_assemble', 'build_link', 'build_exec', 'build_base',
		'build_dir', 'build_join', 'build_root' { TypeInfo{ kind: .string_t } }
		'build_glob', 'build_ls' { TypeInfo{ kind: .array_t } }
		'build_run', 'build_test', 'build_bench', 'build_clean', 'build_exec_status',
		'build_exists', 'build_mkdir', 'build_rm', 'build_copy' { TypeInfo{ kind: .int_t } }
		// HTTP client: returns a {status, body} struct
		'http_get', 'http_post' { TypeInfo{ kind: .struct_t } }
		// date/time
		'now', 'time_ms', 'parse_time' { TypeInfo{ kind: .int_t } }
		'format_time', 'weekday' { TypeInfo{ kind: .string_t } }
		// regex
		'regex_match' { TypeInfo{ kind: .int_t } }
		'regex_find_all', 'regex_split', 'csv_parse' { TypeInfo{ kind: .array_t } }
		'regex_replace' { TypeInfo{ kind: .string_t } }
		// crypto/encoding
		'base64_encode', 'base64_decode', 'sha256', 'md5' { TypeInfo{ kind: .string_t } }
		// extended HTTP + path/process helpers
		'http_req', 'exec_full' { TypeInfo{ kind: .struct_t } }
		'path_ext', 'path_abs', 'path_rel' { TypeInfo{ kind: .string_t } }
		else { TypeInfo{ kind: .unknown } }
	}
}

fn is_num_kind(k CType) bool {
	return k == .int_t || k == .float_t
}

fn type_name(k CType) string {
	return match k {
		.int_t { 'int' }
		.float_t { 'float' }
		.string_t { 'string' }
		.bool_t { 'bool' }
		.array_t { 'array' }
		.struct_t { 'struct' }
		.enum_t { 'enum' }
		.closure_t { 'function' }
		.none_t { 'none' }
		else { 'value' }
	}
}

fn (mut c Checker) expect_numeric(t TypeInfo, what string, line int) ! {
	if t.kind == .string_t || t.kind == .array_t || t.kind == .struct_t || t.kind == .bool_t || t.kind == .none_t || t.kind == .closure_t {
		return error('${what} on a ${type_name(t.kind)} (line ${line})')
	}
}

fn (mut c Checker) expect_int(t TypeInfo, what string, line int) ! {
	if t.kind == .string_t || t.kind == .array_t || t.kind == .struct_t || t.kind == .bool_t || t.kind == .none_t || t.kind == .closure_t || t.kind == .float_t {
		return error('${what} requires an int, got a ${type_name(t.kind)} (line ${line})')
	}
}

fn (mut c Checker) expect_container(t TypeInfo, what string, line int) ! {
	if t.kind == .int_t || t.kind == .float_t || t.kind == .bool_t || t.kind == .none_t || t.kind == .closure_t {
		return error('${what} on a ${type_name(t.kind)} (line ${line})')
	}
}

fn (mut c Checker) expect_struct_like(t TypeInfo, what string, line int) ! {
	if t.kind == .int_t || t.kind == .float_t || t.kind == .bool_t || t.kind == .string_t || t.kind == .none_t || t.kind == .closure_t {
		return error('${what} on a ${type_name(t.kind)} (line ${line})')
	}
}
