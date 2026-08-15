# Composed formal-call cardinality boundary

The jq.test:864 closure query is parsed into nested `Binding`, `Call`,
`Fork`, and `Parameter_Reference` instructions, but the current call ABI cannot
preserve the formal argument stream across nested body references. The pinned
jq oracle emits one result, `[1,100,2100,100,2100]`, for input `"more testing"`.
The same query emits that result for `{}`, `null`, and `1`; the current
candidate exits with status 139 for each input, so this is not an
input-shape-specific failure.

The existing direct `Parameter_Reference` phase can retain one argument edge,
but a composed body such as `1 as $x | id([$x, x, x])` requires each formal
reference to share the enclosing argument cursor and lexical owner. A temporary
route that scans nested Call argument edges removed the existing segfault but
either returned `internal misuse` or repeatedly re-entered the argument stream,
showing that frame-local ownership is insufficient. The required phase needs an
explicit callable argument-stream object with owner scope, cursor/cardinality,
per-reference replay semantics, and cleanup when nested `Binding`/`Fork` frames
exhaust.

Relevant seams are the nested-definition routing in
`src/driver/package.odin:1260-1285`, formal-reference activation and Call frame
setup in `src/eval/evaluator.odin:8910-8970,11890-11950`, and argument/binding
continuations in `src/eval/evaluator.odin:3910-3990,5100-5180`. No source route
change is integrated until this shared continuation contract is implemented;
the current candidate remains a crash on the un-routed query.
