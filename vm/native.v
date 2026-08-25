// native.v — host builtins for the VuurRaaf VM.
//
// The op_native instruction carries a builtin id and an argument count. Each
// builtin pops its arguments off the stack (left-to-right push order means the
// last argument is on top) and pushes a single result (except exit(), which
// halts the machine). This is where the language touches the host: file I/O,
// environment, time, randomness, and the math/collection helpers.
module vm

import os
import math
import rand
import time
import obj
import compiler
import assembler
import linker

fn (mut v Vm) native(id int, _argc int) ! {
	match id {
		native_abs {
			x := v.pop()!
			if v.is_float(x) {
				v.push(v.push_float(math.abs(v.fval(x))))!
			} else {
				val := v.dec_int(x)
				v.push(v.enc_int(if val < 0 { -val } else { val }))!
			}
		}
		native_min {
			b := v.pop()!
			a := v.pop()!
			if v.is_float(a) || v.is_float(b) {
				v.push(v.push_float(math.min(v.to_f64(a), v.to_f64(b))))!
			} else {
				x := v.dec_int(a)
				y := v.dec_int(b)
				v.push(v.enc_int(if x < y { x } else { y }))!
			}
		}
		native_max {
			b := v.pop()!
			a := v.pop()!
			if v.is_float(a) || v.is_float(b) {
				v.push(v.push_float(math.max(v.to_f64(a), v.to_f64(b))))!
			} else {
				x := v.dec_int(a)
				y := v.dec_int(b)
				v.push(v.enc_int(if x > y { x } else { y }))!
			}
		}
		native_pow {
			b := v.pop()!
			a := v.pop()!
			v.push(v.push_float(math.pow(v.to_f64(a), v.to_f64(b))))!
		}
		native_sqrt {
			x := v.pop()!
			v.push(v.push_float(math.sqrt(v.to_f64(x))))!
		}
		native_floor {
			x := v.pop()!
			v.push(v.enc_int(i64(math.floor(v.to_f64(x)))))!
		}
		native_ceil {
			x := v.pop()!
			v.push(v.enc_int(i64(math.ceil(v.to_f64(x)))))!
		}
		native_round {
			x := v.pop()!
			v.push(v.enc_int(i64(math.round(v.to_f64(x)))))!
		}
		native_rand {
			v.push(v.push_float(rand.f64()))!
		}
		native_rand_int {
			n := int(v.dec_int(v.pop()!))
			if n <= 0 {
				return error('rand_int() expects a positive bound')
			}
			v.push(v.enc_int(i64(rand.intn(n) or { return error('rand_int() failed') })))!
		}
		native_int {
			x := v.pop()!
			if v.is_str(x) && v.valid_handle(x) {
				v.push(v.enc_int(i64(v.strings[v.hand(x)].i64())))!
			} else if v.is_float(x) {
				v.push(v.enc_int(i64(v.fval(x))))!
			} else if v.is_arr(x) || v.is_struct(x) {
				return error('cannot convert a ${v.type_name(x)} to int')
			} else {
				v.push(x)!
			}
		}
		native_str {
			x := v.pop()!
			v.push(v.alloc_str(v.val_str(x, 0)))!
		}
		native_float {
			x := v.pop()!
			if v.is_str(x) && v.valid_handle(x) {
				v.push(v.push_float(v.strings[v.hand(x)].f64()))!
			} else if v.is_float(x) {
				v.push(x)!
			} else if v.is_arr(x) || v.is_struct(x) {
				return error('cannot convert a ${v.type_name(x)} to float')
			} else {
				v.push(v.push_float(f64(v.dec_int(x))))!
			}
		}
		native_type {
			x := v.pop()!
			v.push(v.alloc_str(v.type_name(x)))!
		}
		native_split {
			delim := v.pop_str()!
			s := v.pop_str()!
			parts := s.split(delim)
			mut arr := []i64{}
			for p in parts {
				v.strings << p
				arr << v.mkstr(v.strings.len - 1)
			}
			v.arrays << arr
			v.push(v.mkarr(v.arrays.len - 1))!
		}
		native_join {
			delim := v.pop_str()!
			h := v.pop()!
			if !v.is_arr(h) || !v.valid_arr_handle(h) {
				return error('join() expects an array as its first argument')
			}
			a := v.arrays[v.hand(h)]
			mut parts := []string{}
			for x in a {
				if v.is_str(x) && v.valid_handle(x) {
					parts << v.strings[v.hand(x)]
				} else {
					parts << v.val_str(x, 0)
				}
			}
			v.push(v.alloc_str(parts.join(delim)))!
		}
		native_contains {
			sub := v.pop_str()!
			s := v.pop_str()!
			v.push(v.enc_int(bool_i64(s.contains(sub))))!
		}
		native_starts_with {
			sub := v.pop_str()!
			s := v.pop_str()!
			v.push(v.enc_int(bool_i64(s.starts_with(sub))))!
		}
		native_ends_with {
			sub := v.pop_str()!
			s := v.pop_str()!
			v.push(v.enc_int(bool_i64(s.ends_with(sub))))!
		}
		native_trim {
			s := v.pop_str()!
			v.push(v.alloc_str(s.trim_space()))!
		}
		native_lower {
			s := v.pop_str()!
			v.push(v.alloc_str(s.to_lower()))!
		}
		native_upper {
			s := v.pop_str()!
			v.push(v.alloc_str(s.to_upper()))!
		}
		native_pop {
			h := v.pop()!
			if !v.is_arr(h) || !v.valid_arr_handle(h) {
				return error('pop() expects an array')
			}
			mut a := v.arrays[v.hand(h)]
			if a.len == 0 {
				return error('pop() on an empty array')
			}
			val := a[a.len - 1]
			v.arrays[v.hand(h)] = a[..a.len - 1]
			v.push(val)!
		}
		native_insert {
			val := v.pop()!
			idx := int(v.dec_int(v.pop()!))
			h := v.pop()!
			if !v.is_arr(h) || !v.valid_arr_handle(h) {
				return error('insert() expects an array as its first argument')
			}
			a := v.arrays[v.hand(h)]
			if idx < 0 || idx > a.len {
				return error('insert index ${idx} out of bounds (len ${a.len})')
			}
			mut na := []i64{}
			for i, x in a {
				if i == idx {
					na << val
				}
				na << x
			}
			if idx == a.len {
				na << val
			}
			v.arrays[v.hand(h)] = na
			v.push(h)!
		}
		native_remove {
			idx := int(v.dec_int(v.pop()!))
			h := v.pop()!
			if !v.is_arr(h) || !v.valid_arr_handle(h) {
				return error('remove() expects an array as its first argument')
			}
			a := v.arrays[v.hand(h)]
			if idx < 0 || idx >= a.len {
				return error('remove index ${idx} out of bounds (len ${a.len})')
			}
			mut na := []i64{}
			for i, x in a {
				if i != idx {
					na << x
				}
			}
			v.arrays[v.hand(h)] = na
			v.push(h)!
		}
		native_sort {
			h := v.pop()!
			if !v.is_arr(h) || !v.valid_arr_handle(h) {
				return error('sort() expects an array')
			}
			mut a := v.arrays[v.hand(h)]
			// insertion sort by numeric value
			for i in 1..a.len {
				key := a[i]
				mut j := i - 1
				for j >= 0 && v.num_gt(a[j], key) {
					a[j + 1] = a[j]
					j--
				}
				a[j + 1] = key
			}
			v.push(h)!
		}
		native_clone {
			x := v.pop()!
			if v.is_arr(x) && v.valid_arr_handle(x) {
				v.arrays << v.arrays[v.hand(x)].clone()
				v.push(v.mkarr(v.arrays.len - 1))!
			} else if v.is_struct(x) && v.valid_struct_handle(x) {
				s := v.structs[v.hand(x)]
				v.structs << StructVal{ fields: s.fields.clone() }
				v.push(v.mkstruct_handle(v.structs.len - 1))!
			} else if v.is_str(x) && v.valid_handle(x) {
				v.push(v.alloc_str(v.strings[v.hand(x)]))!
			} else if v.is_float(x) {
				v.push(v.push_float(v.fval(x)))!
			} else {
				v.push(x)!
			}
		}
		native_reverse {
			h := v.pop()!
			if !v.is_arr(h) || !v.valid_arr_handle(h) {
				return error('reverse() expects an array')
			}
			mut a := v.arrays[v.hand(h)]
			for i in 0..a.len / 2 {
				a[i], a[a.len - 1 - i] = a[a.len - 1 - i], a[i]
			}
			v.push(h)!
		}
		native_index_of {
			val := v.pop()!
			h := v.pop()!
			if v.is_arr(h) && v.valid_arr_handle(h) {
				a := v.arrays[v.hand(h)]
				for i, x in a {
					if v.cmp(x, val, '==')! == 1 {
						v.push(v.enc_int(i64(i)))!
						return
					}
				}
				v.push(v.enc_int(-1))!
				return
			}
			if v.is_str(h) && v.valid_handle(h) {
				if !v.is_str(val) || !v.valid_handle(val) {
					return error('index_of() on a string expects a string needle')
				}
				s := v.strings[v.hand(h)]
				needle := v.strings[v.hand(val)]
				byte_idx := s.index(needle) or { -1 }
				if byte_idx < 0 {
					v.push(v.enc_int(-1))!
					return
				}
				// convert byte offset to a rune index so UTF-8 strings count characters
				rune_idx := s[..byte_idx].runes().len
				v.push(v.enc_int(i64(rune_idx)))!
				return
			}
			return error('index_of() expects an array or string as its first argument')
		}
		native_args {
			mut arr := []i64{}
			for s in v.prog_args {
				v.strings << s
				arr << v.mkstr(v.strings.len - 1)
			}
			v.arrays << arr
			v.push(v.mkarr(v.arrays.len - 1))!
		}
		native_getenv {
			name := v.pop_str()!
			v.push(v.alloc_str(os.getenv(name)))!
		}
		native_setenv {
			val := v.pop_str()!
			name := v.pop_str()!
			os.setenv(name, val, true)
			v.push(v.enc_int(0))!
		}
		native_exit {
			code := int(v.dec_int(v.pop()!))
			v.exit_code = i64(code)
			v.did_exit = true
			v.halted = true
		}
		native_time {
			v.push(v.push_float(f64(time.now().unix_milli()) / 1000.0))!
		}
		native_sleep {
			ms := int(v.dec_int(v.pop()!))
			time.sleep(time.Duration(ms) * time.millisecond)
			v.push(v.enc_int(0))!
		}
		native_read_file {
			path := v.pop_str()!
			content := os.read_file(path) or { return error('cannot read file "${path}": ${err}') }
			v.push(v.alloc_str(content))!
		}
		native_write_file {
			content := v.pop_str()!
			path := v.pop_str()!
			os.write_file(path, content) or { return error('cannot write file "${path}": ${err}') }
			v.push(v.enc_int(0))!
		}
		native_eprint {
			x := v.pop()!
			eprintln(v.val_str(x, 0))
		}
		// -------------------------------------------------------------------
		// build-module builtins (.vrmm) — these let a VuurRaaf program drive
		// the toolchain itself, the way V's .vsh scripts drive `v build`.
		native_build_compile {
			out := v.pop_str()!
			src := v.pop_str()!
			o := compiler.compile_file(src) or { return error('build_compile: ${err.msg()}') }
			o_path := if out.len == 0 { src.all_before_last('.') + '.vobj' } else { out }
			obj.write(o_path, o) or { return error('build_compile: cannot write ${o_path}: ${err.msg()}') }
			println('compiled ${src} -> ${o_path} (${o.code.len} bytes code, ${o.symbols.len} symbols)')
			v.push(v.alloc_str(o_path))!
		}
		native_build_assemble {
			out := v.pop_str()!
			src := v.pop_str()!
			o := assembler.assemble_file(src) or { return error('build_assemble: ${err.msg()}') }
			o_path := if out.len == 0 { src.all_before_last('.') + '.vobj' } else { out }
			obj.write(o_path, o) or { return error('build_assemble: cannot write ${o_path}: ${err.msg()}') }
			println('assembled ${src} -> ${o_path} (${o.code.len} bytes code)')
			v.push(v.alloc_str(o_path))!
		}
		native_build_link {
			out := v.pop_str()!
			h := v.pop()!
			if !v.is_arr(h) || !v.valid_arr_handle(h) {
				return error('build_link() expects an array of object files as its first argument')
			}
			mut objs := []string{}
			for x in v.arrays[v.hand(h)] {
				if !v.is_str(x) || !v.valid_handle(x) {
					return error('build_link() expects string paths inside the object array')
				}
				objs << v.strings[v.hand(x)]
			}
			if objs.len == 0 {
				return error('build_link() needs at least one object file')
			}
			o_path := if out.len == 0 { os.base(objs[0]).all_before_last('.') + '.vbin' } else { out }
			linker.link(objs, o_path) or { return error('build_link: ${err.msg()}') }
			println('linked ${objs.len} object file(s) -> ${o_path}')
			v.push(v.alloc_str(o_path))!
		}
		native_build_run {
			f := v.pop_str()!
			if f.ends_with('.vbin') {
				bin := obj.read_bin(f) or { return error('build_run: ${err.msg()}') }
				code := run_with_args(bin, 'main', false, []string{}) or {
					return error('build_run: ${err.msg()}')
				}
				v.push(v.enc_int(code))!
				return
			}
			if !f.ends_with('.vr') {
				return error('build_run() expects a .vr or .vbin file')
			}
			tmp_obj := os.join_path(os.temp_dir(), 'vr_build_${os.getpid()}.vobj')
			tmp_bin := os.join_path(os.temp_dir(), 'vr_build_${os.getpid()}.vbin')
			defer {
				os.rm(tmp_obj) or {}
				os.rm(tmp_bin) or {}
			}
			o := compiler.compile_file(f) or { return error('build_run: ${err.msg()}') }
			obj.write(tmp_obj, o) or { return error('build_run: ${err.msg()}') }
			linker.link([tmp_obj], tmp_bin) or { return error('build_run: ${err.msg()}') }
			bin := obj.read_bin(tmp_bin) or { return error('build_run: ${err.msg()}') }
			code := run_with_args(bin, 'main', false, []string{}) or {
				return error('build_run: ${err.msg()}')
			}
			v.push(v.enc_int(code))!
		}
		native_build_test {
			src := v.pop_str()!
			o := compiler.compile_file(src) or { return error('build_test: ${err.msg()}') }
			mut tests := []string{}
			for s in o.symbols {
				if s.name.starts_with('test_') {
					tests << s.name
				}
			}
			if tests.len == 0 {
				return error('build_test: no test_* functions found in ${src}')
			}
			tmp_obj := os.join_path(os.temp_dir(), 'vr_build_${os.getpid()}.vobj')
			tmp_bin := os.join_path(os.temp_dir(), 'vr_build_${os.getpid()}.vbin')
			defer {
				os.rm(tmp_obj) or {}
				os.rm(tmp_bin) or {}
			}
			obj.write(tmp_obj, o) or { return error('build_test: ${err.msg()}') }
			linker.link([tmp_obj], tmp_bin) or { return error('build_test: ${err.msg()}') }
			bin := obj.read_bin(tmp_bin) or { return error('build_test: ${err.msg()}') }
			mut passes := 0
			mut fails := 0
			for t in tests {
				run(bin, t, false) or {
					eprintln('  FAIL  ${t}  —  ${err}')
					fails++
					continue
				}
				println('  PASS  ${t}')
				passes++
			}
			if fails > 0 {
				return error('build_test: ${fails} of ${tests.len} test(s) failed in ${src}')
			}
			println('${passes} test(s) passed')
			v.push(v.enc_int(i64(passes)))!
		}
		native_build_bench {
			n := int(v.dec_int(v.pop()!))
			src := v.pop_str()!
			if n < 1 {
				return error('build_bench() expects a positive iteration count')
			}
			tmp_obj := os.join_path(os.temp_dir(), 'vr_build_${os.getpid()}.vobj')
			tmp_bin := os.join_path(os.temp_dir(), 'vr_build_${os.getpid()}.vbin')
			defer {
				os.rm(tmp_obj) or {}
				os.rm(tmp_bin) or {}
			}
			o := compiler.compile_file(src) or { return error('build_bench: ${err.msg()}') }
			obj.write(tmp_obj, o) or { return error('build_bench: ${err.msg()}') }
			linker.link([tmp_obj], tmp_bin) or { return error('build_bench: ${err.msg()}') }
			bin := obj.read_bin(tmp_bin) or { return error('build_bench: ${err.msg()}') }
			start := time.now().unix_milli()
			for _ in 0..n {
				run(bin, 'main', false) or { return error('build_bench: ${err.msg()}') }
			}
			ms := time.now().unix_milli() - start
			rate := if ms > 0 { f64(n) / (f64(ms) / 1000.0) } else { f64(0) }
			println('bench: ${n} runs of main() in ${ms}ms (${rate:.0} runs/s)')
			v.push(v.enc_int(0))!
		}
		native_build_clean {
			mut n := 0
			if files := os.ls('.') {
				for f in files {
					if f.ends_with('.vobj') || f.ends_with('.vbin') {
						os.rm(f) or {}
						n++
					}
				}
			}
			println('cleaned ${n} artifact(s)')
			v.push(v.enc_int(i64(n)))!
		}
		native_build_exec {
			cmd := v.pop_str()!
			res := os.execute(cmd)
			if res.exit_code != 0 {
				return error('build_exec: "${cmd}" failed with exit code ${res.exit_code}: ${res.output}')
			}
			v.push(v.alloc_str(res.output))!
		}
		native_build_exec_status {
			cmd := v.pop_str()!
			res := os.execute(cmd)
			v.push(v.enc_int(i64(res.exit_code)))!
		}
		native_build_exists {
			p := v.pop_str()!
			v.push(v.enc_int(bool_i64(os.exists(p))))!
		}
		native_build_mkdir {
			p := v.pop_str()!
			os.mkdir_all(p) or { return error('build_mkdir: cannot create ${p}: ${err.msg()}') }
			v.push(v.enc_int(0))!
		}
		native_build_rm {
			p := v.pop_str()!
			if !os.exists(p) {
				v.push(v.enc_int(0))!
				return
			}
			if os.is_dir(p) {
				os.rmdir_all(p) or { return error('build_rm: cannot remove ${p}: ${err.msg()}') }
			} else {
				os.rm(p) or { return error('build_rm: cannot remove ${p}: ${err.msg()}') }
			}
			v.push(v.enc_int(1))!
		}
		native_build_copy {
			dst := v.pop_str()!
			src := v.pop_str()!
			if os.is_dir(src) {
				v.copy_tree(src, dst) or { return error('build_copy: ${err.msg()}') }
			} else {
				os.cp(src, dst, os.CopyParams{}) or {
					return error('build_copy: cannot copy ${src} -> ${dst}: ${err.msg()}')
				}
			}
			v.push(v.enc_int(0))!
		}
		native_build_glob {
			pat := v.pop_str()!
			files := os.glob(pat) or { return error('build_glob: ${err.msg()}') }
			mut arr := []i64{}
			for f in files {
				v.strings << f
				arr << v.mkstr(v.strings.len - 1)
			}
			v.arrays << arr
			v.push(v.mkarr(v.arrays.len - 1))!
		}
		native_build_ls {
			dir := v.pop_str()!
			entries := os.ls(dir) or { return error('build_ls: cannot read ${dir}: ${err.msg()}') }
			mut arr := []i64{}
			for f in entries {
				v.strings << f
				arr << v.mkstr(v.strings.len - 1)
			}
			v.arrays << arr
			v.push(v.mkarr(v.arrays.len - 1))!
		}
		native_build_base {
			p := v.pop_str()!
			v.push(v.alloc_str(os.base(p)))!
		}
		native_build_dir {
			p := v.pop_str()!
			v.push(v.alloc_str(os.dir(p)))!
		}
		native_build_join {
			b := v.pop_str()!
			a := v.pop_str()!
			v.push(v.alloc_str(os.join_path(a, b)))!
		}
		native_build_root {
			v.push(v.alloc_str(v.build_root))!
		}
		else {
			return error('unknown native builtin ${id}')
		}
	}
}

// copy_tree recursively copies a directory tree (used by build_copy).
fn (mut v Vm) copy_tree(src string, dst string) ! {
	if !os.is_dir(src) {
		return error('${src} is not a directory')
	}
	os.mkdir_all(dst) or { return error('cannot create ${dst}: ${err.msg()}') }
	for entry in os.ls(src) or { return error('cannot read ${src}: ${err.msg()}') } {
		sp := os.join_path(src, entry)
		dp := os.join_path(dst, entry)
		if os.is_dir(sp) {
			v.copy_tree(sp, dp)!
		} else if os.is_file(sp) {
			os.cp(sp, dp, os.CopyParams{}) or { return error('cannot copy ${sp}: ${err.msg()}') }
		}
	}
}

// pop_str pops the top value and requires it to be a string.
fn (mut v Vm) pop_str() !string {
	x := v.pop()!
	if !v.is_str(x) || !v.valid_handle(x) {
		return error('expected a string argument')
	}
	return v.strings[v.hand(x)]
}

// type_name returns the type label of a tagged value.
fn (mut v Vm) type_name(x i64) string {
	if v.is_str(x) {
		return 'string'
	}
	if v.is_float(x) {
		return 'float'
	}
	if v.is_arr(x) {
		return 'array'
	}
	if v.is_struct(x) {
		return 'struct'
	}
	return 'int'
}

// str_method dispatches a string method call. The receiver was pushed before
// the arguments, so it is the first argument from the native builtin's point
// of view; delegating keeps the behavior identical to the free-function forms.
fn (mut v Vm) str_method(name string, argc int) ! {
	bid := match name {
		'to_upper' { native_upper }
		'to_lower' { native_lower }
		'trim' { native_trim }
		'contains' { native_contains }
		'starts_with' { native_starts_with }
		'ends_with' { native_ends_with }
		'split' { native_split }
		'index_of' { native_index_of }
		'to_int' { native_int }
		'to_float' { native_float }
		else { -1 }
	}
	if bid >= 0 {
		// native builtins pop the first argument (the receiver) last
		v.native(bid, argc + 1)!
		return
	}
	if name == 'len' {
		h := v.pop()!
		if !v.is_str(h) || !v.valid_handle(h) {
			return error('len() on a non-string value')
		}
		v.push(v.enc_int(i64(v.strings[v.hand(h)].runes().len)))!
		return
	}
	return error('unknown string method "${name}"')
}

// num_gt compares two values by their numeric value (int or float).
fn (mut v Vm) num_gt(x i64, y i64) bool {
	if v.is_float(x) || v.is_float(y) {
		return v.to_f64(x) > v.to_f64(y)
	}
	return v.dec_int(x) > v.dec_int(y)
}
