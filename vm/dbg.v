// dbg.v — the interactive debugger, enabled by `vr debug`.
//
// While enabled the VM checks dbg_tick before every instruction. When a
// breakpoint is hit (or a step/next/finish condition is met) it drops into
// dbg_session, a small command loop over stdin:
//
//   c | continue   resume until the next breakpoint (or the end)
//   s | step       execute one instruction
//   n | next       run to the next line of the current frame (skip calls)
//   f | finish     run until the current function returns
//   b [line]       set a breakpoint on a source line (no arg: list them)
//   d <n>          delete breakpoint n (1-based)
//   p <name>       print a local variable's value
//   l | locals     list the current function's locals and their values
//   bt | stack     print the call chain
//   q | quit       abort the program
//
// Reading EOF (e.g. piped input) is treated as `continue`, so scripts can
// drive a session non-interactively.
module vm

import os

// dbg_tick runs once per instruction while the debugger is enabled and
// decides whether to stop and open an interactive session.
fn (mut v Vm) dbg_tick() ! {
	line := v.line_at(v.ip)
	mut stop := false
	match v.dbg.mode {
		.step {
			stop = true
		}
		.next {
			// run until the line changes while still at (or above) the frame
			// level where next began — calls push deeper frames, which we skip
			stop = v.bp <= v.dbg.start_bp && line != v.dbg.last_line
		}
		.finish {
			// run until the current frame returns to its caller
			stop = v.bp < v.dbg.start_bp
		}
		.run {
			// stop at the first instruction of a breakpoint line only, so a
			// multi-instruction line does not re-trigger mid-line
			if line in v.dbg.breakpoints {
				first := v.ip == 0 || v.line_at(v.ip - 1) != line
				stop = first
			}
		}
	}
	if stop {
		v.dbg_session()!
	}
}

// dbg_session is the interactive command loop. It returns when the user
// chooses a resume mode (continue/step/next/finish) or quits.
fn (mut v Vm) dbg_session() ! {
	v.dbg.last_line = v.line_at(v.ip)
	println('')
	println('== stopped at ${v.func_at(v.ip)} (line ${v.dbg.last_line}, ip ${v.ip}) — help: h')
	for {
		input := os.input_opt('(vr-dbg) ') or { 'c' } // EOF → continue
		parts := input.trim_space().split(' ')
		cmd := parts[0]
		arg := if parts.len > 1 { parts[1] } else { '' }
		match cmd {
			'c', 'continue', '' {
				v.dbg.mode = .run
				return
			}
			's', 'step' {
				v.dbg.mode = .step
				return
			}
			'n', 'next' {
				v.dbg.mode = .next
				v.dbg.start_bp = v.bp
				return
			}
			'f', 'finish' {
				v.dbg.mode = .finish
				v.dbg.start_bp = v.bp
				return
			}
			'b', 'break' {
				if arg == '' {
					if v.dbg.breakpoints.len == 0 {
						println('  no breakpoints set')
					} else {
						for i, bp in v.dbg.breakpoints {
							println('  ${i + 1}: line ${bp}')
						}
					}
				} else {
					line := arg.int()
					if line <= 0 {
						println('  usage: b <line>')
					} else if line !in v.dbg.breakpoints {
						v.dbg.breakpoints << line
						println('  breakpoint set at line ${line}')
					}
				}
			}
			'd', 'delete' {
				n := arg.int()
				if n >= 1 && n <= v.dbg.breakpoints.len {
					v.dbg.breakpoints.delete(n - 1)
					println('  breakpoint ${n} deleted')
				} else {
					println('  usage: d <n> (see `b` for the list)')
				}
			}
			'p', 'print' {
				if arg == '' {
					println('  usage: p <name>')
				} else {
					v.dbg_print_local(arg)
				}
			}
			'l', 'locals' {
				v.dbg_list_locals()
			}
			'bt', 'stack', 'backtrace' {
				println(v.stack_trace())
			}
			'h', 'help' {
				println('  c continue · s step · n next · f finish · b [line] · d <n>')
				println('  p <name> · l locals · bt stack · q quit')
			}
			'q', 'quit', 'exit' {
				v.halted = true
				return
			}
			else {
				println('  unknown command "${cmd}" — h for help')
			}
		}
	}
}

// dbg_print_local prints the value of one local variable of the current
// function, resolving its slot from the debug locals table.
fn (mut v Vm) dbg_print_local(name string) {
	fn_name := v.func_at(v.ip)
	slot := v.dbg_slot(fn_name, name)
	if slot < 0 {
		println('  no local "${name}" in ${fn_name}')
		return
	}
	println('  ${name} = ${v.val_str(v.stack[v.bp + slot], 0)}')
}

// dbg_list_locals prints every named local of the current function with its
// current value.
fn (mut v Vm) dbg_list_locals() {
	fn_name := v.func_at(v.ip)
	mut found := false
	for l in v.dbg_locals {
		if l.fn == fn_name {
			found = true
			println('  ${l.name} = ${v.val_str(v.stack[v.bp + l.slot], 0)}  (slot ${l.slot})')
		}
	}
	if !found {
		println('  (no named locals for ${fn_name})')
	}
}

// dbg_slot finds the stack slot of a local by (function, name), or -1.
fn (v Vm) dbg_slot(fn_name string, name string) int {
	for l in v.dbg_locals {
		if l.fn == fn_name && l.name == name {
			return l.slot
		}
	}
	return -1
}
