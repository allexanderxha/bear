// obj.v — the VuurRaaf object file format (VROBJ) and executable format (VRBIN).
//
// VROBJ is the linker input: code, exported symbols, string constants, and
// relocations for call sites that the linker must resolve.
// VRBIN is the final executable consumed by the runtime VM.
//
// Both formats are little-endian and self-describing:
//
//   VROBJ: "VROBJ" ver u32 nsym  { u32 name_len name i64 entry }*
//          u32 nstr { u32 len bytes }*  u32 ncode code  u32 nreloc { u32 off u32 name_len name u8 kind }*
//   VRBIN: "VRBIN" ver u32 nfn { u32 name_len name i64 entry }*
//          u32 nstr { u32 len bytes }*  u32 ncode code
module obj

import os
import math

pub const magic = 'VROBJ'
pub const bin_magic = 'VRBIN'

pub struct Symbol {
pub mut:
	name  string
	entry int // code offset of the function entry
}

pub struct Reloc {
pub mut:
	offset u32 // byte offset of the 8-byte operand inside `code`
	name   string // kind 0: symbol name; kind 1: the string constant itself
	kind   u8 // 0 = call site, 1 = string constant reference
}

pub struct Obj {
pub mut:
	symbols []Symbol
	strings []string
	code    []u8
	relocs  []Reloc
	lines   []LineInfo
}

pub struct BinFn {
pub mut:
	name  string
	entry int
}

// LineInfo maps a code offset to the source line it was generated from,
// enabling source-level locations in runtime errors.
pub struct LineInfo {
pub mut:
	off  u32
	line int
}

pub struct Bin {
pub mut:
	fns     []BinFn
	strings []string
	code    []u8
	lines   []LineInfo
}

// ---------------------------------------------------------------------------
// encoding helpers

pub fn encode_u32(v u32) []u8 {
	return [u8(v & 0xff), u8((v >> 8) & 0xff), u8((v >> 16) & 0xff), u8((v >> 24) & 0xff)]
}

pub fn encode_i64(v i64) []u8 {
	mut b := []u8{}
	for i in 0..8 {
		b << u8((v >> (8 * i)) & 0xff)
	}
	return b
}

// encode_f64 writes a little-endian f64 (its IEEE-754 bit pattern).
pub fn encode_f64(v f64) []u8 {
	bits := math.f64_bits(v)
	mut b := []u8{}
	for i in 0..8 {
		b << u8((bits >> (8 * i)) & 0xff)
	}
	return b
}

// patch_i64 writes a little-endian i64 over `code[off..off+8]`.
pub fn patch_i64(mut code []u8, off u32, v i64) {
	for i in 0..8 {
		code[off + u32(i)] = u8((v >> (8 * i)) & 0xff)
	}
}

// ---------------------------------------------------------------------------
// reading

struct Reader {
mut:
	b   []u8
	pos int
}

fn (mut r Reader) u8_() !u8 {
	if r.pos >= r.b.len {
		return error('object file truncated')
	}
	b := r.b[r.pos]
	r.pos++
	return b
}

fn (mut r Reader) u32_() !u32 {
	mut v := u32(0)
	for i in 0..4 {
		b := r.u8_()!
		v |= u32(b) << u32(8 * i)
	}
	return v
}

fn (mut r Reader) i64_() !i64 {
	mut v := i64(0)
	for i in 0..8 {
		b := r.u8_()!
		v |= i64(u64(b) << u32(8 * i))
	}
	return v
}

fn (mut r Reader) read_str() !string {
	n := int(r.u32_()!)
	if r.pos + n > r.b.len {
		return error('object file truncated')
	}
	s := r.b[r.pos..r.pos + n].bytestr()
	r.pos += n
	return s
}

// ---------------------------------------------------------------------------
// VROBJ

pub fn write(path string, o Obj) ! {
	mut b := []u8{}
	b << magic.bytes()
	b << u8(1) // format version
	b << encode_u32(u32(o.symbols.len))
	for s in o.symbols {
		b << encode_u32(u32(s.name.len))
		b << s.name.bytes()
		b << encode_i64(i64(s.entry))
	}
	b << encode_u32(u32(o.strings.len))
	for s in o.strings {
		b << encode_u32(u32(s.len))
		b << s.bytes()
	}
	b << encode_u32(u32(o.code.len))
	b << o.code
	b << encode_u32(u32(o.relocs.len))
	for r in o.relocs {
		b << encode_u32(r.offset)
		b << encode_u32(u32(r.name.len))
		b << r.name.bytes()
		b << r.kind
	}
	b << encode_u32(u32(o.lines.len))
	for l in o.lines {
		b << encode_u32(l.off)
		b << encode_i64(i64(l.line))
	}
	os.write_bytes(path, b)!
}

pub fn read(path string) !Obj {
	b := os.read_bytes(path)!
	if b.len < magic.len || b[0..magic.len].bytestr() != magic {
		return error('not a VROBJ file: ${path}')
	}
	mut r := Reader{ b: b, pos: magic.len }
	_ := r.u8_()! // version
	mut o := Obj{}
	nsym := int(r.u32_()!)
	for _ in 0..nsym {
		name := r.read_str()!
		entry := int(r.i64_()!)
		o.symbols << Symbol{ name: name, entry: entry }
	}
	nstr := int(r.u32_()!)
	for _ in 0..nstr {
		o.strings << r.read_str()!
	}
	ncode := int(r.u32_()!)
	if r.pos + ncode > b.len {
		return error('object file truncated')
	}
	o.code = b[r.pos..r.pos + ncode]
	r.pos += ncode
	nrel := int(r.u32_()!)
	for _ in 0..nrel {
		off := r.u32_()!
		name := r.read_str()!
		kind := r.u8_()!
		o.relocs << Reloc{ offset: off, name: name, kind: kind }
	}
	nlines := int(r.u32_()!)
	for _ in 0..nlines {
		off := r.u32_()!
		line := int(r.i64_()!)
		o.lines << LineInfo{ off: off, line: line }
	}
	return o
}

// ---------------------------------------------------------------------------
// VRBIN

pub fn write_bin(path string, bin Bin) ! {
	mut b := []u8{}
	b << bin_magic.bytes()
	b << u8(1) // format version
	b << encode_u32(u32(bin.fns.len))
	for f in bin.fns {
		b << encode_u32(u32(f.name.len))
		b << f.name.bytes()
		b << encode_i64(i64(f.entry))
	}
	b << encode_u32(u32(bin.strings.len))
	for s in bin.strings {
		b << encode_u32(u32(s.len))
		b << s.bytes()
	}
	b << encode_u32(u32(bin.code.len))
	b << bin.code
	b << encode_u32(u32(bin.lines.len))
	for l in bin.lines {
		b << encode_u32(l.off)
		b << encode_i64(i64(l.line))
	}
	os.write_bytes(path, b)!
}

pub fn read_bin(path string) !Bin {
	b := os.read_bytes(path)!
	if b.len < bin_magic.len || b[0..bin_magic.len].bytestr() != bin_magic {
		return error('not a VRBIN file: ${path}')
	}
	mut r := Reader{ b: b, pos: bin_magic.len }
	_ := r.u8_()! // version
	mut bin := Bin{}
	nfn := int(r.u32_()!)
	for _ in 0..nfn {
		name := r.read_str()!
		entry := int(r.i64_()!)
		bin.fns << BinFn{ name: name, entry: entry }
	}
	nstr := int(r.u32_()!)
	for _ in 0..nstr {
		bin.strings << r.read_str()!
	}
	ncode := int(r.u32_()!)
	if r.pos + ncode > b.len {
		return error('executable file truncated')
	}
	bin.code = b[r.pos..r.pos + ncode]
	r.pos += ncode
	nlines := int(r.u32_()!)
	for _ in 0..nlines {
		off := r.u32_()!
		line := int(r.i64_()!)
		bin.lines << LineInfo{ off: off, line: line }
	}
	return bin
}
