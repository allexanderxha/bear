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
	return v.dec_int(x).str()
}

fn (mut v Vm) trace_op(op u8) {
	name := match op {
		op_halt { 'halt' }
		op_push_i { 'push_int' }
		op_push_s { 'push_str' }
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
		else { '??' }
	}
	mut s := ''
	for i in 0..v.sp {
		if i > 0 {
			s += ' '
		}
		if v.is_str(v.stack[i]) && v.valid_handle(v.stack[i]) {
			s += '"${v.strings[v.hand(v.stack[i])]}"'
		} else {
			s += v.val_str(v.stack[i], 0)
		}
	}
	println('  [ip=${v.ip:4}] ${name:-9}  stack: [${s}]')
}
