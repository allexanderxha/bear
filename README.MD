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
vr clean                                    remove .vobj/.vbin artifacts
vr up                                       rebuild bin/vr
vr symlink                                  link bin/vr into your PATH
vr config [set <key> <value>]               toolchain config (outdir, verbose)
vr info | loader | alloc | version | help
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

## The VuurRaaf language

A small, V-flavored language. Everything is a 64-bit integer or a string
(strings concatenate with `+` and compare with `==`/`!=`; `print`/`println`
accept both).

```
fn greet(name) {
    println("hello, " + name + "!")
}

fn fib(n) {
    if n < 2 {
        return n
    }
    return fib(n - 1) + fib(n - 2)
}

fn main() {
    let x = 6 * 7                       // let with type inference
    assert x == 42                       // checked by the vm at runtime
    let big = x > 40 and x < 50          // and / or / not, short-circuiting
    if big {
        println("x is big")
    } else {
        println("x is small")
    }
    let i = 0
    while i < 3 {
        println("counting " + i)         // "counting 0", ...
        i = i + 1
    }
    println(fib(10))                     // 55
}
```

- functions: `fn name(a, b) { ... }` with `return expr`
- variables: `let name = expr`, reassignment `name = expr`
- operators: `+ - * / %`, `== != < <= > >=`, `and or not`, unary `-`
- statements: `let`, assignment, `if/else`, `while`, `return`, `assert`, calls,
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
enter`.

## Formats

- **VROBJ** (`.vobj`) — linker input: bytecode, exported symbols (function
  name -> code offset), string constants, and relocations (call sites and
  string references).
- **VRBIN** (`.vbin`) — the executable: function table, string table, bytecode.

## Architecture

| module       | role                                                        |
|--------------|-------------------------------------------------------------|
| `compiler/`  | lexer, recursive-descent parser, bytecode codegen (VROBJ)   |
| `assembler/` | `.vasm` -> VROBJ                                            |
| `linker/`    | resolves relocations, rebases strings, emits VRBIN          |
| `vm/`        | stack VM: tagged values, call frames, string heap, tracing  |
| `obj/`       | VROBJ/VRBIN binary formats                                  |
| `bin/`       | small standalone tools: `tl_alloc.v`, `tl_loader.v`         |

The VM is a stack machine with 64-bit tagged values (numbers are stored
shifted left so no integer collides with a string handle). Calls push a frame
(return address, base pointer, argc), copy arguments into local slots, and
reserve extra locals with `enter n`. `vr debug` prints every instruction with
the stack contents.

## Repository layout

```
main.v               CLI entry point (vr <command> ...)
v.mod                module definition
compiler/ assembler/ linker/ vm/ obj/   the toolchain itself
bin/                 built binary + standalone tools
examples/            runnable examples (hello, lib, asm, tests, fib)
```
