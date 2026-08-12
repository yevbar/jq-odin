# Decision 0240: `isempty` literal object semantics

Literal arrays and objects are both value-producing children of `isempty`, so
the evaluator returns `false` even for empty containers. This keeps the
bounded implementation independent of resumable generator frames. Dynamic
objects, generators, and argument-bearing control forms remain deferred.
