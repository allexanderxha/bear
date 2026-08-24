// toolchain loader

module tl_loader

import os
import v.vmod

pub fn load_toolchain() {
	// Load the toolchain modules and initialize them
	// We call the package functions to load the toolchain modules and initialize them
	// each package has their own load argument, which is passed to the package function.
	toolchain_loader(load)
	toolchain_alloc(load)
	toolchain_compile(load)
	toolchain_assemble(load)
	toolchain_link(load)
	toolchain_run(load)
	toolchain_debug(load)
	toolchain_help(load)
	toolchain_version(load)
	toolchain_info(load)
	toolchain_config(load)
	toolchain_test(load)
	toolchain_bench(load)
	toolchain_clean(load)
	toolchain_up(load)
	toolchain_symlink(load)
}