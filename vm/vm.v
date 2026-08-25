// vm.v — the VuurRaaf runtime: a small stack-based virtual machine.
//
// Call convention: CALL pushes a frame (retaddr, old bp, argc) and copies the
// arguments into the callee's local slots; the callee reserves extra locals
// with `enter n` and cleans up with `ret`/`retv`.
module vm

import obj
import math

// run executes the function named `entry` from the executable `bin` and
// returns its return value (0 if it never returns one).
pub fn run(bin obj.Bin, entry string, trace bool) !i64 {
	return run_with_args(bin, entry, trace, []string{})
}

// run_with_args is run() with command-line arguments exposed to the program
// via the `args()` builtin.
pub fn run_with_args(bin obj.Bin, entry string, trace bool, args []string) !i64 {
	return run_internal(bin, entry, trace, args, '')!
}

// run_build executes a .vrmm build module: the entry target receives the
// extra CLI arguments via `args()`, and `build_root()` reports the module's
// own directory so scripts can find files regardless of the working directory.
pub fn run_build(bin obj.Bin, entry string, args []string, root string) !i64 {
	return run_internal(bin, entry, false, args, root)!
}

fn run_internal(bin obj.Bin, entry string, trace bool, args []string, root string) !i64 {
	mut v := Vm{
		code:       bin.code
		strings:    bin.strings.clone()
		stack:      []i64{len: stack_cap}
		trace:      trace
		prog_args:  args
		lines:      bin.lines
		const_strs: bin.strings.len
		build_root: root
	}
	mut entry_ip := -1
	for f in bin.fns {
		if f.name == entry {
			entry_ip = f.entry
			break
		}
	}
	if entry_ip < 0 {
		names := bin.fns.map(fn (f obj.BinFn) string {
			return f.name
		})
		return error('no function "${entry}" in program (available: ${names.join(', ')})')
	}
	// synthetic frame: retaddr = -1 (halt sentinel), old bp = 0, argc = 0
	v.stack[v.sp] = v.enc_int(-1)
	v.sp++
	v.stack[v.sp] = v.enc_int(0)
	v.sp++
	v.stack[v.sp] = v.enc_int(0)
	v.sp++
	v.bp = v.sp
	v.ip = entry_ip
	v.exec() or {
		return error('${err.msg()} at ${v.where()}')
	}
	if v.did_exit {
		return v.exit_code
	}
	if v.sp > 0 {
		return v.dec_int(v.stack[0])
	}
	return 0
}

// where returns a source-level location for the current instruction pointer:
// `line 12 (ip 345)` when debug info is available, otherwise just `(ip 345)`.
fn (v Vm) where() string {
	// line table entries are recorded in code order, so walk backwards from
	// the most recent entry to find the last one at or before v.ip
	for i := v.lines.len - 1; i >= 0; i-- {
		if v.ip >= int(v.lines[i].off) {
			return 'line ${v.lines[i].line} (ip ${v.ip})'
		}
	}
	return '(ip ${v.ip})'
}

fn (mut v Vm) exec() ! {
	for !v.halted {
		// garbage collection: runs between opcodes when the heap has grown by
		// gc_alloc_trigger entries since the last collection, so no live value
		// is ever mid-flight in an instruction handler
		heap := v.strings.len + v.arrays.len + v.structs.len + v.floats.len + v.closures.len
		if heap > v.last_heap + gc_alloc_trigger {
			v.collect()
			v.last_heap = v.strings.len + v.arrays.len + v.structs.len + v.floats.len + v.closures.len
		} else {
			v.last_heap = heap
		}
		op := v.code[v.ip]
		if v.trace {
			v.trace_op(op)
		}
		match op {
			op_halt {
				v.halted = true
			}
			op_push_i {
				v.ip++
				v.push(v.enc_int(v.read_i64()))!
			}
			op_push_s {
				v.ip++
				idx := int(v.read_i64())
				v.push(v.mkstr(idx))!
			}
			op_push_f {
				v.ip++
				f := v.read_f64()
				v.push(v.push_float(f))!
			}
			op_load {
				v.ip++
				idx := int(v.read_i64())
				v.push(v.stack[v.bp + idx])!
			}
			op_store {
				v.ip++
				idx := int(v.read_i64())
				v.stack[v.bp + idx] = v.pop()!
			}
			op_pop {
				v.ip++
				v.pop()!
			}
			op_dup {
				v.ip++
				a := v.pop()!
				v.push(a)!
				v.push(a)!
			}
			op_add {
				v.ip++
				b := v.pop()!
				a := v.pop()!
				v.push(v.add(a, b)!)!
			}
			op_sub {
				v.ip++
				b := v.pop()!
				a := v.pop()!
				v.push(v.arith(a, b, '-')!)!
			}
			op_mul {
				v.ip++
				b := v.pop()!
				a := v.pop()!
				v.push(v.arith(a, b, '*')!)!
			}
			op_div {
				v.ip++
				b := v.pop()!
				a := v.pop()!
				v.push(v.arith(a, b, '/')!)!
			}
			op_mod {
				v.ip++
				b := v.pop()!
				a := v.pop()!
				v.push(v.arith(a, b, '%')!)!
			}
			op_neg {
				v.ip++
				a := v.pop()!
				if v.is_float(a) {
					v.push(v.push_float(-v.fval(a)))!
				} else if v.is_str(a) {
					return error('cannot negate a string')
				} else if v.is_arr(a) {
					return error('cannot negate an array')
				} else if v.is_struct(a) {
					return error('cannot negate a struct')
				} else {
					v.push(v.enc_int(-v.dec_int(a)))!
				}
			}
			op_eq {
				v.ip++
				b := v.pop()!
				a := v.pop()!
				v.push(v.enc_int(v.cmp(a, b, '==')!))!
			}
			op_ne {
				v.ip++
				b := v.pop()!
				a := v.pop()!
				v.push(v.enc_int(v.cmp(a, b, '!=')!))!
			}
			op_lt {
				v.ip++
				b := v.pop()!
				a := v.pop()!
				v.push(v.enc_int(v.cmp(a, b, '<')!))!
			}
			op_le {
				v.ip++
				b := v.pop()!
				a := v.pop()!
				v.push(v.enc_int(v.cmp(a, b, '<=')!))!
			}
			op_gt {
				v.ip++
				b := v.pop()!
				a := v.pop()!
				v.push(v.enc_int(v.cmp(a, b, '>')!))!
			}
			op_ge {
				v.ip++
				b := v.pop()!
				a := v.pop()!
				v.push(v.enc_int(v.cmp(a, b, '>=')!))!
			}
			op_and {
				v.ip++
				b := v.pop()!
				a := v.pop()!
				v.push(v.enc_int(bool_i64(v.truthy(a) && v.truthy(b))))!
			}
			op_or {
				v.ip++
				b := v.pop()!
				a := v.pop()!
				v.push(v.enc_int(bool_i64(v.truthy(a) || v.truthy(b))))!
			}
			op_not {
				v.ip++
				a := v.pop()!
				v.push(v.enc_int(bool_i64(!v.truthy(a))))!
			}
			op_jmp {
				v.ip++
				// jump targets are PC-relative (delta from the end of the
				// operand), so merged/linked bytecode stays position-independent
				v.ip += int(v.read_i64())
			}
			op_jz {
				v.ip++
				target := int(v.read_i64())
				if !v.truthy(v.pop()!) {
					v.ip += target
				}
			}
			op_jnz {
				v.ip++
				target := int(v.read_i64())
				if v.truthy(v.pop()!) {
					v.ip += target
				}
			}
			op_call {
				v.ip++
				target := int(v.read_i64())
				argc := int(v.read_i64())
				v.call(target, argc)
			}
			op_ret {
				v.ret(false)!
			}
			op_retv {
				v.ret(true)!
			}
			op_print {
				v.ip++
				v.print_val(v.pop()!)
			}
			op_println {
				v.ip++
				v.print_val(v.pop()!)
				println('')
			}
			op_assert {
				v.ip++
				if !v.truthy(v.pop()!) {
					return error('assertion failed (ip ${v.ip})')
				}
			}
			op_enter {
				v.ip++
				n := int(v.read_i64())
				for _ in 0..n {
					v.push(0)!
				}
			}
			op_mkarray {
				v.ip++
				n := int(v.read_i64())
				mut arr := []i64{len: n}
				for i := n - 1; i >= 0; i-- {
					arr[i] = v.pop()!
				}
				v.arrays << arr
				v.push(v.mkarr(v.arrays.len - 1))!
			}
			op_aget {
				v.ip++
				idx := int(v.dec_int(v.pop()!))
				h := v.pop()!
				if v.is_arr(h) && v.valid_arr_handle(h) {
					a := v.arrays[v.hand(h)]
					if idx < 0 || idx >= a.len {
						return error('array index ${idx} out of bounds (len ${a.len})')
					}
					v.push(a[idx])!
				} else if v.is_str(h) && v.valid_handle(h) {
					// rune-based string indexing: s[i] is the i-th character
					runes := v.strings[v.hand(h)].runes()
					if idx < 0 || idx >= runes.len {
						return error('string index ${idx} out of bounds (len ${runes.len})')
					}
					v.push(v.alloc_str(runes[idx].str()))!
				} else {
					return error('indexing a non-array, non-string value')
				}
			}
			op_aset {
				v.ip++
				val := v.pop()!
				idx := int(v.dec_int(v.pop()!))
				h := v.pop()!
				if !v.is_arr(h) || !v.valid_arr_handle(h) {
					return error('indexing a non-array value')
				}
				if idx < 0 || idx >= v.arrays[v.hand(h)].len {
					return error('array index ${idx} out of bounds (len ${v.arrays[v.hand(h)].len})')
				}
				v.arrays[v.hand(h)][idx] = val
			}
			op_alen {
				v.ip++
				h := v.pop()!
				if v.is_arr(h) && v.valid_arr_handle(h) {
					v.push(v.enc_int(i64(v.arrays[v.hand(h)].len)))!
				} else if v.is_struct(h) && v.valid_struct_handle(h) {
					v.push(v.enc_int(i64(v.structs[v.hand(h)].fields.len)))!
				} else if v.is_str(h) && v.valid_handle(h) {
					v.push(v.enc_int(i64(v.strings[v.hand(h)].runes().len)))!
				} else {
					return error('len() on a non-array, non-struct, non-string value')
				}
			}
			op_apush {
				v.ip++
				val := v.pop()!
				h := v.pop()!
				if !v.is_arr(h) || !v.valid_arr_handle(h) {
					return error('push() on a non-array value')
				}
				v.arrays[v.hand(h)] << val
				v.push(h)!
			}
			op_mkstruct {
				v.ip++
				n := int(v.read_i64())
				mut fields := []Field{len: n}
				// stack holds (name, value) pairs; pop from the last field back
				for i := n - 1; i >= 0; i-- {
					val := v.pop()!
					name := v.pop()!
					if !v.is_str(name) || !v.valid_handle(name) {
						return error('internal: struct field name is not a string')
					}
					fields[i] = Field{ name: v.strings[v.hand(name)], val: val }
				}
				v.structs << StructVal{ fields: fields }
				v.push(v.mkstruct_handle(v.structs.len - 1))!
			}
			op_sget {
				v.ip++
				name := v.pop()!
				h := v.pop()!
				if !v.is_struct(h) || !v.valid_struct_handle(h) {
					return error('field access on a non-struct value')
				}
				if !v.is_str(name) || !v.valid_handle(name) {
					return error('internal: field name is not a string')
				}
				fname := v.strings[v.hand(name)]
				mut found := false
				for f in v.structs[v.hand(h)].fields {
					if f.name == fname {
						v.push(f.val)!
						found = true
						break
					}
				}
				if !found {
					return error('no field "${fname}" on struct')
				}
			}
			op_sset {
				v.ip++
				// stack: [struct, value, "name"] — the name is on top
				name := v.pop()!
				val := v.pop()!
				h := v.pop()!
				if !v.is_struct(h) || !v.valid_struct_handle(h) {
					return error('field assignment on a non-struct value')
				}
				if !v.is_str(name) || !v.valid_handle(name) {
					return error('internal: field name is not a string')
				}
				fname := v.strings[v.hand(name)]
				mut s := v.structs[v.hand(h)]
				mut found := false
				for i, f in s.fields {
					if f.name == fname {
						s.fields[i].val = val
						found = true
						break
					}
				}
				if !found {
					// setting a missing field adds it, so records can be built
					// incrementally from an empty `{}`
					s.fields << Field{ name: fname, val: val }
				}
				v.structs[v.hand(h)] = s
			}
			op_shas {
				v.op_shas()!
			}
			op_sdel {
				v.op_sdel()!
			}
			op_slen {
				v.op_slen()!
			}
			op_skeys {
				v.op_skeys()!
			}
			op_slice {
				v.op_slice()!
			}
			op_native {
				v.ip++
				id := int(v.read_i64())
				argc := int(v.read_i64())
				v.native(id, argc) or {
					// a failed builtin becomes a VM-level throw, so try/catch can
					// intercept it exactly like an explicit `throw`; with no
					// handler it keeps propagating to the caller
					if v.handlers.len == 0 {
						return err
					}
					h := v.handlers[v.handlers.len - 1]
					v.handlers.delete_last()
					v.bp = h.bp
					v.sp = h.sp
					v.push(v.alloc_str(err.msg()))!
					v.ip = h.ip
				}
			}
			op_and_b {
				v.ip++
				b := v.pop()!
				a := v.pop()!
				v.push(v.enc_int(v.dec_int(a) & v.dec_int(b)))!
			}
			op_or_b {
				v.ip++
				b := v.pop()!
				a := v.pop()!
				v.push(v.enc_int(v.dec_int(a) | v.dec_int(b)))!
			}
			op_xor {
				v.ip++
				b := v.pop()!
				a := v.pop()!
				v.push(v.enc_int(v.dec_int(a) ^ v.dec_int(b)))!
			}
			op_shl {
				v.ip++
				b := v.pop()!
				a := v.pop()!
				x := v.dec_int(a)
				y := u32(v.dec_int(b))
				v.push(v.enc_int(x << y))!
			}
			op_shr {
				v.ip++
				b := v.pop()!
				a := v.pop()!
				x := v.dec_int(a)
				y := u32(v.dec_int(b))
				v.push(v.enc_int(x >> y))!
			}
			op_not_b {
				v.ip++
				a := v.pop()!
				v.push(v.enc_int(~v.dec_int(a)))!
			}
			op_try {
				v.ip++
				catch_ip := int(v.read_i64()) + v.ip
				v.handlers << Handler{ ip: catch_ip, bp: v.bp, sp: v.sp }
			}
			op_throw {
				v.ip++
				err_val := v.pop()!
				if v.handlers.len == 0 {
					return error('unhandled throw: ${v.val_str(err_val, 0)}')
				}
				h := v.handlers[v.handlers.len - 1]
				v.handlers.delete_last()
				v.bp = h.bp
				v.sp = h.sp
				v.push(err_val)!
				v.ip = h.ip
			}
			op_catch_done {
				v.ip++
				if v.handlers.len > 0 {
					v.handlers.delete_last()
				}
			}
			op_closure {
				v.ip++
				entry := int(v.read_i64())
				v.closures << Closure{ entry: entry }
				v.push(v.mkclosure(v.closures.len - 1))!
			}
			op_call_closure {
				v.ip++
				argc := int(v.read_i64())
				// stack: [...closure, arg_0, ..., arg_{argc-1}]
				h := v.stack[v.sp - argc - 1]
				if !v.is_closure(h) || !v.valid_closure_handle(h) {
					return error('cannot call a non-function value')
				}
				entry := v.closures[v.hand(h)].entry
				// Shift args left to overwrite the closure slot (and drop the
				// duplicated tail), so the callee's retv lands exactly where the
				// call sequence began and no stale value is left below the
				// result. The caller's own local holding the closure sits below
				// the pushed sequence and is never touched.
				for i := 0; i < argc; i++ {
					v.stack[v.sp - argc - 1 + i] = v.stack[v.sp - argc + i]
				}
				v.sp-- // drop the duplicated arg tail; closure slot was consumed
				v.call(entry, argc)
			}
			op_argc {
				v.ip++
				argc := v.dec_int(v.stack[v.bp - 1])
				v.push(v.enc_int(argc))!
			}
			op_load_dyn {
				v.ip++
				idx := int(v.dec_int(v.pop()!))
				if v.bp + idx < 0 || v.bp + idx >= v.sp {
					return error('dynamic load index ${idx} out of range')
				}
				v.push(v.stack[v.bp + idx])!
			}
			op_varargs {
				v.ip++
				named := int(v.read_i64())
				dst := int(v.read_i64())
				argc := int(v.dec_int(v.stack[v.bp - 1]))
				mut n := argc - named
				if n < 0 {
					n = 0
				}
				mut arr := []i64{len: n}
				for i in 0..n {
					arr[i] = v.stack[v.bp + named + i]
				}
				v.arrays << arr
				v.stack[v.bp + dst] = v.mkarr(v.arrays.len - 1)
			}
			op_str_method {
				v.ip++
				sidx := int(v.read_i64())
				argc := int(v.read_i64())
				v.str_method(v.strings[sidx], argc)!
			}
			op_push_none {
				v.ip++
				v.push(none_val)!
			}
			else {
				return error('unknown opcode ${op} at ip ${v.ip}')
			}
		}
	}
}

// op_shas checks if a struct has a field with the given name.
// stack: struct, "key"  →  pushes 1 if found, 0 if not.
fn (mut v Vm) op_shas() ! {
	v.ip++
	name := v.pop()!
	h := v.pop()!
	if !v.is_struct(h) || !v.valid_struct_handle(h) {
		return error('has() on a non-struct value')
	}
	if !v.is_str(name) || !v.valid_handle(name) {
		return error('internal: field name is not a string')
	}
	fname := v.strings[v.hand(name)]
	mut found := false
	for f in v.structs[v.hand(h)].fields {
		if f.name == fname {
			found = true
			break
		}
	}
	v.push(v.enc_int(if found { 1 } else { 0 }))!
}

// op_sdel removes a field from a struct.
// stack: struct, "key"  →  pushes the struct handle back.
fn (mut v Vm) op_sdel() ! {
	v.ip++
	name := v.pop()!
	h := v.pop()!
	if !v.is_struct(h) || !v.valid_struct_handle(h) {
		return error('delete() on a non-struct value')
	}
	if !v.is_str(name) || !v.valid_handle(name) {
		return error('internal: field name is not a string')
	}
	fname := v.strings[v.hand(name)]
	mut s := v.structs[v.hand(h)]
	mut new_fields := []Field{}
	for f in s.fields {
		if f.name != fname {
			new_fields << f
		}
	}
	s.fields = new_fields
	v.structs[v.hand(h)] = s
	v.push(h)!
}

// op_slen returns the number of fields in a struct.
// stack: struct  →  pushes field count.
fn (mut v Vm) op_slen() ! {
	v.ip++
	h := v.pop()!
	if !v.is_struct(h) || !v.valid_struct_handle(h) {
		return error('len() on a non-struct value')
	}
	v.push(v.enc_int(i64(v.structs[v.hand(h)].fields.len)))!
}

// op_skeys returns an array of field name strings.
// stack: struct  →  pushes array handle.
fn (mut v Vm) op_skeys() ! {
	v.ip++
	h := v.pop()!
	if !v.is_struct(h) || !v.valid_struct_handle(h) {
		return error('keys() on a non-struct value')
	}
	mut arr := []i64{}
	for f in v.structs[v.hand(h)].fields {
		v.strings << f.name
		arr << v.mkstr(v.strings.len - 1)
	}
	v.arrays << arr
	v.push(v.mkarr(v.arrays.len - 1))!
}

// op_slice slices an array or string: stack = [value, start, end] → sliced value.
// end == -1 means "open-ended" (slice to the end).
fn (mut v Vm) op_slice() ! {
	v.ip++
	end_val := v.dec_int(v.pop()!)
	start_val := v.dec_int(v.pop()!)
	h := v.pop()!
	// --- array slicing ---
	if v.is_arr(h) && v.valid_arr_handle(h) {
		arr := v.arrays[v.hand(h)]
		mut s := if start_val < 0 { 0 } else { int(start_val) }
		mut e := if end_val < 0 { arr.len } else { int(end_val) }
		if s > arr.len {
			s = arr.len
		}
		if e > arr.len {
			e = arr.len
		}
		if s > e {
			e = s
		}
		mut sliced := []i64{}
		for i in s..e {
			sliced << arr[i]
		}
		v.arrays << sliced
		v.push(v.mkarr(v.arrays.len - 1))!
		return
	}
	// --- string slicing ---
	if v.is_str(h) && v.valid_handle(h) {
		src := v.strings[v.hand(h)]
		runes := src.runes()
		mut s := if start_val < 0 { 0 } else { int(start_val) }
		mut e := if end_val < 0 { runes.len } else { int(end_val) }
		if s > runes.len {
			s = runes.len
		}
		if e > runes.len {
			e = runes.len
		}
		if s > e {
			e = s
		}
		mut sliced := ''
		for i in s..e {
			sliced += runes[i].str()
		}
		v.push(v.alloc_str(sliced))!
		return
	}
	return error('slice() on a non-array, non-string value')
}

fn (mut v Vm) read_i64() i64 {
	mut val := u64(0)
	for i in 0..8 {
		val |= u64(v.code[v.ip + i]) << u32(8 * i)
	}
	v.ip += 8
	return i64(val)
}

fn (mut v Vm) read_f64() f64 {
	mut val := u64(0)
	for i in 0..8 {
		val |= u64(v.code[v.ip + i]) << u32(8 * i)
	}
	v.ip += 8
	return math.f64_from_bits(val)
}

fn (mut v Vm) push(x i64) ! {
	if v.sp >= v.stack.len {
		return error('stack overflow')
	}
	v.stack[v.sp] = x
	v.sp++
}

fn (mut v Vm) pop() !i64 {
	if v.sp <= 0 {
		return error('stack underflow')
	}
	v.sp--
	return v.stack[v.sp]
}

fn (mut v Vm) call(target int, argc int) {
	v.stack[v.sp] = v.enc_int(i64(v.ip)) // return address (ip already past both operands)
	v.sp++
	v.stack[v.sp] = v.enc_int(i64(v.bp))
	v.sp++
	v.stack[v.sp] = v.enc_int(i64(argc))
	v.sp++
	v.bp = v.sp
	// copy the arguments below the frame into local slots 0..argc-1
	for i in 0..argc {
		v.stack[v.bp + i] = v.stack[v.bp - 3 - argc + i]
	}
	v.sp = v.bp + argc
	v.ip = target
}

fn (mut v Vm) ret(with_val bool) ! {
	retval := if with_val { v.pop()! } else { v.enc_int(0) }
	v.sp = v.bp - 1
	argc := int(v.dec_int(v.stack[v.sp]))
	v.sp = v.bp - 2
	old_bp := int(v.dec_int(v.stack[v.sp]))
	v.sp = v.bp - 3
	ip := int(v.dec_int(v.stack[v.sp]))
	v.sp -= argc
	v.bp = old_bp
	if ip == -1 {
		// returned to the synthetic frame: we are done
		v.halted = true
		v.push(retval)!
		return
	}
	v.ip = ip
	v.push(retval)!
}
