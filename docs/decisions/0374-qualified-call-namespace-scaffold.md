# Qualified-call namespace metadata scaffold

## Decision

Retain the namespace prefix of a qualified identifier as source-owned syntax
metadata (`Definition.namespace_span` and `Node.call_namespace_span`) and as
fixed source offsets on `program.Callable_Entry`. The compiler validates that a
namespace span is the prefix before `::`, but evaluator dispatch does not route
qualified calls yet.

## Scope

This is an ABI scaffold only. It does not resolve imported aliases, populate a
module definition table, expand modules, or change runtime call behavior. The
existing driver/module loader remains the owner of textual module expansion for
unsupported imported definitions.

## Evidence and boundary

- `src/syntax/package.odin:272-280,640-650` already lexes `foo::a` as one
  namespaced identifier span.
- `src/syntax/parser.odin:318-328,427-430` previously retained only the full
  declaration/call span; no namespace component crossed the syntax boundary.
- `src/program/package.odin:17-25` previously carried only ordinal, arity, and
  body on callable metadata.
- `src/driver/module_loader.odin:875-896` explicitly keeps imported callable
  bodies on the textual-expansion bridge.

The next runtime phase still requires a namespace-aware definition table and
driver alias population; this change intentionally does not attempt that
cross-package routing.
