# IEC 61131-3 IL Parser

A Common Lisp lexer, parser, and validator for IEC 61131-3 Instruction List (IL) programs.

## Features

- Tokenizes IL source into labeled opcodes and operands
- Strips `//`, `;`, and `(* *)` comments
- Builds a structured AST of `il-statement` nodes
- Validates basic IEC 61131-3 semantic rules (CALL operands, arithmetic arity)

## Dependencies

- [Alexandria](https://github.com/sharplispers/alexandria)
- [cl-ppcre](https://github.com/edicl/cl-ppcre)

## Installation

### Via ASDF

Symlink or copy this directory into your ASDF source registry (e.g. `~/quicklisp/local-projects/`):

```sh
ln -s /path/to/il-parser ~/quicklisp/local-projects/il-parser
```

Then load:

```lisp
(asdf:load-system "il-parser")
```

### Manual

Load dependencies via Quicklisp first, then load the file directly:

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

### Output

```
;; IEC 61131-3 IL AST (4 statements)
;; START:
   LD I0.0
   ANDN I0.1
   ST Q0.0
   RET
Errors: NIL
```

## API

| Function | Description |
|---|---|
| `(parse-il source)` | Parse an IL string into a list of `il-statement` structs |
| `(dump-il statements)` | Print the AST to stdout |
| `(validate-iec-syntax statements)` | Return a list of semantic error strings, or `NIL` |

### `il-statement` struct

| Accessor | Type | Description |
|---|---|---|
| `il-statement-label` | `(or null string)` | Optional label name (without colon) |
| `il-statement-opcode` | `string` | Uppercase opcode |
| `il-statement-operands` | `list` | Zero or more operand strings |

## Label Syntax

Labels follow the standard IEC 61131-3 trailing-colon format:

```
START_LATCH:
LD I0.0
```

## Supported Opcodes

Load/Store, Boolean (`AND`, `OR`, `XOR`, `NOT`), Arithmetic (`ADD`, `SUB`, `MUL`, `DIV`),
Comparison (`EQ`, `GT`, `GE`, `LT`, `LE`, `NE`), Flow control (`JMP`, `CALL`, `RET`, `CAL`),
Timers (`TON`, `TOF`, `TP`), Counters (`CTU`, `CTD`), Math (`SIN`, `COS`, `SQRT`, `ABS`, …),
Bitwise (`SHL`, `SHR`, `ROL`, `ROR`, `BIT_AND`, …), and more.
