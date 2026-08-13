# Dynamic `contains` needles from bindings

This shard covers jq 1.8.1 `contains/1` when the needle is a bound variable
produced by an enclosing `as` binding. The parser retains the variable child,
and the evaluator resolves it through the existing lexical binding frame before
calling the ownership-safe containment kernel. Arbitrary filter-valued needles
remain outside this bounded ABI.

Evidence: `upstream/jq/tests/jq.test:1615-1619`.

Run with:

```sh
python3 tools/compat/jq_compat.py \
  --tests compat/contains-bound-variable.jq.test \
  --candidate /tmp/jq-contains-odin \
  --oracle /private/tmp/jq-integrated-local/.tools/jq-oracle-1.8.1 \
  --show-passes
```
