// ops.v — arithmetic, comparison, and string operations for the VuurRaaf VM.
module vm

import math

fn (mut v Vm) add(a i64, b i64) !i64 {
	if v.is_arr(a) || v.is_arr(b) {
		return error('cannot add arrays with +')
	}
	if v.is_struct(a) || v.is_struct(b) {
		return error('cannot add structs with +')
	}
	if v.is_str(a) && v.is_str(b) {
		return v.alloc_str(v.strings[v.hand(a)] + v.strings[v.hand(b)])
	}
	if v.is_str(a) {
		return v.alloc_str(v.strings[v.hand(a)] + v.num_str(b))
	}
	if v.is_str(b) {
		return v.alloc_str(v.num_str(a) + v.strings[v.hand(b)])
	}
	if v.is_float(a) || v.is_float(b) {
		return v.push_float(v.to_f64(a) + v.to_f64(b))
	}
	return v.enc_int(v.dec_int(a) + v.dec_int(b))
}

// to_f64 promotes an integer or float tagged value to f64.
fn (mut v Vm) to_f64(x i64) f64 {
	if v.is_float(x) {
		return v.fval(x)
	}
	return f64(v.dec_int(x))
}

fn (mut v Vm) alloc_str(s string) i64 {
	v.strings << s
	return v.mkstr(v.strings.len - 1)
}

fn (mut v Vm) num_str(x i64) string {
	if v.is_float(x) {
		return fmt_float(v.fval(x))
	}
	return v.dec_int(x).str()
}

// fmt_float renders an f64 nicely: integral values lose the trailing ".0",
// -0 collapses to 0, and most floats avoid V's default scientific notation.
fn fmt_float(f f64) string {
	if f == 0.0 {
		return '0'
	}
	if math.is_nan(f) {
		return 'NaN'
	}
	if math.is_inf(f, 1) {
		return 'Inf'
	}
	if math.is_inf(f, -1) {
		return '-Inf'
	}
	if f == math.floor(f) && math.abs(f) < 1e18 {
		return i64(f).str()
	}
	if math.abs(f) < 1e18 {
		mut s := '${f:.14f}'
		s = s.trim_right('0').trim_right('.')
		if s == '' {
			return '0'
		}
		return s
	}
	return f.str()
}

fn (mut v Vm) arith(a i64, b i64, op string) !i64 {
	if v.is_str(a) || v.is_str(b) {
		return error('cannot use strings with "${op}"')
	}
	if v.is_arr(a) || v.is_arr(b) {
		return error('cannot use arrays with "${op}"')
	}
	if v.is_struct(a) || v.is_struct(b) {
		return error('cannot use structs with "${op}"')
	}
	if v.is_float(a) || v.is_float(b) {
		x := v.to_f64(a)
		y := v.to_f64(b)
		match op {
			'-' {
				return v.push_float(x - y)
			}
			'*' {
				return v.push_float(x * y)
			}
			'/' {
				if y == 0.0 {
					return error('division by zero')
				}
				return v.push_float(x / y)
			}
			'%' {
				if y == 0.0 {
					return error('division by zero')
				}
				return v.push_float(math.fmod(x, y))
			}
			else {
				return error('internal: bad arith op "${op}"')
			}
		}
	}
	x := v.dec_int(a)
	y := v.dec_int(b)
	match op {
		'-' {
			return v.enc_int(x - y)
		}
		'*' {
			return v.enc_int(x * y)
		}
		'/' {
			if y == 0 {
				return error('division by zero')
			}
			return v.enc_int(x / y)
		}
		'%' {
			if y == 0 {
				return error('division by zero')
			}
			return v.enc_int(x % y)
		}
		else {
			return error('internal: bad arith op "${op}"')
		}
	}
}

fn (mut v Vm) cmp(a i64, b i64, op string) !i64 {
	if v.is_arr(a) || v.is_arr(b) {
		// arrays compare by identity (handle equality) with ==/!=
		if op == '==' || op == '!=' {
			return bool_i64(if op == '==' { a == b } else { a != b })
		}
		return error('cannot order arrays')
	}
	if v.is_struct(a) || v.is_struct(b) {
		// structs compare by identity (handle equality) with ==/!=
		if op == '==' || op == '!=' {
			return bool_i64(if op == '==' { a == b } else { a != b })
		}
		return error('cannot order structs')
	}
	if v.is_str(a) && v.is_str(b) {
		sa := v.strings[v.hand(a)]
		sb := v.strings[v.hand(b)]
		return bool_i64(match op {
			'==' { sa == sb }
			'!=' { sa != sb }
			'<' { sa < sb }
			'<=' { sa <= sb }
			'>' { sa > sb }
			'>=' { sa >= sb }
			else { return error('internal: bad cmp op "${op}"') }
		})
	}
	if v.is_str(a) || v.is_str(b) {
		return error('cannot compare a string and a number')
	}
	if v.is_float(a) || v.is_float(b) {
		x := v.to_f64(a)
		y := v.to_f64(b)
		return bool_i64(match op {
			'==' { x == y }
			'!=' { x != y }
			'<' { x < y }
			'<=' { x <= y }
			'>' { x > y }
			'>=' { x >= y }
			else { return error('internal: bad cmp op "${op}"') }
		})
	}
	x := v.dec_int(a)
	y := v.dec_int(b)
	return bool_i64(match op {
		'==' { x == y }
		'!=' { x != y }
		'<' { x < y }
		'<=' { x <= y }
		'>' { x > y }
		'>=' { x >= y }
		else { return error('internal: bad cmp op "${op}"') }
	})
}
