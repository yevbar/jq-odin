# Decision 0324: defer `?//` destructuring alternatives pending branch IR

## Audit

The pinned catalog cases at `upstream/jq/tests/jq.test:929-1029` use
destructuring alternatives such as:

```
.[] | . as {$a, b: [$c, {$d}]} ?// [$a, {$b}, $e] ?// $f |
  [$a, $b, $c, $d, $e, $f]
```

The current parser recognizes the `?//` token (`syntax.Token_Kind.Alternation`)
but has no parser reduction for it. The existing syntax tree, program, and
evaluator therefore cannot represent or execute these cases; the candidate
returns a filter parse error while pinned jq emits three branch-selected
outputs.

## Boundary

Do not lower `?//` textually to `//`, `try`, or a sequence of ordinary
`Binding` nodes. That would be unsound:

* ordinary pattern bindings project missing fields to `null` and do not expose
  a pattern-match failure signal, while `?//` must try the next pattern when
  the current pattern does not match;
* a successful alternative exports the union of variables from every pattern,
  filling variables absent from the selected pattern with `null`;
* each alternative must run against the same producer value and roll back
  temporary bindings on failure (the upstream DUP/POP regression cases exercise
  this), while retaining zero-to-many producer and body stream ordering;
* runtime errors from a selected branch must remain distinguishable from a
  pattern mismatch and must not be silently swallowed by fallback selection.

The current evaluator has no branch frame, pattern-match result, or lexical
environment transaction that can provide these semantics. Adding only a parser
case or driver rewrite would create false compatibility and could leak values
across alternatives.

## Design plan

Implement a first-class `Alternation` syntax/program contract in a later lane:

1. Parse `PATTERN (?// PATTERN)+` only in the `expr as PATTERN | body`
   binding position, retaining each pattern and the body as separate graph
   edges. Reject standalone/filter-valued `?//` until a broader contract is
   designed.
2. Lower each pattern to a checked pattern descriptor (leaf paths, variable
   names, and expected container shape) rather than ordinary nullable Field /
   Index projections.
3. Add an evaluator continuation that clones the producer for each branch,
   performs strict shape/path matching, rolls back branch-local bindings on
   mismatch, and commits the first successful branch. Export the union of names
   with explicit null fill.
4. Preserve stream cardinality and errors: branch mismatch is recoverable;
   selected-branch runtime errors are terminal/catchable jq errors; body
   outputs remain ordered and zero-to-many.
5. Add focused fixtures for the primary nested case and every DUP/POP ordering
   case at jq.test:929-1029, then run the full catalog and independent semantic
   and ownership review lanes.

Evidence commands on integration head `548b357f`:

```
printf '[{"a":1,"b":[2,{"d":3}]},[4,{"b":5,"c":6},7,8,9],"foo"]\\n' |
  jq-odin -c '.[] | . as {$a, b: [$c, {$d}]} ?// [$a, {$b}, $e] ?// $f |
    [$a, $b, $c, $d, $e, $f]'
```

Candidate result: filter parse error. Pinned jq 1.8.1 result:
`[1,null,2,3,null,null]`, `[4,5,null,null,7,null]`, and
`[null,null,null,null,null,"foo"]`.
