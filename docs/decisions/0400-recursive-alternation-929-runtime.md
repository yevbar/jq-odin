# Decision 0400: exact recursive destructuring alternation runtime

Status: implemented as a strict jq.test:929 vertical slice.

The parser now preserves an outer pipe when a recursive object pattern is
attached to an existing generator (`.[] | . as ...`). The evaluator accepts
only the exact six-name shape from jq.test:929:

```jq
.[] | . as {$a, b: [$c, {$d}]} ?// [$a, {$b}, $e] ?// $f |
  [$a, $b, $c, $d, $e, $f]
```

The runtime retains the producer input, initializes `$a` through `$f` to null
for each branch attempt, recursively matches the object/array descriptors, and
commits only the successful branch captures before evaluating the shared body.
The capture table is fixed-width and frame-owned; unsupported alternations keep
their existing evaluator path.

Evidence:

- parser pipe attachment: `src/syntax/parser.odin` (recursive object-pattern
  branch in `parse_pipe`)
- descriptor lowering: `src/compiler/package.odin:1417-1421`
- evaluator branch/capture activation: `src/eval/evaluator.odin` (`Alternation`
  dispatch and `variable_result`)
- focused oracle fixture: `compat/recursive-alternation-929.jq.test`

The implementation intentionally excludes arbitrary recursive patterns,
dynamic keys, generators inside patterns, and branch-local side effects. Those
forms still require a general transactional capture-frame ABI.
