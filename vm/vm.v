// vm.v — the VuurRaaf runtime: a small stack-based virtual machine.
//
// Stack values are 64-bit tagged integers with two tag bits:
//   low bits 00  -> encoded number  (value = raw << 2)
//   low bits 01  -> string handle   (handle = value >> 2, into v.strings)
//   low bits 11  -> array handle    (handle = value >> 2, into v.arrays)
// Encoding numbers with a constant shift means no integer ever collides with
// a string or array handle.
//
// Call convention: CALL pushes a frame (retaddr, old bp, argc) and copies the
// arguments into the callee's local slots; the callee reserves extra locals
// with `enter n` and cleans up with `ret`/`retv`.
module vm

import obj

// opcodes — keep in sync with the compiler, assembler, and this interpreter
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

const stack_cap = 65536

struct Vm {
mut:
	code    []u8
	strings []string
	arrays  [][]i64
	stack   []i64
	sp      int
	bp      int
	ip      int
	trace   bool
	halted  bool
}

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
				if !v.is_arr(h) || !v.valid_arr_handle(h) {
					return error('len() on a non-array value')
				}
				v.push(v.enc_int(i64(v.arrays[v.hand(h)].len)))!
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
			else {
				return error('unknown opcode ${op} at ip ${v.ip}')
			}
		}
	}
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

fn (mut v Vm) is_str(x i64) bool {
	return x & 3 == 1
}

fn (mut v Vm) is_arr(x i64) bool {
	return x & 3 == 3
}

fn (mut v Vm) enc_int(x i64) i64 {
	return x << 2
}

fn (mut v Vm) dec_int(x i64) i64 {
	return x >> 2
}

fn (mut v Vm) hand(x i64) int {
	return int(x >> 2)
}

fn (mut v Vm) mkstr(idx int) i64 {
	return (i64(idx) << 2) | 1
}

fn (mut v Vm) mkarr(idx int) i64 {
	return (i64(idx) << 2) | 3
}

fn (mut v Vm) truthy(x i64) bool {
	return x != 0
}

fn bool_i64(b bool) i64 {
	return if b { i64(1) } else { i64(0) }
}

fn (mut v Vm) add(a i64, b i64) !i64 {
	if v.is_arr(a) || v.is_arr(b) {
		return error('cannot add arrays with +')
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
	return v.dec_int(x).str()
}

fn (mut v Vm) valid_handle(x i64) bool {
	h := v.hand(x)
	return h >= 0 && h < v.strings.len
}

fn (mut v Vm) valid_arr_handle(x i64) bool {
	h := v.hand(x)
	return h >= 0 && h < v.arrays.len
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
