// assembler.v — assembles VuurRaaf assembly (.vasm) into VROBJ object files.
//
// Assembly syntax:
//   ; comment
//   .global main            ; export the label as a linkable symbol
//   main:                   ; label definition (local unless .global)
//       push_int 42
//       push_str "hello"
//       call helper 1       ; call <symbol-or-label> <argc>
//       println
//       halt
//
// Jumps (jmp/jz/jnz) target local labels and are resolved here; calls to
// exported symbols become relocations resolved by the linker.
module assembler

import os
import obj

pub fn assemble(src string) !obj.Obj {
	lines := src.split_into_lines()
	// pass 1: collect labels, globals, and code offsets
	mut labels := map[string]int{}
	mut globals := map[string]bool{}
	mut offset := 0
	for raw in lines {
		line := clean(raw)
		if line.len == 0 {
			continue
		}
		if line.starts_with('.global') {
			name := line.all_after('.global').trim_space()
			if name.len == 0 {
				return error('`.global` needs a name')
			}
			globals[name] = true
			continue
		}
		if line.ends_with(':') {
			name := line[..line.len - 1].trim_space()
			if name in labels {
				return error('duplicate label "${name}"')
			}
			labels[name] = offset
			continue
		}
		offset += instr_len(line)!
	}
	// pass 2: emit code
	mut o := obj.Obj{}
	for raw in lines {
		line := clean(raw)
		if line.len == 0 || line.starts_with('.global') || line.ends_with(':') {
			continue
		}
		parts := split_line(line)!
		op := parts[0]
		arg := if parts.len > 1 { parts[1] } else { '' }
		match op {
			'halt' {
				o.code << u8(0)
			}
			'push_int' {
				val := parse_int(arg, 'push_int')!
				o.code << u8(1)
				o.code << obj.encode_i64(val)
			}
			'push_str' {
				s := unquote(arg)!
				o.code << u8(2)
				o.code << obj.encode_i64(0) // placeholder — rebased by the linker
				o.relocs << obj.Reloc{ offset: u32(o.code.len) - 8, name: s, kind: 1 }
			}
			'load' {
				o.code << u8(3)
				o.code << obj.encode_i64(parse_int(arg, 'load')!)
			}
			'store' {
				o.code << u8(4)
				o.code << obj.encode_i64(parse_int(arg, 'store')!)
			}
			'pop' {
				o.code << u8(5)
			}
			'dup' {
				o.code << u8(6)
			}
			'add' {
				o.code << u8(7)
			}
			'sub' {
				o.code << u8(8)
			}
			'mul' {
				o.code << u8(9)
			}
			'div' {
				o.code << u8(10)
			}
			'mod' {
				o.code << u8(11)
			}
			'neg' {
				o.code << u8(12)
			}
			'eq' {
				o.code << u8(13)
			}
			'ne' {
				o.code << u8(14)
			}
			'lt' {
				o.code << u8(15)
			}
			'le' {
				o.code << u8(16)
			}
			'gt' {
				o.code << u8(17)
			}
			'ge' {
				o.code << u8(18)
			}
			'and' {
				o.code << u8(19)
			}
			'or' {
				o.code << u8(20)
			}
			'not' {
				o.code << u8(21)
			}
			'jmp' {
				o.code << u8(22)
				o.code << obj.encode_i64(i64(label(labels, arg)!))
			}
			'jz' {
				o.code << u8(23)
				o.code << obj.encode_i64(i64(label(labels, arg)!))
			}
			'jnz' {
				o.code << u8(24)
				o.code << obj.encode_i64(i64(label(labels, arg)!))
			}
			'call' {
				o.code << u8(25)
				o.code << obj.encode_i64(0) // placeholder for the target
				if arg in labels && arg !in globals {
					obj.patch_i64(mut o.code, u32(o.code.len) - 8, i64(labels[arg]))
				} else {
					// reference to an exported symbol — resolved at link time
					o.relocs << obj.Reloc{ offset: u32(o.code.len) - 8, name: arg, kind: 0 }
				}
				argc := if parts.len > 2 { parse_int(parts[2], 'call argc')! } else { i64(0) }
				o.code << obj.encode_i64(argc)
			}
			'ret' {
				o.code << u8(26)
			}
			'retv' {
				o.code << u8(27)
			}
			'print' {
				o.code << u8(28)
			}
			'println' {
				o.code << u8(29)
			}
			'assert' {
				o.code << u8(30)
			}
			'enter' {
				o.code << u8(31)
				o.code << obj.encode_i64(parse_int(arg, 'enter')!)
			}
			'mkarray' {
				o.code << u8(32)
				o.code << obj.encode_i64(parse_int(arg, 'mkarray')!)
			}
			'aget' {
				o.code << u8(33)
			}
			'aset' {
				o.code << u8(34)
			}
			'alen' {
				o.code << u8(35)
			}
			'apush' {
				o.code << u8(36)
			}
			else {
				return error('unknown instruction "${op}"')
			}
		}
	}
	// export the globals as symbols
	for name in globals.keys() {
		entry := labels[name] or { return error('.global "${name}" is not a defined label') }
		o.symbols << obj.Symbol{ name: name, entry: entry }
	}
	return o
}

pub fn assemble_file(path string) !obj.Obj {
	src := os.read_file(path)!
	return assemble(src)!
}

// ---------------------------------------------------------------------------

fn clean(line string) string {
	// strip ';' comments and trim
	if idx := line.index(';') {
		return line[..idx].trim_space()
	}
	return line.trim_space()
}

// split_line splits an assembly line into whitespace-separated fields while
// keeping a double-quoted string (which may contain spaces) as a single field.
fn split_line(line string) ![]string {
	mut parts := []string{}
	mut i := 0
	for i < line.len {
		for i < line.len && (line[i] == ` ` || line[i] == `\t`) {
			i++
		}
		if i >= line.len {
			break
		}
		if line[i] == `"` {
			// scan to the closing quote
			start := i
			i++
			for i < line.len && line[i] != `"` {
				i++
			}
			i++
			parts << line[start..if i <= line.len { i } else { line.len }]
		} else {
			start := i
			for i < line.len && line[i] != ` ` && line[i] != `\t` {
				i++
			}
			parts << line[start..i]
		}
	}
	return parts
}

fn instr_len(line string) !int {
	parts := split_line(line)!
	op := parts[0]
	match op {
		'halt', 'pop', 'dup', 'add', 'sub', 'mul', 'div', 'mod', 'neg', 'eq', 'ne', 'lt', 'le',
		'gt', 'ge', 'and', 'or', 'not', 'ret', 'retv', 'print', 'println', 'assert', 'aget',
		'aset', 'alen', 'apush' {
			return 1
		}
		'push_int', 'push_str', 'load', 'store', 'jmp', 'jz', 'jnz', 'enter', 'mkarray' {
			return 9
		}
		'call' {
			return 17 // opcode + target(8) + argc(8)
		}
		else {
			return error('unknown instruction "${op}"')
		}
	}
}

fn label(labels map[string]int, name string) !int {
	return labels[name] or { return error('unknown label "${name}"') }
}

fn parse_int(s string, what string) !i64 {
	if s.len == 0 {
		return error('${what}: bad integer "${s}"')
	}
	start := if s[0] == `-` { 1 } else { 0 }
	if start >= s.len {
		return error('${what}: bad integer "${s}"')
	}
	for i in start..s.len {
		if s[i] < `0` || s[i] > `9` {
			return error('${what}: bad integer "${s}"')
		}
	}
	return s.i64()
}

fn unquote(s string) !string {
	if s.len < 2 || s[0] != `"` || s[s.len - 1] != `"` {
		return error('expected a string literal, got "${s}"')
	}
	inner := s[1..s.len - 1]
	mut out := ''
	mut i := 0
	for i < inner.len {
		c := inner[i]
		if c == `\\` && i + 1 < inner.len {
			i++
			match inner[i] {
				`n` {
					out += '\n'
				}
				`t` {
					out += '\t'
				}
				`"` {
					out += '"'
				}
				`\\` {
					out += '\\'
				}
				else {
					out += '\\${inner[i].ascii_str()}'
				}
			}
		} else {
			out += c.ascii_str()
		}
		i++
	}
	return out
}

