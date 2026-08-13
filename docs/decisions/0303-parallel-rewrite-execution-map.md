# Parallel jq-to-Odin execution map

Status: coordinator planning record, 2026-08-13.

The compatibility catalog currently selects 522 cases: 411 pass and 111 fail
with no harness errors. The failing set is not a single queue; it contains
independent leaf gaps and several shared continuation contracts. This record
defines the safe parallel boundary for Vers workers and the required merge
order.

## Independent implementation tracks

These tracks can start from the same integration head and do not share AST or
evaluator state when kept within their owned paths:

1. **Diagnostics and compile-failure parity** — source spans, invalid escapes,
   and typed runtime messages. Evidence includes `jq.test:63,127,133,139`.
2. **Module fixtures and data imports** — loader path resolution, nested data
   aliases, and module metadata. Evidence includes `jq.test:1862-1939`.
3. **Numeric and string leaf builtins** — only when the parser and opcode
   already exist; each worker must add an oracle fixture and ownership test.
4. **Computed-key/object constructor cases** — evaluator key-stream ownership,
   separate from path mutation. Evidence includes `jq.test:122,139`.
5. **Vers infrastructure** — launcher/API compatibility, watchdog policy, and
   COWFS lifecycle diagnostics. Infrastructure commits must not change jq
   semantics or source packages.

## Shared-contract tracks

These must be assigned one owner at a time, with an adversarial reviewer after
each vertical slice:

- **Generator control:** `while`, `until`, labels, and `break` require parser,
  Program, compiler, and evaluator continuation changes (`jq.test:315-333`).
- **Resumable updates:** root/index/slice/filter-valued assignment requires
  original-input retention while evaluating RHS streams (`jq.test:474-490,
  1216-1357,2437-2441`).
- **First-class definitions/calls:** nested definitions, lexical snapshots,
  closures, and general recursion require a Program definition table and call
  frames (`jq.test:775,789,864,875`).
- **Pattern bindings:** nested destructuring and `?//` require recursive
  pattern representation and binding backtracking (`jq.test:524-566,
  894-1029`).
- **Filter-valued builtins:** `any/all`, `contains`, `sort_by/group_by`,
  `INDEX/JOIN/IN`, and `walk` require child-generator continuations rather
  than textual rewrites (`jq.test:1615-1639,2047-2119,2388`).

## VM and review protocol

Each implementation VM receives one track and one immutable integration base.
No worker may edit `upstream/jq/**`, merge its own PR, or modify another
track's AST/Program ABI. The coordinator merges only after:

1. focused oracle shard, package checks, `make validate`, and full catalog;
2. an independent semantic-parity, Odin-ownership, or test-gap reviewer sees
   the exact PR head in a fresh VM;
3. the watchdog reports the worker retired or paused, not left running.

The current installed Vers CLI accepts `run-commit <key> -N <alias>` and
`execute <vm> -- <command>`; it no longer accepts the older `--wait`, `-t`, or
`resize` flags. The launcher compatibility fixes are isolated in commits
`978d862c` and `e4b3f025`. A real VM still disappeared during preparation, so
there is no author PR or adversarial artifact to claim yet.

No COWFS/backend change is evidenced by the repository or retained VM state.
If a future Vers checkpoint shows a backend or filesystem migration, create a
separate infrastructure commit and validate it independently before changing
the jq integration base.
