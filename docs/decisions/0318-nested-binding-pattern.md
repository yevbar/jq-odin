# Decision 0318: bounded ordinary nested-binding patterns

## Context

The pinned jq suite uses ordinary `expr as PATTERN | body` bindings with
nested arrays, objects, quoted keys, computed keys, and a named nested array
value (`jq.test:524,530,920,924`). The existing lowering only handled flat
one- or two-entry patterns and rejected these cases at compile time.

## Decision

Lower a bounded nested pattern to the existing ordinary `Binding`, `Field`,
and `Index` nodes. A temporary binding retains the producer value; each leaf
path is projected from that temporary and bound in reverse execution order so
the temporary name is not shadowed before later projections run. Object keys
use static fields for identifiers and quoted strings, while parenthesized
expressions remain dynamic index keys. A variable key followed by `:` binds
the whole field as well as recursively binding its nested pattern.

The lowering is limited to eight path segments and sixteen leaves and accepts
only variable leaves and nested array/object containers. `?//`, assignment
updates, and `Reduce`/`Foreach` synthetic pattern metadata remain separate
contracts.

## Evidence

- `upstream/jq/tests/jq.test:524,530,920,924` are the compatibility source
  cases.
- `compat/nested-binding-pattern.jq.test` passes all four cases against the
  pinned jq 1.8.1 oracle.
- Existing ordinary `Binding` scope validation and evaluator paths are reused;
  no program ABI or evaluator state shape changes are required.
