# Decision 0354: generated path-valued assignment boundary

## Status

Superseded for the bounded `=` slice by Decision 0356. The broader generated
path/update contract remains deferred.

## Evidence

The target catalog case `upstream/jq/tests/jq.test:1281` is:

```jq
def x: .[1,2]; x=10
```

Pinned jq emits `[0,10,10]` for `[0,1,2]`. The current candidate accepts the
path generator itself (`def x: .[1,2]; x` and `path(.[1,2])`), but both this
assignment and direct `.[1,2] = 10` stop at filter parse error. Oracle probes
also establish the required stream contracts:

```text
.[1,2] = 10             => [0,10,10]
.[1,2] = (1,2)          => [0,1,1], [0,2,2]
.[1,2] |= .+1           => [0,2,3]
def x: .[1,2]; x=(1,2)  => [0,1,1], [0,2,2]
```

## ABI seam

`static_assignment_path` in `src/syntax/parser.odin` only lowers direct
Field/Index trees into literal `Setpath`; it cannot lower a Call or a comma
index stream. `Setpath` in `src/eval/evaluator.odin` accepts only a literal or
bound path and a literal replacement. The existing `Path` evaluator can emit
multiple path arrays, but no assignment frame owns that stream or its
continuation.

## Required staged contract

Add an append-only generated-path update opcode with path-filter and RHS child
instructions. Its evaluator must (1) collect zero/one/many owned path arrays in
source order, (2) distinguish `=` RHS evaluation once globally from `|=` RHS
evaluation against each selected value, (3) retain only jq's first RHS result
per assignment branch while suppressing later outputs/errors, (4) apply all
paths copy-on-write against one input snapshot, and (5) preserve typed path
diagnostics for invalid components and overlapping paths. Focused tests should
cover empty path streams, duplicated/overlapping numeric paths, RHS empty,
multi-output and late errors, null/missing synthesis, and array/object scalar
intermediate failures before enabling jq.test:1281.
