// value.v — tagged value encoding and helpers for the VuurRaaf VM.
//
// Stack values are 64-bit tagged integers with two tag bits:
//   low bits 00  -> encoded number  (value = raw << 2)
//   low bits 01  -> string handle   (handle = value >> 2, into v.strings)
//   low bits 10  -> struct handle   (handle = value >> 2, into v.structs)
//   low bits 11  -> array handle    (handle = value >> 2, into v.arrays)
module vm

fn (mut v Vm) is_str(x i64) bool {
	return x & 3 == 1
}

fn (mut v Vm) is_arr(x i64) bool {
	return x & 3 == 3
}

fn (mut v Vm) is_struct(x i64) bool {
	return x & 3 == 2
}

fn (mut v Vm) enc_int(x i64) i64 {
	return u64(x) << 2
}

fn (mut v Vm) dec_int(x i64) i64 {
	return x >> 2
}

fn (mut v Vm) hand(x i64) int {
	return int(x >> 2)
}

fn (mut v Vm) mkstr(idx int) i64 {
	return (u64(idx) << 2) | 1
}

fn (mut v Vm) mkarr(idx int) i64 {
	return (u64(idx) << 2) | 3
}

fn (mut v Vm) mkstruct_handle(idx int) i64 {
	return (u64(idx) << 2) | 2
}

fn (mut v Vm) truthy(x i64) bool {
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
