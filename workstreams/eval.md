# Evaluator workstream

Own the explicit resumable evaluator.

First deliverable is a bounded prototype proving zero, one, and many outputs,
Cartesian composition, `empty`, early termination, and error propagation.
Odin has neither capturing closures nor generators; represent suspended state
explicitly. Do not finalize a broad VM API before the prototype is
adversarially reviewed.

