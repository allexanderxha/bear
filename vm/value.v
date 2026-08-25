// value.v — tagged value encoding and helpers for the VuurRaaf VM.
//
// Stack values are 64-bit tagged integers with three tag bits:
//   low bits 000 -> encoded integer (value = raw << 3)
//   low bits 001 -> string handle   (handle = value >> 3, into v.strings)
//   low bits 010 -> struct handle   (handle = value >> 3, into v.structs)
//   low bits 011 -> array handle    (handle = value >> 3, into v.arrays)
//   low bits 100 -> float handle    (handle = value >> 3, into v.floats)
module vm

const tag_mask = u64(7)
const tag_int = u64(0)
const tag_str = u64(1)
const tag_struct = u64(2)
const tag_arr = u64(3)
const tag_float = u64(4)
const tag_closure = u64(5)
const tag_builder = u64(7)

// none_val is the sentinel for the `none` literal (and JSON null). Tag 110
// is not a valid encoded integer (those are multiples of 8) nor any handle,
// so it can never collide with a real value. The GC ignores it (its tag
// matches no heap pool).
const none_val = i64(6)

fn (mut v Vm) tag(x i64) u64 {
	return u64(x) & tag_mask
}

fn (mut v Vm) is_int(x i64) bool {
	return u64(x) & tag_mask == tag_int
}

fn (mut v Vm) is_str(x i64) bool {
	return u64(x) & tag_mask == tag_str
}

fn (mut v Vm) is_struct(x i64) bool {
	return u64(x) & tag_mask == tag_struct
}

fn (mut v Vm) is_arr(x i64) bool {
	return u64(x) & tag_mask == tag_arr
}

fn (mut v Vm) is_float(x i64) bool {
	return u64(x) & tag_mask == tag_float
}

fn (mut v Vm) is_closure(x i64) bool {
	return u64(x) & tag_mask == tag_closure
}

fn (mut v Vm) is_builder(x i64) bool {
	return u64(x) & tag_mask == tag_builder
}

fn (mut v Vm) is_none(x i64) bool {
	return x == none_val
}

// is_num reports whether x is an integer (tag 0). Floats are a distinct type.
fn (mut v Vm) is_num(x i64) bool {
	return u64(x) & tag_mask == tag_int
}

fn (mut v Vm) enc_int(x i64) i64 {
	return i64(u64(x) << 3)
}

fn (mut v Vm) dec_int(x i64) i64 {
	return x >> 3
}

fn (mut v Vm) hand(x i64) int {
	return int(x >> 3)
}

fn (mut v Vm) mkstr(idx int) i64 {
	return i64((u64(idx) << 3) | tag_str)
}

fn (mut v Vm) mkarr(idx int) i64 {
	return i64((u64(idx) << 3) | tag_arr)
}

fn (mut v Vm) mkstruct_handle(idx int) i64 {
	return i64((u64(idx) << 3) | tag_struct)
}

fn (mut v Vm) mkfloat(idx int) i64 {
	return i64((u64(idx) << 3) | tag_float)
}

fn (mut v Vm) mkclosure(idx int) i64 {
	return i64((u64(idx) << 3) | tag_closure)
}

fn (mut v Vm) mkbuilder(idx int) i64 {
	return i64((u64(idx) << 3) | tag_builder)
}

// push_float interns a float into the pool and returns its tagged handle.
fn (mut v Vm) push_float(f f64) i64 {
	v.floats << f
	return v.mkfloat(v.floats.len - 1)
}

// fval returns the f64 value of a float handle.
fn (mut v Vm) fval(x i64) f64 {
	return v.floats[v.hand(x)]
}

fn (mut v Vm) truthy(x i64) bool {
	if v.is_none(x) {
		return false
	}
	if v.is_float(x) {
		return v.fval(x) != 0.0
	}
	return x != 0
}

fn (mut v Vm) valid_handle(x i64) bool {
	h := v.hand(x)
	return h >= 0 && h < v.strings.len
}

fn (mut v Vm) valid_arr_handle(x i64) bool {
	h := v.hand(x)
	return h >= 0 && h < v.arrays.len
}

fn (mut v Vm) valid_struct_handle(x i64) bool {
	h := v.hand(x)
	return h >= 0 && h < v.structs.len
}

fn (mut v Vm) valid_float_handle(x i64) bool {
	h := v.hand(x)
	return h >= 0 && h < v.floats.len
}

fn (mut v Vm) valid_closure_handle(x i64) bool {
	h := v.hand(x)
	return h >= 0 && h < v.closures.len
}

fn (mut v Vm) valid_builder_handle(x i64) bool {
	h := v.hand(x)
	return h >= 0 && h < v.builders.len
}

// valid_handle_for bounds-checks a handle against the pool matching its tag.
fn (mut v Vm) valid_handle_for(x i64) bool {
	return match v.tag(x) {
		tag_str { v.valid_handle(x) }
		tag_struct { v.valid_struct_handle(x) }
		tag_arr { v.valid_arr_handle(x) }
		tag_float { v.valid_float_handle(x) }
		tag_closure { v.valid_closure_handle(x) }
		tag_builder { v.valid_builder_handle(x) }
		else { true }
	}
}
