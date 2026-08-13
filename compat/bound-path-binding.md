# Bound literal path arrays

This shard covers the narrow lexical-binding bridge for path builtins:
`["foo",1] as $p | getpath($p)` and `setpath($p; value)`. The evaluator clones
the array owned by the binding frame before lookup or copy-on-write mutation.
Computed path generators and general assignment remain separate contracts.

Run the focused oracle comparison with:

```sh
python3 tools/compat/jq_compat.py \
  --tests compat/bound-path-binding.jq.test \
  --oracle /private/tmp/jq-merge-next/.tools/jq-oracle-1.8.1 \
  --candidate /tmp/jq-bound-path-candidate
```
