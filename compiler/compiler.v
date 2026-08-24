// compiler.v — public API for the VuurRaaf compiler.
module compiler

import os
import obj

// compile parses and compiles VuurRaaf source into an object file.
pub fn compile(src string) !obj.Obj {
	toks := tokenize(src)!
	prog := parse(toks)!
	return gen(prog)
}

pub fn compile_file(path string) !obj.Obj {
	src := os.read_file(path)!
	return compile(src)!
}
