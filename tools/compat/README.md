# Compatibility tools

- `build-oracle.sh` archives the pinned jq and Oniguruma commits into a fresh
  randomized directory under ignored `.tools/` storage, builds jq 1.8.1
  there, and leaves the submodules clean. It never reuses a cached binary.
- `jq_compat.py` parses `jq.test`, executes explicit oracle and candidate
  paths, compares observable process behavior, supports deterministic shards,
  and emits reproducible text and JSON reports.
- `shtest_compat.py` strictly loads the explicit process catalog at
  `compat/shtest-process.json`, never evaluates shell, runs literal argv and
  arbitrary Base64-encoded stdin bytes from bounded, regular-file-only sealed
  Linux master images copied into fresh disposable execution images for each run in
  isolated process sessions, caps each output stream, bounds post-exit pipe
  draining, pidfd-binds every validated signal, reaps same-namespace descendants,
  and retains workspace/parent descriptors so renamed quarantines can be found
  only within a bounded trusted search root and identity-verified before removal.
  Executable capture uses one process-level wall-clock alarm across initial
  lookup/open, recursive dependency lookup/open, and reads, restoring the prior
  handler and timer afterward. ELF dynamic tables are parsed from the sealed image;
  dependencies resolved through origin-relative RPATH/RUNPATH entries share the
  five-second and 128-MiB cumulative capture budget and are sealed separately.
  The Linux dynamic-string tokens `$ORIGIN`, `$LIB`, and `$PLATFORM` accept
  their braced and unbraced spellings. `$LIB` and `$PLATFORM` come from the
  exact active glibc loader's bounded diagnostics after its device/inode is
  matched to the ELF `PT_INTERP`; they are not inferred from a machine-name
  table. Its reported glibc-hwcaps order and active mask are cross-checked
  against the same loader's searched-level help, and lookup captures the
  highest-priority existing regular artifact at its exact hwcaps or base path.
  Private tmpfs mounts hide each captured search directory's entire live
  `glibc-hwcaps` subtree, including higher candidates created after capture.
  Slash-bearing `DT_NEEDED` accepts absolute literals and absolute paths formed
  with the same braced/unbraced token grammar, then captures their recursive
  closure using each consumer's own `$ORIGIN`. Relative-to-runtime-CWD,
  unresolved, malformed, and unsupported forms fail closed. An
  origin-relative search entry containing an unknown, malformed, or
  unresolvable residual token fails executable capture instead of being
  omitted from an apparently complete dependency image. An effective RPATH or
  RUNPATH containing any entry without `ORIGIN` also fails capture, including a
  mixed ordered path with an unsealed entry before an origin-relative entry.
  Legacy RPATH search state is inherited through indirect dependencies;
  RUNPATH is intentionally direct-only.
  Each launch uses retained component-wise no-follow parent authority to
  privately overlay fresh captured clones, reconstructing a renamed hierarchy
  without reopening source parents and preserving `$ORIGIN` and
  `$ORIGIN/../` without trusting later host path contents.
  Overlay staging uses only the bounded `/dev/shm`, `/tmp`, and `/run` bases
  that are outside every active overlay anchor. If no such base is available,
  setup fails closed at `path_staging`; it never stages beneath an anchor where
  the subsequent overlay would hide the staging tree. Launches are normalized
  so overlapping ancestors mount before descendants regardless of discovery
  order, preserving every sealed descendant.
  Absolute argument-free shebangs additionally bind a
  separately captured native interpreter image; relative, argument-bearing,
  and nested shebang interpreters are rejected before launch.
  A separate one-second setup deadline covers quarantine and containment
  preparation through kernel-confirmed native or accepted-shebang `exec`; the case
  execution deadline is anchored to the parent's first monotonic observation of
  that event, independently for oracle and candidate. Parent staging and descriptor
  cleanup after that observation consumes case time and cannot be reclassified as a
  setup timeout. Both native and shebang setup run in a directly tracked session leader:
  the child emits framed stage/error records while the parent exclusively owns
  its wait status and traces only through the kernel `PTRACE_EVENT_EXEC` stop.
  Status-pipe EOF is never accepted as execution evidence, so an ordinary exit
  or signal at any setup stage is a structured setup failure. The parent can
  kill and reap a child blocked in image copying, namespace setup, mounting, or
  validation at the cumulative deadline. Only standard I/O, the status writer,
  sealed execution images, and retained path-parent descriptors survive
  into setup; the execution and parent descriptors are marked close-on-exec
  before target code.
  The inclusive absolute execution deadline is checked before exit polling, so
  an exit first observed at or after it is timed out while partial output is
  still drained. Cleanup never uses numeric `kill`/`killpg`: it opens a pidfd,
  validates the captured start time, and signals through that bound descriptor
  for the leader and every discovered descendant.
  Workspace cleanup shares the process deadline and work budgets and proves the
  retained inode was unlinked before comparing exact process outcomes. Its
  platform and containment contract is documented in
  `compat/shtest-process-safety.md`.

The runner requires both `--version` probes to exit zero without a signal,
stderr, timeout, cleanup failure, or malformed output. Each must emit one
non-empty UTF-8, LF-terminated stdout line, and the candidate identity must
equal the validated oracle identity. The oracle must identify as `jq-1.8.1`
unless `--allow-unpinned-oracle` is supplied for harness self-tests. A rejected
candidate probe is an infrastructure error and no candidate case is executed.
Report schema version 5 still emits a machine-readable report for every early
executable identity or version failure; a failed version probe includes its
complete process result, `descendant_cleanup_required`, and any retained
`quarantined_path`. The cleanup-required field records discovery of a
non-leader process identity for signaling, liveness checking, or reaping; it is
not set by ordinary post-exit verification and remains independent of
`cleanup_incomplete`.
Setup deadline and setup failure use the existing schema-v5 `startup_failure`
shape with stages `process_setup_timeout` and `process_setup_failure`,
respectively; post-launch failures preserve their emergency-cleanup
`process_result`, while pre-launch failures keep it null. Any incomplete
containment is infrastructure-fatal before another untrusted launch. Setup
handling adds no schema field; an accepted shebang executable uses the nested
schema-v5 `interpreter` identity record. Top-level native identities and nested
shebang-interpreter identities also carry an additive, path-sorted
`dependencies` array with each sealed dependency's path, SHA-256, source
device, and source inode. For a dynamic native image this existing array
includes the captured `PT_INTERP` identity; each invocation directly executes
a fresh loader clone, so later pathname replacement cannot affect the probe or
cases. The schema remains version 5 because existing field meanings are
unchanged and the new evidence is additive.
A directly forked leader's wait status is exclusively owned by its
`ForkedProcess`. If another waiter consumes it, sticky `ECHILD` handling fails
closed as infrastructure status loss; repeated polls and bounded or unbounded
waits never report the child as live or map it to a timeout. Cleanup still
treats that already-reaped identity as dead while preserving the failure.
