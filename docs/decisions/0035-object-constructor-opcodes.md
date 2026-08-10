# Object and array constructor opcodes

## Decision

The source parser retains array and object constructors as syntax nodes. The
compiler lowers them to `program.Opcode.Array` and `program.Opcode.Object`,
appended after the existing opcode discriminants so previously serialized
programs retain their meaning. Array instructions carry child filter operands;
object instructions alternate source-owned key text and child value operands.

Object entries remain parser-only links and are not emitted as constructor
operands. Their key span is copied into the owned program text area during
lowering. Runtime collection semantics (including collecting generator output
for array values and evaluating dynamic object keys) remain an evaluator lane;
until that lane lands, the evaluator reports `Unsupported_Opcode` for these
instructions rather than fabricating a value.

## Ownership and compatibility

The parser owns source spans and entry links until destruction. The compiled
program owns copied key bytes and operand metadata after `lower_filter`
returns. This keeps syntax independent from runtime `value.Value` ownership.

The grammar basis is jq's `Array`/`Object` term productions in
`upstream/jq/src/parser.y:658-669` and dictionary-pair productions in
`upstream/jq/src/parser.y:888-945`. Pinned compatibility examples include
`jq -n '{}'`, `jq -n '{a:1}'`, shorthand `{a}`, and nested constructors.
