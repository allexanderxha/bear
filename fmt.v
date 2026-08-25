// fmt.v — `vr fmt`: a source formatter for VuurRaaf.
//
// Works line-by-line: it fixes indentation from brace depth, trims stray
// whitespace, collapses space runs outside string literals, and preserves
// every comment (whole-line and inline). It never reorders or rewrites code.
//
//   vr fmt file.vr        print the formatted source to stdout
//   vr fmt -w file.vr     rewrite the file in place
module main

import os

fn toolchain_fmt(args []string) ! {
	if args.len == 0 {
		return error('usage: vr fmt [-w] <file.vr>')
	}
	mut write := false
	mut files := []string{}
	for a in args {
		if a == '-w' || a == '--write' {
			write = true
		} else {
			files << a
		}
	}
	if files.len == 0 {
		return error('usage: vr fmt [-w] <file.vr>')
	}
	for f in files {
		src := os.read_file(f) or { return error('cannot read "${f}": ${err.msg()}') }
		formatted := fmt_source(src)
		if write {
			os.write_file(f, formatted) or { return error('cannot write "${f}": ${err.msg()}') }
			println('formatted ${f}')
		} else {
			print(formatted)
		}
	}
}

// fmt_source normalizes a whole source file. Comment lines are indented with
// the surrounding depth; closing braces drop one level like the code does.
fn fmt_source(src string) string {
	mut out := ''
	mut depth := 0
	for raw in src.split_into_lines() {
		line := raw.trim_space()
		if line == '' {
			out += '\n'
			continue
		}
		d := brace_delta(line)
		mut indent := depth
		if line.starts_with('}') && depth > 0 {
			indent = depth - 1
		}
		out += '\t'.repeat(indent) + collapse_spaces(line) + '\n'
		depth += d
		if depth < 0 {
			depth = 0
		}
	}
	return out
}

// collapse_spaces replaces runs of spaces outside of string literals with a
// single space, so indentation and padding become canonical without touching
// string contents.
fn collapse_spaces(line string) string {
	mut out := ''
	mut in_str := false
	mut i := 0
	for i < line.len {
		c := line[i]
		if c == `"` {
			in_str = !in_str
			out += c.ascii_str()
			i++
			continue
		}
		if in_str && c == `\\` {
			out += c.ascii_str()
			i++
			if i < line.len {
				out += line[i].ascii_str()
				i++
			}
			continue
		}
		if !in_str && c == ` ` {
			for i < line.len && line[i] == ` ` {
				i++
			}
			out += ' '
			continue
		}
		out += c.ascii_str()
		i++
	}
	return out
}

// brace_delta is shared with the REPL (repl.v): it tokenizes the line so
// braces inside string literals do not affect depth.
