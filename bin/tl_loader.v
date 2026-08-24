// toolchain loader
// Discovers and describes the toolchain components baked into the binary.
// Run standalone with:  v run bin/tl_loader.v

module main

import os

struct Component {
mut:
	name    string
	role    string
	path    string
	enabled bool
}

// load_toolchain returns the components that make up this toolchain.
fn load_toolchain() []Component {
	root := os.dir(os.executable())
	return [
		Component{
			name:    'compiler'
			role:    'lexer, parser, bytecode codegen'
			path:    os.join_path(root, 'compiler')
			enabled: true
		},
		Component{
			name:    'assembler'
			role:    'vasm -> vobj'
			path:    os.join_path(root, 'assembler')
			enabled: true
		},
		Component{
			name:    'linker'
			role:    'vobj set -> vbin'
			path:    os.join_path(root, 'linker')
			enabled: true
		},
		Component{
			name:    'vm'
			role:    'stack-based runtime'
			path:    os.join_path(root, 'vm')
			enabled: true
		},
	]
}

fn main() {
	for c in load_toolchain() {
		status := if c.enabled { 'loaded' } else { 'disabled' }
		println('[${status}]  ${c.name:-12}  ${c.role}  (${c.path})')
	}
}
