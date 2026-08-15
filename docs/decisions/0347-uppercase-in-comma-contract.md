# Decision 0347: bounded uppercase `IN` comma-literal form

Uppercase `IN({}, [])` is lowered to the existing two-child `In` continuation:
the comma literal is the source stream and the identity predicate compares each
source value with the original input. This covers the literal comma form used
inside jq's `walk(select(IN({}, []) | not))` definition without adding a new
program or evaluator opcode.

The focused shard `compat/in-uppercase-args.jq.test` verifies null, object,
array, and scalar inputs. Dynamic comma generators and the surrounding `walk`
filter remain deferred; those require a resumable `walk` predicate contract.
