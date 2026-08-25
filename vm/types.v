// types.v — core types and constants for the VuurRaaf VM.
module vm

import obj

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

// Handler records a try/catch handler pushed at runtime.
struct Closure {
	entry int // code IP of the function body
}

struct Handler {
	ip int // catch_ip
	bp int // frame base at try point
	sp int // stack pointer right after the handler record
}

struct Vm {
mut:
	code      []u8
	strings   []string
	arrays    [][]i64
	structs   []StructVal
	floats    []f64
	closures  []Closure
	stack     []i64
	sp        int
	bp        int
	ip        int
	trace     bool
	halted    bool
	prog_args []string
	exit_code i64
	did_exit  bool
	handlers  []Handler
	lines     []obj.LineInfo // debug info: code offset -> source line
	const_strs int          // strings[0..const_strs] are bytecode constants, never collected
	last_heap  int          // heap size at the last GC check (allocation trigger)
	build_root string       // directory of the .vrmm build module (build_root() builtin)
}

fn bool_i64(b bool) i64 {
	return if b { i64(1) } else { i64(0) }
}
