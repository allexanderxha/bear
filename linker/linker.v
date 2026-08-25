// linker.v — links one or more VROBJ object files into a VRBIN executable.
//
// Code sections are concatenated, symbol entries are rebased, and call-site
// relocations are patched with the final code offsets. Duplicate or unresolved
// symbols are link errors.
module linker

import obj

pub fn link(paths []string, out string) ! {
	if paths.len == 0 {
		return error('no object files to link')
	}
	mut code := []u8{}
	mut strings := []string{}
	mut symbols := map[string]int{}
	mut relocs := []obj.Reloc{}
	mut lines := []obj.LineInfo{}
	mut locals := []obj.DbgLocal{}
	for p in paths {
		o := obj.read(p)!
		base := code.len
		for s in o.symbols {
			if s.name in symbols {
				return error('duplicate symbol "${s.name}" (in ${p})')
			}
			symbols[s.name] = base + s.entry
		}
		code << o.code
		for r in o.relocs {
			relocs << obj.Reloc{ offset: r.offset + u32(base), name: r.name, kind: r.kind }
		}
		for l in o.lines {
			lines << obj.LineInfo{ off: l.off + u32(base), line: l.line }
		}
		locals << o.locals
	}
	// resolve relocations
	for r in relocs {
		if r.kind == 1 {
			// string constant: rebase to its index in the merged table
			idx := intern_str(mut strings, r.name)
			obj.patch_i64(mut code, r.offset, i64(idx))
			continue
		}
		entry := symbols[r.name] or {
			return error('unresolved symbol "${r.name}" (no such function)')
		}
		obj.patch_i64(mut code, r.offset, i64(entry))
	}
	// build the executable
	mut fns := []obj.BinFn{}
	for name, entry in symbols {
		fns << obj.BinFn{ name: name, entry: entry }
	}
	obj.write_bin(out, obj.Bin{ fns: fns, strings: strings, code: code, lines: lines, locals: locals })!
}

fn intern_str(mut table []string, s string) int {
	for i, t in table {
		if t == s {
			return i
		}
	}
	table << s
	return table.len - 1
}
