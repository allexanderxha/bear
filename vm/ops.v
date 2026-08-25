// ops.v — arithmetic, comparison, and string operations for the VuurRaaf VM.
module vm

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
	return v.enc_int(v.dec_int(a) + v.dec_int(b))
}

fn (mut v Vm) alloc_str(s string) i64 {
	v.strings << s
	return v.mkstr(v.strings.len - 1)
}

fn (mut v Vm) num_str(x i64) string {
	return v.dec_int(x).str()
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
