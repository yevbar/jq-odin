# Decision 0327: bounded stable `sort_by(.field)` key opcode

The static unary `sort_by(.field)` bridge now materializes pairs with the
existing `map` constructor, then invokes the real `Sort_By_Key` program
instruction before projecting the original value. The evaluator compares only
the first pair element and inserts new records strictly before lower keys;
equal keys therefore retain their source order. Ordinary `Sort` is unchanged.

Evidence:

* jq defines `sort_by(f)` through key-stream materialization in
  `upstream/jq/src/builtin.jq:5`.
* jq's stable tie behavior stores and compares an explicit input index in
  `upstream/jq/src/jv_aux.c:663-675`.
* The equal-key records are exercised by
  `compat/sort-by-key-stable.jq.test:2-11` and the catalog's sort_by cases at
  `upstream/jq/tests/jq.test:1639-1645`.

Scope is deliberately bounded to a static identifier field and whole-filter
`sort_by(.field)` (optionally followed by `| .[]`). Dynamic/generator keys,
multi-key streams, and `group_by` remain deferred; those require preserving
zero/one/many key outputs and a first-class materialization lifecycle.
