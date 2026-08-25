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
vr debug <file.vr|file.vbin>                run with an instruction trace
vr test <file.vr>                           run every test_* function
vr bench <file.vr> [iterations]             benchmark main()
vr make [target] [args...]                  run build.vrmm (target = main)
vr make -f <file.vrmm> [target] [args...]   run another build module
vr build [target] [args...]                 alias for make
vr clean                                    remove .vobj/.vbin artifacts
vr up                                       rebuild bin/vr
vr symlink                                  link bin/vr into your PATH
vr config [set <key> <value>]               toolchain config (outdir, verbose)
vr repl                                     interactive session
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
```

Quick start:

```bash
./bin/vr run examples/hello.vr        # run a program
./bin/vr test examples/tests.vr       # run the tests (one fails on purpose)
./bin/vr debug examples/hello.vr      # watch every bytecode instruction

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
  `let f = fn(x) { return x * 2 }` stored in variables and arrays
- generics: `fn first[T](arr) { return arr[0] }` with checked call sites
  `first[int](arr)` — the VM is dynamically typed, so type parameters erase
  to a single function but arity and duplicates are validated
- variables: `let name = expr`, reassignment `name = expr`
- floats: `3.14`, `0.5`, `1e3` — float literals and `float(x)`; arithmetic
  promotes to float; `floor` / `ceil` / `round` / `sqrt` / `pow` / `abs` /
  `min` / `max` / `rand` / `rand_int`
- strings are UTF-8: `len(s)` counts characters, `s[i]` and `s[a..b]` index
  and slice by character (runes), and methods like `s.to_upper()`,
  `s.contains(x)`, `s.split(d)`, `s.index_of(x)`, `s.to_int()`, `s.len()`
  work on any string-valued expression
- arrays: `[e1, e2, ...]`, indexing `a[i]` (read and write), `len(a)`,
  `push/insert/remove/pop/sort/reverse/clone/index_of/join`; array literals
  may nest
- error handling: `try { ... } catch e { ... }` and `throw "message"` — the
  runtime unwinds to the nearest catch
- bitwise operators: `& | ^ ~ << >>`
- host builtins: `read_file` / `write_file`, `args()`, `getenv` / `setenv`,
  `exit`, `sleep`, `time()`, `type(x)`, `str(x)`, `int(x)`, `split` / `join`
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
- `break` / `continue` inside `while` and `for` loops (in `for` loops
  `continue` advances the loop variable / iterator first)
- else-if chains: `if a { } else if b { } else { }`
- `match`: `match expr { v1 { } v2 { } else { } }` — arms test equality on
  any comparable value (ints, strings, ...); the `else` arm is optional
- structs: literals `{ name: value, ... }` (may nest and may be empty `{}`),
  field access `a.b` and assignment `a.b = v` (chained: `a[i].b`, `a.b[i]`);
  structs are mutable references (identity `==`/`!=`), and setting a missing
  field adds it, so records can be built incrementally
- enums: `enum Color { red green blue }` with `Color.red`, `e.to_string()`,
  `e.count()`, and iteration in `for`
- constants: `const NAME = 42` (compile-time integer/bool values)
- operators: `+ - * / %`, `== != < <= > >=`, `and or not`, `& | ^ ~ << >>`,
  unary `-`; constant expressions fold at compile time
- statements: `let`, assignment, `if/else`, `match`, `while`, `for`,
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
| `vm/`        | stack VM: tagged values, call frames, string/array heaps    |
| `obj/`       | VROBJ/VRBIN binary formats                                  |
| `bin/`       | small standalone tools: `tl_alloc.v`, `tl_loader.v`         |

The VM is a stack machine with 64-bit tagged values using three tag bits:
ints, string/array/struct/float/closure handles — so no integer ever
collides with a heap handle. A mark-and-sweep garbage collector runs between
opcodes when the heap grows past a threshold, tracing the stack (which holds
every frame's locals) and compacting the pools; string constants baked into
bytecode are never collected. Bytecode carries a line table, so runtime
errors report the source line. A conservative compile-time type checker
(`compiler/check.v`) rejects provably wrong programs (unknown variables,
field access on numbers, arithmetic on strings, wrong arity) while leaving
dynamic programs alone. `vr debug` prints every instruction with the stack
contents (arrays rendered as `[1, 2, ...]`).

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
