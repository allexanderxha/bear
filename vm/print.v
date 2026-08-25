// print.v — value rendering and instruction tracing for the VuurRaaf VM.
module vm

fn (mut v Vm) print_val(x i64) {
	print(v.val_str(x, 0))
}

// val_str renders a value: strings as-is, arrays as [a, b, ...] (with a depth
// guard so self-referential arrays cannot hang the printer), numbers as ints.
fn (mut v Vm) val_str(x i64, depth int) string {
	if depth > 16 {
		return '...'
	}
	if v.is_none(x) {
		return 'none'
	}
	if v.is_str(x) && v.valid_handle(x) {
		return v.strings[v.hand(x)]
	}
	if v.is_arr(x) && v.valid_arr_handle(x) {
		a := v.arrays[v.hand(x)]
		mut s := '['
		limit := if a.len > 20 { 20 } else { a.len }
		for i in 0..limit {
			if i > 0 {
				s += ', '
			}
			s += v.val_str(a[i], depth + 1)
		}
		if a.len > limit {
			s += ', ...'
		}
		return s + ']'
	}
	if v.is_struct(x) && v.valid_struct_handle(x) {
		s := v.structs[v.hand(x)]
		mut out := '{'
		limit := if s.fields.len > 20 { 20 } else { s.fields.len }
		for i in 0..limit {
			if i > 0 {
				out += ', '
			}
			out += s.fields[i].name + ': ' + v.val_str(s.fields[i].val, depth + 1)
		}
		if s.fields.len > limit {
			out += ', ...'
		}
		return out + '}'
	}
	if v.is_float(x) && v.valid_float_handle(x) {
		return fmt_float(v.fval(x))
	}
	if v.is_closure(x) && v.valid_closure_handle(x) {
		return '<fn@${v.closures[v.hand(x)].entry}>'
	}
	return v.dec_int(x).str()
}

fn (mut v Vm) trace_op(op u8) {
	name := match op {
		op_halt { 'halt' }
		op_push_i { 'push_int' }
		op_push_s { 'push_str' }
		op_push_f { 'push_float' }
		op_load { 'load' }
		op_store { 'store' }
		op_pop { 'pop' }
		op_dup { 'dup' }
		op_add { 'add' }
		op_sub { 'sub' }
		op_mul { 'mul' }
		op_div { 'div' }
		op_mod { 'mod' }
		op_neg { 'neg' }
		op_eq { 'eq' }
		op_ne { 'ne' }
		op_lt { 'lt' }
		op_le { 'le' }
		op_gt { 'gt' }
		op_ge { 'ge' }
		op_and { 'and' }
		op_or { 'or' }
		op_not { 'not' }
		op_jmp { 'jmp' }
		op_jz { 'jz' }
		op_jnz { 'jnz' }
		op_call { 'call' }
		op_ret { 'ret' }
		op_retv { 'retv' }
		op_print { 'print' }
		op_println { 'println' }
		op_assert { 'assert' }
		op_enter { 'enter' }
		op_mkarray { 'mkarray' }
		op_aget { 'aget' }
		op_aset { 'aset' }
		op_alen { 'alen' }
		op_apush { 'apush' }
		op_mkstruct { 'mkstruct' }
		op_sget { 'sget' }
		op_sset { 'sset' }
		op_shas { 'shas' }
		op_sdel { 'sdel' }
		op_slen { 'slen' }
		op_skeys { 'skeys' }
		op_slice { 'slice' }
		op_native { 'native' }
		op_and_b { 'and_b' }
		op_or_b { 'or_b' }
		op_xor { 'xor' }
		op_shl { 'shl' }
		op_shr { 'shr' }
		op_not_b { 'not_b' }
		op_try { 'try' }
		op_throw { 'throw' }
		op_catch_done { 'catch_done' }
		op_closure { 'closure' }
		op_call_closure { 'call_closure' }
		op_argc { 'argc' }
		op_load_dyn { 'load_dyn' }
		op_varargs { 'varargs' }
		op_str_method { 'str_method' }
		op_push_none { 'push_none' }
		else { '??' }
	}
	mut s := ''
	for i in 0..v.sp {
		if i > 0 {
			s += ' '
		}
		x := v.stack[i]
		if v.is_str(x) && v.valid_handle(x) {
			s += '"${v.strings[v.hand(x)]}"'
		} else if v.is_closure(x) {
			s += '<fn>'
		} else {
			s += v.val_str(x, 0)
		}
	}
	println('  [ip=${v.ip:4}] ${name:-9}  stack: [${s}]')
}
