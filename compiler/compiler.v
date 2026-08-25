// compiler.v — public API for the VuurRaaf compiler.
module compiler

import os
import obj

// stdlib_dir is the toolchain's bundled library (lib/*.vr), resolved at build
// time so `import os` works from any working directory.
const stdlib_dir = @VMODROOT + '/lib'

// compile parses and compiles VuurRaaf source into an object file.
pub fn compile(src string) !obj.Obj {
	toks := tokenize(src)!
	prog := parse(toks)!
	// conservative compile-time type check; catches provable errors early
	check(prog)!
	return gen(prog)
}

pub fn compile_file(path string) !obj.Obj {
	src := os.read_file(path)!
	return compile(src)!
}

// resolve_import turns an import path into a readable source file. It tries
// the path as given first, then the package-manager layout (vendor/) and the
// toolchain's own standard library (lib/), so both `import "pkg/file.vr"`
// and the bare module form `import os` resolve from anywhere.
pub fn resolve_import(path string) !string {
	if os.exists(path) {
		return path
	}
	for cand in ['vendor/${path}', 'vendor/${path}.vr', 'vendor/${path}/main.vr',
		'vendor/${path}/src/main.vr', os.join_path(stdlib_dir, path + '.vr'),
		os.join_path(stdlib_dir, path, 'main.vr')] {
		if os.exists(cand) {
			return cand
		}
	}
	return error('cannot resolve import "${path}" (tried vendor/ and lib/)')
}
