# 0012: Source filter AST and parser ownership

- Status: proposed
- Date: 2026-08-01
- Workstream: language

## Context and evidence

jq declares pipe right-associative at its lowest expression-operator tier and
comma left-associative at the next, tighter tier
(`upstream/jq/src/parser.y:100-103`). The `Query` productions implement both
operators (`upstream/jq/src/parser.y:324-345`). Identity, field shorthand,
general postfix optional, and parenthesized queries are `Term` productions;
specialized field-optional productions have the same observable syntax for
this slice (`upstream/jq/src/parser.y:545-580,640-656`). The lexer supplies
field value text without the dot and uses a length-delimited scanner input
(`upstream/jq/src/lexer.l:129-131`;
`upstream/jq/src/parser.y:956-965`). Any accumulated parser error destroys the
partial compiled block (`upstream/jq/src/parser.y:956-970`).

Official jq 1.8.1 probes confirm that `.`, `.name`, `(.)`, comma, pipe, `.?`,
`.??`, `.name??`, and `(.?)?` compile. They also confirm that field suffixes
chain after fields, optional terms, and parentheses, while malformed trailing
dots fail. Unsupported `[]`, `..`, and `//` forms compile in jq but remain
deliberately outside this foundation. Those probes establish acceptance and
rejection boundaries for the slice, not a claim that this parser reproduces
jq's final rendered diagnostic strings.

The postfix-dot grammar shifts `.` as part of field-index and error productions
before deciding whether the following token is valid
(`upstream/jq/src/parser.y:570-595`). Because `?` is a distinct single-byte
token (`upstream/jq/src/lexer.l:81`), `(.a).?` is rejected at `?`, not at the
already-consumed dot.

The generated parser starts with 200 state/value/location stack entries and
caps built-in growth at 10000 entries
(`upstream/jq/src/parser.c:1690-1704,2247-2264,2320-2385`). Its stacks grow
through jq's allocator, and the grammar declares destructors for discarded
literal and block semantic values (`upstream/jq/src/parser.y:9-10,37-38`).
With the same official binary and hash used below, binary-search probes found
that nested groups succeed through depth 9994 and report `memory exhausted` at
9995; pipe chains succeed through 4997 operators and report `memory exhausted`
at 4998. These are observed generated-parser resource transitions, not jq
language nesting limits. The probes are reproducible without generating files:

```sh
JQ=/tmp/jq-pr35-oracle-bin
for spec in groups:9994 groups:9995 pipes:4997 pipes:4998; do
  kind=${spec%:*}; depth=${spec#*:}
  program=$(python3 -c 'import sys; k=sys.argv[1]; n=int(sys.argv[2]); print("("*n+"."+")"*n if k == "groups" else ".|"*n+".")' "$kind" "$depth")
  "$JQ" -n "$program" >/dev/null
  printf '%s status=%s\n' "$spec" "$?"
done
```

The fixer re-ran these representative probes with the official Linux jq 1.8.1
release binary (SHA-256
`020468de7539ce70ef1bceaf7cde2e8c4f2ca6c3afb84642aabc5c97d9fc2a0d`):

```text
JQ=.tools/probes/jq-1.8.1
printf '%s\n' '{"a":{"b":{"c":1}}}' | "$JQ" -c '.a.b'
=> stdout {"c":1}; stderr empty; status 0
printf '%s\n' '{"a":{"b":1}}' | "$JQ" -c '.a?.b, .a.b?, .a?.b?, .a??.b, (.a?)?.b?'
=> stdout 1\n1\n1\n1\n1; stderr empty; status 0
printf '%s\n' '{"a":{"b":1}}' | "$JQ" -c '(.a).b, (.a?).b, (.a?)?.b?'
=> stdout 1\n1\n1; stderr empty; status 0
printf '%s\n' '{"a":{"b":1},"c":{"d":2}}' | "$JQ" -c '.a.b, .c.d | .'
=> stdout 1\n2; stderr empty; status 0
printf '%s\n' '{"a":{"b":1},"c":{"d":2}}' | "$JQ" -c '.a | .b, .c.d'
=> stdout 1\nnull; stderr empty; status 0
"$JQ" -n '.a.'
=> stdout empty; stderr reports unexpected EOF at trailing dot; status 3
"$JQ" -n '.a?.'
=> stdout empty; stderr reports unexpected EOF at trailing dot; status 3
"$JQ" -n '.a?name'
=> stdout empty; stderr reports unexpected IDENT at name; status 3
"$JQ" -n '(.a).?'
=> stdout empty; stderr reports unexpected ?; status 3
"$JQ" -n '.a..b'
=> stdout empty; stderr reports unexpected ..; status 3
```

Odin owns dynamic storage manually, and a parser can encounter allocation
failure after producing partial nodes. A returned flat slice cannot by itself
retain allocator provenance or safely represent retryable destruction.

## Decision

`syntax.Parser` is an address-stable, single-use owner initialized with one
borrowed `diagnostic.Source` and one allocator. It owns its integrated
`syntax.Scanner` and a flat dynamic node arena. Copying a live parser with Odin
`=` is forbidden. The caller keeps the exact source view, both source backing
strings, the allocator, and allocator backing state alive until
`destroy_parser` succeeds.

`parse_filter` consumes the complete source exactly once. A successful
`Parse_Outcome` identifies its root by `Node_Id`; `parser_nodes` returns a
borrowed arena view. The outcome, node indices, node spans, field-name spans,
and node view own no storage and remain usable only until parser destruction
begins. AST nodes contain source syntax only and never runtime `Value`.

The arena has explicit nodes for identity, field shorthand, parentheses,
comma, pipe, and postfix optional. Parentheses are retained rather than erased
so every node has its own exact half-open byte span. A field node's optional
`name_span` excludes its leading dot. A standalone field has no explicit child
and applies to implicit identity; a postfix field has a child and spans the
complete chained term. Child relationships are arena indices, so destroying
the arena releases the entire tree without recursive cleanup.

`Parse_Error` is an allocation-free structured value containing a kind,
expected grammar class, exact source span, and an actual token kind when one
exists. Lexical and resource failures remain distinct. End-of-input errors use
a zero-width span at the explicit source-length boundary. Every token outside
the slice, including otherwise valid jq syntax, is rejected, and successful
parsing requires lexer end-of-input.

`Scan_Outcome` and `Parse_Outcome` retain the exact `runtime.Allocator_Error`
for resource failures. Resource failure remains distinct from an input
diagnostic, but allocation and release errors are not collapsed into an
uninspectable boolean.

Parsing this slice uses explicit state rather than native recursion. A newly
appended parenthesized node temporarily holds the suspended outer expression
state while its child is parsed, then becomes the final parenthesized AST node
in place. Comma and pipe nodes likewise begin as incomplete arena placeholders
and are completed before success. No separate parse-stack allocation or owner
is introduced: every complete or partial placeholder remains in the existing
Parser-owned node arena on success, input error, and resource failure.

The syntax parser has no fixed nesting cap. Its boundary is successful growth
of the fallible scanner and node buffers under the caller's allocator, reported
as `Resource_Failure` when allocation cannot continue. Tests cover all depths
accepted by the pinned jq boundary probes above; no jq parity claim is made for
greater depths, where the pinned generated parser exhausts its implementation
stack even though the grammar remains balanced.

On success, syntax error, lexical error, or allocation failure, the parser
remains the sole owner of complete and partial storage. Scanner states and AST
nodes use an explicit fallible buffer owner rather than Odin dynamic-array
growth. Growth allocates and copies a replacement while the old allocation
remains active. The old allocation is released before the new element becomes
visible. If that release fails, the count and active allocation remain
unchanged and the replacement is retained in a `Transfer_Pending` owner state.
The same append can retry that release and transfer without allocating or
copying again.

`destroy_parser` first destroys scanner storage and then the node arena. It
retries any pending old-to-replacement transfer before releasing the resulting
sole owner. `Mode_Not_Implemented` retires a handle under a bulk-lifetime
allocator. Any other allocator free error preserves every remaining handle and
allocator provenance for another retry; once cleanup begins no parse or AST
query operation is valid. Successful destruction is idempotent.

## Alternatives

- Returning a self-owning AST value was rejected because ordinary Odin copies
  would duplicate a buffer owner without move enforcement.
- One allocation per tree node was rejected because it complicates cleanup,
  increases failure points, and requires recursive destruction.
- Erasing parentheses was rejected because it loses the requested precise
  source span for that source-level form.
- Recursive descent with a fixed nesting count was rejected because an
  arbitrary count rejects grammar-valid input below jq's observed parser-stack
  resource transitions. Native recursion without a count was also rejected
  because it could exhaust Odin's call stack.
- Importing runtime `value` for field text was rejected by the package graph;
  the field spelling remains a borrowed source span.

## Consequences

This adds a public syntax contract consumed by future `compiler` work. It
creates no new package or import edge: `syntax` continues to import only
`diagnostic`. Consumers must compile or copy any needed source spelling before
destroying the parser, and they must not retain node-array element pointers
across parser growth during parsing. The coordinator must accept this proposal
before treating it as a cross-workstream contract.

## Validation

- Focused tests cover every supported form, precedence and associativity,
  parentheses, optional chaining, exact nested spans, malformed/trailing and
  unsupported tokens, lexer errors, embedded NUL, the exact postfix-dot error
  boundary, a checked-in 1,818-filter acceptance corpus, all reachable
  allocation failures, dual-owner growth-release failure and transfer retry
  for parser and scanner buffers, cleanup retry, jq-accepted depths 128, 129,
  1000, 4997 pipes, and 9994 groups, plus deep incomplete-input cleanup.
- Run syntax tests sequentially with allocation tracking in default, optimized,
  debug, AddressSanitizer, and assertions-disabled modes, then run
  `make validate` and `git diff --check`.
- Request source-aware semantic-parity, Odin ownership/resource-safety, and
  parser test-gap review lanes.
