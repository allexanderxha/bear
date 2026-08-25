// native.v — host builtins for the VuurRaaf VM.
//
// The op_native instruction carries a builtin id and an argument count. Each
// builtin pops its arguments off the stack (left-to-right push order means the
// last argument is on top) and pushes a single result (except exit(), which
// halts the machine). This is where the language touches the host: file I/O,
// environment, time, randomness, and the math/collection helpers.
module vm

import os
import math
import rand
import time

fn (mut v Vm) native(id int, _argc int) ! {
	match id {
		native_abs {
			x := v.pop()!
			if v.is_float(x) {
				v.push(v.push_float(math.abs(v.fval(x))))!
			} else {
				val := v.dec_int(x)
				v.push(v.enc_int(if val < 0 { -val } else { val }))!
			}
		}
		native_min {
			b := v.pop()!
			a := v.pop()!
			if v.is_float(a) || v.is_float(b) {
				v.push(v.push_float(math.min(v.to_f64(a), v.to_f64(b))))!
			} else {
				x := v.dec_int(a)
				y := v.dec_int(b)
				v.push(v.enc_int(if x < y { x } else { y }))!
			}
		}
		native_max {
			b := v.pop()!
			a := v.pop()!
			if v.is_float(a) || v.is_float(b) {
				v.push(v.push_float(math.max(v.to_f64(a), v.to_f64(b))))!
			} else {
				x := v.dec_int(a)
				y := v.dec_int(b)
				v.push(v.enc_int(if x > y { x } else { y }))!
			}
		}
		native_pow {
			b := v.pop()!
			a := v.pop()!
			v.push(v.push_float(math.pow(v.to_f64(a), v.to_f64(b))))!
		}
		native_sqrt {
			x := v.pop()!
			v.push(v.push_float(math.sqrt(v.to_f64(x))))!
		}
		native_floor {
			x := v.pop()!
			v.push(v.enc_int(i64(math.floor(v.to_f64(x)))))!
		}
		native_ceil {
			x := v.pop()!
			v.push(v.enc_int(i64(math.ceil(v.to_f64(x)))))!
		}
		native_round {
			x := v.pop()!
			v.push(v.enc_int(i64(math.round(v.to_f64(x)))))!
		}
		native_rand {
			v.push(v.push_float(rand.f64()))!
		}
		native_rand_int {
			n := int(v.dec_int(v.pop()!))
			if n <= 0 {
				return error('rand_int() expects a positive bound')
			}
			v.push(v.enc_int(i64(rand.intn(n) or { return error('rand_int() failed') })))!
		}
		native_int {
			x := v.pop()!
			if v.is_str(x) && v.valid_handle(x) {
				v.push(v.enc_int(i64(v.strings[v.hand(x)].i64())))!
			} else if v.is_float(x) {
				v.push(v.enc_int(i64(v.fval(x))))!
			} else if v.is_arr(x) || v.is_struct(x) {
				return error('cannot convert a ${v.type_name(x)} to int')
			} else {
				v.push(x)!
			}
		}
		native_str {
			x := v.pop()!
			v.push(v.alloc_str(v.val_str(x, 0)))!
		}
		native_float {
			x := v.pop()!
			if v.is_str(x) && v.valid_handle(x) {
				v.push(v.push_float(v.strings[v.hand(x)].f64()))!
			} else if v.is_float(x) {
				v.push(x)!
			} else if v.is_arr(x) || v.is_struct(x) {
				return error('cannot convert a ${v.type_name(x)} to float')
			} else {
				v.push(v.push_float(f64(v.dec_int(x))))!
			}
		}
		native_type {
			x := v.pop()!
			v.push(v.alloc_str(v.type_name(x)))!
		}
		native_split {
			delim := v.pop_str()!
			s := v.pop_str()!
			parts := s.split(delim)
			mut arr := []i64{}
			for p in parts {
				v.strings << p
				arr << v.mkstr(v.strings.len - 1)
			}
			v.arrays << arr
			v.push(v.mkarr(v.arrays.len - 1))!
		}
		native_join {
			delim := v.pop_str()!
			h := v.pop()!
			if !v.is_arr(h) || !v.valid_arr_handle(h) {
				return error('join() expects an array as its first argument')
			}
			a := v.arrays[v.hand(h)]
			mut parts := []string{}
			for x in a {
				if v.is_str(x) && v.valid_handle(x) {
					parts << v.strings[v.hand(x)]
				} else {
					parts << v.val_str(x, 0)
				}
			}
			v.push(v.alloc_str(parts.join(delim)))!
		}
		native_contains {
			sub := v.pop_str()!
			s := v.pop_str()!
			v.push(v.enc_int(bool_i64(s.contains(sub))))!
		}
		native_starts_with {
			sub := v.pop_str()!
			s := v.pop_str()!
			v.push(v.enc_int(bool_i64(s.starts_with(sub))))!
		}
		native_ends_with {
			sub := v.pop_str()!
			s := v.pop_str()!
			v.push(v.enc_int(bool_i64(s.ends_with(sub))))!
		}
		native_trim {
			s := v.pop_str()!
			v.push(v.alloc_str(s.trim_space()))!
		}
		native_lower {
			s := v.pop_str()!
			v.push(v.alloc_str(s.to_lower()))!
		}
		native_upper {
			s := v.pop_str()!
			v.push(v.alloc_str(s.to_upper()))!
		}
		native_pop {
			h := v.pop()!
			if !v.is_arr(h) || !v.valid_arr_handle(h) {
				return error('pop() expects an array')
			}
			mut a := v.arrays[v.hand(h)]
			if a.len == 0 {
				return error('pop() on an empty array')
			}
			val := a[a.len - 1]
			v.arrays[v.hand(h)] = a[..a.len - 1]
			v.push(val)!
		}
		native_insert {
			val := v.pop()!
			idx := int(v.dec_int(v.pop()!))
			h := v.pop()!
			if !v.is_arr(h) || !v.valid_arr_handle(h) {
				return error('insert() expects an array as its first argument')
			}
			a := v.arrays[v.hand(h)]
			if idx < 0 || idx > a.len {
				return error('insert index ${idx} out of bounds (len ${a.len})')
			}
			mut na := []i64{}
			for i, x in a {
				if i == idx {
					na << val
				}
				na << x
			}
			if idx == a.len {
				na << val
			}
			v.arrays[v.hand(h)] = na
			v.push(h)!
		}
		native_remove {
			idx := int(v.dec_int(v.pop()!))
			h := v.pop()!
			if !v.is_arr(h) || !v.valid_arr_handle(h) {
				return error('remove() expects an array as its first argument')
			}
			a := v.arrays[v.hand(h)]
			if idx < 0 || idx >= a.len {
				return error('remove index ${idx} out of bounds (len ${a.len})')
			}
			mut na := []i64{}
			for i, x in a {
				if i != idx {
					na << x
				}
			}
			v.arrays[v.hand(h)] = na
			v.push(h)!
		}
		native_sort {
			h := v.pop()!
			if !v.is_arr(h) || !v.valid_arr_handle(h) {
				return error('sort() expects an array')
			}
			mut a := v.arrays[v.hand(h)]
			// insertion sort by numeric value
			for i in 1..a.len {
				key := a[i]
				mut j := i - 1
				for j >= 0 && v.num_gt(a[j], key) {
					a[j + 1] = a[j]
					j--
				}
				a[j + 1] = key
			}
			v.push(h)!
		}
		native_clone {
			x := v.pop()!
			if v.is_arr(x) && v.valid_arr_handle(x) {
				v.arrays << v.arrays[v.hand(x)].clone()
				v.push(v.mkarr(v.arrays.len - 1))!
			} else if v.is_struct(x) && v.valid_struct_handle(x) {
				s := v.structs[v.hand(x)]
				v.structs << StructVal{ fields: s.fields.clone() }
				v.push(v.mkstruct_handle(v.structs.len - 1))!
			} else if v.is_str(x) && v.valid_handle(x) {
				v.push(v.alloc_str(v.strings[v.hand(x)]))!
			} else if v.is_float(x) {
				v.push(v.push_float(v.fval(x)))!
			} else {
				v.push(x)!
			}
		}
		native_reverse {
			h := v.pop()!
			if !v.is_arr(h) || !v.valid_arr_handle(h) {
				return error('reverse() expects an array')
			}
			mut a := v.arrays[v.hand(h)]
			for i in 0..a.len / 2 {
				a[i], a[a.len - 1 - i] = a[a.len - 1 - i], a[i]
			}
			v.push(h)!
		}
		native_index_of {
			val := v.pop()!
			h := v.pop()!
			if v.is_arr(h) && v.valid_arr_handle(h) {
				a := v.arrays[v.hand(h)]
				for i, x in a {
					if v.cmp(x, val, '==')! == 1 {
						v.push(v.enc_int(i64(i)))!
						return
					}
				}
				v.push(v.enc_int(-1))!
				return
			}
			if v.is_str(h) && v.valid_handle(h) {
				if !v.is_str(val) || !v.valid_handle(val) {
					return error('index_of() on a string expects a string needle')
				}
				s := v.strings[v.hand(h)]
				needle := v.strings[v.hand(val)]
				byte_idx := s.index(needle) or { -1 }
				if byte_idx < 0 {
					v.push(v.enc_int(-1))!
					return
				}
				// convert byte offset to a rune index so UTF-8 strings count characters
				rune_idx := s[..byte_idx].runes().len
				v.push(v.enc_int(i64(rune_idx)))!
				return
			}
			return error('index_of() expects an array or string as its first argument')
		}
		native_args {
			mut arr := []i64{}
			for s in v.prog_args {
				v.strings << s
				arr << v.mkstr(v.strings.len - 1)
			}
			v.arrays << arr
			v.push(v.mkarr(v.arrays.len - 1))!
		}
		native_getenv {
			name := v.pop_str()!
			v.push(v.alloc_str(os.getenv(name)))!
		}
		native_setenv {
			val := v.pop_str()!
			name := v.pop_str()!
			os.setenv(name, val, true)
			v.push(v.enc_int(0))!
		}
		native_exit {
			code := int(v.dec_int(v.pop()!))
			v.exit_code = i64(code)
			v.did_exit = true
			v.halted = true
		}
		native_time {
			v.push(v.push_float(f64(time.now().unix_milli()) / 1000.0))!
		}
		native_sleep {
			ms := int(v.dec_int(v.pop()!))
			time.sleep(time.Duration(ms) * time.millisecond)
			v.push(v.enc_int(0))!
		}
		native_read_file {
			path := v.pop_str()!
			content := os.read_file(path) or { return error('cannot read file "${path}": ${err}') }
			v.push(v.alloc_str(content))!
		}
		native_write_file {
			content := v.pop_str()!
			path := v.pop_str()!
			os.write_file(path, content) or { return error('cannot write file "${path}": ${err}') }
			v.push(v.enc_int(0))!
		}
		native_eprint {
			x := v.pop()!
			eprintln(v.val_str(x, 0))
		}
		else {
			return error('unknown native builtin ${id}')
		}
	}
}

// pop_str pops the top value and requires it to be a string.
fn (mut v Vm) pop_str() !string {
	x := v.pop()!
	if !v.is_str(x) || !v.valid_handle(x) {
		return error('expected a string argument')
	}
	return v.strings[v.hand(x)]
}

// type_name returns the type label of a tagged value.
fn (mut v Vm) type_name(x i64) string {
	if v.is_str(x) {
		return 'string'
	}
	if v.is_float(x) {
		return 'float'
	}
	if v.is_arr(x) {
		return 'array'
	}
	if v.is_struct(x) {
		return 'struct'
	}
	return 'int'
}

// str_method dispatches a string method call. The receiver was pushed before
// the arguments, so it is the first argument from the native builtin's point
// of view; delegating keeps the behavior identical to the free-function forms.
fn (mut v Vm) str_method(name string, argc int) ! {
	bid := match name {
		'to_upper' { native_upper }
		'to_lower' { native_lower }
		'trim' { native_trim }
		'contains' { native_contains }
		'starts_with' { native_starts_with }
		'ends_with' { native_ends_with }
		'split' { native_split }
		'index_of' { native_index_of }
		'to_int' { native_int }
		'to_float' { native_float }
		else { -1 }
	}
	if bid >= 0 {
		// native builtins pop the first argument (the receiver) last
		v.native(bid, argc + 1)!
		return
	}
	if name == 'len' {
		h := v.pop()!
		if !v.is_str(h) || !v.valid_handle(h) {
			return error('len() on a non-string value')
		}
		v.push(v.enc_int(i64(v.strings[v.hand(h)].runes().len)))!
		return
	}
	return error('unknown string method "${name}"')
}

// num_gt compares two values by their numeric value (int or float).
fn (mut v Vm) num_gt(x i64, y i64) bool {
	if v.is_float(x) || v.is_float(y) {
		return v.to_f64(x) > v.to_f64(y)
	}
	return v.dec_int(x) > v.dec_int(y)
}
