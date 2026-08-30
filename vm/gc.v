// gc.v — mark-and-sweep garbage collector for the VuurRaaf VM.
//
// The collector runs between opcodes (never mid-instruction, so no live value
// is ever hidden in a temporary). Roots are the value stack, which also holds
// every frame's locals (they live at bp+idx). Arrays and structs are traced
// transitively. The sweep compacts each pool and remaps surviving handles.
//
// String constants baked into the bytecode (op_push_s operands) live in
// strings[0..const_strs] and are never collected; only runtime-allocated
// strings participate in the cycle.
module vm

const gc_alloc_trigger = 4096

// collect marks all heap values reachable from the stack, then sweeps and
// compacts the pools, remapping handles on the stack and inside live
// containers.
fn (mut v Vm) collect() {
	// ---- mark ----
	mut str_mark := []bool{len: v.strings.len}
	mut arr_mark := []bool{len: v.arrays.len}
	mut struct_mark := []bool{len: v.structs.len}
	mut float_mark := []bool{len: v.floats.len}
	mut closure_mark := []bool{len: v.closures.len}
	for i in 0..v.sp {
		v.mark_value(v.stack[i], mut str_mark, mut arr_mark, mut struct_mark, mut float_mark, mut closure_mark)
	}
	// ---- remap tables: old index -> new index (-1 = collected) ----
	mut str_new := []int{len: v.strings.len, init: -1}
	mut arr_new := []int{len: v.arrays.len, init: -1}
	mut struct_new := []int{len: v.structs.len, init: -1}
	mut float_new := []int{len: v.floats.len, init: -1}
	mut closure_new := []int{len: v.closures.len, init: -1}
	mut nstr := v.const_strs
	for i in v.const_strs..v.strings.len {
		if str_mark[i] {
			str_new[i] = nstr
			nstr++
		}
	}
	mut narr := 0
	for i in 0..v.arrays.len {
		if arr_mark[i] {
			arr_new[i] = narr
			narr++
		}
	}
	mut nstruct := 0
	for i in 0..v.structs.len {
		if struct_mark[i] {
			struct_new[i] = nstruct
			nstruct++
		}
	}
	mut nfloat := 0
	for i in 0..v.floats.len {
		if float_mark[i] {
			float_new[i] = nfloat
			nfloat++
		}
	}
	mut nclosure := 0
	for i in 0..v.closures.len {
		if closure_mark[i] {
			closure_new[i] = nclosure
			nclosure++
		}
	}
	// ---- rewrite live references ----
	for i in 0..v.sp {
		v.stack[i] = v.remap(v.stack[i], str_new, arr_new, struct_new, float_new, closure_new)
	}
	for h in 0..v.arrays.len {
		if arr_mark[h] {
			for j in 0..v.arrays[h].len {
				v.arrays[h][j] = v.remap(v.arrays[h][j], str_new, arr_new, struct_new, float_new, closure_new)
			}
		}
	}
	for h in 0..v.structs.len {
		if struct_mark[h] {
			for j in 0..v.structs[h].fields.len {
				v.structs[h].fields[j].val = v.remap(v.structs[h].fields[j].val, str_new, arr_new, struct_new, float_new, closure_new)
			}
		}
	}
	for h in 0..v.closures.len {
		if closure_mark[h] {
			for j in 0..v.closures[h].captured.len {
				v.closures[h].captured[j] = v.remap(v.closures[h].captured[j], str_new, arr_new, struct_new, float_new, closure_new)
			}
		}
	}
	// ---- compact pools ----
	mut strings := v.strings[..v.const_strs]
	for i in v.const_strs..v.strings.len {
		if str_mark[i] {
			strings << v.strings[i]
		}
	}
	v.strings = strings
	mut arrays := [][]i64{}
	for i in 0..v.arrays.len {
		if arr_mark[i] {
			arrays << v.arrays[i]
		}
	}
	v.arrays = arrays
	mut structs := []StructVal{}
	for i in 0..v.structs.len {
		if struct_mark[i] {
			structs << v.structs[i]
		}
	}
	v.structs = structs
	mut floats := []f64{}
	for i in 0..v.floats.len {
		if float_mark[i] {
			floats << v.floats[i]
		}
	}
	v.floats = floats
	mut closures := []Closure{}
	for i in 0..v.closures.len {
		if closure_mark[i] {
			closures << v.closures[i]
		}
	}
	v.closures = closures
}

// mark_value traces a value and everything it references using an explicit
// worklist (arrays of arrays can nest deeply; recursion could overflow).
fn (mut v Vm) mark_value(x i64, mut str_mark []bool, mut arr_mark []bool, mut struct_mark []bool, mut float_mark []bool, mut closure_mark []bool) {
	mut work := []i64{}
	work << x
	for work.len > 0 {
		val := work.pop()
		match v.tag(val) {
			tag_str {
				h := v.hand(val)
				if h >= v.const_strs && h < str_mark.len && !str_mark[h] {
					str_mark[h] = true
				}
			}
			tag_arr {
				h := v.hand(val)
				if h >= 0 && h < arr_mark.len && !arr_mark[h] {
					arr_mark[h] = true
					for el in v.arrays[h] {
						work << el
					}
				}
			}
			tag_struct {
				h := v.hand(val)
				if h >= 0 && h < struct_mark.len && !struct_mark[h] {
					struct_mark[h] = true
					for f in v.structs[h].fields {
						work << f.val
					}
				}
			}
			tag_float {
				h := v.hand(val)
				if h >= 0 && h < float_mark.len && !float_mark[h] {
					float_mark[h] = true
				}
			}
			tag_closure {
				h := v.hand(val)
				if h >= 0 && h < closure_mark.len && !closure_mark[h] {
					closure_mark[h] = true
					for cv in v.closures[h].captured {
						work << cv
					}
				}
			}
			else {}
		}
	}
}

// remap translates a handle to its post-compaction index, leaving integers
// and uncollected values untouched.
fn (mut v Vm) remap(x i64, str_new []int, arr_new []int, struct_new []int, float_new []int, closure_new []int) i64 {
	match v.tag(x) {
		tag_str {
			h := v.hand(x)
			if h >= v.const_strs && h < str_new.len && str_new[h] >= 0 {
				return v.mkstr(str_new[h])
			}
		}
		tag_arr {
			h := v.hand(x)
			if h >= 0 && h < arr_new.len && arr_new[h] >= 0 {
				return v.mkarr(arr_new[h])
			}
		}
		tag_struct {
			h := v.hand(x)
			if h >= 0 && h < struct_new.len && struct_new[h] >= 0 {
				return v.mkstruct_handle(struct_new[h])
			}
		}
		tag_float {
			h := v.hand(x)
			if h >= 0 && h < float_new.len && float_new[h] >= 0 {
				return v.mkfloat(float_new[h])
			}
		}
		tag_closure {
			h := v.hand(x)
			if h >= 0 && h < closure_new.len && closure_new[h] >= 0 {
				return v.mkclosure(closure_new[h])
			}
		}
		else {}
	}
	return x
}
