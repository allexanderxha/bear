// repl.v — an interactive read-eval-print loop for VuurRaaf.
//
// The REPL keeps two growing buffers: top-level declarations (fn / struct /
// enum / const / import / interface) and persistent statements (let, assert,
// assignment). Every other line — expressions, println, if/while/for blocks,
// match, try — is transient: it is evaluated once against the accumulated
// state and its output is not repeated on later lines. Expressions are
// echoed like Python's REPL (1 + 1 prints 2); statement keywords run for
// their side effects.
//
//   > let x = 5
//   > x * 2
//   10
//   > fn square(n) { return n * n }
//   > square(9)
//   81
//
// Multi-line input is gathered while braces are unbalanced:
//
//   > fn fib(n) {
//   ...   if n < 2 { return n }
//   ...   return fib(n - 1) + fib(n - 2)
//   ... }
module main

import os
import obj
import compiler
import linker
import vm

fn toolchain_repl() ! {
	println('VuurRaaf ${version} — type :help for commands, :quit to exit')
	mut top := ''    // fn / struct / enum / const / import declarations
	mut body := ''   // persistent statements (let / assert / assignment)
	mut pending := '' // accumulated multi-line input
	mut depth := 0   // brace balance of pending input
	for {
		prompt := if depth > 0 { '... ' } else { '> ' }
		line := os.input(prompt)
		if line == '' {
			continue
		}
		trimmed := line.trim_space()
		if trimmed.starts_with(':') && depth == 0 {
			act := repl_meta(trimmed)
			if act == 1 {
				break
			}
			if act == 2 {
				top = ''
				body = ''
				println('session reset')
			}
			continue
		}
		// gather multi-line input until braces balance
		pending += line + '\n'
		depth += brace_delta(line)
		if depth > 0 {
			continue
		}
		block := pending
		pending = ''
		depth = 0
		match repl_classify(block) {
			'top' {
				// fn / struct / enum / const / import — compile-time only
				candidate := top + '\n' + block
				if repl_compile(candidate, body, '') {
					top = candidate
				}
			}
			'body' {
				candidate := body + '\n' + block
				if repl_compile(top, candidate, '') {
					body = candidate
				}
			}
			else {
				// transient: run once against the accumulated state
				tail := if repl_is_expr(block) { 'println(${block.trim_space()})' } else { block }
				repl_compile(top, body, tail)
			}
		}
	}
}

// repl_meta handles :quit / :reset / :help. Returns 1 to quit, 2 to reset,
// and 0 otherwise.
fn repl_meta(cmd string) int {
	match cmd {
		':q', ':quit', ':exit' {
			println('bye')
			return 1
		}
		':reset' {
			return 2
		}
		':help', ':h' {
			println('  :help          this help')
			println('  :quit  :exit   leave the REPL')
			println('  :reset         clear all definitions')
			println('  expressions are echoed; let/assign/fn persist')
		}
		else {
			eprintln('repl: unknown command "${cmd}" (:help for a list)')
		}
	}
	return 0
}

// repl_compile compiles top declarations plus a main body (with an optional
// trailing tail statement), links, runs, and reports errors without exiting.
// Returns true when the program compiled and ran cleanly.
fn repl_compile(top string, body string, tail string) bool {
	src := top + '\nfn main() {\n' + body + '\n' + tail + '\n}'
	o := compiler.compile(src) or {
		eprintln('repl: ${err.msg()}')
		return false
	}
	tmp_obj := os.join_path(os.temp_dir(), 'vr_repl_${os.getpid()}.vobj')
	tmp_bin := os.join_path(os.temp_dir(), 'vr_repl_${os.getpid()}.vbin')
	defer {
		os.rm(tmp_obj) or {}
		os.rm(tmp_bin) or {}
	}
	obj.write(tmp_obj, o) or {
		eprintln('repl: ${err.msg()}')
		return false
	}
	linker.link([tmp_obj], tmp_bin) or {
		eprintln('repl: ${err.msg()}')
		return false
	}
	bin := obj.read_bin(tmp_bin) or {
		eprintln('repl: ${err.msg()}')
		return false
	}
	vm.run(bin, 'main', false) or {
		eprintln('repl: ${err.msg()}')
		return false
	}
	return true
}

// repl_classify buckets a (possibly multi-line) input block.
fn repl_classify(block string) string {
	toks := compiler.tokenize(block) or { return 'transient' }
	if toks.len == 0 {
		return 'transient'
	}
	match toks[0].kind {
		.kw_fn, .kw_struct, .kw_enum, .kw_const, .kw_import, .kw_interface {
			return 'top'
		}
		.kw_let, .kw_assert {
			return 'body'
		}
		.ident {
			// assignment persists; anything else is an expression
			if toks.len >= 2 && toks[1].kind in [.assign, .plus_eq, .minus_eq, .star_eq, .slash_eq] {
				return 'body'
			}
			return 'transient'
		}
		else {
			return 'transient'
		}
	}
}

// repl_is_expr reports whether a transient block is a bare expression that
// should be echoed (as opposed to a statement keyword like println or if).
fn repl_is_expr(block string) bool {
	toks := compiler.tokenize(block) or { return false }
	if toks.len == 0 {
		return false
	}
	match toks[0].kind {
		.kw_print, .kw_println, .kw_if, .kw_while, .kw_for, .kw_match, .kw_break, .kw_continue, .kw_return, .kw_try, .kw_throw {
			return false
		}
		else {
			return true
		}
	}
}

// brace_delta counts the brace balance of a line using the tokenizer, so
// braces inside string literals do not confuse continuation detection.
fn brace_delta(line string) int {
	toks := compiler.tokenize(line) or { return 0 }
	mut d := 0
	for t in toks {
		if t.kind == .lbrace {
			d++
		} else if t.kind == .rbrace {
			d--
		}
	}
	return d
}
