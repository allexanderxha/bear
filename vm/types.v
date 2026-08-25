// types.v — core types and constants for the VuurRaaf VM.
module vm

const stack_cap = 65536

// Field is one `name: value` entry of a struct value.
struct Field {
mut:
	name string
	val  i64
}

struct StructVal {
mut:
	fields []Field
}

struct Vm {
mut:
	code    []u8
	strings []string
	arrays  [][]i64
	structs []StructVal
	stack   []i64
	sp      int
	bp      int
	ip      int
	trace   bool
	halted  bool
}

fn bool_i64(b bool) i64 {
	return if b { i64(1) } else { i64(0) }
}
