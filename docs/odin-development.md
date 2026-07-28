# Odin development notes

These notes pin assumptions for the jq rewrite. They are guardrails, not a
premature package or implementation design.

## Toolchain

The repository pins Odin `dev-2026-05`. Odin uses monthly development release
names rather than semantic versions, so compiler upgrades must be explicit and
must rerun the entire compatibility suite.

Odin's compiler expects its `base`, `core`, and `vendor` collections beside
the compiler unless `ODIN_ROOT` is set. For that reason, the bootstrap script
installs the whole release under `.tools/odin-dev-2026-05` rather than copying
only the executable.

On macOS, the Xcode command-line tools provide the linker toolchain. The
official macOS ARM64 release is used on Apple Silicon; Rosetta is not required.

References:

- <https://odin-lang.org/docs/install/>
- <https://github.com/odin-lang/Odin/releases/tag/dev-2026-05>

## Declarations and assignment operators

Odin's declaration and assignment syntax must not be confused with jq's
filter-level assignment semantics:

- `name: Type` declares storage, zero-initialized by default.
- `name := value` is an inferred variable declaration. It is the tokens `:`
  and `=`, not a separate assignment operator.
- `name = value` assigns to an existing location.
- `::` declares a compile-time constant, including named procedures and types.
- Declarations must be unique within a scope; `:=` cannot be used to
  redeclare one existing name in a multi-name declaration.
- Procedure parameters are immutable. Make an explicit local copy when an
  algorithm needs to mutate a parameter value.
- Compound assignments such as `+=`, `-=`, and `||=` are supported.

jq's `=`, `|=`, `+=`, and related operators operate on paths and streams of
values. They can update multiple selected paths and have behavior that is not
equivalent to Odin's storage assignment. The future parser/IR should represent
each jq operator explicitly rather than translating it to a similarly spelled
Odin operator.

Reference: <https://odin-lang.org/docs/overview/#assignment-statements>

## Generators, continuations, and coroutines

jq filters are generators: one input may produce zero, one, or many outputs,
and combinators rely on resumable evaluation and backtracking-like behavior.
This is a central semantic requirement, not merely a performance detail.

The pinned Odin language and core documentation do not expose language-level
generator, `yield`, async/await, fiber, or coroutine primitives. Odin's
`thread.yield` yields an operating-system thread; it does not suspend and
resume an Odin procedure as a coroutine. `core:thread`, thread pools, and
thread-safe channels provide concurrency, but threads are not a substitute for
jq continuations and would add scheduling and synchronization costs.

Until a focused prototype proves otherwise, assume:

- no stackful or stackless coroutine support from the language;
- no direct translation of a jq generator into a yielding Odin procedure;
- jq evaluation will need explicit resumable state, such as VM frames,
  continuations, or an iterator/state-machine representation;
- concurrency should remain separate from generator semantics.

Choosing among those representations is intentionally deferred. It should be
driven by small semantic probes for Cartesian products, `empty`, `try/catch`,
`reduce`, `foreach`, path assignment, and early termination.

References:

- <https://pkg.odin-lang.org/core/thread/>
- <https://pkg.odin-lang.org/core/sync/chan/>

## Memory and ownership

Odin uses manual memory management. Built-ins such as `new`, `make`, dynamic
arrays, and maps normally allocate through the allocator in the implicit
`context`. This is useful for arena-scoped parse/evaluation lifetimes, but
allocator choice and ownership still need to be explicit in the design.

Guardrails for later work:

- document the owner and lifetime of every JSON value, string, compiled filter,
  and VM frame;
- do not return slices or strings backed by a temporary arena;
- pair dynamic-array and map allocation with clear deletion or arena teardown;
- preserve jq's value semantics deliberately rather than relying on accidental
  shallow copies;
- use the test runner's memory tracking during development.

Reference: <https://odin-lang.org/docs/overview/#allocators>

## Strings, JSON, and C boundaries

An Odin `string` is length-delimited and immutable; it is not a NUL-terminated
C string. A `cstring` is for C interop. Keep the distinction visible around
CLI arguments, libc calls, and any temporary reuse of upstream C components.

JSON text is Unicode encoded as UTF-8, while jq's observable behavior also
includes escaping, invalid-input errors, byte-oriented I/O, and embedded NUL
handling. Do not let conversion through `cstring` define internal string
semantics.

Odin supports foreign C bindings, so differential or transitional reuse is
possible. Any such use should stay behind a narrow boundary so the final
runtime dependency policy remains a conscious decision.

References:

- <https://odin-lang.org/docs/overview/#string-type>
- <https://odin-lang.org/docs/overview/#foreign-system>

## Packages and tests

An Odin package is a directory, and every `.odin` file in that directory must
declare the same package. Nested directories are separate packages, not
implicitly nested namespaces. The future layout should be chosen around
dependency boundaries after the test harness has been inventoried.

Odin tests use `@(test)` procedures and `odin test`. The runner is
multi-threaded by default and includes allocation tracking. Language-agnostic
compatibility tests should remain the primary oracle; small Odin unit tests can
cover local invariants without replacing black-box jq behavior tests.

References:

- <https://odin-lang.org/docs/overview/#packages>
- <https://odin-lang.org/docs/testing/>

## Error handling and portability

Odin has multiple return values and common `(value, ok)` / `(value, error)`
patterns rather than exceptions. Do not collapse jq parse errors, compile
errors, runtime errors, `empty`, and process exit statuses into one boolean.
Their externally visible messages and exit codes belong in the compatibility
surface.

Use platform file suffixes and compile-time `when` branches only where host
behavior genuinely differs. The initial target is native macOS ARM64, but
portable CLI and filesystem behavior should not be made Apple-specific.
