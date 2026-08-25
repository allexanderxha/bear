// pkg.v — `vr init` / `vr get` / `vr install`: a minimal package manager.
//
// Packages are fetched into ./vendor/<name>/ and recorded in vr.mod as
// `dep "<spec>"`. The compiler resolves `import "pkg/file"` against vendor/
// automatically (see compiler/compiler.v). Supported package specs:
//
//   vr get owner/repo         clone from GitHub (https://github.com/owner/repo)
//   vr get https://host/repo  clone any git repository
//   vr get ./local/path       copy a local directory
module main

import os

const manifest_file = 'vr.mod'
const vendor_dir = 'vendor'

fn toolchain_init(args []string) ! {
	pkg := if args.len > 0 { args[0] } else { os.base(os.getwd()) }
	if os.exists(manifest_file) {
		return error('${manifest_file} already exists here')
	}
	os.write_file(manifest_file, 'module ${pkg}\nversion 0.1.0\n\n# deps:\n# dep "owner/repo"\n')!
	os.mkdir('vendor') or {}
	if !os.exists('main.vr') {
		os.write_file('main.vr', 'fn main() {\n\tprintln("hello from ${pkg}")\n}\n')!
	}
	println('initialized project "${pkg}" (${manifest_file}, main.vr)')
}

fn toolchain_get(args []string) ! {
	if args.len == 0 {
		return error('usage: vr get <owner/repo | git-url | ./path>')
	}
	spec := args[0]
	// determine the package name and how to fetch it
	mut pkg := ''
	if spec.starts_with('./') || spec.starts_with('/') {
		pkg = os.base(spec)
	} else if spec.contains('://') {
		pkg = os.base(spec)
	} else if spec.contains('/') {
		pkg = spec.all_after('/')
	} else {
		pkg = spec
	}
	if pkg.ends_with('.git') {
		pkg = pkg[..pkg.len - 4]
	}
	if pkg == '' || pkg == '.' {
		return error('cannot derive a package name from "${spec}"')
	}
	os.mkdir(vendor_dir) or {}
	dst := os.join_path(vendor_dir, pkg)
	if os.exists(dst) {
		return error('package "${pkg}" already exists at ${dst}')
	}
	if spec.starts_with('./') || spec.starts_with('/') {
		copy_dir(spec, dst) or { return error('cannot copy ${spec}: ${err.msg()}') }
	} else {
		url := if spec.contains('://') { spec } else { 'https://github.com/${spec}.git' }
		println('cloning ${url} -> ${dst} ...')
		r := os.exec(['git', 'clone', '--depth', '1', url, dst])
		if r.exit_code != 0 {
			return error('git clone failed: ${r.output}')
		}
	}
	// record the dependency in the manifest (idempotent)
	if os.exists(manifest_file) {
		manifest := os.read_file(manifest_file) or { '' }
		if !manifest.contains('dep "${spec}"') {
			os.write_file(manifest_file, manifest.trim_space() + '\ndep "${spec}"\n') or {
				return error('cannot update ${manifest_file}: ${err.msg()}')
			}
		}
	}
	println('added package "${pkg}" (${spec})')
}

fn toolchain_install() ! {
	if !os.exists(manifest_file) {
		return error('no ${manifest_file} found — run `vr init` first')
	}
	manifest := os.read_file(manifest_file)!
	mut n := 0
	for line in manifest.split_into_lines() {
		t := line.trim_space()
		if !t.starts_with('dep "') {
			continue
		}
		mut spec := t[5..]
		if spec.ends_with('"') {
			spec = spec[..spec.len - 1]
		}
		if spec == '' {
			continue
		}
		n++
		toolchain_get([spec]) or { eprintln('  install: ${err.msg()}') }
	}
	if n == 0 {
		println('no dependencies in ${manifest_file}')
		return
	}
	println('installed ${n} package(s) into ${vendor_dir}/')
}

// copy_dir recursively copies a local directory tree.
fn copy_dir(src string, dst string) ! {
	if !os.is_dir(src) {
		return error('${src} is not a directory')
	}
	os.mkdir_all(dst) or { return error('cannot create ${dst}: ${err.msg()}') }
	for entry in os.ls(src) or { return error('cannot read ${src}: ${err.msg()}') } {
		sp := os.join_path(src, entry)
		dp := os.join_path(dst, entry)
		if os.is_dir(sp) {
			copy_dir(sp, dp)!
		} else if os.is_file(sp) {
			os.cp(sp, dp, os.CopyParams{}) or { return error('cannot copy ${sp}: ${err.msg()}') }
		}
	}
}

fn toolchain_list() ! {
	if !os.exists(manifest_file) {
		return error('no ${manifest_file} found here')
	}
	manifest := os.read_file(manifest_file)!
	mod_name := manifest.all_before('\n').replace('module ', '').trim_space()
	println('project: ${mod_name}')
	mut found := false
	for line in manifest.split_into_lines() {
		t := line.trim_space()
		if t.starts_with('dep "') {
			found = true
			mut spec := t[5..]
			if spec.ends_with('"') {
				spec = spec[..spec.len - 1]
			}
			mut pkg := os.base(spec)
			if pkg.ends_with('.git') {
				pkg = pkg[..pkg.len - 4]
			}
			status := if os.exists(os.join_path(vendor_dir, pkg)) { 'installed' } else { 'missing' }
			println('  ${pkg}  (${status})  <- ${spec}')
		}
	}
	if !found {
		println('  (no dependencies)')
	}
}
