# vuurraaf/v

A complete toolchain for **VuurRaaf**, written in V from scratch: a compiler,
an assembler, a linker, and a stack-based runtime. Everything — including the
object file format and the virtual machine — lives in this repository.

```
.vr  --compiler-->  .vobj  --linker-->  .vbin  --vm-->  output
.vasm --assembler--> .vobj
```

## Build

Requires [V](https://vlang.io) (`v` in your PATH).

```bash
v -o bin/vr .        # build the toolchain
./bin/vr up          # or rebuild from inside the toolchain
./bin/vr symlink     # optionally symlink bin/vr into your PATH
```

> Note: build with `v .` from the project root. Building via an explicit file
> or path argument makes V pick tcc without the Boehm GC, a combination that
> miscompiles this codebase (`vr up` already does the right thing).

## Usage

```
vr compile <file.vr> [-o out.vobj]          source  -> object
vr assemble <file.vasm> [-o out.vobj]       assembly -> object
vr link <a.vobj> [more.vobj ...] [-o out]   objects -> executable (.vbin)
vr run <file.vr|file.vbin>                  compile+link+run, or run a binary
vr debug <file.vr|file.vbin>                interactive debugger (breakpoints, step, locals)
vr profile <file.vr|file.vbin>              run and report per-function instruction counts
vr fuzz [--seed N] [--iters N]              fuzz the compiler and VM for crashes/hangs
vr test <file.vr|dir>                       run every test_* function
vr bench <file.vr> [iterations]             benchmark main()
vr make [target] [args...]                  run build.vrmm (target = main)
vr make -f <file.vrmm> [target] [args...]   run another build module
vr build [target] [args...]                 alias for make
vr clean                                    remove .vobj/.vbin artifacts
vr up                                       rebuild bin/vr
vr symlink                                  link bin/vr into your PATH
vr config [set <key> <value>]               toolchain config (outdir, verbose)
vr repl                                     interactive session
vr lsp                                      language server (JSON-RPC over stdio)
vr fmt [-w] <file.vr>                       format source (keeps comments)
vr init [name]                              scaffold a project (vr.mod + main.vr)
vr get <owner/repo | git-url | ./path>      fetch a package into vendor/
vr install                                  install dependencies from vr.mod
vr list                                     show the project manifest
vr info | loader | alloc | version | help
```

```bash
./bin/vr repl          # try expressions and functions interactively
./bin/vr fmt -w f.vr   # normalize a file's indentation/spacing in place
./bin/vr init myproj   # start a project; vr get owner/repo fetches packages
./bin/vr run -w f.vr   # watch f.vr and rerun on every save
./bin/vr test examples # run every test_* fn in every .vr file under examples/
./bin/vr lsp           # language server for editors (diagnostics, go-to-def)
./bin/vr run --profile f.vr  # hot-function report (instructions + calls)
```

### Debugging

`vr debug` is an interactive debugger. Run to the first breakpoint (or stop at
entry), then inspect state:

```
vr debug f.vr --break 12
== stopped at main (line 12, ip 105) — help: h
(vr-dbg) l            # list locals with values
(vr-dbg) p x          # print one local
(vr-dbg) bt           # backtrace (call chain)
(vr-dbg) n            # next: run to the next line (skips calls)
(vr-dbg) s            # step: one instruction
(vr-dbg) f            # finish: run until the current function returns
(vr-dbg) b 20         # set another breakpoint
(vr-dbg) c            # continue
```

Breakpoints stop at the *start* of a source line, so locals hold the values
from before that line executes. `vr debug --trace f.vr` keeps the old
instruction-by-instruction trace.

### Fuzzing

`vr fuzz` generates random programs, compiles them, and runs each one twice
with an instruction budget — every case in its own subprocess so a crash in
the compiler or VM is isolated and reported instead of killing the run:

```
vr fuzz --seed 42 --iters 500 --save-dir fuzz-repros
fuzz: no bugs found
```

Findings (crashes, hangs via `--max-ops`, nondeterminism) are saved as .vr
repros; a nonzero exit reports bugs for CI.

### Profiling

`vr profile f.vr` (or `vr run --profile f.vr`) counts instructions and calls
per function and prints the hot-function table:

```
function                   calls       instr      %
fib                           25         271  96.8%
main                           0           9   3.2%
total                            280
```

Quick start:

```bash
./bin/vr run examples/hello.vr        # run a program
./bin/vr test examples/tests.vr       # run the tests (one fails on purpose)
./bin/vr debug examples/hello.vr      # interactive debugger (breakpoints, step, locals)

# the assembler path
./bin/vr assemble examples/math.vasm -o math.vobj
./bin/vr link math.vobj -o math.vbin
./bin/vr run math.vbin

# multi-file programs (functions in one file may call functions in another)
./bin/vr compile examples/lib.vr -o lib.vobj
./bin/vr compile examples/use_lib.vr -o use_lib.vobj
./bin/vr link lib.vobj use_lib.vobj -o use_lib.vbin
./bin/vr run use_lib.vbin
```

## Build modules (.vrmm)

A **VuurRaaf Make Module** (`.vrmm`) is build instructions for the toolchain,
written in VuurRaaf itself — the same idea as V's `.vsh` scripts. The toolchain
compiles the module and runs one of its functions (a *target*) with the
`build_*` builtins available, so the script can drive every stage of the
pipeline: compile, assemble, link, run, test, bench, clean, and shell out to
the host.

```
# build.vrmm
fn main() {
    build_compile("main.vr", "main.vobj")
    build_link(["main.vobj"], "main.vbin")
}

fn clean() {
    build_clean()
}
```

```bash
vr make              # runs main() from build.vrmm
vr make clean        # runs the clean() target
vr make deploy --prod  # runs deploy() with args() == ["--prod"]
vr make -f x.vrmm t  # run target t from another module
```

A target that returns a nonzero integer, calls `exit(n)` with `n > 0`, or
`throw`s fails the build. Paths are relative to the working directory;
`build_root()` returns the module's own directory for absolute paths.

### Running build modules as scripts

A `.vrmm` (or `.vr`) file may start with a shebang line so it can be executed
directly like any script — the toolchain skips the shebang when compiling, so
error line numbers stay aligned with the file:

```
#!/usr/bin/env vr
fn main() {
    build_compile("main.vr", "main.vobj")
    build_link(["main.vobj"], "main.vbin")
}
```

```bash
chmod +x build.vrmm
./build.vrmm            # equivalent to: vr make
./build.vrmm clean      # run the clean() target
./build.vrmm deploy --prod
```

The kernel invokes `vr <script> [args...]`; the toolchain routes an existing
`.vrmm` path to `vr make -f <file>` and an existing `.vr` path to
`vr run <file>`, so `vr myprog.vr` also just works.

Build builtins:

| builtin | description |
|---------|-------------|
| `build_compile(src, out)` | source → object (out defaults to `src.vobj`); returns the out path |
| `build_assemble(src, out)` | `.vasm` → object; returns the out path |
| `build_link(objs, out)` | objects → executable; returns the out path |
| `build_run(file)` | compile+link+run a `.vr`, or run a `.vbin`; returns the exit code |
| `build_test(file)` | run every `test_*` function; throws if any fail |
| `build_bench(file, n)` | benchmark `main()` n times |
| `build_clean()` | remove `.vobj`/`.vbin` in the cwd; returns the count |
| `build_exec(cmd)` | run a shell command; returns its output (throws on nonzero exit) |
| `build_exec_status(cmd)` | run a shell command; returns its exit code |
| `build_exists(path)` | 1 if the path exists, else 0 |
| `build_mkdir(path)` | create a directory (and parents) |
| `build_rm(path)` | remove a file or directory tree; returns 1 if something was removed |
| `build_copy(src, dst)` | copy a file or a whole directory tree |
| `build_glob(pattern)` | list files matching a glob (e.g. `"src/*.vr"`) |
| `build_ls(dir)` | list a directory's entries |
| `build_base(path)` / `build_dir(path)` / `build_join(a, b)` | path helpers |
| `build_root()` | absolute directory of the running `.vrmm` |

`vr init` scaffolds a project with a working `build.vrmm`; see
`examples/build.vrmm` for a tour (targets: `main`, `multi`, `test`, `bench`,
`deploy`, `clean`).

## Standard library modules

The toolchain ships a small stdlib in `lib/`, imported by name like in V
(`import os` resolves against `lib/` and `vendor/` from any directory).
Module functions are namespaced: `os.exists()`, `json.encode()`, ...

| module | functions |
| --- | --- |
| `os` | filesystem + process: `exists`, `is_dir`, `is_file`, `mkdir`, `remove`, `copy`, `list_dir`, `glob`, `join`, `base`, `dir`, `read_lines`, `write_lines`, `cwd`, `env`, `exec`, `exec_full` (`{code, stdout, stderr}`), `ext`, `abs`, `rel` |
| `json` | `encode`, `decode`, `pretty` — objects become structs, integral numbers decode as ints, `null` ⇄ `none` |
| `strings` | `length`, `lines`, `split`, `join`, `replace`, `contains`, `starts_with`, `ends_with`, `upper`, `lower`, `trim`, `pad`, `pad_left`, `repeat`, `format`, `capitalize` |
| `math` | `abs`, `min`, `max`, `floor`, `ceil`, `round`, `sqrt`, `pow`, `clamp`, `sign`, `pi` |
| `http` | `get(url)`, `post(url, data)`, `get_text(url)`, `request(method, url, data, headers, timeout_ms)`, `get_with_headers`, `post_with_headers`, `get_timeout`, `post_timeout` — return `{status, body}`; network failures throw (catchable), HTTP errors (404) are normal responses |
| `time` | `now()` (epoch s), `ms()` (epoch ms), `format(t, "YYYY-MM-DD HH:mm:ss")`, `date(t)`, `clock(t)`, `parse("2026-08-25 13:36:45")`, `add_days/add_hours/add_minutes/add_seconds`, `weekday(t)` — Moment-style tokens |
| `regex` | `is_match(pattern, s)`, `find_all(pattern, s)`, `replace(pattern, s, repl)`, `split(pattern, s)` — RE2 syntax; use raw strings `r"\d+"` for patterns |
| `crypto` | `sha256(s)`, `md5(s)`, `base64_encode(s)`, `base64_decode(s)` |
| `cli` | getopt-style flag parsing over `args()`: `flag(name, default)`, `has(name)`, `positional()` — supports `--name value`, `--name=value`, boolean `--flag`, and short aliases `-n=value` |

Examples: `examples/imports.vr`, `examples/http.vr`, `examples/time.vr`, `examples/cli_tool.vr` (CLI flags + interactive input + typed errors), `examples/defer_reflection.vr` (`defer`, `in`, `type_info`, `range`), `examples/stdlib.vr` (tests for the regex/crypto/csv/os/time additions).

## The VuurRaaf language

A small, V-flavored language. Values are 64-bit integers, 64-bit floats,
strings, arrays, structs, enums, and closures (strings concatenate with `+`
and compare with `==`/`!=`; arrays and structs are mutable references that
compare by identity).

```
fn sum(items) {
    let total = 0
    for x in items {            // iterate an array
        total = total + x
    }
    return total
}

fn main() {
    let x = 6 * 7
    assert x == 42
    let big = x > 40 and x < 50 // and / or / not, short-circuiting
    if big {
        println("x is big")
    } else {
        println("x is small")
    }

    let a = [10, 20, 30]
    a[1] = 99                    // index assignment
    push(a, 40)                  // grow in place
    println(a)                   // [10, 99, 30, 40]
    println(len(a))              // 4
    println(sum(a))              // 179

    for i in 0..5 { ... }        // 0 1 2 3 4   (exclusive ..)
    for i in 1...3 { ... }       // 1 2 3       (inclusive ...)

    for i in 0..10 {
        if i == 2 {
            continue             // skip this iteration
        }
        if i == 5 {
            break                // leave the loop early
        }
    }

    let grid = [[1, 2], [3, 4]]  // nested arrays
    println(grid[1][0])          // 3

    let i = 100
    for i in 0..3 { ... }        // loop vars are scoped to the loop
    println(i)                   // 100

    if score >= 90 {             // else-if chains
        grade = "A"
    } else if score >= 80 {
        grade = "B"
    } else {
        grade = "F"
    }

    match day {                  // match on any comparable value
        "sat" {
            println("weekend")
        }
        "sun" {
            println("weekend")
        }
        else {                   // optional fallback arm
            println("workday")
        }
    }

    let pt = { x: 3, y: 4 }      // struct literal: { name: value, ... }
    println(pt.x)                // 3 — field access
    pt.y = 5                     // field assignment
    let p = { name: "amy", addr: { city: "nyc" } }  // nested structs
    println(p.addr.city)         // nyc
}
```

- functions: `fn name(a, b) { ... }` with `return expr`; default parameter
  values `fn f(a, b = 10)`, variadic params `fn f(nums...)`, destructuring
  `let { a, b } = rec` and `let [x, y] = arr`, and anonymous closures
  `let f = fn(x) { return x * 2 }` stored in variables and arrays; a closure
  **captures the enclosing locals it references by value** (nested closures
  included), so `let n = 1; let bump = fn() { n = n + 1; return n }` works —
  writes hit the closure's own copy, the outer variable is untouched
- raw strings: `r"..."` passes text through verbatim (no escape processing),
  ideal for regex patterns like `r"\d+"`
- generics: `fn first[T](arr) { return arr[0] }` with checked call sites
  `first[int](arr)` — the VM is dynamically typed, so type parameters erase
  to a single function but arity and duplicates are validated
- variables: `let name = expr` binds **immutably** (reassignment is a
  compile-time error); declare `mut name = expr` to opt in to reassignment
  `name = expr`. Loop variables, function parameters, and the receiver are
  always reassignable, as are element/field writes (`a[i] = v`, `s.f = v`)
- string builders: `strings.builder()` / `strings.build_add(sb, piece)` /
  `strings.build_str(sb)` (also unqualified `sb_new` / `sb_add` / `sb_str`)
  accumulate many pieces and materialize once — O(n) instead of the O(n²)
  of a long `+` chain
- concurrency: `spawn(fn, args...)` runs the closure on its own OS thread in
  an isolated VM (captured values and args are deep-copied) and returns a job
  id; `spawn_join(id)` blocks until the job finishes and returns its result
  (int/float/string, or a flat array/struct rendered as its string form).
  Jobs run truly in parallel and their failures propagate as catchable errors
- floats: `3.14`, `0.5`, `1e3` — float literals and `float(x)`; arithmetic
  promotes to float; `floor` / `ceil` / `round` / `sqrt` / `pow` / `abs` /
  `min` / `max` / `rand` / `rand_int`
- strings are UTF-8: `len(s)` counts characters, `s[i]` and `s[a..b]` index
  and slice by character (runes), and methods like `s.to_upper()`,
  `s.contains(x)`, `s.split(d)`, `s.index_of(x)`, `s.to_int()`, `s.len()`
  work on any string-valued expression
- maps: structs serve as string-keyed maps with **hash-indexed O(1)** access;
  keys may be computed expressions (`m[key_var] = v`, `m[key_var]`), not just
  literals; `has(m, k)`, `delete(m, k)`, `keys(m)`, `len(m)` all work
- arrays: `[e1, e2, ...]`, indexing `a[i]` (read and write), `len(a)`,
  `push/insert/remove/pop/sort/reverse/clone/index_of/join`; array literals
  may nest; `sort` is a stable merge sort — guaranteed O(n log n)
- error handling: `try { ... } catch e { ... }` and `throw <any value>` — the
  runtime unwinds to the nearest catch. Throwing a struct/int/float/string works
  and the caught value stringifies safely
- `String + <any value>` stringifies the other operand, so `"caught: " + e`,
  `"n=" + count`, and record/array debug messages "just work". Only
  `Array + Array` / `struct + struct` remain errors
- interactive input: `read_line()` reads one line from stdin (empty on EOF),
  and `input(prompt)` shows a prompt on stderr then reads a line — stdout stays
  clean for piping
- flag parsing: `flag_val(name)` / `flag_has(name)` / `flag_positional()` parse
  `args()` getopt-style (`--name value`, `--name=value`, `--verbose`, `-n=value`,
  `--` stops parsing, `-5` is a value not a flag); use `import cli` for the
  namespaced `cli.flag` / `cli.has` / `cli.positional` helpers
- bitwise operators: `& | ^ ~ << >>`
- host builtins: `read_file` / `write_file`, `args()`, `getenv` / `setenv`,
  `exit`, `sleep`, `time()`, `type(x)`, `str(x)`, `int(x)`, `split` / `join`
- HTTP: `http_get(url)` / `http_post(url, data)` return `{status, body}`
  structs and throw on network failure (catchable) — or use `import http`
- date/time: `now()` (epoch s), `time_ms()`, `format_time(t, "YYYY-MM-DD")`,
  `parse_time(s)` (ISO timestamps) — or use `import time`
- JSON: `json_encode(x)` / `json_decode(s)` — objects become structs, arrays
  become arrays, integral numbers decode as ints, `null` decodes to `none`
- `none`: a literal for "no value" (JSON null); `x == none` compares,
  and it renders as `none` / encodes as `null`
- string formatting: `format(x, "%.2f")` (printf-style: `%d %i %f %s %x %X`,
  width, `-`/`0` flags, precision), `replace`, `split_lines`, `pad` /
  `pad_left`, `repeat` — all also available as string methods (`s.replace()`,
  `s.pad(4)`, ...)
- native builtin errors (failed `read_file`, `json_decode`, ...) are caught by
  `try { } catch e { }` like explicit `throw`s
- for loops: `for x in arr { }` and ranges `for i in 0..10 { }` /
  `for i in 0...10 { }`; loop variables are scoped to the loop body
- `defer <stmt>` runs the statement when the function exits (LIFO, on every
  return path), so file/resource cleanup reads naturally: `defer remove(tmp)`
- `x in col` membership operator works on arrays (`2 in [1,2,3]`), maps
  (`"key" in m`), and strings (`"sub" in s`), and with `not` (`not (x in a)`)
- `type_info(v)` reflects any value into a `{kind, is_number, is_int, is_float,
  is_string, is_array, is_struct, is_none, is_closure, len, fields, contents}`
  struct for duck-typing and generic utilities
- `range(a, b)` builds `[a, a+1, ..., b)` (descends when `a > b`) as an array
- reflection: `type(x)` returns "int"/"float"/"string"/"array"/"struct"/
  "none"/"closure"; `keys(m)`, `has(m, k)`, `len(m)` inspect records
- `break` / `continue` inside `while` and `for` loops (in `for` loops
  `continue` advances the loop variable / iterator first)
- else-if chains: `if a { } else if b { } else { }`
- `match`: `match expr { v1 { } v2 { } else { } }` — arms test equality on
  any comparable value (ints, strings, ...); the `else` arm is optional
- structs: literals `{ name: value, ... }` (may nest and may be empty `{}`),
  field access `a.b` and assignment `a.b = v` (chained: `a[i].b`, `a.b[i]`);
  structs are mutable references (identity `==`/`!=`), and setting a missing
  field adds it, so records can be built incrementally
- declared struct field types:
  `struct Point { x int, y int, tag ?string, next Point }` — fields may declare
  a type (`int`, `float`, `string`, `bool`, `array`, another struct, or an
  enum); a leading `?` also accepts `none`. The checker validates struct
  literals and field reads/writes against the declaration: unknown fields and
  mistyped values are compile-time errors. Untyped fields stay fully dynamic,
  and ints widen to `float` fields
- enums: `enum Color { red green blue }` with `Color.red`, `e.to_string()`,
  `e.count()`, and iteration in `for`
- constants: `const NAME = 42` (compile-time integer/bool values)
- operators: `+ - * / %`, `== != < <= > >=`, `and or not`, `& | ^ ~ << >>`,
  unary `-`; constant expressions fold at compile time
- statements: `let`/`mut`, assignment, `if/else`, `match`, `while`, `for`,
  `break`, `continue`, `return`, `assert`, `try/catch`/`throw`, calls,
  `print(...)` / `println(...)`
- comments: `//`

## Assembly

`.vasm` files talk to the VM directly. Labels, `.global` exports, and the full
opcode set:

```
; comment
.global main
main:
    push_int 42
    call helper 1        ; call <target> <argc>
    println
    halt

.global helper
helper:
    enter 0              ; reserve extra locals (args were copied in by `call`)
    load 0
    retv
```

Opcodes: `halt push_int push_str load store pop dup add sub mul div mod neg
eq ne lt le gt ge and or not jmp jz jnz call ret retv print println assert
enter mkarray aget aset alen apush mkstruct sget sset`.

Struct opcodes: `mkstruct n` pops `n` (name, value) pairs and pushes a struct
handle; `sget "field"` / `sset "field"` read/write a named field (pushing the
field name as a string first, exactly like the compiler does).

## Formats

- **VROBJ** (`.vobj`) — linker input: bytecode, exported symbols (function
  name -> code offset), string constants, and relocations (call sites and
  string references).
- **VRBIN** (`.vbin`) — the executable: function table, string table, bytecode.

## Architecture

| module       | role                                                        |
|--------------|-------------------------------------------------------------|
| `compiler/`  | lexer, parser, type checker, bytecode codegen (VROBJ)      |
| `assembler/` | `.vasm` -> VROBJ                                            |
| `linker/`    | resolves relocations, rebases strings, emits VRBIN          |
| `vm/`        | stack VM: tagged values, call frames, string/array heaps, hash-indexed structs, GC-traced closure captures |
| `obj/`       | VROBJ/VRBIN binary formats                                  |
| `bin/`       | small standalone tools: `tl_alloc.v`, `tl_loader.v`         |

The VM is a stack machine with 64-bit tagged values using three tag bits:
ints, string/array/struct/float/closure handles — so no integer ever
collides with a heap handle. A mark-and-sweep garbage collector runs between
opcodes when the heap grows past a threshold, tracing the stack (which holds
every frame's locals) and compacting the pools; string constants baked into
bytecode are never collected. Structs carry a hash index, so map-style field
access is O(1); closure captures live inside the closure and are traced and
remapped by the GC like any other heap value. Bytecode carries a line table,
so runtime errors report the source line **and a full call-stack trace**
(`fn` → line for every frame). A conservative compile-time type checker
(`compiler/check.v`) rejects provably wrong programs (unknown variables,
field access on numbers, arithmetic on strings, wrong arity) while leaving
dynamic programs alone. `vr debug` prints every instruction with the stack
contents (arrays rendered as `[1, 2, ...]`).

## Editor support

`vr lsp` speaks LSP over stdio, so any LSP-capable editor gets diagnostics
(the compiler's errors, positioned at the right line), go-to-definition
(functions, structs, enums, constants, locals, and stdlib module functions),
and hover (symbol kind + line). The `extension/` folder contains a VS Code
client (`code --install-extension extension/` after `npm install` in
`extension/`) with syntax highlighting for `.vr` / `.vrmm` source and
`.vasm` assembly (labels, `.global` directives, and mnemonics; the
assembly language gets highlighting only — no language server), or point
any other LSP client at `vr lsp`.

## Releases

Tagging `vX.Y.Z` (matching `v.mod`) builds `vr` for Linux, macOS and
Windows and attaches them to a GitHub Release.

## Repository layout

```
main.v               CLI entry point (vr <command> ...)
repl.v               interactive REPL
fmt.v                source formatter
pkg.v                package manager (init/get/install/list)
vm/native.v          host builtins incl. the build_* (.vrmm) builtins
v.mod                module definition
compiler/ assembler/ linker/ vm/ obj/   the toolchain itself
bin/                 built binary + standalone tools
examples/            runnable examples (hello, lib, asm, tests, fib, json)
```
