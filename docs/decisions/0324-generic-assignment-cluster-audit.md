# Decision 0324: generic assignment cluster requires a new path-update contract

## Audit scope

This audit starts from integration `f5432fc8` and covers the generic
assignment cases at `upstream/jq/tests/jq.test:1216-1289`, `:1357`, `:2088`,
`:2335`, and `:2348`. The pinned catalog run on this head is **447/522
selected cases passed, 75 failed, 0 harness errors**. The existing scalar
assignment cases at lines 1204, 1208, 1212, 1265, and 1269 pass; the cases
listed below fail before evaluation with a parser error (or an internal misuse
for `.[] = 1`).

## Evidence

The jq oracle exercises several distinct observable contracts:

| jq source | required behavior | current result |
| --- | --- | --- |
| `jq.test:1216-1222` | compound operators over `.[]`, including division and modulo | parser rejects generator LHS and non-literal update |
| `jq.test:1228` | compound update whose RHS reads the selected field | parser accepts neither compound operator nor filter RHS |
| `jq.test:1232` | nested path update with an object-constructor stream | parser's nested assignment path only accepts scalar literals |
| `jq.test:1236` | updates through a definition and `.[].a` path | no callable path-update ABI |
| `jq.test:1241` | `getpath(...)` as a path expression, with per-input errors caught | `Setpath` only accepts a literal path and literal replacement |
| `jq.test:1253-1261` | generator selection, empty deletion, and repeated indices | no path generator/update continuation |
| `jq.test:1273-1277` | invalid generated paths produce jq's path diagnostics | no generated-path validation boundary |
| `jq.test:1281-1287` | function-generated path assignment and invalid multi-result path errors | no path-valued LHS contract |
| `jq.test:1289` | scalar assignment over an array generator | `.[] =` reaches unsupported internal misuse |
| `jq.test:1357` | defined-or assignment over an array generator | no compound generator update |
| `jq.test:2088` | assignment with a binding in the path expression | no binding-aware path capture |
| `jq.test:2335`, `:2348` | optional/try RHS streams, including empty and caught errors | parser only allows identity, field, or literal RHS |

The implementation makes these boundaries explicit. The assignment parser
dispatches `|=` to a field-only helper (`src/syntax/parser.odin:2320-2327`),
restricts nested `=` RHS values to scalar literals
(`src/syntax/parser.odin:2359-2380`), and restricts ordinary field RHS values
to identity/field/scalar literals (`src/syntax/parser.odin:2715-2731`). The
compiled `Setpath` opcode carries two child instructions, but the evaluator
requires both a literal path and a literal replacement
(`src/eval/evaluator.odin:7384-7393`). `Dynamic_Field_Set` similarly evaluates
only identity, one field, or a literal (`src/eval/evaluator.odin:7828-7845`).

## Smallest genuine shared contract

The smallest contract that unlocks more than one of these cases is not another
literal rewrite. It is a first-class path-update instruction with:

1. a path child that may yield zero, one, or many path values;
2. an RHS filter child evaluated once per selected path and allowed to yield
   zero, one, or many values;
3. an explicit assignment operator (`=`, `|=`, `+=`, `-=`, `*=`, `/=`, `%=` or
   `//=`); and
4. source-span/error metadata for jq's invalid-path diagnostics.

The evaluator must suspend while path and RHS streams run, retain the original
input for each path branch, apply copy-on-write updates in jq order, and treat
an empty RHS as deletion for update operators. It must also reject a path
generator that produces non-path values or multiple paths in the `x=10`
regression cases. This is a shared syntax/AST, program ABI, compiler, and
resumable-evaluator change, not a safe local parser relaxation.

## Decision

Do not implement this cluster on the current lane. Relaxing the existing
scalar guards or adding a driver-specific rewrite would either misrepresent
the path/update ABI or pass one fixture while silently changing stream,
deletion, and error semantics. Schedule a dedicated cross-package contract
task with an adversarial semantic-parity lane. The task should first implement
one end-to-end vertical slice (`.[] = literal` plus `.[] |= empty`) and then
expand operators and path generators only with oracle-backed fixtures.

## Validation

- Candidate build: `odin build cmd/jq-odin -collection:jq=src -vet -warnings-as-errors`
- Catalog: `tools/compat/jq_compat.py` against pinned jq 1.8.1, 447/522 pass
- Existing package baseline is unchanged; no source implementation was made
  in this audit.
