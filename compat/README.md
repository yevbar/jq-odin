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
order, and number rendering are therefore outside this adapter. The separate
`shtest_compat.py` process adapter checks those observable bytes exactly.

`compat/skips.json` maps exact case IDs to non-empty reasons. Unsupported cases
must be listed there explicitly; unknown skip IDs are harness errors.

## Process-oriented `shtest` catalog

`compat/shtest-process.json` is an explicit, shell-free catalog for the first
deterministically representable cluster in `upstream/jq/tests/shtest`. Runnable
entries contain exact argv elements and stdin encoded as canonical RFC 4648
Base64. Base64 keeps NUL and invalid UTF-8 bytes visible and round-trippable;
the loader rejects invalid or non-canonical encodings. Entries that require a
shell loop or multi-process pipeline are catalogued as skips with reasons.

List the stable catalog IDs without launching either executable:

```sh
tools/compat/shtest_compat.py --list
```

Run the catalog or a stable glob selection:

```sh
tools/compat/shtest_compat.py \
  --oracle "$ORACLE" \
  --candidate /absolute/path/to/jq-odin \
  --case 'seq-*' \
  --json-report build/compat/shtest-process.json
```

The adapter is Linux-only. Before launching any untrusted code, it classifies
both paths through nonblocking, no-follow descriptors, rejects symlinks and all
special files before a readable open, and copies only regular executable files
into separately sealed, non-executable master `memfd` images. For ELF images,
the same capture parses `PT_INTERP` and the sealed dynamic table, snapshots and
reports the resolved program-interpreter bytes in the existing dependency
array, and recursively snapshots
libraries found through origin-relative RPATH/RUNPATH entries. Braced and
unbraced `$ORIGIN`, `$LIB`, and `$PLATFORM` use token-boundary-aware expansion;
the ABI values come from the exact active glibc loader identified through
`PT_INTERP` and `AT_BASE`. The same bounded diagnostics provide the ordered
glibc-hwcaps levels and active mask, cross-checked against that loader's own
searched-level help. For every origin search directory the adapter captures
the first regular artifact in that reported hwcaps order, or the base artifact,
and privately masks the complete live `glibc-hwcaps` subtree at launch.
Slash-bearing `DT_NEEDED` names are expanded with the same token parser when
they bind an absolute path; absolute literal and per-consumer `$ORIGIN` forms
are recursively sealed, while runtime-working-directory-relative and
unresolved forms fail closed. Unknown or unresolvable tokens in an
origin-relative entry fail closed instead of yielding partial evidence. An
effective RPATH or RUNPATH entry without `ORIGIN` also fails closed, so a mixed
ordered path cannot select an earlier uncaptured object while reporting a later
origin-relative object. Legacy RPATH search
state is inherited by indirect dependencies as it is by the Linux loader;
RUNPATH remains direct-only. Capture is bounded to
five seconds and 134,217,728 cumulative executable-and-dependency bytes. One
process-level wall-clock alarm spans initial lookup/open, recursive dependency
lookup/open, and reads, then restores the prior handler and timer. The adapter
validates source device/inode throughout. It hashes
the sealed masters, then creates fresh disposable clones for every `--version`
and case launch. Images with captured origin dependencies are exposed at their
original loader-visible paths by private overlay uppers. Retained no-follow
parent authority keeps the narrow parent overlay while attached and rebuilds a
renamed or removed hierarchy without reopening a source parent, so `$ORIGIN` and
`$ORIGIN/../` remain valid while later rename, removal, exchange, or replacement
cannot change the staged bytes. Overlapping anchors are mounted in canonical
ancestor-before-descendant order so the complete sealed set stays visible.
Every dynamic native probe and case directly executes a fresh sealed clone of
that one captured loader against a fresh executable clone at its private
loader-visible path; later replacement of the pathname in `PT_INTERP` cannot
change execution. Static native images retain the memfd exec path. A shebang helper is
accepted only with an absolute, argument-free, native interpreter; relative,
argument-bearing, and nested shebang interpreters fail closed before launch.
The adapter separately captures, seals, hashes, and reports that interpreter,
including its native ELF loader and any origin-relative ELF dependencies,
then every probe and case directly executes a fresh interpreter clone against a
fresh script clone. Linux executable-mode seals reject execute-bit changes, and
source interpreter replacement after `--version` cannot affect later execution.

Each oracle and candidate invocation gets a different quarantined working
directory, a minimal environment, and a new process session. The adapter is a
Linux child subreaper: after timeout, output limit, or normal leader exit, it
opens a pidfd before validating each captured PID/start-time identity and sends
SIGKILL only through that bound descriptor. It never signals a numeric PID or
PGID after a separate validation. Bounded discovery handles original group
members and same-PID-namespace descendants that created a new session/process
group, then reaps them. Process discovery and
explicit no-follow workspace removal share a 0.5-second absolute deadline and
cumulative work budgets. Pipe drain after process cleanup is separately limited
to 0.25 seconds. A process or workspace that defeats a bound is explicitly
reported; the adapter never waits indefinitely for pipe EOF or invokes implicit
recursive temporary-directory cleanup.

Setup has its own one-second deadline covering subreaper preparation,
quarantine and authority creation, descendant-baseline discovery, and a
kernel-confirmed exec. The declared case timeout starts immediately afterward,
using the monotonic timestamp captured at the parent's first observation of
that exec event. Later parent-side staging and descriptor cleanup is charged
to the case deadline and cannot become a post-exec setup timeout. Native and
accepted-shebang children announce framed setup stages and are traced only
until Linux reports their `exec` event; status-pipe EOF alone is never treated
as successful execution. Exit or signal before that event is therefore a
structured setup failure. The direct-fork wrapper exclusively owns child wait
status and reports sticky infrastructure failure if another reaper consumes it,
rather than presenting the dead child as live or timed out.
Setup failure and setup timeout use distinct schema-v5
`startup_failure.stage` values and clean any launched process, pipes,
descriptors, and workspace under separate bounded emergency-cleanup deadlines.
If a tracked child was forked, the existing `startup_failure.process_result` preserves
partial output, descendant evidence, cleanup state, and any retained quarantine.

The execution deadline is absolute and inclusive. It is enforced before each
exit poll, so an exit first observed at or after the deadline is a timeout for
both oracle and candidate; bounded drain still preserves partial output.

Workspace and trusted-parent descriptors, including device/inode/mount
identities, are retained across candidate execution. Cleanup searches only the
retained parent boundary, verifies any relocated workspace before removal, and
requires the retained workspace descriptor to show a zero link count before it
reports clean success. An inode moved beyond that boundary is reported as
`cleanup_incomplete` with the trusted boundary and retained identity encoded in
the schema-v5 `quarantined_path` string.

stdout and stderr are drained concurrently and captured independently up to
1,048,576 bytes per stream per invocation. The first byte beyond that cap
kills the invocation and records which stream was truncated. A truncated
prefix is always a resource-limit failure, never an exact-byte match. Bytes up
to and including the cap retain exact comparison semantics. No catalog value
is evaluated by a shell. A skip is counted separately and can never be
reported as a pass. See `shtest-process-safety.md` for the containment boundary
and report fields.

The version-5 JSON report records canonical input/output bytes, literal argv,
`path:line` provenance, isolated working-directory identities, process
outcomes, per-stream truncation, forced pipe closure, whether non-leader
descendant cleanup was required, incomplete cleanup, observable quarantined
paths, resource bounds, executable versions and
sealed-image hashes/source identities and stable recursive dependency identity
arrays (including a bound shebang interpreter), complete oracle and candidate version
probe results, deterministic structured startup failures, selection, and
aggregate pass/fail/skip/error counts. Early capture/version failure still
writes the report and exits nonzero; when a version probe leaves a quarantine,
its full process result preserves that path. The
operator must dispose of any retained quarantine, preferably by destroying the
credential-free VM; see the safety document. This is harness infrastructure:
catalog presence does not imply that the current Odin CLI supports or passes a
case.

`descendant_cleanup_required` is distinct from routine bounded post-exit
verification and from `cleanup_incomplete`: it becomes true only after a
non-leader PID/start-time identity is discovered for signaling, liveness
checking, or reaping. Candidate/oracle evidence is compared explicitly, and a
candidate `--version` probe requiring such cleanup fails closed.
Any invocation with `cleanup_incomplete=true` is infrastructure-fatal and stops
the run before another untrusted invocation can establish a descendant baseline.

Later adapters will cover:

- the remaining process and CLI behavior in `upstream/jq/tests/shtest`;
- regex fixtures in `onig.test` and `manonig.test`;
- documentation, codecs, modules, UTF-8, torture, and fuzz surfaces.

Fixtures remain in the immutable submodule unless a copy has recorded
provenance and a licensing reason.

Run harness self-tests with:

```sh
python3 -m unittest discover -s tools/compat/tests -v
```
