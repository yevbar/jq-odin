# Decision 0372: defer recursive alternation capture activation (jq.test:929)

Status: boundary; no partial implementation is safe on the current evaluator ABI.

The valid jq filter

```jq
.[] | . as {$a, b: [$c, {$d}]} ?// [$a, {$b}, $e] ?// $f |
  [$a, $b, $c, $d, $e, $f]
```

must produce, for the fixture input
`[{"a":1,"b":[2,{"d":3}]},[4,{"b":5,"c":6},7,8,9],"foo"]`:

```text
[1,null,2,3,null,null]
[4,5,null,null,7,null]
[null,null,null,null,null,"foo"]
```

The current parser deliberately routes only the bounded array branch shape to
`parse_alternation_binding` (`src/syntax/parser.odin:3586-3604`). Object patterns
remain on the specialized lowering path, which is required for the already-passing
952/959/966/973/980/987/994/1001 cluster. The 929 filter therefore currently emits
a parser error rather than silently taking the wrong branch ABI.

Safe activation requires a recursive pattern representation (nested object/array
nodes), a branch-local capture environment initialized with nulls for every name,
transactional rollback on pattern failure, and commit of only the successful branch's
captures before body evaluation. The producer stream (`.[]`) must retain each item
while every branch is attempted; re-evaluating it would change generator cardinality.
The existing Binding frames expose mutable lexical values directly and do not provide
these snapshot/rollback guarantees. Extending them piecemeal risks leaking `$a`/`$b`
from a failed branch into the fallback, so implementation is deferred until a shared
capture-frame ABI is designed and tested.

Evidence probes: `/usr/bin/jq` returns the three lines above; the Odin candidate at
37a3278f returns `jq-odin: filter parse error` (exit 3). No evaluator or parser source
changes are included in this boundary commit.
