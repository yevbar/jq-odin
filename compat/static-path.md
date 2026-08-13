# Bounded static path implementation shard

This shard records the currently implemented path slice: `path(.foo)`,
`paths`, and `getpath(["foo",1])`. The path representation is a JSON array
of string object keys and numeric array indices. The source contracts are the
pinned jq fixtures at `upstream/jq/tests/jq.test:1101-1112` and
`upstream/jq/tests/jq.test:1138-1148`; the path primitive wrappers are at
`upstream/jq/src/builtin.c:1372-1377`.

The implementation deliberately excludes dynamic path expressions,
`path(.foo[0,1])` generator composition, and mutating `setpath`/`delpaths`.
Those remain in `compat/paths-api.jq.test` as visible failures for later
lanes.

Run the focused differential shard with:

```sh
tools/compat/jq_compat.py \
  --tests compat/static-path.jq.test \
  --skips compat/static-path-skips.json \
  --oracle "$ORACLE" --candidate /absolute/path/to/jq-odin \
  --show-passes
```
