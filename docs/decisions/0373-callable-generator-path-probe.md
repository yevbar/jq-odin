# Decision 0373: generator-valued callable path probe

## Status

Deferred as a staged ABI milestone; no source specialization is accepted yet.

## Probe evidence

Pinned jq 1.8.1 produces the following for
`def inc(x): x |= .+1; inc(.[].a)`:

```text
[{"a":1,"b":2},{"a":7,"b":8}] -> [{"a":2,"b":2},{"a":8,"b":8}]
[]                          -> []
null                        -> Cannot iterate over null (null)
1                           -> Cannot iterate over number (1)
```

This is the generator-valued callable case in
`upstream/jq/tests/jq.test:1236-1238`. jq's path VM retains the caller path,
root value, and resumable program counter around `PATH_BEGIN`/`PATH_END`
(`upstream/jq/src/execute.c:629-672`); the argument cannot be reduced to a
scalar before call activation.

## Current ABI gap

The integrated literal callable arithmetic phase (`37a3278f`) stores one field
key and one numeric RHS in the Call frame. Non-literal arguments still use the
ordinary two-edge Call path, which evaluates values before entering the body.
There is no frame-owned path vector, path cursor, original-root snapshot, or
resume phase for a generator argument. Reusing the literal key path would
silently drop all but one selected element and would mishandle empty and typed
iteration errors.

## Staged implementation contract

The next source phase should add a bounded argument-shape recognizer for
`.[].field`, then a frame-owned path array and cursor:

`Callable_Path_Capture → Callable_Path_RHS → Callable_Path_Apply →
Callable_Path_Resume`.

Capture must evaluate the array iterator against a cloned caller root, append
owned `[index, field]` vectors in source order, and preserve the original root
for every apply. Empty capture emits the unchanged root once; null/number roots
raise jq's iterate diagnostic before RHS evaluation. Apply must retain one RHS
result per selected path, use copy-on-write from the original root, and resume
without duplicating outputs. All vectors, selected values, RHS values, and
pending roots are frame-owned; Program instruction/text references remain
borrowed under the existing seal lifetime.

Do not land a textual rewrite or scalar argument shortcut. Required validation
must include zero/one/many paths, overlapping paths, RHS empty/multi-output,
late errors, and try/catch suppression before this phase is promoted.
