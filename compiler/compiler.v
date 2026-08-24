// compiler.v — bytecode code generator for VuurRaaf.
//
// Compiles a parsed program into a VROBJ object file: flat bytecode plus a
// symbol per function and a relocation per call site. Call targets are left as
// relocations and resolved by the linker, so functions may live in other files.
module compiler

import os
import obj

// opcodes — keep in sync with vm/vm.v and assembler/assembler.v
const op_halt = u8(0)
const op_push_i = u8(1)
const op_push_s = u8(2)
const op_load = u8(3)
const op_store = u8(4)
const op_pop = u8(5)
const op_dup = u8(6)
const op_add = u8(7)
const op_sub = u8(8)
const op_mul = u8(9)
const op_div = u8(10)
const op_mod = u8(11)
const op_neg = u8(12)
const op_eq = u8(13)
const op_ne = u8(14)
const op_lt = u8(15)
const op_le = u8(16)
const op_gt = u8(17)
const op_ge = u8(18)
const op_and = u8(19)
const op_or = u8(20)
const op_not = u8(21)
const op_jmp = u8(22)
const op_jz = u8(23)
const op_jnz = u8(24)
const op_call = u8(25)
const op_ret = u8(26)
const op_retv = u8(27)
const op_print = u8(28)
const op_println = u8(29)
const op_assert = u8(30)
const op_enter = u8(31)
const op_mkarray = u8(32)
const op_aget = u8(33)
const op_aset = u8(34)
const op_alen = u8(35)
const op_apush = u8(36)

// compile parses and compiles VuurRaaf source into an object file.
pub fn compile(src string) !obj.Obj {
	toks := tokenize(src)!
	prog := parse(toks)!
	return gen(prog)
}

pub fn compile_file(path string) !obj.Obj {
	src := os.read_file(path)!
	return compile(src)!
}

// ---------------------------------------------------------------------------

struct Fixup {
	name string
	off  u32
}

// LoopCtx records where `break` and `continue` should jump while generating
// the body of a loop. For `for` loops `continue` targets the increment, not
// the condition check, so the loop variable still advances.
struct LoopCtx {
	break_l    string
	continue_l string
}

struct Gen {
mut:
	code      []u8
	strings   []string
	str_map   map[string]int
	symbols   []obj.Symbol
	relocs    []obj.Reloc
	locals    map[string]int
	local_cnt int
	argc      int
	cur_fn    string
	labels    map[string]int
	fixups    []Fixup
	loops     []LoopCtx
	enter_off u32
	next_lbl  int
}

fn gen(prog Program) !obj.Obj {
	mut g := Gen{}
	for fd in prog.fns {
		g.gen_fn(fd)!
	}
	return obj.Obj{
		symbols: g.symbols
		strings: g.strings
		code:    g.code
		relocs:  g.relocs
	}
}

fn (mut g Gen) gen_fn(fd FnDecl) ! {
	g.cur_fn = fd.name
	g.symbols << obj.Symbol{ name: fd.name, entry: g.code.len }
	g.locals.clear()
	g.local_cnt = 0
	g.argc = fd.params.len
	for i, p in fd.params {
		g.locals[p] = i
	}
	g.local_cnt = g.argc
	// `enter n` reserves the non-parameter locals; n is patched once the body
	// has been scanned.
	g.code << op_enter
	g.enter_off = u32(g.code.len)
	g.code << obj.encode_i64(0)
	for st in fd.body {
		g.gen_stmt(st)!
	}
	g.code << op_ret // trailing return for fall-through
	obj.patch_i64(mut g.code, g.enter_off, i64(g.local_cnt - g.argc))
	// resolve intra-function jump targets
	for f in g.fixups {
		target := g.labels[f.name] or {
			return error('internal error: unresolved label ${f.name} in fn ${fd.name}')
		}
		obj.patch_i64(mut g.code, f.off, i64(target))
	}
	g.fixups.clear()
	g.labels.clear()
	g.cur_fn = ''
}

fn (mut g Gen) gen_stmt(st Stmt) ! {
	match st.kind {
		.expr_stmt {
			g.gen_expr(st.expr)!
			// print/println already consume their value; everything else
			// leaves one on the stack that must be discarded
			if st.expr.kind == .call && (st.expr.name == 'print' || st.expr.name == 'println') {
				// nothing to discard
			} else {
				g.code << op_pop
			}
		}
		.let_stmt {
			g.gen_expr(st.expr)!
			idx := g.local_cnt
			g.local_cnt++
			g.locals[st.target] = idx
			g.code << op_store
			g.code << obj.encode_i64(i64(idx))
		}
		.assign_stmt {
			idx := g.locals[st.target] or {
				return error('unknown variable "${st.target}" at line ${st.line}')
			}
			g.gen_expr(st.expr)!
			g.code << op_store
			g.code << obj.encode_i64(i64(idx))
		}
		.index_assign {
			g.gen_expr(st.base)!
			g.gen_expr(st.idx)!
			g.gen_expr(st.expr)!
			g.code << op_aset
		}
		.if_stmt {
			else_l := g.new_label()
			end_l := g.new_label()
			g.gen_expr(st.cond)!
			g.code << op_jz
			g.code << obj.encode_i64(0)
			g.fixups << Fixup{ name: else_l, off: u32(g.code.len) - 8 }
			for s in st.body {
				g.gen_stmt(s)!
			}
			g.code << op_jmp
			g.code << obj.encode_i64(0)
			g.fixups << Fixup{ name: end_l, off: u32(g.code.len) - 8 }
			g.emit_label(else_l)
			for s in st.els {
				g.gen_stmt(s)!
			}
			g.emit_label(end_l)
		}
		.while_stmt {
			loop_l := g.new_label()
			end_l := g.new_label()
			g.emit_label(loop_l)
			g.gen_expr(st.cond)!
			g.code << op_jz
			g.code << obj.encode_i64(0)
			g.fixups << Fixup{ name: end_l, off: u32(g.code.len) - 8 }
			g.loops << LoopCtx{ break_l: end_l, continue_l: loop_l }
			for s in st.body {
				g.gen_stmt(s)!
			}
			g.loops.delete_last()
			g.code << op_jmp
			g.code << obj.encode_i64(0)
			g.fixups << Fixup{ name: loop_l, off: u32(g.code.len) - 8 }
			g.emit_label(end_l)
		}
		.for_range_stmt {
			// for i in a..b / for i in a...b  →  i := a; while i <(<=) b { body; i++ }
			var_idx := g.new_local()
			bound_idx := g.new_local()
			loop_l := g.new_label()
			inc_l := g.new_label()
			end_l := g.new_label()
			g.gen_expr(st.expr)!
			g.gen_expr(st.cond)!
			g.emit_store(bound_idx)
			g.emit_store(var_idx)
			g.emit_label(loop_l)
			g.emit_load(var_idx)
			g.emit_load(bound_idx)
			g.code << if st.inclusive { op_le } else { op_lt }
			g.code << op_jz
			g.code << obj.encode_i64(0)
			g.fixups << Fixup{ name: end_l, off: u32(g.code.len) - 8 }
			g.loops << LoopCtx{ break_l: end_l, continue_l: inc_l }
			prev := g.locals[st.target] or { -1 }
			g.locals[st.target] = var_idx
			for s in st.body {
				g.gen_stmt(s)!
			}
			if prev >= 0 {
				g.locals[st.target] = prev
			} else {
				g.locals.delete(st.target)
			}
			g.loops.delete_last()
			g.emit_label(inc_l)
			g.emit_load(var_idx)
			g.code << op_push_i
			g.code << obj.encode_i64(1)
			g.code << op_add
			g.emit_store(var_idx)
			g.code << op_jmp
			g.code << obj.encode_i64(0)
			g.fixups << Fixup{ name: loop_l, off: u32(g.code.len) - 8 }
			g.emit_label(end_l)
		}
		.for_in_stmt {
			// for x in arr  →  idx := 0; while idx < len(arr) { x := arr[idx]; body; idx++ }
			arr_idx := g.new_local()
			idx_idx := g.new_local()
			elem_idx := g.new_local()
			loop_l := g.new_label()
			inc_l := g.new_label()
			end_l := g.new_label()
			g.gen_expr(st.expr)!
			g.emit_store(arr_idx)
			g.code << op_push_i
			g.code << obj.encode_i64(0)
			g.emit_store(idx_idx)
			g.emit_label(loop_l)
			g.emit_load(idx_idx)
			g.emit_load(arr_idx)
			g.code << op_alen
			g.code << op_lt
			g.code << op_jz
			g.code << obj.encode_i64(0)
			g.fixups << Fixup{ name: end_l, off: u32(g.code.len) - 8 }
			g.loops << LoopCtx{ break_l: end_l, continue_l: inc_l }
			g.emit_load(arr_idx)
			g.emit_load(idx_idx)
			g.code << op_aget
			g.emit_store(elem_idx)
			prev := g.locals[st.target] or { -1 }
			g.locals[st.target] = elem_idx
			for s in st.body {
				g.gen_stmt(s)!
			}
			if prev >= 0 {
				g.locals[st.target] = prev
			} else {
				g.locals.delete(st.target)
			}
			g.loops.delete_last()
			g.emit_label(inc_l)
			g.emit_load(idx_idx)
			g.code << op_push_i
			g.code << obj.encode_i64(1)
			g.code << op_add
			g.emit_store(idx_idx)
			g.code << op_jmp
			g.code << obj.encode_i64(0)
			g.fixups << Fixup{ name: loop_l, off: u32(g.code.len) - 8 }
			g.emit_label(end_l)
		}
		.ret_stmt {
			if st.has_val {
				g.gen_expr(st.expr)!
				g.code << op_retv
			} else {
				g.code << op_ret
			}
		}
		.assert_stmt {
			g.gen_expr(st.expr)!
			g.code << op_assert
		}
		.break_stmt {
			if g.loops.len == 0 {
				return error('break outside of a loop (line ${st.line})')
			}
			ctx := g.loops[g.loops.len - 1]
			g.code << op_jmp
			g.code << obj.encode_i64(0)
			g.fixups << Fixup{ name: ctx.break_l, off: u32(g.code.len) - 8 }
		}
		.continue_stmt {
			if g.loops.len == 0 {
				return error('continue outside of a loop (line ${st.line})')
			}
			ctx := g.loops[g.loops.len - 1]
			g.code << op_jmp
			g.code << obj.encode_i64(0)
			g.fixups << Fixup{ name: ctx.continue_l, off: u32(g.code.len) - 8 }
		}
	}
}

fn (mut g Gen) gen_expr(e Expr) ! {
	match e.kind {
		.int_lit {
			g.code << op_push_i
			g.code << obj.encode_i64(e.int_v)
		}
		.str_lit {
			// the index is a placeholder; the linker rebases it via a string
			// relocation so multi-file links keep working
			g.code << op_push_s
			g.code << obj.encode_i64(0)
			g.relocs << obj.Reloc{ offset: u32(g.code.len) - 8, name: e.str_v, kind: 1 }
		}
		.array_lit {
			for el in e.elems {
				g.gen_expr(el)!
			}
			g.code << op_mkarray
			g.code << obj.encode_i64(i64(e.elems.len))
		}
		.index {
			g.gen_expr(*e.left)!
			g.gen_expr(*e.right)!
			g.code << op_aget
		}
		.bool_lit {
			g.code << op_push_i
			g.code << obj.encode_i64(e.int_v)
		}
		.ident {
			idx := g.locals[e.name] or {
				return error('unknown variable "${e.name}" at line ${e.line}')
			}
			g.code << op_load
			g.code << obj.encode_i64(i64(idx))
		}
		.unary {
			g.gen_expr(*e.right)!
			if e.op == .kw_not {
				g.code << op_not
			} else {
				g.code << op_neg
			}
		}
		.binary {
			g.gen_binary(e)!
		}
		.call {
			g.gen_call(e)!
		}
	}
}

fn (mut g Gen) gen_call(e Expr) ! {
	if e.name == 'print' || e.name == 'println' {
		if e.args.len != 1 {
			return error('${e.name}() takes exactly one argument (line ${e.line})')
		}
		g.gen_expr(e.args[0])!
		g.code << if e.name == 'print' { op_print } else { op_println }
		return
	}
	if e.name == 'len' {
		if e.args.len != 1 {
			return error('len() takes exactly one argument (line ${e.line})')
		}
		g.gen_expr(e.args[0])!
		g.code << op_alen
		return
	}
	if e.name == 'push' {
		if e.args.len != 2 {
			return error('push() takes exactly two arguments (line ${e.line})')
		}
		g.gen_expr(e.args[0])!
		g.gen_expr(e.args[1])!
		g.code << op_apush
		return
	}
	for a in e.args {
		g.gen_expr(a)!
	}
	g.code << op_call
	g.code << obj.encode_i64(0) // placeholder — patched by the linker
	g.relocs << obj.Reloc{ offset: u32(g.code.len) - 8, name: e.name, kind: 0 }
	g.code << obj.encode_i64(i64(e.args.len)) // argc
}

fn (mut g Gen) gen_binary(e Expr) ! {
	match e.op {
		.kw_and {
			// a and b  →  short-circuit: if !a or !b then 0 else 1
			false_l := g.new_label()
			end_l := g.new_label()
			g.gen_expr(*e.left)!
			g.code << op_jz
			g.code << obj.encode_i64(0)
			g.fixups << Fixup{ name: false_l, off: u32(g.code.len) - 8 }
			g.gen_expr(*e.right)!
			g.code << op_jz
			g.code << obj.encode_i64(0)
			g.fixups << Fixup{ name: false_l, off: u32(g.code.len) - 8 }
			g.code << op_push_i
			g.code << obj.encode_i64(1)
			g.code << op_jmp
			g.code << obj.encode_i64(0)
			g.fixups << Fixup{ name: end_l, off: u32(g.code.len) - 8 }
			g.emit_label(false_l)
			g.code << op_push_i
			g.code << obj.encode_i64(0)
			g.emit_label(end_l)
		}
		.kw_or {
			// a or b  →  short-circuit: if a or b then 1 else 0
			true_l := g.new_label()
			end_l := g.new_label()
			g.gen_expr(*e.left)!
			g.code << op_jnz
			g.code << obj.encode_i64(0)
			g.fixups << Fixup{ name: true_l, off: u32(g.code.len) - 8 }
			g.gen_expr(*e.right)!
			g.code << op_jnz
			g.code << obj.encode_i64(0)
			g.fixups << Fixup{ name: true_l, off: u32(g.code.len) - 8 }
			g.code << op_push_i
			g.code << obj.encode_i64(0)
			g.code << op_jmp
			g.code << obj.encode_i64(0)
			g.fixups << Fixup{ name: end_l, off: u32(g.code.len) - 8 }
			g.emit_label(true_l)
			g.code << op_push_i
			g.code << obj.encode_i64(1)
			g.emit_label(end_l)
		}
		else {
			g.gen_expr(*e.left)!
			g.gen_expr(*e.right)!
			op := match e.op {
				.plus { op_add }
				.minus { op_sub }
				.star { op_mul }
				.slash { op_div }
				.percent { op_mod }
				.eq_eq { op_eq }
				.not_eq { op_ne }
				.lt { op_lt }
				.le { op_le }
				.gt { op_gt }
				.ge { op_ge }
				else {
					return error('unsupported binary operator at line ${e.line}')
				}
			}
			g.code << op
		}
	}
}

fn (mut g Gen) intern(s string) int {
	if s in g.str_map {
		return g.str_map[s]
	}
	idx := g.strings.len
	g.strings << s
	g.str_map[s] = idx
	return idx
}

fn (mut g Gen) new_local() int {
	idx := g.local_cnt
	g.local_cnt++
	return idx
}

fn (mut g Gen) emit_load(idx int) {
	g.code << op_load
	g.code << obj.encode_i64(i64(idx))
}

fn (mut g Gen) emit_store(idx int) {
	g.code << op_store
	g.code << obj.encode_i64(i64(idx))
}



fn (mut g Gen) new_label() string {
	g.next_lbl++
	return 'L${g.next_lbl}'
}

fn (mut g Gen) emit_label(name string) {
	g.labels[name] = g.code.len
}
