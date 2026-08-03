# `shtest` process adapter safety boundary

The process adapter is intentionally Linux-only. Its guarantees depend on
`memfd_create(2)` plus content and executable-mode seals, `renameat2(2)`, `/proc` process identities,
`prctl(2)` child subreaping, `ptrace(2)` exec events, `pidfd_open(2)`,
`pidfd_send_signal(2)`, process sessions, and nonblocking pipe polling.

## Executable identity

The oracle and candidate are both classified and copied before either is run.
The supplied path is made absolute without resolving its final symlink, then
opened with Linux `O_PATH|O_NOFOLLOW`. `fstat` rejects symlinks, FIFOs, sockets,
devices, and every non-regular or non-executable object before any readable
open occurs. Only a validated regular file is reopened through its trusted
`/proc/self/fd` identity using `O_NONBLOCK`; device and FIFO open behavior is
therefore never invoked. The readable descriptor's device/inode must equal the
classified descriptor before and after capture. Capture has a five-second
wall-clock deadline enforced with `ITIMER_REAL`/`SIGALRM`, including while a
source `read(2)` is blocked, and a cumulative 134,217,728-byte
executable-and-origin-dependency limit. The adapter fails closed if it cannot
establish and later restore that real-time alarm state.

Each accepted copy is placed in a non-executable master `memfd`, sealed against
writes, growth, and shrinkage, and hashed. Before each `--version` or catalog
launch, the adapter copies those authoritative bytes into a fresh executable
`memfd`, applies the same content seals plus Linux `F_SEAL_EXEC`, and disposes of that per-invocation
image after the tracked launch. The master descriptor is never inherited. Its SHA-256 plus
captured source device/inode are recorded in the report. The alarm spans path
lookup and classification, descriptor opens, all recursive dependency
resolution, and reads, then restores the prior signal handler and timer.
Original path
replacement cannot affect an already captured image.

For a native ELF image, the adapter parses `PT_INTERP`, `DT_NEEDED`, and
`DT_RUNPATH` (or legacy `DT_RPATH`) directly from the sealed bytes. Search
entries containing `$ORIGIN` or `${ORIGIN}` expand the glibc `$ORIGIN`, `$LIB`,
and `$PLATFORM` tokens in both braced and unbraced forms with complete token
boundaries. `$ORIGIN` remains the directory of each individual consumer.
The program interpreter named by `PT_INTERP` is identity-checked, captured,
sealed, and reported in the native executable's existing `dependencies` array.
Every version probe and case directly executes a fresh clone of that captured
loader against a fresh clone of the program at its private loader-visible path;
the kernel never resolves the live `PT_INTERP` pathname for a later invocation.
When dynamic-token expansion is needed, the adapter identifies its current
loader from the kernel `AT_BASE` mapping, requires `PT_INTERP` to name that same
device/inode, and reads
`dl_dst_lib`, `dl_platform`, `dl_hwcaps_subdirs`, and
`dl_hwcaps_subdirs_active` from that exact loader's bounded
`--list-diagnostics` output. The active-mask interpretation and priority order
must exactly match the searched levels printed by the same loader's bounded
`--help`; disagreement is a deterministic capture failure. It does not guess ABI directories from
`uname`/machine aliases. A loader without those glibc diagnostics, a different
program interpreter, or any unknown, malformed, or unresolvable token in an
origin-relative entry is a deterministic capture failure; the adapter never
silently reports the resulting partial dependency closure as complete. Every
entry in an effective `DT_RPATH` or `DT_RUNPATH` must contain `ORIGIN`; a mixed
ordered search path with a non-origin entry fails capture before launch rather
than allowing the loader to select an uncaptured object.
Regular dependencies found in expanded directories are recursively captured,
identity-checked, sealed, and charged to the same time and byte budget, with at
most 256 dependency images. Each directory lookup tries only the bounded active
glibc-hwcaps list in loader priority order before its base path. The selected
regular artifact is captured and reported at that exact path; recursive token
expansion therefore uses the selected object's actual directory. Slash-bearing
`DT_NEEDED` names bypass directory search as glibc does: absolute literals and
supported-token expansions that produce absolute paths are captured, while
relative-to-runtime-CWD, unresolved, malformed, or unsupported forms fail
closed rather than leaving a partial closure. Legacy `DT_RPATH` directories are inherited while
walking indirect dependencies, matching loader search scope, while
`DT_RUNPATH` remains local to the object's direct dependencies. Apart from the
identity-matched loader's diagnostics, it invokes no dependency-enumeration
tool and snapshots no unbounded directory. Before exec, fresh clones of the image
and captured origin dependencies are materialized into private overlay uppers.
Every captured search directory's `glibc-hwcaps` subtree is additionally
replaced by a private tmpfs containing only sealed captured artifacts, so a
higher-priority live candidate created or replaced after capture is invisible.
Capture retains bounded, component-wise no-follow directory authority for each
source parent. An attached authority keeps the narrow original-parent overlay;
after rename, removal, or exchange, the upper reconstructs the complete path
below a stable top-level namespace anchor. No executable or dependency source
parent is reopened. The child execs that private path, so the dynamic loader
observes the intended origin,
including `$ORIGIN/../` layouts, while rename, removal, exchange, or replacement
of the captured hierarchy remains masked. Every overlay staging directory is
created under one of the bounded supported bases only when that base is outside
every active overlay anchor. In particular, an active `/dev` anchor excludes
`/dev/shm`; active `/tmp`, `/workspace`, and simultaneous anchors are evaluated
together. If `/dev/shm`, `/tmp`, and `/run` are unavailable or equal to or below
any active anchor, setup fails closed at `path_staging` instead of placing a
staging tree where a later overlay would hide it.
Overlapping overlay launches are canonicalized independently of discovery
order, with ancestors mounted before descendants so later parent mounts cannot
cover sealed descendant material.
Failure to clone, validate, materialize,
or mount any captured material is a structured setup failure. Only a static
native image, which has no `PT_INTERP`, keeps the sealed memfd launch.

The normal jq oracle and Odin candidate are native executables. Their disposable
execution FD is marked close-on-exec immediately before Linux executes
`/proc/self/fd/N`, so it does not leak into the program. A shebang is accepted
only when an LF-terminated directive within the first 256 bytes names an
absolute interpreter path with no argument. Only ASCII space and tab are
recognized as shebang whitespace; other control bytes are malformed rather
than separators. Relative interpreters, interpreter arguments (including
`/usr/bin/env python3`), nested shebang interpreters, and malformed or overlong
directives are rejected before any target is launched.
These deliberate limits avoid working-directory-dependent resolution and
unbound dispatcher identities.

For an accepted shebang, the interpreter is captured recursively as a native,
sealed master image before either executable is run. Every probe and case uses
fresh disposable clones of both the same script master and the same interpreter
master; the interpreter clone is executed directly with the script clone as its
first argument. The interpreter execution FD closes at `exec`, while the script
clone remains available to the interpreter. The schema-v5 executable record
contains the shebang interpreter path, SHA-256, source device/inode, and a stable
`dependencies` array in its nested `interpreter` object. Native top-level
records have the same additive dependency array, which also identifies their
captured `PT_INTERP`; each entry reports path,
SHA-256, source device, and source inode. Replacing the source interpreter after
`--version` cannot alter later executed code while those reported identities
remain unchanged.
If the native interpreter has captured `$ORIGIN` dependencies, its executable
and libraries use the same private loader-visible overlay as a native candidate
or oracle, while the separately captured script retains its supplied path.

## Setup and execution deadlines

Every invocation has a separate one-second setup deadline. It starts before
child-subreaper preparation and covers quarantine creation, workspace-authority
capture, bounded descendant-baseline discovery, and a kernel-confirmed exec.
A process-level real-time alarm covers the parent-side preparation operations.
Before fork the alarm is disarmed; native and accepted-shebang images then use
the same directly tracked child and absolute-deadline status/ptrace handshake.
The child handle and pipes are published immediately after fork, so a child
that stalls before exec remains available to identity-bound emergency cleanup.
An individual Linux syscall is not preempted, but an over-budget child setup is
not admitted as a case execution: the launched PID/start-time identity, pipes,
and retained workspace are cleaned under separate bounded cleanup allowances
before a structured setup-timeout error is returned.

The configured case execution deadline starts from the monotonic timestamp
taken at the parent's earliest observation of the kernel-confirmed exec event.
Oracle and candidate pre-exec setup time is therefore excluded from their declared
runtime allowance, while later parent-side staging and descriptor release consumes
that allowance. Crossing the setup deadline after this timestamp cannot turn a
confirmed execution into `process_setup_timeout`. Adapter `duration_ms`
continues to record total wall time, including bounded setup and cleanup, rather
than redefining the existing schema-v5 field. Setup failures use the existing
`startup_failure` object with stage `process_setup_failure`; setup deadline
exhaustion uses stage `process_setup_timeout`. Both retain the executable role
and require no report-schema extension.

Native and accepted-shebang setup use a directly forked child. That child emits bounded,
framed records before session creation, `chdir`, script-path preparation,
descriptor closure, and `exec`. The parent is the exclusive wait-status owner
and traces the child only until Linux reports `PTRACE_EVENT_EXEC`, then detaches.
A close-on-exec status-pipe EOF is not success evidence: exit, signal, malformed
or truncated status, and timeout before the kernel exec event are structured
setup failures attributed to the last announced stage. This keeps forced death
at every setup boundary distinct from ordinary candidate behavior.

The execution deadline is absolute and inclusive: `now >= deadline` is timed
out. The adapter tests that deadline before polling for exit, so a process exit
first observed after the deadline cannot be reported as on-time even if the
runner was descheduled while the process exited. Buffered partial output is
still drained under the existing bound, and the rule is identical for oracle
and candidate.

## Output and termination

stdin, stdout, and stderr are pumped concurrently without a shell. stdout and
stderr each have an independent 1,048,576-byte capture cap. The adapter keeps
exactly the first cap bytes, records `stdout_truncated` or `stderr_truncated`,
kills the invocation on the first excess byte, and sets the deterministic
`output_limit_exceeded` resource-limit classification. It never treats a
matching truncated prefix as a pass.

After timeout, output limit, or normal leader exit, the adapter starts bounded
cleanup. It never calls `kill(2)` with a bare PID or `killpg(2)` with a bare
PGID. For the leader and every discovered descendant it opens a pidfd first,
then rereads `/proc/PID/stat` and requires the captured PID/start-time identity
to match before calling `pidfd_send_signal`. A replacement present before the
open fails validation; reuse after validation cannot redirect the signal
because the pidfd remains bound to the checked process lifetime. The original
session-leader metadata is still required before initiating group cleanup, but
group members, session escapees, and adopted orphans are each found by the
bounded snapshot loop and individually pidfd-signaled and reaped. `ESRCH` and
permission failure are handled without throwing.

The direct-fork wrapper owns its leader's child status exclusively. An
unexpected `ECHILD` means an external waiter or adopted-child reaper violated
that ownership; it becomes a sticky infrastructure error. Repeated `poll`,
bounded `wait`, and unbounded `wait` calls reproduce that error instead of
claiming the child is live or timing out. Bounded cleanup may treat the already
reaped identity as terminated for process-tree discovery, but it does not erase
or downgrade the status-loss failure.

Every process result separately records `descendant_cleanup_required`. It is
false for ordinary bounded post-exit process-table verification. It becomes
true only when cleanup discovers a non-leader PID/start-time identity that must
be signaled, checked for liveness, or reaped. A completed containment action can
therefore report `descendant_cleanup_required=true` and
`cleanup_incomplete=false`; these fields are deliberately independent.

One absolute monotonic 0.5-second deadline is shared by process-table scanning,
descendant discovery, identity-safe signaling, liveness checks, reaping, and
explicit writable-workspace removal. Each cleanup call also has deterministic
cumulative budgets of 65,536 `/proc` directory entries, 32,768 snapshot
identity reads, 4,096 descendant visits, 32,768 workspace entries, 67,108,864
workspace bytes, and 65,536 workspace operations. One bounded process-table
snapshot is reused for all roots in a discovery round instead of rescanning
`/proc` for every descendant.

Exhausting the deadline or any work budget stops discovery, marks cleanup
incomplete, and permits only already discovered PID/start-time identities to be
signaled, checked, or reaped within the remaining deadline. Every signal uses
the pidfd-open-then-start-time-validation protocol, so no validation-to-signal
window can retarget it to a reused PID. Pipe
draining then gets at most 0.25 seconds; remaining parent read descriptors are
forcibly closed and `pipe_drain_timed_out` is reported. `cleanup_incomplete`
therefore covers both a process identity that could not be removed and a
process table that could not be fully inspected within the cleanup deadline or
work budgets; neither state can be reported as successful cleanup.

Containment loss is infrastructure-fatal. Immediately after each oracle or
candidate invocation, `cleanup_incomplete=true` stops the overall run before
another untrusted process can start. In particular, a surviving child can never
be incorporated into a later descendant baseline and thereby excluded from
cleanup. Successfully resolved descendant cleanup remains observable and keeps
the established oracle/candidate comparison semantics.

## Writable workspace cleanup

Every invocation starts in an explicitly named `shtest-quarantine-*`
directory. Before execution, the adapter retains no-follow descriptors for
both that directory and its parent search boundary, together with both Linux
device/inode/mount identities. The descriptors are close-on-exec and remain
open in the adapter until cleanup finishes. The adapter never creates a
`TemporaryDirectory` object and never invokes implicit recursive cleanup.

After process and pipe handling preserves the main execution outcome, cleanup
searches for the exact retained workspace inode only beneath the retained
parent descriptor. It does not search an absolute pathname or an unbounded
filesystem. A located inode is atomically moved with
`renameat2(RENAME_NOREPLACE)` to a fresh recovery name under that boundary and
then identity-checked. Before removing either an emptied nested directory or
the final recovery directory, cleanup keeps the validated descriptor open,
atomically renames the entry to a new unpredictable removal name, and validates
that the moved name still denotes the descriptor's device/inode/mount identity.
A substitution at either validation/removal boundary is retained and reported
as incomplete; it is never passed to `rmdir`. Cleanup empties the retained
inode itself with an
iterative, descriptor-relative traversal under the shared deadline and
cumulative entry/byte/work budgets. It uses no-follow opens, validates inode,
device, and Linux mount identity, does not cross mount points, unlinks symlinks
rather than following them, and handles regular files, sockets, FIFOs,
devices, permission failures, disappearance, and concurrent churn without
escaping the quarantine. Clean success additionally requires `fstat` on the
original retained descriptor to report a zero link count after removal.

If removal cannot be proven complete, `cleanup_incomplete` is true. When the
exact inode is found, `quarantined_path` is derived from the retained parent
descriptor and verified descriptor-relative entries. If it escaped that
strict search boundary, the same schema-v5 string records the trusted boundary
plus the retained device/inode/mount identity in an
`<unlocated-shtest-quarantine ...>` marker. Original-path replacement or
symlink substitution is reported as incomplete and the verified replacement
path is retained without being followed or deleted. That failure does not
replace or erase the captured exit status, signal, timeout, or output. The
host/VM operator owns disposal of any recorded quarantine. For an untrusted
tree, destroy the disposable VM (preferred) or inspect and remove it with an
equivalently mount-aware, no-follow bounded procedure; do not pass the string
to an unrestricted recursive remover on a credentialed host.

The hostile tests cover repeated prompt rejection of a FIFO without a writer,
a FIFO with a writer, a symlink, a Unix socket, and a device without executing
the target, as well as a blocked regular-file read, capture deadline, and size
exhaustion. They also cover
timeout descendants, a normal-exit child that calls
`setsid()`, a repeatedly expanding tree whose descendants each escape their
session, mocked unbounded process tables with PID reuse, forced substitution
before and after pidfd validation, an exit observed after a scheduler-delayed
deadline check, inclusive exact-deadline behavior, cleanup exhaustion with an unresolved
leader return code, both infinite output streams, exact output at the cap, a
self-replacing `--version` executable, and fail-closed candidate probes for
nonzero exit, signal, timeout, malformed or empty output, cleanup failure, and
identity mismatch. Hostile shebang probes replace the named interpreter after
`--version`, attempt to remove disposable-image execute mode, reject relative
and argument-bearing shebangs, and prove that later execution still uses the
reported sealed identities. Workspace tests cover huge
and continually churning trees,
budget/deadline exhaustion, deterministic nested and final-recovery inode
substitution, symlink no-escape, permission failures, FIFOs and
Unix sockets, ordinary and parent directory rename, rename exchange,
original-path replacement, symlink substitution, search-boundary escape,
repeated concurrent exchange churn, quarantine observability, and the absence
of implicit destructor cleanup. Process tests also cover real leader identity,
numeric-group-signal exclusion, native and shebang setup stalls, alarm
restoration, descriptor closure, external/adopted reaping, and repeated launches.

## Rename regression evidence

The accepted bypass was reproduced at required branch head
`f76a7ea0c63193a6843aa7415294485a7a539439` with a Python candidate that ran:

```python
cwd = pathlib.Path.cwd()
moved = cwd.with_name(cwd.name + "-moved")
os.rename(cwd, moved)
(moved / "survivor").write_text("survived")
```

The direct `run_process` probe reported
`cleanup_incomplete=False`, `quarantined_path=None`, and a surviving
`shtest-quarantine-*-moved/survivor`. The deterministic fixed regression is:

```sh
python3 -m unittest \
  tools.compat.tests.test_shtest_compat.RunnerTests.test_run_process_removes_workspace_renamed_within_trusted_parent
```

It asserts clean success only when the retained inode has been unlinked and no
entry remains beneath the trusted parent. The adjacent hostile tests exercise
exchange, replacement, symlink, parent rename, boundary escape, and twenty
concurrent exchange-churn rounds.

## Containment boundary

This is deterministic process cleanup, not an OS security sandbox. It assumes
the adapter is the only subprocess launcher in its process and that targets
remain unprivileged in the adapter's Linux PID namespace. A privileged target
that can enter another PID namespace, modify the adapter, evade `/proc`, or
otherwise exceed the adapter's authority is outside the guarantee. Run
untrusted candidates only inside a disposable, credential-free VM or stronger
cgroup/PID-namespace sandbox. Executable source reads are preempted by the
process-level capture alarm. Other individual Linux filesystem and process
syscalls are not preempted by userspace deadlines, but the adapter performs only
the documented finite number of them and checks the deadline between operations.
The strict traversal and pipe policies bound adapter work and classify cleanup
as incomplete when descendant containment cannot be established.

## Early-failure reporting

Report schema version 5 emits a deterministic document for every oracle or
candidate executable-capture, version-probe, and version-identity failure.
`startup_failure` records the stage, role, message, and the complete
`ProcessResult` when a process was launched. Each executable record also keeps
its complete `version_process`. Thus an incomplete version-probe cleanup
retains `descendant_cleanup_required`, `cleanup_incomplete`,
`quarantined_path`, exit/signal/timeout, and captured output in the
machine-readable report while the harness exits nonzero. A version probe fails
closed when descendant cleanup was required even if containment completed.
Case comparison explicitly compares oracle and candidate descendant-cleanup
evidence. Capture rejection has no process result because the rejected object
is never executed. Process setup failures and timeouts also produce this
deterministic document. They use the distinct `startup_failure.stage` values
documented above and are emitted only after bounded emergency cleanup closes
any directly tracked child. A pre-launch failure has no `ProcessResult`; a
post-fork failure preserves partial capped output, exit/signal state,
descendant-cleanup evidence, `cleanup_incomplete`, and any retained quarantine
path in the existing `startup_failure.process_result`. Cleanup is never claimed
complete when identity, process, pipe, or workspace cleanup remained unresolved.
