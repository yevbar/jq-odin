# Decision 0204: bounded numeric slice reads

Implement read-only numeric array slices as a postfix opcode. Bounds are
literal integers with jq's negative-index normalization and omitted-bound
defaults. The result owns a fresh array; assignment, deletion, string slices,
and dynamic bounds remain deferred.

Oracle evidence: `upstream/jq/tests/jq.test:466-470`.
