# Core-suite failure taxonomy

The core parser sees 522 cases in the pinned fixture: 503 executable cases and
19 `%%FAIL` cases. The jq harness already records every observation, but its
flat `differences` arrays do not answer which implementation owner should
consume a cluster. `tools/compat/catalog_report.py` adds that reporting layer;
it does not alter comparison, skip, status, stderr, or output semantics.

## Reproduction

Build the pinned oracle and run the complete suite against the current Odin
CLI (inside the candidate VM):

```sh
ORACLE=$(tools/compat/build-oracle.sh)
REPORT=build/compat/jq-522.json
rm -f "$REPORT"
if tools/compat/jq_compat.py \
  --oracle "$ORACLE" \
  --candidate /absolute/path/to/jq-odin \
  --json-report "$REPORT"
then
  harness_status=0
else
  harness_status=$?
fi
case "$harness_status" in
  0|1) ;;
  *)
    printf 'jq_compat.py failed with unexpected status %s\n' "$harness_status" >&2
    exit "$harness_status"
    ;;
esac
tools/compat/catalog_report.py \
  "$REPORT" \
  --output build/compat/jq-522-taxonomy.json
```

The report is removed before the runner starts, and the catalog step is
reachable only for the documented runner statuses: `0` for no differences or
`1` for compatibility differences. Any other harness status stops the
sequence, so a stale or partial report cannot be mistaken for a fresh result.

The first report is the before form: each failed case has only a flat list,
for example `exit status differs: ...` and `stderr bytes differ`. The taxonomy
is the after form: the same case remains under both `status` and `stderr`, with
its original `case_id`, `source`, `line`, and exact `differences` retained.
Clusters are sorted by descending case count and then name, so repeated runs
are diffable. A case can belong to multiple clusters; `cluster_case_total`
therefore intentionally may exceed the number of cases.

For example, the relevant before fragment is:

```json
{"status":"fail","differences":[
  "output 1 differs: oracle=1, candidate=2",
  "stderr bytes differ"
]}
```

The corresponding after fragment is:

```json
{"case_id":"upstream/jq/tests/jq.test:123","line":123,
 "categories":["output-order","stderr"],
 "differences":[
  "output 1 differs: oracle=1, candidate=2",
  "stderr bytes differ"
]}
```

## Handoff from a complete run

The actionable owner mapping is deliberately coarse and does not infer a
failure from the jq program text:

| Cluster | Consumer workstream |
| --- | --- |
| `output-value`, `output-cardinality`, `output-order`, `timeout` | value/eval |
| `malformed-output` | cli |
| `compile-diagnostic` | syntax/diagnostic |
| `compile-status` | program/compiler |
| `status`, `signal`, `stdout`, `compile-stdout` | cli |
| `stderr` | diagnostic/cli |
| `harness-error`, `skip`, `unknown` | compat |

The analyzer preserves oracle version and SHA-256, candidate identity, suite,
selection, and every case's `path:line` provenance. It rejects unknown report
schemas instead of silently normalizing them. The current integration-base
checkout has no Odin CLI, so this branch does not claim a candidate result; the
exact command above is the reproducible run to execute once that candidate is
available.

Evidence for the 522-case count is the parser's direct read of
`upstream/jq/tests/jq.test`; the case format and `%%FAIL` markers are defined
by the pinned fixture at `upstream/jq/tests/jq.test:8-2506`.
