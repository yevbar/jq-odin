# Decision 0382: bounded callable generator path update

The first runtime phase for `def inc(x): x |= .+1; inc(.[].a)` recognizes only
an array caller, an empty-index field chain (`.[].a`), and a one-number
`Parameter_Identity_Update` body. It applies the update to each array element
in source order using copy-on-write object/array ownership. Empty arrays emit
unchanged; null/number roots preserve jq's catchable iterate diagnostics;
missing fields are created as null before `+ 1`; incompatible values retain jq's
typed add diagnostic.

The broader path-vector continuation (arbitrary RHS streams, overlapping paths,
late errors, `try`/optional suppression, and resumable allocator suspension)
remains deferred. This phase is deliberately structural and does not rewrite
the driver filter text.

Evidence: `src/driver/package.odin:1100-1132` recognizes the nested field AST;
`src/eval/evaluator.odin:11765-11870` applies the bounded array path update;
`upstream/jq/tests/jq.test:1236-1238` is the oracle case.
