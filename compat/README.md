# Differential compatibility harness

The harness drives the pinned jq 1.8.1 CLI and an Odin candidate as separate
processes. It parses `upstream/jq/tests/jq.test` without requiring the
candidate to implement jq's internal `--run-tests` option.

Build the immutable oracle out of tree:

```sh
ORACLE=$(tools/compat/build-oracle.sh)
```

The builder creates a fresh randomized directory for every invocation; it
never trusts a previously cached executable. Build output goes to stderr and
the sole stdout line is the new oracle path.

Run every core-language case in the same shell:

```sh
tools/compat/jq_compat.py \
  --oracle "$ORACLE" \
  --candidate /absolute/path/to/jq-odin \
  --json-report build/compat/core.json
```

The text summary reports how many selected cases passed, failed, skipped, or
encountered harness errors. The JSON report records every case, including
passing cases, exact `path:line` provenance, commands, output bytes, exit
status, signal, duration, comparison mode, working directory, stable
environment overrides, platform labels, and differences.

Useful selection options:

```sh
# Show stable case IDs without executing them.
tools/compat/jq_compat.py --oracle ORACLE --candidate CANDIDATE --list

# Run one case or glob.
tools/compat/jq_compat.py \
  --oracle ORACLE --candidate CANDIDATE \
  --case 'upstream/jq/tests/jq.test:63'

# Deterministically split the suite among four agents.
tools/compat/jq_compat.py \
  --oracle ORACLE --candidate CANDIDATE \
  --shard-count 4 --shard-index 0
```

Normal cases compare the ordered JSON output stream semantically and stderr
bytes exactly. Compile-failure cases compare process status, stdout, and
diagnostic bytes unless the fixture uses `%%FAIL IGNORE MSG`. Timeouts,
signals, invalid JSON, duplicate object members, missing outputs, extra
outputs, and reordered outputs are failures. The runner captures all oracle
results before it launches any candidate code, including candidate
`--version`, so the candidate cannot replace the reference executable between
validation and use. It records the oracle SHA-256 and verifies that the binary
does not change during capture. Candidate and oracle processes receive a
minimal, secret-free environment, and timeouts terminate their process group
and close captured pipes.

The runner is process containment, not an operating-system sandbox. Execute
untrusted pull-request candidates only inside a separate disposable VM with no
coordinator, Codex, or repository credentials; do not run them on a
credentialed agent VM.

Semantic JSON is intentional for this core suite. jq's own `--run-tests`
implementation parses each expected output and compares it to the evaluator
result with `jv_equal` (`upstream/jq/src/jq_test.c:181` and
`upstream/jq/src/jq_test.c:193`). Exact whitespace, escaping, object-member
order, and number rendering are therefore outside this adapter; the future
shell/CLI adapter must check those observable presentation details.

`compat/skips.json` maps exact case IDs to non-empty reasons. Unsupported cases
must be listed there explicitly; unknown skip IDs are harness errors.

Later adapters will cover:

- process and CLI behavior in `upstream/jq/tests/shtest`;
- regex fixtures in `onig.test` and `manonig.test`;
- documentation, codecs, modules, UTF-8, torture, and fuzz surfaces.

Fixtures remain in the immutable submodule unless a copy has recorded
provenance and a licensing reason.

Run harness self-tests with:

```sh
python3 -m unittest discover -s tools/compat/tests -v
```
