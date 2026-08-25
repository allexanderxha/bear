// json.v — JSON encoding and decoding for the VuurRaaf VM.
//
// The decoder is self-contained (no json2) because json2.decode[Any] can loop
// forever on truncated input; this parser is strictly bounded — every loop
// consumes input, so malformed documents always fail with a position.
//
// Values map 1:1 to the language: objects -> structs (keys in input order,
// last duplicate wins), arrays -> arrays, strings -> strings, numbers -> int
// when integral (42, 42.0) else float, true/false -> 1/0, null -> `none`.
module vm

import math

// JsonParser walks a JSON document one byte at a time.
struct JsonParser {
mut:
	src string
	pos int
}

// json_parse decodes a whole JSON document into a VM value.
fn (mut v Vm) json_parse(s string) !i64 {
	mut p := JsonParser{ src: s }
	p.skip_ws()
	if p.pos >= p.src.len {
		return p.error('empty input')
	}
	val := v.json_parse_value(mut p)!
	p.skip_ws()
	if p.pos < p.src.len {
		return p.error('trailing data after the value')
	}
	return val
}

fn (mut p JsonParser) peek() u8 {
	if p.pos >= p.src.len {
		return 0
	}
	return p.src[p.pos]
}

fn (mut p JsonParser) skip_ws() {
	for p.pos < p.src.len {
		c := p.src[p.pos]
		if c == ` ` || c == `\t` || c == `\n` || c == `\r` {
			p.pos++
		} else {
			break
		}
	}
}

// error builds a parse error with the current line and column.
fn (mut p JsonParser) error(msg string) IError {
	mut line := 1
	mut col := 1
	for i in 0..p.pos {
		if p.src[i] == `\n` {
			line++
			col = 1
		} else {
			col++
		}
	}
	return error('${msg} at line ${line}, col ${col}')
}

fn (mut p JsonParser) expect_word(w string) ! {
	if p.pos + w.len > p.src.len || p.src[p.pos..p.pos + w.len] != w {
		return p.error('invalid token')
	}
	p.pos += w.len
}

fn (mut v Vm) json_parse_value(mut p JsonParser) !i64 {
	p.skip_ws()
	match p.peek() {
		`{` {
			return v.json_parse_object(mut p)!
		}
		`[` {
			return v.json_parse_array(mut p)!
		}
		`"` {
			return v.alloc_str(p.parse_string()!)
		}
		`t` {
			p.expect_word('true')!
			return v.enc_int(1)
		}
		`f` {
			p.expect_word('false')!
			return v.enc_int(0)
		}
		`n` {
			p.expect_word('null')!
			return none_val
		}
		else {
			c := p.peek()
			if (c >= `0` && c <= `9`) || c == `-` {
				return v.json_parse_number(mut p)!
			}
			return p.error('unexpected character "${c.ascii_str()}"')
		}
	}
}

fn (mut v Vm) json_parse_object(mut p JsonParser) !i64 {
	p.pos++ // consume '{'
	mut fields := []Field{}
	p.skip_ws()
	if p.peek() == `}` {
		p.pos++
		v.structs << StructVal{ fields: fields }
		return v.mkstruct_handle(v.structs.len - 1)
	}
	for {
		p.skip_ws()
		if p.peek() != `"` {
			return p.error('expected a string key in object')
		}
		key := p.parse_string()!
		p.skip_ws()
		if p.peek() != `:` {
			return p.error('expected ":" after object key')
		}
		p.pos++
		val := v.json_parse_value(mut p)!
		// last duplicate key wins (like most JSON parsers)
		mut replaced := false
		for i in 0..fields.len {
			if fields[i].name == key {
				fields[i].val = val
				replaced = true
				break
			}
		}
		if !replaced {
			fields << Field{ name: key, val: val }
		}
		p.skip_ws()
		c := p.peek()
		if c == `,` {
			p.pos++
			continue
		}
		if c == `}` {
			p.pos++
			break
		}
		return p.error('expected "," or "}" in object')
	}
	v.structs << StructVal{ fields: fields }
	return v.mkstruct_handle(v.structs.len - 1)
}

fn (mut v Vm) json_parse_array(mut p JsonParser) !i64 {
	p.pos++ // consume '['
	mut arr := []i64{}
	p.skip_ws()
	if p.peek() == `]` {
		p.pos++
		v.arrays << arr
		return v.mkarr(v.arrays.len - 1)
	}
	for {
		arr << v.json_parse_value(mut p)!
		p.skip_ws()
		c := p.peek()
		if c == `,` {
			p.pos++
			continue
		}
		if c == `]` {
			p.pos++
			break
		}
		return p.error('expected "," or "]" in array')
	}
	v.arrays << arr
	return v.mkarr(v.arrays.len - 1)
}

fn (mut v Vm) json_parse_number(mut p JsonParser) !i64 {
	start := p.pos
	if p.peek() == `-` {
		p.pos++
	}
	mut digits := 0
	for p.pos < p.src.len && p.src[p.pos] >= `0` && p.src[p.pos] <= `9` {
		p.pos++
		digits++
	}
	if digits == 0 {
		return p.error('invalid number')
	}
	mut is_float := false
	if p.pos < p.src.len && p.src[p.pos] == `.` {
		is_float = true
		p.pos++
		mut fd := 0
		for p.pos < p.src.len && p.src[p.pos] >= `0` && p.src[p.pos] <= `9` {
			p.pos++
			fd++
		}
		if fd == 0 {
			return p.error('invalid number (missing digits after ".")')
		}
	}
	if p.pos < p.src.len && (p.src[p.pos] == `e` || p.src[p.pos] == `E`) {
		is_float = true
		p.pos++
		if p.pos < p.src.len && (p.src[p.pos] == `+` || p.src[p.pos] == `-`) {
			p.pos++
		}
		mut ed := 0
		for p.pos < p.src.len && p.src[p.pos] >= `0` && p.src[p.pos] <= `9` {
			p.pos++
			ed++
		}
		if ed == 0 {
			return p.error('invalid number (missing exponent digits)')
		}
	}
	raw := p.src[start..p.pos]
	if is_float {
		f := raw.f64()
		// integral floats become ints so `42` and `42.0` round-trip cleanly
		if f == math.floor(f) && math.abs(f) < 1e18 {
			return v.enc_int(i64(f))
		}
		return v.push_float(f)
	}
	return v.enc_int(raw.i64())
}

fn (mut p JsonParser) parse_string() !string {
	p.pos++ // opening quote
	mut out := ''
	for {
		if p.pos >= p.src.len {
			return p.error('unterminated string')
		}
		c := p.src[p.pos]
		if c == `"` {
			p.pos++
			return out
		}
		if c == `\\` {
			p.pos++
			if p.pos >= p.src.len {
				return p.error('unterminated escape sequence')
			}
			e := p.src[p.pos]
			p.pos++
			match e {
				`"` {
					out += '"'
				}
				`\\` {
					out += '\\'
				}
				`/` {
					out += '/'
				}
				`b` {
					out += '\b'
				}
				`f` {
					out += '\f'
				}
				`n` {
					out += '\n'
				}
				`r` {
					out += '\r'
				}
				`t` {
					out += '\t'
				}
				`u` {
					out += p.parse_unicode_escape()!
				}
				else {
					return p.error('invalid escape "\\${e.ascii_str()}"')
				}
			}
			continue
		}
		// pass a UTF-8 code point through as raw bytes
		width := utf8_width(c)
		if width == 0 {
			return p.error('invalid UTF-8 byte')
		}
		out += p.src[p.pos..p.pos + width]
		p.pos += width
	}
	return p.error('unterminated string')
}

// parse_unicode_escape handles \uXXXX, combining surrogate pairs so emoji and
// astral characters decode correctly.
fn (mut p JsonParser) parse_unicode_escape() !string {
	if p.pos + 4 > p.src.len {
		return p.error('invalid \\u escape')
	}
	hi := hex4(p.src[p.pos..p.pos + 4]) or { return p.error('invalid \\u escape') }
	p.pos += 4
	mut code := hi
	if hi >= 0xD800 && hi <= 0xDBFF {
		// high surrogate: combine with an immediately following low surrogate
		if p.pos + 6 <= p.src.len && p.src[p.pos] == `\\` && p.src[p.pos + 1] == `u` {
			lo := hex4(p.src[p.pos + 2..p.pos + 6]) or { return p.error('invalid \\u escape') }
			if lo >= 0xDC00 && lo <= 0xDFFF {
				code = 0x10000 + (hi - 0xD800) * 0x400 + (lo - 0xDC00)
				p.pos += 6
			}
		}
	} else if hi >= 0xDC00 && hi <= 0xDFFF {
		return p.error('unpaired low surrogate')
	}
	return utf8_encode(code)
}

fn hex4(s string) !u32 {
	mut n := u32(0)
	for i in 0..4 {
		c := s[i]
		d := match c {
			`0`...`9` { u32(c - `0`) }
			`a`...`f` { u32(c - `a` + 10) }
			`A`...`F` { u32(c - `A` + 10) }
			else { return error('bad hex digit "${c.ascii_str()}"') }
		}
		n = n * 16 + d
	}
	return n
}

fn utf8_width(b u8) int {
	if b < 0x80 {
		return 1
	}
	if b >= 0xC0 && b <= 0xDF {
		return 2
	}
	if b >= 0xE0 && b <= 0xEF {
		return 3
	}
	if b >= 0xF0 && b <= 0xF7 {
		return 4
	}
	return 0
}

// utf8_encode renders a Unicode code point as UTF-8 bytes.
fn utf8_encode(code u32) string {
	if code < 0x80 {
		return u8(code).ascii_str()
	}
	mut bytes := []u8{}
	if code < 0x800 {
		bytes << u8(0xC0 | (code >> 6))
		bytes << u8(0x80 | (code & 0x3F))
	} else if code < 0x10000 {
		bytes << u8(0xE0 | (code >> 12))
		bytes << u8(0x80 | ((code >> 6) & 0x3F))
		bytes << u8(0x80 | (code & 0x3F))
	} else {
		bytes << u8(0xF0 | (code >> 18))
		bytes << u8(0x80 | ((code >> 12) & 0x3F))
		bytes << u8(0x80 | ((code >> 6) & 0x3F))
		bytes << u8(0x80 | (code & 0x3F))
	}
	return bytes.bytestr()
}

// ---------------------------------------------------------------------------
// encoding

// json_encode_value renders a VuurRaaf value as a JSON string. Ints (and
// bools, which are 0/1) become numbers, floats use fmt_float so integral
// floats stay clean, structs become objects, arrays become arrays, and the
// `none` value becomes null. Functions cannot be encoded.
fn (mut v Vm) json_encode_value(x i64, depth int) !string {
	if depth > 64 {
		return error('value is nested too deeply (possible cycle)')
	}
	if v.is_none(x) {
		return 'null'
	}
	if v.is_str(x) && v.valid_handle(x) {
		return json_quote(v.strings[v.hand(x)])
	}
	if v.is_arr(x) && v.valid_arr_handle(x) {
		mut parts := []string{}
		for el in v.arrays[v.hand(x)] {
			parts << v.json_encode_value(el, depth + 1)!
		}
		return '[' + parts.join(',') + ']'
	}
	if v.is_struct(x) && v.valid_struct_handle(x) {
		mut parts := []string{}
		for f in v.structs[v.hand(x)].fields {
			parts << json_quote(f.name) + ':' + v.json_encode_value(f.val, depth + 1)!
		}
		return '{' + parts.join(',') + '}'
	}
	if v.is_float(x) && v.valid_float_handle(x) {
		f := v.fval(x)
		if math.is_nan(f) || math.is_inf(f, 1) || math.is_inf(f, -1) {
			return error('cannot encode NaN or Infinity as JSON')
		}
		return fmt_float(f)
	}
	if v.is_closure(x) && v.valid_closure_handle(x) {
		return error('cannot encode a function value as JSON')
	}
	return v.dec_int(x).str()
}

// json_pretty_value renders a value as indented, multi-line JSON (the
// `json_pretty` builtin used by the json stdlib module).
fn (mut v Vm) json_pretty_value(x i64, depth int) !string {
	ind := '  '.repeat(depth)
	ind1 := '  '.repeat(depth + 1)
	if v.is_none(x) {
		return 'null'
	}
	if v.is_str(x) && v.valid_handle(x) {
		return json_quote(v.strings[v.hand(x)])
	}
	if v.is_arr(x) && v.valid_arr_handle(x) {
		a := v.arrays[v.hand(x)]
		if a.len == 0 {
			return '[]'
		}
		mut parts := []string{}
		for el in a {
			parts << ind1 + v.json_pretty_value(el, depth + 1)!
		}
		return '[\n' + parts.join(',\n') + '\n' + ind + ']'
	}
	if v.is_struct(x) && v.valid_struct_handle(x) {
		s := v.structs[v.hand(x)]
		if s.fields.len == 0 {
			return '{}'
		}
		mut parts := []string{}
		for f in s.fields {
			parts << ind1 + json_quote(f.name) + ': ' + v.json_pretty_value(f.val, depth + 1)!
		}
		return '{\n' + parts.join(',\n') + '\n' + ind + '}'
	}
	if v.is_float(x) && v.valid_float_handle(x) {
		f := v.fval(x)
		if math.is_nan(f) || math.is_inf(f, 1) || math.is_inf(f, -1) {
			return error('cannot encode NaN or Infinity as JSON')
		}
		return fmt_float(f)
	}
	if v.is_closure(x) && v.valid_closure_handle(x) {
		return error('cannot encode a function value as JSON')
	}
	return v.dec_int(x).str()
}

// json_quote escapes a string into a JSON string literal. UTF-8 bytes pass
// through untouched; control characters become \\u00XX escapes.
fn json_quote(s string) string {
	hex := '0123456789ABCDEF'
	mut out := '"'
	for b in s.bytes() {
		match b {
			`"` { out += '\\"' }
			`\\` { out += '\\\\' }
			`\n` { out += '\\n' }
			`\r` { out += '\\r' }
			`\t` { out += '\\t' }
			`\b` { out += '\\b' }
			`\f` { out += '\\f' }
			else {
				if b < 0x20 {
					out += '\\u00'
					out += hex[int(b >> 4)].ascii_str()
					out += hex[int(b & 0xF)].ascii_str()
				} else {
					out += b.ascii_str()
				}
			}
		}
	}
	return out + '"'
}
