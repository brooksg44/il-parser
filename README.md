# IEC 61131-3 IL Parser

A Common Lisp lexer, parser, and validator for IEC 61131-3 Instruction List (IL) programs.

## Features

- Strips `//`, `;`, and `(* *)` comments (including multi-line block comments)
- Builds a structured AST of CLOS objects with decomposed operands
- Classifies operands as IEC addresses (`I0.0`, `MW10`), numeric/boolean literals, or raw symbols
- Signals `il-parse-error` on bad input with `skip-statement` and `use-nop` restarts for recovery
- Validates basic IEC 61131-3 semantic rules (CALL operands, arithmetic arity)

## Dependencies

- [Alexandria](https://github.com/sharplispers/alexandria)
- [cl-ppcre](https://github.com/edicl/cl-ppcre)

## Installation

### Via ASDF (preferred)

Symlink or copy this directory into your ASDF source registry:

```sh
ln -s /path/to/il-parser ~/quicklisp/local-projects/il-parser
```

Then load:

```lisp
(asdf:load-system "il-parser")
```

### Manual

```lisp
(ql:quickload '(:alexandria :cl-ppcre))
(load "il-parser.lisp")
```

## Usage

```lisp
(in-package :iec-il-parser)

(defparameter *program*
  "START:
   LD   I0.0
   ANDN I0.1
   ST   Q0.0
   RET")

(defparameter *ast* (parse-il *program*))
(dump-il *ast*)
(format t "Errors: ~A~%" (validate-iec-syntax *ast*))
```

Output:

```
;; IEC 61131-3 IL AST (4 statements)
;; START:
   LD I0.0
   ANDN I0.1
   ST Q0.0
   RET
Errors: NIL
```

Call `(demo)` to parse and display a built-in motor latch example.

## API

| Function | Description |
|---|---|
| `(parse-il source)` | Parse an IL string into a list of `il-statement` objects |
| `(dump-il statements)` | Print the AST to stdout |
| `(validate-iec-syntax statements)` | Return a list of semantic error strings, or `NIL` |
| `(demo)` | Parse and display the built-in sample program |

### `il-statement`

| Accessor | Type | Description |
|---|---|---|
| `il-statement-label` | `(or null string)` | Optional label name (without colon) |
| `il-statement-opcode` | keyword symbol | Uppercase opcode, e.g. `:LD`, `:ANDN` |
| `il-statement-operands` | list of `il-operand` | Zero or more structured operand objects |

### Operand classes

Operands are CLOS objects. Use `typep` to dispatch on subtype.

| Class | Slots | Description |
|---|---|---|
| `il-operand` | `operand-raw` | Base class; used for variable/FB names |
| `il-address` | `operand-area`, `operand-size`, `operand-byte-index`, `operand-bit-index` | IEC address (`I0.0`, `MW10`, `QD4`) |
| `il-literal` | `operand-value` | Numeric (`42`, `3.14`) or boolean (`TRUE`/`FALSE`) |

`operand-area` is `:input`, `:output`, or `:memory`. `operand-size` is `:bit`, `:byte`, `:word`, `:dword`, or `:lword`.

### Error handling

`parse-il` signals `il-parse-error` when an opcode is expected but not found. Two restarts are available:

| Restart | Effect |
|---|---|
| `skip-statement` | Discard tokens until the next opcode or label; return `NIL` for this statement |
| `use-nop` | Insert a `:NOP` instruction in place of the missing opcode |

```lisp
(handler-bind ((il-parse-error
                (lambda (c)
                  (declare (ignore c))
                  (invoke-restart 'skip-statement))))
  (parse-il "LD I0.0\nbad-token\nST Q0.0"))
```

## Label Syntax

Labels use a trailing-colon format per IEC 61131-3:

```
START:
LD I0.0
```

## Supported Opcodes

Load/Store, Boolean (`AND`, `OR`, `XOR`, `NOT` — with `N` variants like `ANDN`), Arithmetic (`ADD`, `SUB`, `MUL`, `DIV`),
Comparison (`EQ`, `GT`, `GE`, `LT`, `LE`, `NE`), Flow control (`JMP`, `JMPN`, `CALL`, `RET`, `CAL`),
Timers (`TON`, `TOF`, `TP`), Counters (`CTU`, `CTD`), Math (`SIN`, `COS`, `SQRT`, `ABS`, …),
Bitwise (`SHL`, `SHR`, `ROL`, `ROR`, `BIT_AND`, …), and more.

## Running the Tests

The 14-test suite is in `Run-Tests.md` as a single `sbcl` shell command covering parsing, operand decomposition, comment stripping, error recovery, and reentrancy.
