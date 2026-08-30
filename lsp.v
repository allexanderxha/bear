// lsp.v — a minimal Language Server Protocol server for VuurRaaf.
//
//   vr lsp
//
// Speaks JSON-RPC 2.0 over stdio with Content-Length framing. The editor
// (see extension/ for a VS Code client) sends the open document, and the
// server replies with:
//   - diagnostics: the compiler's first error, positioned via its line/col
//   - go-to-definition: jumps to function/struct/enum/const/let declarations
//     in the current file (and stdlib module functions)
//   - hover: the kind of the symbol under the cursor
//
// Text sync is "full document" (version 1), which keeps the client simple.

module main

import os
import json2
import compiler

// stdio bindings used for the JSON-RPC transport (Content-Length framing)
fn C.fgetc(stream voidptr) int
fn C.fread(dest voidptr, size usize, count usize, stream voidptr) usize
fn C.fwrite(src voidptr, size usize, count usize, stream voidptr) usize
fn C.fflush(stream voidptr) int

// ---------------------------------------------------------------------------
// JSON-RPC framing

struct LspParams {
mut:
	text_document     TextDocParam @[json: 'textDocument']
	position          LspPosition
	content_changes   []TextChangeParam @[json: 'contentChanges']
}

struct TextDocParam {
mut:
	uri     string
	text    string
	version int
}

struct LspPosition {
mut:
	line      int
	character int
}

struct TextChangeParam {
mut:
	text string
}

struct LspMsg {
mut:
	jsonrpc string
	id      int
	method  string
	params  LspParams
}

fn toolchain_lsp() {
	run_lsp()
}

fn run_lsp() {
	mut docs := map[string]string{} // uri -> latest text (full sync)
	for {
		raw := read_rpc() or { break }
		if raw.len == 0 {
			continue
		}
		handle_rpc(raw, mut docs)
	}
}

fn handle_rpc(raw string, mut docs map[string]string) {
	msg := json2.decode[LspMsg](raw) or { return }
	match msg.method {
		'initialize' {
			// textDocumentSync 1 = full document sync
			send_response(msg.id,
				'{"capabilities":{"textDocumentSync":1,"definitionProvider":true,"hoverProvider":true}}')
		}
		'initialized' {
			// notification — nothing to do
		}
		'shutdown' {
			send_response(msg.id, 'null')
		}
		'exit' {
			exit(0)
		}
		'textDocument/didOpen' {
			docs[msg.params.text_document.uri] = msg.params.text_document.text
			publish_diagnostics(msg.params.text_document.uri, msg.params.text_document.text)
		}
		'textDocument/didChange' {
			// full sync: the last content change carries the whole document
			if msg.params.content_changes.len > 0 {
				docs[msg.params.text_document.uri] = msg.params.content_changes[msg.params.content_changes.len -
					1].text
			}
			text := docs[msg.params.text_document.uri] or { '' }
			publish_diagnostics(msg.params.text_document.uri, text)
		}
		'textDocument/didSave' {
			text := docs[msg.params.text_document.uri] or { '' }
			publish_diagnostics(msg.params.text_document.uri, text)
		}
		'textDocument/definition' {
			loc := definition_at(msg.params.text_document.uri, docs, msg.params.position)
			send_response(msg.id, loc)
		}
		'textDocument/hover' {
			h := hover_at(msg.params.text_document.uri, docs, msg.params.position)
			send_response(msg.id, h)
		}
		else {
			// respond null to unknown requests so editors don't hang
			if msg.id > 0 {
				send_response(msg.id, 'null')
			}
		}
	}
}

// read_rpc reads one Content-Length framed JSON-RPC message from stdin.
fn read_rpc() !string {
	mut content_len := 0
	for {
		line := read_stdin_line() or { return err }
		if line.len == 0 {
			break // blank line ends the header block
		}
		if line.starts_with('Content-Length:') {
			content_len = line.all_after(':').trim_space().int()
		}
	}
	if content_len <= 0 {
		return ''
	}
	return read_stdin_bytes(content_len).bytestr()
}

fn read_stdin_line() !string {
	mut line := []u8{}
	for {
		b := read_stdin_byte() or { return err }
		if b == `\n` {
			break
		}
		if b != `\r` {
			line << b
		}
	}
	return line.bytestr()
}

fn read_stdin_byte() !u8 {
	c := unsafe { C.fgetc(C.stdin) }
	if c == -1 {
		return error('stdin closed')
	}
	return u8(c)
}

fn read_stdin_bytes(n int) []u8 {
	mut buf := []u8{len: n}
	if n > 0 {
		unsafe {
			C.fread(buf.data, 1, usize(n), C.stdin)
		}
	}
	return buf
}

fn send_response(id int, result string) {
	send_raw('{"jsonrpc":"2.0","id":${id},"result":${result}}')
}

fn send_raw(body string) {
	header := 'Content-Length: ${body.len}\r\n\r\n'
	unsafe {
		C.fwrite(header.str, 1, usize(header.len), C.stdout)
		C.fwrite(body.str, 1, usize(body.len), C.stdout)
		C.fflush(C.stdout)
	}
}

// ---------------------------------------------------------------------------
// diagnostics

fn publish_diagnostics(uri string, text string) {
	diags := collect_diagnostics(text)
	send_raw('{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"${json_escape(uri)}","diagnostics":[${diags}]}}')
}

// collect_diagnostics runs the compiler over `text` and renders the first
// error as an LSP diagnostic. Returns the diagnostics array body (or empty).
fn collect_diagnostics(text string) string {
	_ = compiler.compile(text) or {
		mut line, mut col := extract_pos(err.msg())
		if line < 1 {
			line = 1
		}
		start_line := line - 1
		msg := json_escape(err.msg())
		return '{"range":{"start":{"line":${start_line},"character":${col}},"end":{"line":${start_line},"character":${col + 1}}},"severity":1,"source":"vr","message":"${msg}"}'
	}
	return ''
}

// extract_pos pulls "line N[, col M]" out of a compiler error message.
// The toolchain's errors are formatted as `... at line 12, col 5`,
// `... at line 12` or `... (line 12)`.
fn extract_pos(msg string) (int, int) {
	mut line := 0
	mut col := 0
	if start := msg.index('line ') {
		mut i := start + 5
		mut num := ''
		for i < msg.len && msg[i] >= `0` && msg[i] <= `9` {
			num += msg[i].ascii_str()
			i++
		}
		if num.len > 0 {
			line = num.int()
		}
		if c := msg.index('col ') {
			mut j := c + 4
			mut cnum := ''
			for j < msg.len && msg[j] >= `0` && msg[j] <= `9` {
				cnum += msg[j].ascii_str()
				j++
			}
			if cnum.len > 0 {
				col = cnum.int()
			}
		}
	}
	return line, col
}

// ---------------------------------------------------------------------------
// symbols (definition + hover)

// symbol_at resolves the identifier under the cursor and returns its kind and
// definition line, looking in the current document and then in imported
// stdlib modules.
fn symbol_at(uri string, docs map[string]string, pos LspPosition) (string, int, string) {
	text := docs[uri] or { return '', 0, '' }
	word := word_at(text, pos)
	if word.len == 0 {
		return '', 0, ''
	}
	line, kind, ok := find_symbol(text, word)
	if ok {
		return uri, line, kind
	}
	// module call: the cursor may sit on the module part ("os" in "os.exists")
	// or the function part ("exists"). Look up imported modules either way.
	mut mod_name := ''
	mut fn_name := word
	if word.contains('.') {
		parts := word.split('.')
		if parts.len == 2 {
			mod_name = parts[0]
			fn_name = parts[1]
		}
	} else {
		// cursor on the module part: extend to the dotted name
		if pos.character > 0 && pos.character < text.len {
			if e := word_at_ext(text, pos) {
				parts := e.split('.')
				if parts.len == 2 && parts[0] == word {
					mod_name = parts[0]
					fn_name = parts[1]
				}
			}
		}
	}
	if mod_name.len > 0 {
		if path := compiler.resolve_import(mod_name) {
			src := os.read_file(path) or { return '', 0, '' }
			l2, k2, ok2 := find_symbol(src, fn_name)
			if ok2 {
				return 'file://${path}', l2, k2
			}
		}
	}
	// bare function name: search every module this file imports
	for m in imported_modules(text) {
		if path := compiler.resolve_import(m) {
			src := os.read_file(path) or { continue }
			l2, k2, ok2 := find_symbol(src, word)
			if ok2 {
				return 'file://${path}', l2, k2
			}
		}
	}
	return '', 0, ''
}

// word_at_ext returns the dotted identifier starting at `pos` when the cursor
// is on the module part of a call like os.exists (word_at alone would stop
// at the dot).
fn word_at_ext(text string, pos LspPosition) ?string {
	mut line_i := 0
	for l in text.split('\n') {
		if line_i == pos.line {
			if pos.character < 0 || pos.character > l.len {
				return none
			}
			// scan back to the start of the dotted identifier
			mut start := pos.character
			for start > 0 && (is_ident_char(l[start - 1]) || l[start - 1] == `.`) {
				start--
			}
			mut end := pos.character
			for end < l.len && (is_ident_char(l[end]) || l[end] == `.`) {
				end++
			}
			if start == end {
				return none
			}
			return l[start..end]
		}
		line_i++
	}
	return none
}

// imported_modules returns the bare module names (`import os`) in a file.
fn imported_modules(text string) []string {
	toks := compiler.tokenize(text) or { return []string{} }
	prog := compiler.parse(toks) or { return []string{} }
	mut out := []string{}
	for imp in prog.imports {
		if imp.name.len > 0 {
			out << imp.name
		}
	}
	return out
}

fn definition_at(uri string, docs map[string]string, pos LspPosition) string {
	loc_uri, line, _ := symbol_at(uri, docs, pos)
	if loc_uri.len == 0 {
		return 'null'
	}
	return location_json(loc_uri, line)
}

fn hover_at(uri string, docs map[string]string, pos LspPosition) string {
	_, line, kind := symbol_at(uri, docs, pos)
	if line == 0 {
		return 'null'
	}
	return '{"contents":{"kind":"markdown","value":"**${kind}** at line ${line}"}}'
}

fn location_json(uri string, line int) string {
	// 1-based source line → 0-based LSP position; character 0 (we only track lines)
	return '{"uri":"${json_escape(uri)}","range":{"start":{"line":${line - 1},"character":0},"end":{"line":${line - 1},"character":0}}}'
}

// word_at returns the identifier covering the given position in `text`.
fn word_at(text string, pos LspPosition) string {
	mut line_i := 0
	for l in text.split('\n') {
		if line_i == pos.line {
			if pos.character < 0 || pos.character > l.len {
				return ''
			}
			mut start := pos.character
			mut end := pos.character
			for start > 0 && is_ident_char(l[start - 1]) {
				start--
			}
			for end < l.len && is_ident_char(l[end]) {
				end++
			}
			if start == end {
				return ''
			}
			return l[start..end]
		}
		line_i++
	}
	return ''
}

fn is_ident_char(c u8) bool {
	lo := c >= `a` && c <= `z`
	hi := c >= `A` && c <= `Z`
	dig := c >= `0` && c <= `9`
	return lo || hi || dig || c == `_`
}

// find_symbol parses VuurRaaf source and locates the definition line and kind
// of a named symbol (functions, structs, enums, constants, locals, params).
fn find_symbol(src string, name string) (int, string, bool) {
	toks := compiler.tokenize(src) or { return 0, '', false }
	prog := compiler.parse(toks) or { return 0, '', false }
	mut line := 0
	mut kind := ''
	for fd in prog.fns {
		if fd.name == name {
			return fd.line, 'function', true
		}
		for p in fd.params {
			if p == name {
				line = fd.line
				kind = 'parameter'
			}
		}
	}
	for sd in prog.structs {
		if sd.name == name {
			return sd.line, 'struct', true
		}
	}
	for ed in prog.enums {
		if ed.name == name {
			return ed.line, 'enum', true
		}
	}
	for cd in prog.consts {
		if cd.name == name {
			return cd.line, 'constant', true
		}
	}
	for fd in prog.fns {
		for st in fd.body {
			l, k, ok := find_symbol_stmt(st, name)
			if ok {
				line = l
				kind = k
			}
		}
	}
	if line > 0 {
		return line, kind, true
	}
	return 0, '', false
}

fn find_symbol_stmt(st compiler.Stmt, name string) (int, string, bool) {
	match st.kind {
		.let_stmt {
			if st.target == name {
				return st.line, 'variable', true
			}
		}
		.destruct_stmt {
			for t in st.destruct_targets {
				if t == name {
					return st.line, 'variable', true
				}
			}
		}
		.for_range_stmt, .for_in_stmt {
			if st.target == name {
				return st.line, 'loop variable', true
			}
			if st.idx_target == name {
				return st.line, 'loop variable', true
			}
		}
		.try_stmt {
			if st.target == name {
				return st.line, 'catch variable', true
			}
		}
		else {}
	}
	// recurse into nested statements so inner blocks are covered too
	for s in st.body {
		l, k, ok := find_symbol_stmt(s, name)
		if ok {
			return l, k, true
		}
	}
	for s in st.els {
		l, k, ok := find_symbol_stmt(s, name)
		if ok {
			return l, k, true
		}
	}
	for s in st.els_body {
		l, k, ok := find_symbol_stmt(s, name)
		if ok {
			return l, k, true
		}
	}
	for arm in st.arms {
		for s in arm.body {
			l, k, ok := find_symbol_stmt(s, name)
			if ok {
				return l, k, true
			}
		}
	}
	return 0, '', false
}

// ---------------------------------------------------------------------------
// helpers

fn json_escape(s string) string {
	mut out := ''
	for c in s {
		match c {
			`"` {
				out += '\\"'
			}
			`\\` {
				out += '\\\\'
			}
			`\n` {
				out += '\\n'
			}
			`\r` {
				out += '\\r'
			}
			`\t` {
				out += '\\t'
			}
			else {
				out += c.ascii_str()
			}
		}
	}
	return out
}
