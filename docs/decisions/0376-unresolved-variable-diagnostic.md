# Unresolved variable compile diagnostics

## Decision

Extend the existing compiler `Lower_Outcome` diagnostic payload with an
`Unresolved_Variable` kind. The binding-scope walk records the first unresolved
variable's complete token span and its name-only span, and the driver forwards
those borrowed source spans to the CLI formatter. No evaluator or runtime
ownership changes are involved.

## Evidence

The pinned jq oracle for `jq.test:560` is:

```jq
. as $foo | [$foo, $bar]
```

It reports `$bar is not defined` at column 20 with a four-character caret over
`$bar`, and exits with compile status 3. A bound variable remains executable:
`. as $foo | [$foo]` yields `[null]`.

The adjacent `jq.test:566` case, `. as {(true):$foo} | $foo`, is not an
undefined-variable case: jq reports `Cannot use boolean (true) as object key`.
That diagnostic requires a separate parser/compiler validation phase and is
intentionally outside this change.

## Source boundary

`src/compiler/package.odin:9-23` owns `Lower_Error_Kind` and the two borrowed
diagnostic spans. Its recursive binding walk is at
`src/compiler/package.odin:476-588`, and lowering maps the reserved spans to
`Unresolved_Variable` at `src/compiler/package.odin:1170-1174`.
`src/driver/package.odin:469-471` forwards these fields unchanged, while
`cmd/jq-odin/main.odin:346-365` owns jq-compatible source/caret rendering.
