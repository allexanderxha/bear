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

// StructVal is a struct (or map) value. `fields` keeps insertion order for
// rendering and JSON encoding; `by_name` is a hash index for O(1) field
// lookup by name, so map-style access on large records stays fast.
struct StructVal {
mut:
	fields  []Field
	by_name map[string]int // field name -> index into fields
}

// Handler records a try/catch handler pushed at runtime.
struct Closure {
	entry int // code IP of the function body
mut:
	captured []i64 // values of the enclosing locals this closure captures (by value)
}

struct Handler {
	ip int // catch_ip
	bp int // frame base at try point
	sp int // stack pointer right after the handler record
}

// DbgMode says what the debugger should do after an interactive session ends.
enum DbgMode {
	run // keep going until the next breakpoint (or the end)
	step // stop at the very next instruction
	next // stop after the current line returns to this frame level
	finish // stop when the current function returns
}

// DbgState is the interactive debugger's runtime state, checked once per
// instruction while enabled.
struct DbgState {
mut:
	enabled     bool
	breakpoints []int // source lines to stop at (first instruction of the line)
	mode        DbgMode
	start_bp    int // frame base captured when next/finish began
	last_line   int // line at the moment the session stopped
}

struct FnEntry {
	idx   int
	entry int
}

struct Vm {
mut:
	code       []u8
	strings    []string
	arrays     [][]i64
	structs    []StructVal
	floats     []f64
	closures   []Closure
	stack      []i64
	sp         int
	bp         int
	ip         int
	trace      bool
	halted     bool
	prog_args  []string
	exit_code  i64
	did_exit   bool
	handlers   []Handler
	lines      []obj.LineInfo // debug info: code offset -> source line
	fns        []obj.BinFn    // function table (for stack traces)
	const_strs int            // strings[0..const_strs] are bytecode constants, never collected
	last_heap  int            // heap size at the last GC check (allocation trigger)
	build_root string         // directory of the .vrmm build module (build_root() builtin)
	dbg        DbgState       // interactive debugger state (vr debug)
	dbg_locals []obj.DbgLocal // local name -> slot per function (debugger)
	profiling  bool           // instruction/call counting (vr run --profile)
	prof_instr []u64          // instructions executed per function index
	prof_calls []u64          // calls made per function index
	fn_of_ip   []int          // code offset -> function index (for profiling)
	max_ops    i64            // instruction budget; 0 = unlimited (fuzzing safety)
	ops        i64            // instructions executed so far
}

fn bool_i64(b bool) i64 {
	return if b { i64(1) } else { i64(0) }
}
