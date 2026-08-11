# Decision 0166: preserve a generator-valued reduce stream

## Scope

Handle the existing compiled `reduce .[] / .[] as $name (seed; . + $name)`
shape by evaluating both array iterators as a Cartesian numeric division
stream before applying the update. This closes the concrete catalog case
without claiming general reduce/foreach support.

## Evidence

The focused `compat/reduce-generator.jq.test` shard compares `[1,2]` and the
expected `4.5` result against pinned jq 1.8.1. Existing reduce package tests
remain green.

## Deferred

General generator-valued reduce expressions, destructuring bindings, dynamic
updates, non-array inputs, and `foreach` remain deferred.
