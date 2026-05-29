# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Loading and Running

### Via ASDF (preferred)

```lisp
(asdf:load-system "il-parser")
```

Requires the directory to be on `asdf:*central-registry*` or symlinked into `~/quicklisp/local-projects/`.

### Manual

```lisp
(ql:quickload '(:alexandria :cl-ppcre))
(load "il-parser.lisp")
```

`il-parser.lisp` does **not** self-execute on load. Call `(iec-il-parser:demo)` to run the sample motor latch program.

### Running the test suite

The full 14-test suite is in `Run-Tests.md` as a single `sbcl` shell command. Copy and run it directly:

```sh
sbcl --noinform --no-userinit --non-interactive \
  --eval '(require "asdf")' \
  --eval '(load "/Users/brooksg44/quicklisp/setup.lisp")' \
  --eval '(push #p"/Users/brooksg44/common-lisp/il-parser/" asdf:*central-registry*)' \
  --eval '(asdf:load-system "il-parser")' \
  ...  # (see Run-Tests.md for full command)
```

To use the parser interactively:

```lisp
(in-package :iec-il-parser)
(parse-il "LD I0.0\nAND I0.1\nST Q0.0")
```

## Architecture

The pipeline is: source string → `strip-comments` → `lex` → token list → `parse-il` → `il-statement` list.

**Comment stripper** (`strip-comments`, lines 60–96): Character-by-character pass that handles `//` line comments, `;` line comments, and `(* ... *)` block comments (including multi-line). Preserves newlines for line structure. Called by `lex` before tokenization.

**Lexer** (`lex`, lines 159–182): Processes the cleaned source line by line. Splits on whitespace and commas. Each token is classified as `:label` (trailing-colon syntax, e.g. `START:`), `:opcode` (looked up via `find-symbol` into the `:keyword` package, then checked against `*il-opcodes*`), or `:operand`. Opcode lookup is `eq`-based on interned keyword symbols (`:LD`, `:AND`, etc.) — no string comparison. Returns a flat list of `(type . value)` cons cells terminated by `(:eof . nil)`.

**Parser** (`parse-il`, lines 187–225): Closure-based token stream — `peek` and `advance` are `flet`s over a local `tokens` binding. `parse-il` is re-entrant and thread-safe. `parse-statement` consumes one optional `:label`, one required `:opcode`, and zero or more `:operand` tokens. On a missing opcode it signals `il-parse-error` with two restarts: `skip-statement` (discard tokens until the next opcode/label/eof) and `use-nop` (insert `:NOP`).

**AST nodes** (CLOS, lines 40–55): Three classes form a hierarchy:
- `il-statement` — `label` (`(or null string)`), `opcode` (keyword symbol, e.g. `:LD`), `operands` (list of `il-operand` objects)
- `il-address` extends `il-operand` — `area` (`:input`/`:output`/`:memory`), `size` (`:bit`/`:byte`/`:word`/`:dword`/`:lword`), `byte-index`, `bit-index`
- `il-literal` extends `il-operand` — `value` (integer, float, or boolean)
- `il-operand` (base) — `raw` (original string); used for unrecognized tokens like variable/FB names

**Operand parser** (`parse-operand`, lines 123–154): Classifies each raw operand string via regex into `il-address` (IEC address pattern `[IQM][XBWDL]?N[.N]?`), `il-literal` (numeric or `TRUE`/`FALSE`), or bare `il-operand`.

**Utilities**: `dump-il` pretty-prints the AST; `validate-iec-syntax` returns a list of semantic error strings or `NIL`.

## Key Constraints

- `*il-opcodes*` uses `make-hash-table :test #'eq` with keyword symbol keys (`:LD`, `:AND`, …). The lexer interns each uppercased token via `find-symbol` into `:keyword` before the lookup — this is why the hash table uses `eq` not `equal`.
- `il-statement-opcode` holds a keyword symbol (`:LD`), not a string. Use `symbol-name` to get `"LD"`.
- `operand-raw` is always available on any `il-operand` subclass. Use `typep` to dispatch to `il-address` or `il-literal` before accessing their slots.
- Unlike the old version, `parse-il` is re-entrant — the token stream lives in a closure local to each call.
- `il-parser-copy.lisp` is the pre-rewrite version (defstruct AST, global `*tok-stream*`, string-keyed `alist-hash-table`). It is kept for reference only; the canonical implementation is `il-parser.lisp`.
