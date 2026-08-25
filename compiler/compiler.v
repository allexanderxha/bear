// compiler.v — public API for the VuurRaaf compiler.
module compiler

import os
import obj

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
// the path as given first, then falls back to the package-manager layout so
// `import "pkg/file.vr"` finds vendor/pkg/file.vr.
pub fn resolve_import(path string) !string {
	if os.exists(path) {
		return path
	}
	for cand in ['vendor/${path}', 'vendor/${path}.vr', 'vendor/${path}/main.vr', 'vendor/${path}/src/main.vr'] {
		if os.exists(cand) {
			return cand
		}
	}
	return error('cannot resolve import "${path}" (tried vendor/)"')
}
