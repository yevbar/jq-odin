# Walk filter AST lowering prototype

Status: prototype; evaluator and CLI validation are pending.

The pinned jq definition of `walk(f)` is a post-order recursive filter:
objects recurse through `map_values`, arrays through `map`, atoms through
identity, and the supplied filter runs after the child container is rebuilt
(`upstream/jq/src/builtin.jq:212-221`). The prototype recognizes `walk(filter)`
in the parser and constructs that definition directly in the syntax arena. It
creates a recursive `Call` edge to the generated body and keeps the supplied
filter as the final pipe child; no driver source rewrite or new evaluator
opcode is used.

The focused shard is `compat/walk-filter-postorder.jq.test`, covering empty
object/array pruning for the selected `IN({}, [])` predicate on scalar,
nested-object, and array inputs. Because this worktree has no Odin compiler
installed, compile, package validation, and candidate/oracle execution remain
to be run in a Vers VM before integration. If recursive `Call` graph lowering
or existing `Map`/`Map_Values` stream ownership cannot satisfy jq's child
cardinality and error semantics, this prototype must be replaced by a
first-class evaluator continuation contract.
