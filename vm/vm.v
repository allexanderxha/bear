// vm.v — the VuurRaaf runtime: a small stack-based virtual machine.
//
// Call convention: CALL pushes a frame (retaddr, old bp, argc) and copies the
// arguments into the callee's local slots; the callee reserves extra locals
// with `enter n` and cleans up with `ret`/`retv`.
module vm

import obj

// run executes the function named `entry` from the executable `bin` and
// returns its return value (0 if it never returns one).
pub fn run(bin obj.Bin, entry string, trace bool) !i64 {
	mut v := Vm{
		code:    bin.code
		strings: bin.strings.clone()
		stack:   []i64{len: stack_cap}
		trace:   trace
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
	v.exec()!
	if v.sp > 0 {
		return v.dec_int(v.stack[0])
	}
	return 0
}

fn (mut v Vm) exec() ! {
	for !v.halted {
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
				if v.is_str(a) {
					return error('cannot negate a string')
				}
				if v.is_arr(a) {
					return error('cannot negate an array')
				}
				if v.is_struct(a) {
					return error('cannot negate a struct')
				}
				v.push(v.enc_int(-v.dec_int(a)))!
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
				v.ip = int(v.read_i64())
			}
			op_jz {
				v.ip++
				target := int(v.read_i64())
				if !v.truthy(v.pop()!) {
					v.ip = target
				}
			}
			op_jnz {
				v.ip++
				target := int(v.read_i64())
				if v.truthy(v.pop()!) {
					v.ip = target
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
				if !v.is_arr(h) || !v.valid_arr_handle(h) {
					return error('indexing a non-array value')
				}
				a := v.arrays[v.hand(h)]
				if idx < 0 || idx >= a.len {
					return error('array index ${idx} out of bounds (len ${a.len})')
				}
				v.push(a[idx])!
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
				} else {
					return error('len() on a non-array, non-struct value')
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

fn (mut v Vm) read_i64() i64 {
	mut val := u64(0)
	for i in 0..8 {
		val |= u64(v.code[v.ip + i]) << u32(8 * i)
	}
	v.ip += 8
	return i64(val)
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
