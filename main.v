// vuurraaf/v
// A complete toolchain for VuurRaaf, in V. This toolchain is made from zero,
// and includes a custom compiler, assembler, linker, and runtime.
// It is designed to be simple and easy to understand, while still being powerful
// enough to compile and run VuurRaaf programs.
//
//   vr run hello.vr          compile + link + run
//   vr compile hello.vr      source -> object (.vobj)
//   vr assemble math.vasm    assembly -> object (.vobj)
//   vr link a.vobj b.vobj    objects -> executable (.vbin)
//   vr debug hello.vr        run with an instruction trace
//   vr test tests.vr         run every test_* function
//   vr bench fib.vr 1000     benchmark main()
//   vr help                  everything else

module main

import os
import json2
import time
import obj
import compiler
import assembler
import linker
import vm

const name = 'vuurraaf/v'
const version = '0.1.0'
const project_root = @VMODROOT

fn main() {
	args := os.args[1..]
	if args.len == 0 {
		toolchain_help()
		return
	}
	cmd := args[0]
	rest := args[1..]
	match cmd {
		'help', '-h', '--help' {
			toolchain_help()
		}
		'version', '-v', '--version' {
			toolchain_version()
		}
		'info' {
			toolchain_info()
		}
		'config' {
			toolchain_config(rest) or { die('config', err) }
		}
		'compile', 'c' {
			toolchain_compile(rest) or { die('compile', err) }
		}
		'assemble', 'a' {
			toolchain_assemble(rest) or { die('assemble', err) }
		}
		'link', 'l' {
			toolchain_link(rest) or { die('link', err) }
		}
		'run', 'r' {
			toolchain_run(rest) or { die('run', err) }
		}
	'debug', 'd' {
		toolchain_debug(rest) or { die('debug', err) }
	}
	'profile', 'p' {
		toolchain_profile(rest) or { die('profile', err) }
	}
	'fuzz' {
		toolchain_fuzz(rest) or { die('fuzz', err) }
	}
		'test', 't' {
			toolchain_test(rest) or { die('test', err) }
		}
		'bench', 'b' {
			toolchain_bench(rest) or { die('bench', err) }
		}
		'repl', 'i' {
			toolchain_repl() or { die('repl', err) }
		}
		'lsp' {
			toolchain_lsp()
		}
		'fmt' {
			toolchain_fmt(rest) or { die('fmt', err) }
		}
		'init' {
			toolchain_init(rest) or { die('init', err) }
		}
		'get' {
			toolchain_get(rest) or { die('get', err) }
		}
		'install' {
			toolchain_install() or { die('install', err) }
		}
		'list' {
			toolchain_list() or { die('list', err) }
		}
		'clean' {
			toolchain_clean()
		}
		'make', 'm', 'build' {
			toolchain_make(rest) or { die('make', err) }
		}
		'up' {
			toolchain_up() or { die('up', err) }
		}
		'symlink' {
			toolchain_symlink() or { die('symlink', err) }
		}
		'loader' {
			toolchain_loader()
		}
		'alloc' {
			toolchain_alloc()
		}
		'free' {
			toolchain_free()
		}
		'unloader' {
			toolchain_unloader()
		}
		else {
			// direct script execution — this is what makes shebangs work:
			// `#!/usr/bin/env vr` has the kernel call `vr <script> [args...]`,
			// so route an existing .vrmm/.vr file to make/run accordingly
			if os.exists(cmd) && cmd.ends_with('.vrmm') {
				mut m := ['-f', cmd]
				m << args[1..]
				toolchain_make(m) or { die('make', err) }
				return
			}
			if os.exists(cmd) && cmd.ends_with('.vr') {
				mut r := [cmd]
				r << args[1..]
				toolchain_run(r) or { die('run', err) }
				return
			}
			eprintln('vr: unknown command "${cmd}"')
			eprintln("run 'vr help' for usage")
			exit(1)
		}
	}
}

fn die(cmd string, err IError) {
	eprintln('vr ${cmd}: ${err.msg()}')
	exit(1)
}

// ---------------------------------------------------------------------------
// commands

fn toolchain_loader() {
	components := [
		'compiler  (lexer, parser, bytecode codegen)',
		'assembler (vasm -> vobj)',
		'linker    (vobj set -> vbin)',
		'vm        (stack-based runtime)',
		'obj       (VROBJ/VRBIN formats)',
	]
	println('VuurRaaf toolchain components:')
	for c in components {
		println('  [loaded]  ${c}')
	}
	println('')
	println('all components are statically linked into this binary (${os.executable()})')
}

fn toolchain_unloader() {
	println('unloader: nothing to unload — the toolchain is a single static binary')
}

fn toolchain_alloc() {
	// the toolchain keeps one pre-sized arena for scratch work
	arena := 1 * 1024 * 1024
	vm_stack := 65536 * 8
	println('toolchain memory arena:')
	println('  byte arena:   ${arena} bytes (1 MiB, reserved)')
	println('  vm stack:     ${vm_stack} bytes (64k slots x 8)')
	println('  strings:      grow-on-demand heap inside the vm')
}

fn toolchain_free() {
	println('free: no persistent allocations to release')
}

fn toolchain_help() {
	println('VuurRaaf toolchain (vuurraaf/v) v${version}')
	println('')
	println('usage: vr <command> [args]')
	println('')
	println('  compile <file.vr> [-o out.vobj]          compile source to an object file')
	println('  assemble <file.vasm> [-o out.vobj]       assemble raw bytecode to an object file')
	println('  link <a.vobj> [more.vobj ...] [-o out]   link objects into an executable')
	println('  run <file.vr|file.vbin>                  compile, link and run (or run a binary)')
	println('  debug <file.vr|file.vbin>                interactive debugger (breakpoints, step, locals)')
	println('  profile <file.vr|file.vbin>              run and report per-function instruction counts')
	println('  fuzz [--seed N] [--iters N]              fuzz the compiler and VM for crashes/hangs')
	println('  test <file.vr|dir>                       run every test_* function')
	println('  bench <file.vr> [iterations]             benchmark main()')
	println('  repl                                     interactive session')
	println('  lsp                                      language server (JSON-RPC over stdio)')
	println('  fmt [-w] <file.vr>                       format source')
	println('  init [name]                              scaffold a project')
	println('  get <owner/repo | url | ./path>          fetch a package into vendor/')
	println('  install                                  install deps from vr.mod')
	println('  list                                     show the project manifest')
	println('  make [target] [args...]                  run build.vrmm (target = main)')
	println('  make -f <file.vrmm> [target] [args...]   run another build module (.vrmm)')
	println('  build                                    alias for make')
	println('  <script.vrmm> [target] [args...]         run a build module directly (shebang)')
	println('  <file.vr> [args...]                      run a program directly (shebang)')
	println('  clean                                    remove build artifacts')
	println('  up                                       rebuild the vr binary into bin/')
	println('  symlink                                  link bin/vr into your PATH')
	println('  config [set <key> <value>]               show or change toolchain config')
	println('  info                                     show toolchain information')
	println('  loader                                   list toolchain components')
	println('  alloc                                    show toolchain memory arena')
	println('  free | unloader                          release toolchain resources')
	println('  version                                  print version')
	println('  help                                     this help')
}

fn toolchain_version() {
	println('VuurRaaf toolchain v${version}')
}

fn toolchain_info() {
	v_version := os.execute('v version').output.trim_space()
	println('${name} v${version}')
	println('  root:        ${project_root}')
	println('  v compiler:  ${v_version}')
	println('  platform:    ${os.user_os()}')
	println('  components:  compiler, assembler, linker, vm, obj')
	println('  config:      ${config_path()}')
}

// ---------------------------------------------------------------------------
// config

struct Config {
mut:
	outdir  string = '.'
	verbose bool
}

fn config_path() string {
	return os.join_path(os.home_dir(), '.config', 'vuurraaf', 'config.json')
}

fn load_config() Config {
	p := config_path()
	if !os.exists(p) {
		return Config{}
	}
	text := os.read_file(p) or { return Config{} }
	return json2.decode[Config](text) or { Config{} }
}

fn save_config(c Config) ! {
	dir := os.dir(config_path())
	os.mkdir_all(dir) or { return error('cannot create config dir: ${dir}') }
	os.write_file(config_path(), json2.encode(c))!
}

fn toolchain_config(args []string) ! {
	if args.len == 0 {
		c := load_config()
		println('config: ${config_path()}')
		println('  outdir:  ${c.outdir}')
		println('  verbose: ${c.verbose}')
		return
	}
	if args[0] == 'set' && args.len == 3 {
		mut c := load_config()
		match args[1] {
			'outdir' {
				c.outdir = args[2]
			}
			'verbose' {
				c.verbose = args[2] == 'true'
			}
			else {
				return error('unknown config key "${args[1]}" (known: outdir, verbose)')
			}
		}
		save_config(c)!
		println('config updated: ${args[1]} = ${args[2]}')
		return
	}
	return error('usage: vr config [set <key> <value>]')
}

// ---------------------------------------------------------------------------
// compile / assemble / link / run / debug / test / bench

fn toolchain_compile(args []string) ! {
	mut src := ''
	mut out := ''
	mut i := 0
	for i < args.len {
		if args[i] == '-o' && i + 1 < args.len {
			out = args[i + 1]
			i += 2
		} else {
			src = args[i]
			i++
		}
	}
	if src == '' {
		return error('usage: vr compile <file.vr> [-o out.vobj]')
	}
	o := compiler.compile_file(src)!
	if out == '' {
		out = src.all_before_last('.') + '.vobj'
	}
	obj.write(out, o)!
	println('compiled ${src} -> ${out} (${o.code.len} bytes code, ${o.symbols.len} symbols, ${o.relocs.len} relocations)')
}

fn toolchain_assemble(args []string) ! {
	mut src := ''
	mut out := ''
	mut i := 0
	for i < args.len {
		if args[i] == '-o' && i + 1 < args.len {
			out = args[i + 1]
			i += 2
		} else {
			src = args[i]
			i++
		}
	}
	if src == '' {
		return error('usage: vr assemble <file.vasm> [-o out.vobj]')
	}
	o := assembler.assemble_file(src)!
	if out == '' {
		out = src.all_before_last('.') + '.vobj'
	}
	obj.write(out, o)!
	println('assembled ${src} -> ${out} (${o.code.len} bytes code, ${o.symbols.len} symbols, ${o.relocs.len} relocations)')
}

fn toolchain_link(args []string) ! {
	mut objs := []string{}
	mut out := ''
	mut i := 0
	for i < args.len {
		if args[i] == '-o' && i + 1 < args.len {
			out = args[i + 1]
			i += 2
		} else {
			objs << args[i]
			i++
		}
	}
	if objs.len == 0 {
		return error('usage: vr link <a.vobj> [more.vobj ...] [-o out.vbin]')
	}
	if out == '' {
		out = os.base(objs[0]).all_before_last('.') + '.vbin'
	}
	linker.link(objs, out)!
	println('linked ${objs.len} object file(s) -> ${out}')
}

fn toolchain_run(args []string) ! {
	if args.len == 0 {
		return error('usage: vr run <file.vr|file.vbin> [program-args...]  (add -w to watch, --profile to profile, --max-ops N to cap instructions)')
	}
	mut watch := false
	mut profile := false
	mut max_ops := i64(0)
	mut rest := args.clone()
	for rest.len > 0 && (rest[0].starts_with('-') && rest[0] != '-') {
		if rest[0] == '-w' || rest[0] == '--watch' {
			watch = true
			rest = rest[1..]
		} else if rest[0] == '--profile' {
			profile = true
			rest = rest[1..]
		} else if rest[0] == '--max-ops' && rest.len > 1 {
			max_ops = rest[1].i64()
			rest = rest[2..]
		} else {
			return error('unknown flag "${rest[0]}" (supported: -w, --profile, --max-ops N)')
		}
	}
	if rest.len == 0 {
		return error('usage: vr run <file.vr|file.vbin> [program-args...]  (add -w to watch, --profile to profile, --max-ops N to cap instructions)')
	}
	f := rest[0]
	prog_args := rest[1..]
	if watch {
		run_watch(f, prog_args)!
		return
	}
	if f.ends_with('.vbin') {
		bin := obj.read_bin(f)!
		if profile {
			print_profile(vm.run_profiled(bin, 'main', prog_args)!, f)
			return
		}
		vm.run_opts(bin, 'main', vm.RunOpts{ args: prog_args, max_ops: max_ops })!
		return
	}
	if f.ends_with('.vr') {
		if profile {
			run_src_profiled(f, prog_args)!
			return
		}
		run_src_with_args(f, 'main', false, prog_args, max_ops)!
		return
	}
	return error('unsupported file type: ${f} (expected .vr or .vbin)')
}

// print_profile renders the profiled run's report as a table.
fn print_profile(rep vm.ProfileReport, f string) {
	println('profile: ${f}')
	println('${pad_right('function', 24)}${pad_left('calls', 8)}${pad_left('instr', 12)}${pad_left('%', 7)}')
	for r in rep.rows {
		if r.instr == 0 && r.calls == 0 {
			continue
		}
		pct := if rep.total > 0 { 100.0 * f64(r.instr) / f64(rep.total) } else { 0.0 }
		println('${pad_right(r.name, 24)}${pad_left(r.calls.str(), 8)}${pad_left(r.instr.str(), 12)}${pad_left(pct_fmt(pct) + '%', 7)}')
	}
	println('${pad_right('total', 24)}${pad_left(rep.total.str(), 12)}')
}

// pad_left pads s with spaces on the left to reach width w.
fn pad_left(s string, w int) string {
	mut out := s
	for out.len < w {
		out = ' ' + out
	}
	return out
}

// pad_right pads s with spaces on the right to reach width w.
fn pad_right(s string, w int) string {
	mut out := s
	for out.len < w {
		out += ' '
	}
	return out
}

// pct_fmt renders a percentage with one decimal.
fn pct_fmt(p f64) string {
	return '${p:.1f}'
}

// run_src_profiled compiles+links a source file and runs it with profiling.
fn run_src_profiled(src string, prog_args []string) ! {
	tmp_obj := os.join_path(os.temp_dir(), 'vr_${os.getpid()}.vobj')
	tmp_bin := os.join_path(os.temp_dir(), 'vr_${os.getpid()}.vbin')
	defer {
		os.rm(tmp_obj) or {}
		os.rm(tmp_bin) or {}
	}
	o := compiler.compile_file(src)!
	obj.write(tmp_obj, o)!
	linker.link([tmp_obj], tmp_bin)!
	bin := obj.read_bin(tmp_bin)!
	print_profile(vm.run_profiled(bin, 'main', prog_args)!, src)
}

// run_watch recompiles and reruns the program whenever the source file (or
// anything it imports) changes — the classic develop-run-edit loop.
fn run_watch(f string, prog_args []string) ! {
	if !f.ends_with('.vr') {
		return error('watch mode works on .vr source files, got ${f}')
	}
	mut last := os.file_last_mod_unix(f)
	println('watching ${f} (Ctrl-C to stop)')
	for {
		// clear the screen between runs for a clean diff of output
		print('\x1b[2J\x1b[H')
		println('== ${os.file_name(f)} — ${time.now().custom_format('HH:mm:ss')} ==')
		run_src_with_args(f, 'main', false, prog_args, 0) or {
			eprintln('${err.msg()}')
		}
		for {
			time.sleep(400 * time.millisecond)
			cur := os.file_last_mod_unix(f)
			if cur != last {
				last = cur
				break
			}
		}
	}
}

// toolchain_debug starts the interactive debugger: run to the first
// --break <line>, then accept commands (continue/step/next/finish/print/...).
// With no breakpoints it stops at program entry so breakpoints can be set
// before anything runs. --trace keeps the old full instruction trace.
fn toolchain_debug(args []string) ! {
	mut f := ''
	mut bps := []int{}
	mut trace := false
	mut i := 0
	for i < args.len {
		a := args[i]
		if a == '--break' && i + 1 < args.len {
			bps << args[i + 1].int()
			i += 2
		} else if a == '--trace' {
			trace = true
			i++
		} else if f == '' {
			f = a
			i++
		} else {
			return error('unexpected argument "${a}" (usage: vr debug <file> [--break N]... [--trace])')
		}
	}
	if f == '' {
		return error('usage: vr debug <file.vr|file.vbin> [--break N]... [--trace]')
	}
	if f.ends_with('.vbin') {
		bin := obj.read_bin(f)!
		vm.run_opts(bin, 'main', vm.RunOpts{ debug: true, breakpoints: bps, trace: trace })!
		return
	}
	if f.ends_with('.vr') {
		run_src_debug(f, bps, trace)!
		return
	}
	return error('unsupported file type: ${f} (expected .vr or .vbin)')
}

// toolchain_profile is `vr profile <file> [args...]` — run with per-function
// instruction/call counting and print the hot-function report.
fn toolchain_profile(args []string) ! {
	if args.len == 0 {
		return error('usage: vr profile <file.vr|file.vbin> [program-args...]')
	}
	f := args[0]
	prog_args := args[1..]
	if f.ends_with('.vbin') {
		bin := obj.read_bin(f)!
		print_profile(vm.run_profiled(bin, 'main', prog_args)!, f)
		return
	}
	if f.ends_with('.vr') {
		run_src_profiled(f, prog_args)!
		return
	}
	return error('unsupported file type: ${f} (expected .vr or .vbin)')
}

// run_src_debug compiles+links a source file and runs it under the debugger.
fn run_src_debug(src string, bps []int, trace bool) ! {
	tmp_obj := os.join_path(os.temp_dir(), 'vr_${os.getpid()}.vobj')
	tmp_bin := os.join_path(os.temp_dir(), 'vr_${os.getpid()}.vbin')
	defer {
		os.rm(tmp_obj) or {}
		os.rm(tmp_bin) or {}
	}
	o := compiler.compile_file(src)!
	obj.write(tmp_obj, o)!
	linker.link([tmp_obj], tmp_bin)!
	bin := obj.read_bin(tmp_bin)!
	vm.run_opts(bin, 'main', vm.RunOpts{ debug: true, breakpoints: bps, trace: trace })!
}

fn toolchain_test(args []string) ! {
	if args.len == 0 {
		return error('usage: vr test <file.vr|dir>')
	}
	target := args[0]
	if os.is_dir(target) {
		test_dir(target)!
		return
	}
	src := target
	o := compiler.compile_file(src)!
	mut tests := []string{}
	for s in o.symbols {
		if s.name.starts_with('test_') {
			tests << s.name
		}
	}
	if tests.len == 0 {
		println('no test_* functions found in ${src}')
		return
	}
	tmp_obj := os.join_path(os.temp_dir(), 'vr_${os.getpid()}.vobj')
	tmp_bin := os.join_path(os.temp_dir(), 'vr_${os.getpid()}.vbin')
	defer {
		os.rm(tmp_obj) or {}
		os.rm(tmp_bin) or {}
	}
	obj.write(tmp_obj, o)!
	linker.link([tmp_obj], tmp_bin)!
	bin := obj.read_bin(tmp_bin)!
	mut passes := 0
	mut fails := 0
	for t in tests {
		if run_test(bin, t) {
			println('  PASS  ${t}')
			passes++
		} else {
			fails++
		}
	}
	println('')
	println('${passes} passed, ${fails} failed (${tests.len} total)')
	if fails > 0 {
		exit(1)
	}
}

// test_dir runs every test_* function in every .vr file under a directory
// (recursively), so a whole project's suite runs with one command.
fn test_dir(dir string) ! {
	files := os.walk_ext(dir, '.vr', os.WalkParams{})
	mut files_sorted := files.clone()
	files_sorted.sort()
	mut total_pass := 0
	mut total_fail := 0
	mut file_count := 0
	for src in files_sorted {
		if os.file_name(src).starts_with('.') {
			continue
		}
		o := compiler.compile_file(src) or {
			eprintln('  COMPILE FAIL  ${src}  —  ${err.msg()}')
			total_fail++
			continue
		}
		mut tests := []string{}
		for s in o.symbols {
			if s.name.starts_with('test_') {
				tests << s.name
			}
		}
		if tests.len == 0 {
			continue
		}
		file_count++
		println('-- ${src}')
		tmp_obj := os.join_path(os.temp_dir(), 'vr_${os.getpid()}_${file_count}.vobj')
		tmp_bin := os.join_path(os.temp_dir(), 'vr_${os.getpid()}_${file_count}.vbin')
		defer {
			os.rm(tmp_obj) or {}
			os.rm(tmp_bin) or {}
		}
		obj.write(tmp_obj, o)!
		linker.link([tmp_obj], tmp_bin)!
		bin := obj.read_bin(tmp_bin)!
		for t in tests {
			if run_test(bin, t) {
				println('  PASS  ${t}')
				total_pass++
			} else {
				total_fail++
			}
		}
	}
	println('')
	println('${total_pass} passed, ${total_fail} failed across ${file_count} file(s)')
	if total_fail > 0 {
		exit(1)
	}
}

fn run_test(bin obj.Bin, name string) bool {
	vm.run(bin, name, false) or {
		eprintln('  FAIL  ${name}  —  ${err}')
		return false
	}
	return true
}

fn toolchain_bench(args []string) ! {
	if args.len == 0 {
		return error('usage: vr bench <file.vr> [iterations]')
	}
	src := args[0]
	mut n := 1000
	if args.len > 1 {
		n = args[1].int()
	}
	tmp_obj := os.join_path(os.temp_dir(), 'vr_${os.getpid()}.vobj')
	tmp_bin := os.join_path(os.temp_dir(), 'vr_${os.getpid()}.vbin')
	defer {
		os.rm(tmp_obj) or {}
		os.rm(tmp_bin) or {}
	}
	o := compiler.compile_file(src)!
	obj.write(tmp_obj, o)!
	linker.link([tmp_obj], tmp_bin)!
	bin := obj.read_bin(tmp_bin)!
	start := time.now().unix_milli()
	for _ in 0..n {
		vm.run(bin, 'main', false)!
	}
	ms := time.now().unix_milli() - start
	rate := if ms > 0 { f64(n) / (f64(ms) / 1000.0) } else { f64(0) }
	println('bench: ${n} runs of main() in ${ms}ms (${rate:.0} runs/s)')
}

fn run_src(src string, entry string, trace bool) ! {
	run_src_with_args(src, entry, trace, []string{}, 0)!
}

fn run_src_with_args(src string, entry string, trace bool, args []string, max_ops i64) ! {
	tmp_obj := os.join_path(os.temp_dir(), 'vr_${os.getpid()}.vobj')
	tmp_bin := os.join_path(os.temp_dir(), 'vr_${os.getpid()}.vbin')
	defer {
		os.rm(tmp_obj) or {}
		os.rm(tmp_bin) or {}
	}
	o := compiler.compile_file(src)!
	obj.write(tmp_obj, o)!
	linker.link([tmp_obj], tmp_bin)!
	bin := obj.read_bin(tmp_bin)!
	vm.run_opts(bin, entry, vm.RunOpts{ trace: trace, args: args, max_ops: max_ops })!
}

// ---------------------------------------------------------------------------
// housekeeping

// ---------------------------------------------------------------------------
// make — run a .vrmm build module

// toolchain_make compiles a .vrmm build module and runs one of its targets.
// A build module is a VuurRaaf program that drives the toolchain through the
// build_* builtins (build_compile, build_link, build_run, build_exec, ...).
//
//   vr make                 runs main() (or build()) from build.vrmm
//   vr make clean           runs the clean() target
//   vr make deploy --prod   runs deploy() with args() == ["--prod"]
//   vr make -f x.vrmm t     runs target t from x.vrmm
//
// A target that returns nonzero (or calls exit(n>0) / throws) fails the build.
fn toolchain_make(args []string) ! {
	mut file := 'build.vrmm'
	mut rest := []string{}
	mut i := 0
	for i < args.len {
		if args[i] == '-f' && i + 1 < args.len {
			file = args[i + 1]
			i += 2
		} else {
			rest << args[i]
			i++
		}
	}
	if !os.exists(file) {
		return error('no build module "${file}" found (write one, or run `vr init` to scaffold it)')
	}
	mut target := 'main'
	if rest.len > 0 {
		target = rest[0]
		rest = rest[1..].clone()
	}
	// compile and link the build module itself
	tmp_obj := os.join_path(os.temp_dir(), 'vr_make_${os.getpid()}.vobj')
	tmp_bin := os.join_path(os.temp_dir(), 'vr_make_${os.getpid()}.vbin')
	defer {
		os.rm(tmp_obj) or {}
		os.rm(tmp_bin) or {}
	}
	o := compiler.compile_file(file)!
	obj.write(tmp_obj, o)!
	linker.link([tmp_obj], tmp_bin)!
	bin := obj.read_bin(tmp_bin)!
	// pick the entry: an explicit target, else main, else build
	mut names := []string{}
	for f in bin.fns {
		names << f.name
	}
	mut entry := ''
	if target == 'main' && 'main' in names {
		entry = 'main'
	} else if target == 'main' && 'build' in names {
		entry = 'build'
	} else if target in names {
		entry = target
	} else {
		return error('no target function "${target}" in ${file} (available: ${names.join(', ')} or main)')
	}
	println('vr make: ${file} [${entry}]')
	code := vm.run_build(bin, entry, rest, os.abs_path(os.dir(file)))!
	if code != 0 {
		return error('target ${entry} finished with exit code ${code}')
	}
}

fn toolchain_clean() {
	mut n := 0
	if files := os.ls('.') {
		for f in files {
			if f.ends_with('.vobj') || f.ends_with('.vbin') {
				os.rm(f) or {}
				n++
			}
		}
	}
	println('cleaned ${n} artifact(s) (the vr binary in bin/ is left alone; use "vr up" to rebuild it)')
}

fn toolchain_up() ! {
	vcmd := os.find_abs_path_of_executable('v') or { 'v' }
	out := os.join_path(project_root, 'bin', 'vr')
	// build from the project root with `.`, not an explicit file/path:
	// the latter makes V auto-select tcc without the boehm GC, a combination
	// that miscompiles this codebase (verified: `v -o out .` is the safe one)
	res := os.execute('cd "${project_root}" && ${vcmd} -o "${out}" .')
	if res.exit_code != 0 {
		return error('build failed:\n${res.output}')
	}
	println('rebuilt: ${out}')
}

fn toolchain_symlink() ! {
	src := os.join_path(project_root, 'bin', 'vr')
	if !os.exists(src) {
		return error('bin/vr does not exist — run "vr up" first')
	}
	candidates := [os.join_path(os.home_dir(), '.local', 'bin'), '/usr/local/bin']
	for dir in candidates {
		if !os.exists(dir) {
			continue
		}
		link_path := os.join_path(dir, 'vr')
		if os.exists(link_path) {
			os.rm(link_path) or {}
		}
		os.symlink(src, link_path) or { continue }
		println('linked ${src} -> ${link_path}')
		return
	}
	return error('no writable bin dir found; symlink ${src} into your PATH manually')
}
