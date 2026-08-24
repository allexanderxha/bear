// toolchain alloc
// A tiny byte arena for toolchain scratch memory: allocate fixed-size blocks
// from a pre-sized arena and release them all at once.
// Run standalone with:  v run bin/tl_alloc.v

module main

struct Arena {
mut:
	data []u8
	used int
}

// new_arena reserves `cap` bytes of scratch memory.
fn new_arena(cap int) Arena {
	return Arena{
		data: []u8{len: cap}
		used: 0
	}
}

// alloc returns an offset into the arena for a block of `n` bytes.
fn (mut a Arena) alloc(n int) !int {
	if a.used + n > a.data.len {
		return error('arena out of memory: need ${n} bytes, ${a.data.len - a.used} left')
	}
	off := a.used
	a.used += n
	return off
}

// free_all releases everything allocated so far.
fn (mut a Arena) free_all() {
	a.used = 0
}

fn (a Arena) stats() string {
	return 'arena: ${a.used} / ${a.data.len} bytes used'
}

fn main() {
	mut arena := new_arena(1024 * 1024) // 1 MiB
	println('toolchain alloc: arena ready')
	println(arena.stats())
	off1 := arena.alloc(64) or { eprintln(err); exit(1) }
	off2 := arena.alloc(4096) or { eprintln(err); exit(1) }
	println('allocated 64 bytes  at offset ${off1}')
	println('allocated 4096 bytes at offset ${off2}')
	println(arena.stats())
	arena.free_all()
	println('after free_all: ${arena.stats()}')
}
