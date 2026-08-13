# Decision: preserve nested `setpath` index errors

The evaluator's literal path lowering previously accepted only scalar string
and number components. A path such as `[[1]]` therefore failed before the
setter ran and surfaced as internal misuse, making it impossible for jq's
`try ... catch` to observe the error. We preserve nested literal arrays during
path lowering and reject them at the setter boundary with the corresponding
typed diagnostic.

The behavior is pinned by `upstream/jq/tests/jq.test:2489-2492` and the focused
`compat/setpath-nested-error.jq.test` shard.
